import unittest

from delegation_router_policy import (
    choose,
    minimum_score,
    estimate_cost,
    excerpt,
    features,
    normalize,
    prefilter,
    skip_reason,
)
from router.fakes import (
    FEATS,
    FRONTIER,
    MID,
    POOL,
    SMALL,
    meta,
    verdict,
)


BAR = {"mid": 37.6, "frontier": 49.6}


class PolicyTests(unittest.TestCase):
    def test_floor_v1_table(self):
        # The fixture pool sits on the bottom of each band: small 0, mid 37.6,
        # frontier 49.6; the cheapest model that reaches the minimum answers.
        cases = [
            ("trivial → no minimum → small", verdict(0.0), 0.0, "small", "low"),
            ("easy → no minimum → small", verdict(0.25), 0.0, "small", "low"),
            ("moderate → mid band", verdict(0.5), 37.6, "mid", None),
            (
                "between moderate and hard → in proportion",
                verdict(0.625),
                43.6,
                "frontier",
                None,
            ),
            ("hard → frontier band", verdict(0.75), 49.6, "frontier", None),
            ("frontier → frontier, high", verdict(1.0), 49.6, "frontier", "high"),
            (
                "easy code → cheapest code-capable",
                verdict(0.25, code=1.0),
                0.0,
                "small",
                "low",
            ),
            ("moderate code → mid", verdict(0.5, code=1.0), 37.6, "mid", None),
            (
                "easy but long → frontier",
                verdict(0.25, long=1.0),
                49.6,
                "frontier",
                None,
            ),
            ("easy with math → mid", verdict(0.25, math=1.0), 37.6, "mid", None),
            ("yesno strong → frontier", verdict(None, p=0.9), 49.6, "frontier", None),
            ("yesno weak → no minimum", verdict(None, p=0.1), 0.0, "small", None),
            ("yesno middle → mid", verdict(None, p=0.5), 37.6, "mid", None),
        ]
        for name, v, minimum, profile, effort in cases:
            with self.subTest(name):
                choice = choose(v, POOL, MID, FEATS, bar=BAR)
                self.assertEqual(choice["minimum_score"], minimum)
                self.assertEqual(choice["profile"], profile)
                self.assertEqual(choice["reasoning_effort"], effort)
                self.assertFalse(choice["undecidable"])

    def test_a_cheaper_stronger_model_beats_a_pricier_weaker_one(self):
        # The case tiered-v1 got wrong: an easy request went to the small
        # tier even when a cheaper mid model was there.
        pricey_small = meta("luna", "small", 0.2, 1.2, score=37.3)
        cheap_mid = meta("glm", "mid", 0.15, 0.5, score=41.8)
        choice = choose(
            verdict(0.25), [pricey_small, cheap_mid], cheap_mid, FEATS, bar=BAR
        )
        self.assertEqual(choice["profile"], "glm")

    def test_measured_scores_split_a_band(self):
        glm = meta("glm", "mid", 0.15, 0.5, score=41.8)
        kimi = meta("kimi", "mid", 0.5, 2.0, score=43.6)
        qwen = meta("qwen", "mid", 2.0, 6.0, score=45.4)
        opus = meta("opus", "frontier", 4.0, 20.0, score=57.6)
        pool = [glm, kimi, qwen, opus]
        for d, profile in [
            (0.5, "glm"),
            (0.625, "kimi"),
            (0.65, "qwen"),
            (0.75, "opus"),
        ]:
            with self.subTest(d):
                self.assertEqual(
                    choose(verdict(d), pool, glm, FEATS, bar=BAR)["profile"], profile
                )

    def test_minimum_score_points(self):
        for d, expected in [
            (0.0, 0.0),
            (0.25, 0.0),
            (0.375, 18.8),
            (0.5, 37.6),
            (0.625, 43.6),
            (0.75, 49.6),
            (1.0, 49.6),
        ]:
            with self.subTest(d):
                self.assertEqual(minimum_score(verdict(d), BAR), expected)

    def test_effort_is_a_floor_and_only_where_it_is_forwarded(self):
        # `high` never lowers a declared xhigh/max on the hardest requests
        declared_max = meta("ds", "frontier", 1.0, 5.0, effort="max")
        choice = choose(verdict(1.0), [declared_max], declared_max, FEATS)
        self.assertIsNone(choice["reasoning_effort"])
        declared_medium = meta("ds", "frontier", 1.0, 5.0, effort="medium")
        choice = choose(verdict(1.0), [declared_medium], declared_medium, FEATS)
        self.assertEqual(choice["reasoning_effort"], "high")
        # no effort is disclosed for an adapter that never receives one
        plain = dict(SMALL, adapter="openai-compatible")
        choice = choose(verdict(0.0), [plain], plain, FEATS)
        self.assertEqual(choice["profile"], "small")
        self.assertIsNone(choice["reasoning_effort"])

    def test_undecidable_and_low_confidence_fall_to_default(self):
        for v in (verdict(None), verdict(0.0, confidence=0.3)):
            choice = choose(v, POOL, MID, FEATS)
            self.assertEqual(choice["profile"], "mid")
            self.assertTrue(choice["undecidable"])

    def test_climbs_when_nothing_cheaper_reaches_and_takes_the_strongest_when_nothing_does(
        self,
    ):
        choice = choose(verdict(0.0), [MID, FRONTIER], FRONTIER, FEATS, bar=BAR)
        self.assertEqual(choice["profile"], "mid")
        choice = choose(verdict(1.0), [SMALL, MID], SMALL, FEATS, bar=BAR)
        self.assertEqual(choice["profile"], "mid")
        self.assertFalse(choice["undecidable"])
        self.assertIn(
            "no profile reaches 49.6 → the strongest eligible: mid", choice["reasons"]
        )

    def test_cheapest_wins_and_unpriced_ranks_last(self):
        cheap = meta("cheap", "mid", 1.0, 5.0)
        unpriced = meta("credits", "mid", None, None)
        choice = choose(verdict(0.5), [unpriced, MID, cheap], MID, FEATS)
        self.assertEqual(choice["profile"], "cheap")
        choice = choose(verdict(0.5), [unpriced], unpriced, FEATS)
        self.assertEqual(choice["profile"], "credits")

    def test_normalize_scale_and_distribution(self):
        v = normalize(
            [
                {
                    "kind": "scale",
                    "expectation": 3,
                    "confidence": 0.8,
                    "range": [0, 4],
                    "distribution": [{"level": 3, "p": 1.0}],
                },
                {"kind": "tags", "tags": {"code": 1.0, "unknown": 1.0}},
            ]
        )
        self.assertEqual(v["difficulty"], 0.75)
        self.assertEqual(v["p_needs_strong"], 1.0)
        self.assertEqual(v["tags"]["code"], 1.0)
        self.assertNotIn("unknown", v["tags"])
        self.assertTrue(normalize([])["undecidable"])

    def test_features_and_excerpt_never_include_images(self):
        body = {
            "messages": [
                {"role": "system", "content": "S" * 5000},
                {
                    "role": "user",
                    "content": [
                        {"type": "text", "text": "fix bug 42"},
                        {"type": "image_url", "image_url": {"url": "data:..."}},
                    ],
                },
            ],
            "tools": [{"type": "function", "function": {"name": "run_tests"}}],
            "max_tokens": 10,
        }
        feats = features(body)
        self.assertTrue(feats["has_images"] and feats["has_tools"])
        self.assertEqual(feats["max_tokens"], 10)
        text = excerpt(body)
        self.assertIn("fix bug 42", text)
        self.assertIn("run_tests", text)
        self.assertNotIn("data:", text)
        self.assertLessEqual(len(text), 4000)

    def test_prefilter_context_and_ceiling(self):
        tiny = meta("tiny", "small", 0.2, 1.2, context=100)
        feats = dict(FEATS, est_tokens=5000)
        eligible, blocked = prefilter([tiny, MID, FRONTIER], feats, 0.05, "mid")
        self.assertEqual([m["profile"] for m in eligible], ["mid"])
        self.assertEqual(
            {b["profile"]: b["reason"] for b in blocked},
            {"tiny": "context too small", "frontier": "estimated cost above ceiling"},
        )
        # the default is never blocked for lacking a tier
        untiered = dict(MID, tier=None)
        eligible, blocked = prefilter([untiered], FEATS, None, "mid")
        self.assertEqual(len(eligible), 1)

    def test_skip_reason(self):
        self.assertEqual(skip_reason([MID], MID, SMALL, FEATS), "one eligible profile")
        self.assertEqual(skip_reason([], MID, SMALL, FEATS), "no eligible profile")
        # one eligible profile that is not the default still needs the
        # decision: skipping it would land on the (blocked) default
        self.assertIsNone(skip_reason([SMALL], MID, SMALL, FEATS))
        # a cheap default with stronger tiers above it: the decision buys capability
        self.assertIsNone(skip_reason(POOL, SMALL, SMALL, FEATS))
        # the default is the cheapest and nothing stronger is eligible
        pricier_small = meta("small2", "small", 0.5, 2.0)
        self.assertEqual(
            skip_reason([SMALL, pricier_small], SMALL, SMALL, FEATS), "nothing to save"
        )
        # output tokens count: even a short prompt saves on the answer
        self.assertIsNone(skip_reason(POOL, MID, SMALL, dict(FEATS, est_tokens=10)))
        self.assertIsNone(skip_reason(POOL, MID, SMALL, dict(FEATS, est_tokens=50000)))

    def test_reasons_name_the_candidates_with_their_cost(self):
        choice = choose(verdict(difficulty=1.0), POOL, MID, FEATS)
        self.assertIn("candidates: frontier $0.0562 → frontier", choice["reasons"])
        choice = choose(verdict(difficulty=0.1, code=1.0), POOL, MID, FEATS)
        self.assertIn(
            "candidates: small $0.0013, mid $0.0133, frontier $0.0562 → small",
            choice["reasons"],
        )
        free = meta("free", "small", None, None)
        choice = choose(verdict(difficulty=0.1), [free, SMALL], MID, FEATS)
        self.assertIn(
            "candidates: small $0.0013, free unpriced → small", choice["reasons"]
        )

    def test_numbers_mean_arithmetic_not_any_digit(self):
        for text, expected in [
            ("what is 17 % of 2,340 €", True),
            ("split $120 three ways", True),
            ("3 * 4 + 2^10", True),
            ("a 0.75 probability", True),
            ("SELECT ... LIMIT 1 then UPDATE", False),
            ("port 8080 on line 42 of utils.py", False),
            ("rename foo to bar in 2 files", False),
        ]:
            with self.subTest(text):
                feats = features({"messages": [{"role": "user", "content": text}]})
                self.assertEqual(feats["has_numbers"], expected)

    def test_costs_tolerate_unknown_counts(self):
        self.assertIsNone(estimate_cost(SMALL, None, 10))
        self.assertIsNone(estimate_cost(SMALL, "300", 10))
        self.assertIsNone(estimate_cost(meta("free", "small", None, None), 10, 10))
        self.assertAlmostEqual(estimate_cost(SMALL, 1000, 100), 0.2e-3 + 0.12e-3)

    def test_json_mode_rule_and_malformed_tools(self):
        no_json = dict(MID, json_mode=False)
        eligible, blocked = prefilter(
            [SMALL, no_json], dict(FEATS, wants_json=True), None, "mid"
        )
        self.assertEqual([m["profile"] for m in eligible], ["small"])
        self.assertEqual(blocked, [{"profile": "mid", "reason": "no JSON mode"}])
        body = {
            "messages": [{"role": "user", "content": "x"}],
            "tools": [{"type": "function", "function": "run"}, "junk", {"name": "ok"}],
        }
        self.assertIn("tools: ok", excerpt(body))
        self.assertTrue(features(body)["has_tools"])
