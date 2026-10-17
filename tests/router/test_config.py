import unittest

from delegation_config import validate


class ConfigTests(unittest.TestCase):
    def base_config(self, schema=2):
        return {
            "schema_version": schema,
            "review_policy": "optional",
            "profiles": {
                "small": {
                    "adapter": "openai-compatible",
                    "model": "small-model",
                    "roles": ["clerk"],
                    "base_url": "http://127.0.0.1:1/v1",
                    "tier": "small",
                    "price": {"in": 0.2, "out": 1.2},
                },
                "mid": {
                    "adapter": "openai-compatible",
                    "model": "mid-model",
                    "roles": ["builder"],
                    "base_url": "http://127.0.0.1:1/v1",
                    "tier": "mid",
                    "price": {"in": 2, "out": 12},
                },
                "native": {
                    "adapter": "codex",
                    "model": "gpt-5.6-luna",
                    "roles": ["clerk"],
                },
            },
            "router": {
                "pool": ["small", "mid"],
                "default": "mid",
                "decider": {"kind": "none"},
            },
        }

    def test_router_block_accepted_on_schema_2(self):
        validate(self.base_config())
        c = self.base_config()
        c["router"]["pool"].append("native")  # native adapters join the pool
        c["router"]["decider"] = {
            "kind": "sage",
            "credential_env": "SAGE_KEY",
            "price": {"in": 0.05, "out": 10},
        }
        validate(c)
        c["router"]["decider"] = {"kind": "dipylon", "url": "http://127.0.0.1:8888"}
        validate(c)

    def test_rejections(self):
        def with_(mutate):
            c = self.base_config()
            mutate(c)
            return c

        bad = [
            ("no decider", lambda c: c["router"].pop("decider")),
            (
                "decider without kind",
                lambda c: c["router"].update(decider={"profile": "small"}),
            ),
            ("unknown in pool", lambda c: c["router"]["pool"].append("nope")),
            ("default outside pool", lambda c: c["router"].update(default="native")),
            ("remote listen", lambda c: c["router"].update(listen="0.0.0.0:4141")),
            (
                "unknown decider",
                lambda c: c["router"].update(decider={"kind": "oracle"}),
            ),
            (
                "dipylon without url",
                lambda c: c["router"].update(decider={"kind": "dipylon"}),
            ),
            (
                "remote http decider url",
                lambda c: c["router"].update(
                    decider={"kind": "classifier", "url": "http://evil.example/x"}
                ),
            ),
            (
                "service field on llm",
                lambda c: c["router"].update(
                    decider={"kind": "llm", "url": "https://x.example"}
                ),
            ),
            (
                "profile on a service decider",
                lambda c: c["router"].update(
                    decider={"kind": "sage", "profile": "small"}
                ),
            ),
            (
                "bad decider price",
                lambda c: c["router"].update(
                    decider={"kind": "jev", "price": {"in": -1, "out": 0}}
                ),
            ),
            (
                "bad decider credential name",
                lambda c: c["router"].update(
                    decider={"kind": "sage", "credential_env": "1x"}
                ),
            ),
            (
                "decider profile native",
                lambda c: c["router"].update(
                    decider={"kind": "llm", "profile": "native"}
                ),
            ),
            ("bad tier", lambda c: c["profiles"]["small"].update(tier="huge")),
            (
                "bad price",
                lambda c: c["profiles"]["small"].update(price={"in": -1, "out": 1}),
            ),
            (
                "bool price",
                lambda c: c["profiles"]["small"].update(price={"in": True, "out": 1}),
            ),
            ("bad ceiling", lambda c: c["router"].update(max_cost_usd=0)),
            (
                "bad origin",
                lambda c: c["router"].update(allow_origins=["http://evil.example"]),
            ),
            ("unknown router field", lambda c: c["router"].update(fallback=True)),
        ]
        for name, mutate in bad:
            with self.subTest(name):
                with self.assertRaises(ValueError):
                    validate(with_(mutate))
        # a file that still says schema_version 1 is read exactly like 2
        validate(self.base_config(schema=1))
