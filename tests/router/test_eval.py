import json

from router.fakes import (
    Fixture,
    Provider,
)


class EvalTests(Fixture):
    """The offline harness: decides, scores against recorded outcomes, sweeps."""

    def write_items(self):
        items = [
            {
                "id": "easy",
                "prompt": "Rename a variable in one file.",
                "paraphrases": ["Please rename one variable in a single file."],
                "outcomes": {
                    "small": {"correct": True, "cost_usd": 0.001},
                    "mid": {"correct": True, "cost_usd": 0.01},
                    "frontier": {"correct": True, "cost_usd": 0.05},
                },
            },
            {
                "id": "hard",
                "prompt": "HARD: prove the theorem and formalize it.",
                "paraphrases": ["HARD: give a formal proof of the theorem."],
                "outcomes": {
                    "small": {"correct": False, "cost_usd": 0.001},
                    "mid": {"correct": False, "cost_usd": 0.02},
                    "frontier": {"correct": True, "cost_usd": 0.06},
                },
            },
        ]
        path = self.base / "items.jsonl"
        path.write_text("".join(json.dumps(i) + "\n" for i in items))
        return path

    def test_eval_scores_a_decider_against_the_baseline(self):
        Provider.reply_fn = lambda body: {
            "choices": [
                {
                    "message": {
                        "content": '{"difficulty": 4, "tags": []}'
                        if "HARD" in json.dumps(body)
                        else '{"difficulty": 1, "tags": ["code"]}'
                    }
                }
            ],
            "usage": {"prompt_tokens": 100, "completion_tokens": 10},
        }
        items = self.write_items()
        out_dir = self.base / "eval"
        report = json.loads(
            self.run_cli(
                "eval",
                "--items",
                str(items),
                "--decider",
                "llm",
                "--output",
                str(out_dir),
                "--json",
            ).stdout
        )
        self.assertEqual(report["decider"]["id"], "llm")
        self.assertEqual((report["items"], report["prompts"]), (2, 4))
        self.assertEqual(
            len(Provider.requests), 4
        )  # one decision per prompt, no dispatch
        m, b = report["metrics"], report["baseline"]
        self.assertEqual((m["accuracy"], b["accuracy"]), (1.0, 0.5))
        self.assertAlmostEqual(m["cost_usd"], 0.061)
        self.assertAlmostEqual(b["cost_usd"], 0.03)
        self.assertEqual(m["optimal_selection_ratio"], 1.0)
        self.assertEqual(m["robustness"], 1.0)
        self.assertEqual(m["undecidable_rate"], 0.0)
        self.assertGreater(m["decision_cost_usd"], 0)
        checks = report["gate"]["checks"]
        self.assertTrue(
            checks["accuracy"] and checks["optimal_selection"] and checks["robustness"]
        )
        self.assertFalse(
            checks["cost"]
        )  # the frontier answer costs more than the wrong default
        self.assertFalse(report["gate"]["accepted"])
        self.assertEqual(
            [p["frontier_cut"] for p in report["curve"]],
            [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9],
        )
        self.assertTrue(
            (out_dir / "report.json").exists() and (out_dir / "gate.json").exists()
        )
        self.assertEqual(
            json.loads((out_dir / "gate.json").read_text())["accepted"], False
        )
        # one record per prompt and paraphrase, with what the decider answered
        # and never the prompt itself; the report does not carry them
        lines = (out_dir / "decisions.jsonl").read_text().splitlines()
        decisions = [json.loads(line) for line in lines]
        self.assertEqual(len(decisions), 4)
        self.assertEqual(
            {k for k in decisions[0] if k in ("item", "paraphrase", "chosen", "raw")},
            {"item", "paraphrase", "chosen", "raw"},
        )
        self.assertIn("choices", decisions[0]["raw"])
        prompts = [
            text
            for line in items.read_text().splitlines()
            for text in [json.loads(line)["prompt"], *json.loads(line)["paraphrases"]]
        ]
        self.assertFalse(any(text in "\n".join(lines) for text in prompts))
        self.assertNotIn("decisions", report)
        # the rules-only baseline never calls anything and is never accepted
        Provider.requests = []
        report = json.loads(
            self.run_cli(
                "eval", "--items", str(items), "--decider", "none", "--json"
            ).stdout
        )
        self.assertEqual(Provider.requests, [])
        self.assertEqual(report["metrics"]["accuracy"], 0.5)
        self.assertFalse(report["gate"]["accepted"])

    def test_eval_measures_the_decider_even_in_shadow_mode(self):
        Provider.reply_fn = lambda body: {
            "choices": [
                {
                    "message": {
                        "content": '{"difficulty": 4, "tags": []}'
                        if "HARD" in json.dumps(body)
                        else '{"difficulty": 1, "tags": ["code"]}'
                    }
                }
            ],
            "usage": {"prompt_tokens": 100, "completion_tokens": 10},
        }
        self.config["router"]["mode"] = "shadow"
        self.save()
        report = json.loads(
            self.run_cli(
                "eval", "--items", str(self.write_items()), "--decider", "llm", "--json"
            ).stdout
        )
        self.assertEqual(report["metrics"]["accuracy"], 1.0)
        # the rules-only baseline made no decision: no cost, no latency
        self.assertEqual(report["baseline"]["accuracy"], 0.5)
        self.assertEqual(report["baseline"]["decision_cost_usd"], 0.0)
        self.assertEqual(report["baseline"]["latency_ms"]["p95"], 0)
