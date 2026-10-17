import json
import os
import tempfile
import unittest
from pathlib import Path

from delegation_catalog import aa_key, fetch, group, match, parse_row, place, refresh
from router.fakes import (
    AA_ROWS,
)


class CatalogTests(unittest.TestCase):
    """The ladder from a third party: bands, row parsing, matching, refresh."""

    def test_bands_place_relative_to_the_best_of_the_day(self):
        tiering = {"top_index": 58, "frontier_within": 8, "mid_within": 20}
        for index, tier in [
            (58, "frontier"),
            (50, "frontier"),
            (49.9, "mid"),
            (38, "mid"),
            (37.9, "small"),
            (5, "small"),
        ]:
            self.assertEqual(place(index, tiering), tier, index)
        self.assertIsNone(place(None, tiering))

    def test_rows_parse_variants_families_and_prices(self):
        row = parse_row(AA_ROWS[0])
        self.assertEqual(
            (
                row["base"],
                row["variant"],
                row["family"],
                row["index"],
                row["coding_index"],
            ),
            ("Claude Opus 5.5", "max", "claude-opus-5-5", 58, 61),
        )
        self.assertEqual((row["price_in"], row["price_out"]), (4, 20))
        row = parse_row(AA_ROWS[1])  # the variant suffix leaves the slug
        self.assertEqual((row["variant"], row["family"]), ("medium", "claude-opus-5-5"))
        row = parse_row(AA_ROWS[3])  # a date in parentheses is not a variant
        self.assertEqual(
            (row["base"], row["variant"], row["family"]),
            ("Qwen3.8 Max (0902)", None, "qwen3-8-max"),
        )
        self.assertIsNone(parse_row(AA_ROWS[5])["index"])

    def test_matching_by_slug_or_measured_name_never_by_guess(self):
        families = group(AA_ROWS)
        self.assertEqual(
            match("claude-opus-5-5", None, families), ("claudeopus55", "slug")
        )
        self.assertEqual(match("glm-5.3-flash", None, families), ("glm53flash", "slug"))
        self.assertEqual(match("qwen3.8-max", None, families), ("qwen38max", "slug"))
        self.assertEqual(
            match("deepseek-flash", "DeepSeek V4.1 Flash", families),
            ("deepseekv41flash", "name"),
        )
        self.assertEqual(match("deepseek-flash", None, families), (None, None))
        self.assertEqual(match("grok-4.6", None, families), (None, None))
        self.assertEqual(
            match("claude-opus-5", None, families), (None, None)
        )  # not a prefix match

    def test_refresh_places_evidence_and_keeps_the_rest(self):
        shipped = {
            "catalog_version": "2026-01-01",
            "models": {
                "claude-opus-5-5": {
                    "provider": "anthropic",
                    "tier": "mid",
                    "code": True,
                    "price": {"in": 4, "out": 20},
                    "context": 200000,
                    "json_mode": False,
                },
                "glm-5.3-flash": {
                    "provider": "zai",
                    "tier": "small",
                    "code": True,
                    "price": None,
                    "context": 128000,
                    "json_mode": True,
                },
                "deepseek-flash": {
                    "provider": "deepseek",
                    "tier": "small",
                    "code": True,
                    "price": {"in": 0.3, "out": 1.2},
                    "context": 128000,
                    "json_mode": True,
                    "aa_name": "DeepSeek V4.1 Flash",
                },
                "grok-4.6": {
                    "provider": "xai",
                    "tier": "mid",
                    "code": True,
                    "price": {"in": 2, "out": 6},
                    "context": 256000,
                    "json_mode": True,
                },
            },
        }
        new, unmatched = refresh(shipped, AA_ROWS, "2026-10-15")
        self.assertEqual(new["catalog_version"], "2026-10-15")
        self.assertEqual(new["tiering"]["top_index"], 58)
        self.assertEqual(unmatched, ["grok-4.6"])
        opus = new["models"]["claude-opus-5-5"]
        self.assertEqual(
            (opus["tier"], opus["evidence"]["index"], opus["evidence"]["variant"]),
            ("frontier", 58, "max"),
        )
        self.assertEqual(opus["evidence"]["variants"], {"max": 58, "medium": 51})
        glm = new["models"]["glm-5.3-flash"]
        self.assertEqual(
            (glm["tier"], glm["price"]), ("mid", {"in": 0.2, "out": 1.1})
        )  # a missing price is filled
        self.assertEqual(
            new["models"]["deepseek-flash"]["price"], {"in": 0.3, "out": 1.2}
        )  # a declared one is kept
        self.assertEqual(new["models"]["deepseek-flash"]["tier"], "mid")
        grok = new["models"]["grok-4.6"]
        self.assertEqual((grok["tier"], grok["evidence"]), ("mid", None))

        # The next refresh updates the price the board supplied and keeps its
        # source; the declared one is still left alone.
        repriced = [
            {
                **r,
                "pricing": {
                    "price_1m_input_tokens": 0.25,
                    "price_1m_output_tokens": 1.2,
                },
            }
            if r["id"] == "aa-glm"
            else r
            for r in AA_ROWS
        ]
        again, _ = refresh(new, repriced, "2026-10-17")
        glm = again["models"]["glm-5.3-flash"]
        self.assertEqual(
            (glm["price"], glm["price_source"]),
            ({"in": 0.25, "out": 1.2}, "artificialanalysis 2026-10-17"),
        )
        self.assertEqual(
            again["models"]["deepseek-flash"]["price"], {"in": 0.3, "out": 1.2}
        )
        self.assertNotIn("price_source", again["models"]["deepseek-flash"])

    def test_fetch_sends_the_key_and_reads_the_envelope(self):
        seen = {}

        class Response:
            def __init__(self, payload):
                self.payload = payload

            def __enter__(self):
                return self

            def __exit__(self, *args):
                return False

            def read(self, n=-1):
                return json.dumps(self.payload).encode()

        def opener(request, timeout):
            seen["key"] = request.get_header("X-api-key")
            seen["url"] = request.full_url
            return Response({"status": 200, "data": AA_ROWS})

        rows = fetch("sk-canary-aa", opener=opener)
        self.assertEqual(len(rows), len(AA_ROWS))
        self.assertEqual(seen["key"], "sk-canary-aa")
        self.assertTrue(seen["url"].startswith("https://artificialanalysis.ai/api/v2/"))

    def test_key_comes_from_the_variable_or_a_private_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            os.environ["DELEGATION_DATA_HOME"] = tmp
            try:
                self.assertEqual(aa_key({"AA_API_KEY": "from-env"}), "from-env")
                path = Path(tmp) / "config" / "artificial-analysis.env"
                path.parent.mkdir()
                path.write_text("AA_API_KEY=from-file\n")
                path.chmod(0o644)
                self.assertIsNone(aa_key({}))  # group/world readable: refused
                path.chmod(0o600)
                self.assertEqual(aa_key({}), "from-file")
            finally:
                os.environ.pop("DELEGATION_DATA_HOME")
