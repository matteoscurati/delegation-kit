import json

from router.fakes import (
    Fixture,
    Provider,
    Service,
)


class ServiceDeciderTests(Fixture):
    """sage, jev, dipylon and classifier against a fake service: each speaks
    its own wire format, all land in the same signals."""

    SAGE = {
        "results": [
            {
                "ok": True,
                "result": {
                    "answers": [
                        {
                            "ok": True,
                            "result": {
                                "id": "difficulty",
                                "kind": "scale",
                                "result": {
                                    "expectation": 3.4,
                                    "probabilities": [
                                        {"level": 0, "probability": 0},
                                        {"level": 1, "probability": 0},
                                        {"level": 2, "probability": 0.1},
                                        {"level": 3, "probability": 0.4},
                                        {"level": 4, "probability": 0.5},
                                    ],
                                    "confidence": 0.58,
                                },
                            },
                        },
                        {
                            "ok": True,
                            "result": {
                                "id": "tags",
                                "kind": "tags",
                                "result": {
                                    "tags": [
                                        {"id": "code", "probability": 0.9},
                                        {"id": "math", "probability": 0.1},
                                        {"id": "rare", "probability": 0.2},
                                    ]
                                },
                            },
                        },
                    ]
                },
            }
        ],
        "meta": {
            "model": "sage-v1.4",
            "usage": {"input_tokens": 500, "output_tokens": 0},
        },
    }
    JEV = {
        "model": "jev-1.13.0",
        "answers": {
            "difficulty": {
                "type": "score",
                "score": 0.8,
                "confidence": 0.9,
                "probabilities": {"0": 0.3, "1": 0.6, "2": 0.1, "3": 0, "4": 0},
            },
            "strong": {"type": "noul", "noul": 0.05},
            "code": {"type": "noul", "noul": 0.95},
            "rare": {"type": "noul", "noul": 0.1},
        },
        "usage": {"input_tokens": 300, "output_tokens": 20},
    }
    DIPYLON = {
        "response": {
            "type": "yesno",
            "key": "strong",
            "probability": 0.9,
            "answer": "yes",
        },
        "meta": {"model": "dpl-m9", "schema_version": "1.4.0"},
        "selective_use": {"action": "retain", "binding": {"artifact_id": "art-1"}},
    }
    CLASSIFIER = {"prompt_complexity_score": 0.1, "task_type_1": "Code Generation"}

    def decide(self, decider):
        self.config["router"]["decider"] = decider
        self.save()
        return json.loads(
            self.run_cli(
                "decide", "--prompt-file", str(self.base / "prompt"), "--json"
            ).stdout
        )

    def test_each_service_decider_routes_in_its_own_wire_format(self):
        self.env["SAGE_TEST_KEY"] = "sk-canary-sage"
        self.env["TYPESAFE_API_KEY"] = "sk-canary-jev"
        cases = [
            (
                {
                    "kind": "sage",
                    "url": self.service_url,
                    "credential_env": "SAGE_TEST_KEY",
                },
                self.SAGE,
                "frontier",
                "sage-v1.4",
            ),
            ({"kind": "jev", "url": self.service_url}, self.JEV, "small", "jev-1.13.0"),
            (
                {"kind": "dipylon", "url": self.service_url},
                self.DIPYLON,
                "frontier",
                "dpl-m9+art-1",
            ),
            (
                {"kind": "classifier", "url": self.service_url},
                self.CLASSIFIER,
                "small",
                "classifier",
            ),
        ]
        for decider, reply, chosen, version in cases:
            with self.subTest(decider["kind"]):
                Service.requests, Service.reply = [], reply
                out = self.decide(decider)
                self.assertEqual(out["chosen"]["profile"], chosen, out)
                self.assertEqual(
                    out["decider"],
                    {"id": decider["kind"], "version": version, "input": "excerpt"},
                )
                self.assertFalse(out["undecidable"])
                self.assertEqual(len(Service.requests), 1)
                path, body, headers = Service.requests[0]
                self.assertTrue(headers["User-Agent"].startswith("delegation-kit/"))
                self.assertNotIn("sk-canary", json.dumps(out))
                if decider["kind"] == "sage":
                    self.assertEqual(path, "/decide/batch")
                    self.assertEqual(headers["Authorization"], "Bearer sk-canary-sage")
                    self.assertEqual(body["reasoning"], "off")
                    kinds = [q["kind"] for q in body["requests"][0]["questions"]]
                    self.assertEqual(kinds, ["scale", "tags"])
                    self.assertAlmostEqual(out["decision_cost_usd"], 500 * 0.05 / 1e6)
                    self.assertEqual(out["signals"]["tags"]["code"], 0.9)
                elif decider["kind"] == "jev":
                    self.assertEqual(headers["Authorization"], "Bearer sk-canary-jev")
                    self.assertEqual(body["model"], "jev-latest")
                    self.assertEqual(
                        {k: q["type"] for k, q in body["questions"].items()},
                        {
                            "difficulty": "score",
                            "strong": "noul",
                            "code": "noul",
                            "rare": "noul",
                        },
                    )
                    self.assertAlmostEqual(out["decision_cost_usd"], 300 * 0.042 / 1e6)
                elif decider["kind"] == "dipylon":
                    self.assertEqual(path, "/decide")
                    self.assertNotIn("Authorization", headers)
                    self.assertEqual(body["prompt"]["type"], "yesno")
                    self.assertEqual(out["signals"]["p_needs_strong"], 0.9)
                else:
                    self.assertEqual(body, {"text": body["text"]})
                    self.assertEqual(out["signals"]["tags"]["code"], 1.0)
        self.assertEqual(Provider.requests, [])  # no pool profile was called

    def test_service_decider_failures_fall_to_default(self):
        for name, decider, status, reply, env in [
            (
                "missing credential",
                {
                    "kind": "sage",
                    "url": self.service_url,
                    "credential_env": "NO_SUCH_KEY",
                },
                200,
                self.SAGE,
                {},
            ),
            (
                "loading 503",
                {"kind": "dipylon", "url": self.service_url},
                503,
                {"detail": "loading"},
                {},
            ),
            (
                "malformed",
                {"kind": "jev", "url": self.service_url},
                200,
                {"answers": "nope"},
                {"TYPESAFE_API_KEY": "k"},
            ),
            ("empty", {"kind": "classifier", "url": self.service_url}, 200, {}, {}),
        ]:
            with self.subTest(name):
                self.env.update(env)
                Service.requests, Service.status, Service.reply = [], status, reply
                out = self.decide(decider)
                self.assertEqual(out["chosen"]["profile"], "mid")
                self.assertTrue(out["undecidable"])
                self.assertTrue(
                    any(w.startswith("decider failed") for w in out["warnings"]), out
                )
        # an answer that disagrees with its probability is malformed
        Service.status = 200
        Service.reply = dict(
            self.DIPYLON,
            response={
                "type": "yesno",
                "key": "strong",
                "probability": 0.9,
                "answer": "no",
            },
        )
        out = self.decide({"kind": "dipylon", "url": self.service_url})
        self.assertTrue(out["undecidable"])
        self.assertIn(
            "decider failed: decider returned malformed output", out["warnings"]
        )
        # a selective-use verdict other than retain halves dipylon's confidence
        Service.status = 200
        Service.reply = dict(
            self.DIPYLON,
            response={
                "type": "yesno",
                "key": "strong",
                "probability": 0.7,
                "answer": "yes",
            },
            selective_use={"action": "escalate", "binding": {}},
        )
        out = self.decide({"kind": "dipylon", "url": self.service_url})
        self.assertTrue(out["undecidable"])
        self.assertEqual(out["signals"]["confidence"], 0.2)

    def test_an_answer_outside_the_schema_is_undecidable(self):
        self.env.update(TYPESAFE_API_KEY="k", SAGE_API_KEY="k")
        jev = self.JEV["answers"]
        sage_answers = self.SAGE["results"][0]["result"]["answers"]
        sage_tags = dict(
            sage_answers[1],
            result=dict(
                sage_answers[1]["result"],
                result={"tags": [{"id": "code", "probability": float("nan")}]},
            ),
        )
        cases = [
            (
                "jev",
                dict(self.JEV, answers=dict(jev, strong={"type": "noul", "noul": 1.4})),
                "strong probability",
            ),
            (
                "jev",
                dict(
                    self.JEV,
                    answers=dict(
                        jev,
                        difficulty=dict(
                            jev["difficulty"],
                            probabilities={"0": 0.3, "1": 0.3, "2": 0.1},
                        ),
                    ),
                ),
                "difficulty distribution",
            ),
            (
                "sage",
                {
                    "results": [
                        {"ok": True, "result": {"answers": [sage_answers[0], sage_tags]}}
                    ],
                    "meta": self.SAGE["meta"],
                },
                "tag code",
            ),
            (
                "dipylon",
                dict(
                    self.DIPYLON,
                    response={
                        "type": "yesno",
                        "key": "strong",
                        "probability": -0.2,
                        "answer": "no",
                    },
                ),
                "strong probability",
            ),
            (
                "classifier",
                {"prompt_complexity_score": 0.1, "confidence": 1.5},
                "difficulty confidence",
            ),
            ("classifier", {"prompt_complexity_score": 1.3}, "difficulty expectation"),
        ]
        for kind, reply, what in cases:
            with self.subTest(kind=kind, what=what):
                Service.reply = reply
                out = self.decide({"kind": kind, "url": self.service_url})
                self.assertTrue(out["undecidable"], out)
                self.assertEqual(out["chosen"]["profile"], "mid")
                self.assertIn(
                    "decider failed: decider answer outside the schema: " + what,
                    out["warnings"],
                )

    def test_decider_price_override_prices_the_decision(self):
        self.env["SAGE_API_KEY"] = "k"
        Service.reply = self.SAGE
        out = self.decide(
            {"kind": "sage", "url": self.service_url, "price": {"in": 1, "out": 0}}
        )
        self.assertAlmostEqual(out["decision_cost_usd"], 500 / 1e6)
