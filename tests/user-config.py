#!/usr/bin/env python3
"""Behavior tests: real loopback HTTP, isolated config, no provider accounts."""

import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "bin/lib"))
from delegation_config import review_state


class Handler(BaseHTTPRequestHandler):
    requests = []
    response = {}
    status = 200
    delay = 0

    def log_message(self, *args):
        pass

    def do_GET(self):
        type(self).requests.append(("GET", self.path))
        self.send_error(404)

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        type(self).requests.append(
            ("POST", self.path, body, self.headers.get("Authorization"))
        )
        time.sleep(type(self).delay)
        self.send_response(type(self).status)
        self.end_headers()
        data = type(self).response
        try:
            self.wfile.write(
                data if isinstance(data, bytes) else json.dumps(data).encode()
            )
        except BrokenPipeError:
            pass


class ConfigTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        (self.base / "work").mkdir()
        (self.base / "prompt").write_text("Only this prompt is sent.")
        self.env = {
            **os.environ,
            "DELEGATION_CONFIG_FILE": str(self.base / "config.json"),
            "DELEGATION_DATA_HOME": str(self.base / "data"),
        }
        self.config = {
            "schema_version": 1,
            "review_policy": "optional",
            "profiles": {
                "new-model": {
                    "adapter": "openai-compatible",
                    "model": "never-qualified",
                    "roles": ["builder", "reviewer"],
                    "parameters": {"max_tokens": 99, "timeout": 1},
                    "base_url": f"http://127.0.0.1:{self.server.server_port}/v1",
                }
            },
        }
        self.save()
        Handler.requests = []
        Handler.status = 200
        Handler.delay = 0
        Handler.response = {
            "choices": [{"message": {"content": "result"}, "finish_reason": "stop"}]
        }

    def save(self):
        (self.base / "config.json").write_text(json.dumps(self.config))

    def command(self, name, *args, rc=0):
        r = subprocess.run(
            [str(ROOT / "bin" / name), *args],
            env=self.env,
            text=True,
            capture_output=True,
        )
        self.assertEqual(r.returncode, rc, r.stderr)
        return r

    def run_profile(self, *args, rc=0):
        return self.command(
            "delegation-run",
            "--profile",
            "new-model",
            "--lane",
            "builder",
            "--prompt-file",
            str(self.base / "prompt"),
            "--workdir",
            str(self.base / "work"),
            "--output",
            str(self.base / "answer"),
            *args,
            rc=rc,
        )

    def test_new_model_no_inventory_or_identity(self):
        route = json.loads(
            self.command(
                "delegation-route",
                "resolve",
                "--lane",
                "builder",
                "--selected-profile",
                "new-model",
            ).stdout
        )
        self.assertTrue(route["selection_validated"])
        self.assertEqual(route["selected"]["evidence"], {})
        self.assertFalse(route["authorization_granted"])
        self.assertEqual(Handler.requests, [])
        result = json.loads(self.run_profile().stdout)
        self.assertEqual(result["status"], "ready-for-integration")
        m = json.loads((self.base / "answer.metrics.json").read_text())
        self.assertEqual(m["model_identity_source"], "requested-only")
        self.assertIsNone(m["provider_reported_model"])
        self.assertEqual(m["requested_model"], "never-qualified")
        self.assertEqual(len(Handler.requests), 1)
        req = Handler.requests[0]
        self.assertEqual(req[:2], ("POST", "/v1/chat/completions"))
        self.assertEqual(req[2]["max_tokens"], 99)
        self.assertIsNone(req[3])
        self.assertNotIn("tools", req[2])
        self.assertEqual(list((self.base / "work").iterdir()), [])

    def test_matching_identity(self):
        Handler.response["model"] = "never-qualified"
        self.run_profile()
        self.assertEqual(
            json.loads((self.base / "answer.metrics.json").read_text())[
                "model_identity_source"
            ],
            "provider-reported",
        )

    def test_alias(self):
        Handler.response["model"] = "server-alias"
        self.config["profiles"]["new-model"]["aliases"] = ["server-alias"]
        self.save()
        self.run_profile()

    def test_failures_no_retry_or_output(self):
        for reason, rc, response, status, delay in [
            (
                "provider_identity_mismatch",
                70,
                {"model": "other", "choices": []},
                200,
                0,
            ),
            ("invalid_or_empty_response", 70, b"not json", 200, 0),
            ("rate_limited", 75, {}, 429, 0),
            ("deadline_exceeded", 75, {}, 200, 2),
            (
                "output_truncated",
                70,
                {
                    "choices": [
                        {"finish_reason": "length", "message": {"content": "partial"}}
                    ]
                },
                200,
                0,
            ),
        ]:
            with self.subTest(reason=reason):
                Handler.response = response
                Handler.status = status
                Handler.delay = delay
                Handler.requests = []
                self.run_profile(rc=rc)
                self.assertEqual(
                    json.loads((self.base / "answer.error.json").read_text())["reason"],
                    reason,
                )
                self.assertEqual(len(Handler.requests), 1)
                self.assertFalse((self.base / "answer").exists())
                (self.base / "answer.error.json").unlink()

    def test_credentials(self):
        self.config["profiles"]["new-model"]["credential_env"] = "DK_TEST_SECRET"
        self.env.pop("DK_TEST_SECRET", None)
        self.save()
        self.run_profile(rc=69)
        self.assertEqual(Handler.requests, [])
        (self.base / "answer.error.json").unlink()
        self.env["DK_TEST_SECRET"] = "test-not-a-real-key"
        self.run_profile()
        self.assertEqual(Handler.requests[0][3], "Bearer test-not-a-real-key")
        self.assertNotIn(
            "test-not-a-real-key", self.command("delegation-config", "show").stdout
        )

    def test_schema_version_is_an_integer(self):
        self.config["schema_version"] = True
        self.save()
        self.command("delegation-config", "validate", rc=65)
        self.assertEqual(Handler.requests, [])

    def test_technical_rejections(self):
        for field, value in [
            ("base_url", "http://remote.example/v1"),
            ("base_url", "https://user:secret@example.com/v1"),
            ("parameters", {"tools": ["shell"]}),
            ("capabilities", ["write"]),
            ("api_key", "secret"),
        ]:
            original = json.loads(json.dumps(self.config))
            self.config["profiles"]["new-model"][field] = value
            self.save()
            self.command("delegation-config", "validate", rc=65)
            self.assertEqual(Handler.requests, [])
            self.config = original

    def test_paths_do_not_expand_permissions(self):
        self.command(
            "delegation-run",
            "--profile",
            "new-model",
            "--lane",
            "builder",
            "--prompt-file",
            str(self.base / "prompt"),
            "--workdir",
            str(self.base / "work"),
            "--output",
            str(self.base / "work/out"),
            rc=65,
        )
        self.assertEqual(Handler.requests, [])

    def test_review_policies(self):
        for policy in ["required", "cross-family"]:
            self.config["review_policy"] = policy
            self.save()
            result = json.loads(self.run_profile().stdout)
            self.assertEqual(result["review_status"], "pending-authorization")
            self.assertEqual(len(Handler.requests), 1)
            for f in self.base.glob("answer*"):
                f.unlink()
            Handler.requests = []
        a = {"family": "a"}
        b = {"family": "b"}
        self.assertEqual(review_state("required", a, a, True, True), "complete")
        self.assertEqual(
            review_state("cross-family", a, a, True, True),
            "pending-compatible-reviewer",
        )
        self.assertEqual(review_state("cross-family", a, b, True, True), "complete")
        self.assertEqual(
            review_state("cross-family", a, None, True), "pending-reviewer"
        )

    def test_migration_idempotent_and_preserves_edits(self):
        (self.base / "config.json").unlink()
        legacy = self.base / "data/config"
        legacy.mkdir(parents=True)
        (legacy / "routing-gates.json").write_bytes(
            (ROOT / "config/routing-gates.json").read_bytes()
        )
        (legacy / "key.env").write_text("SECRET=kept")
        (legacy / "key.env").chmod(0o600)
        result = json.loads(self.command("delegation-config", "init").stdout)
        self.assertEqual(result["review_policy"], "optional")
        backup = Path(result["backup"])
        digest = hashlib.sha256(
            (backup / "routing-gates.json").read_bytes()
        ).hexdigest()
        migrated = json.loads((self.base / "config.json").read_text())
        migrated["review_policy"] = "required"
        (self.base / "config.json").write_text(json.dumps(migrated))
        self.command("delegation-config", "apply")
        target = self.base / "managed/codex/luna-clerk.toml"
        target.write_text("user edit")
        self.command("delegation-config", "init", "--preset", "strict")
        self.command("delegation-config", "apply")
        self.assertEqual(target.read_text(), "user edit")
        self.assertEqual(
            json.loads((self.base / "config.json").read_text())["review_policy"],
            "required",
        )
        self.assertEqual(
            hashlib.sha256((backup / "routing-gates.json").read_bytes()).hexdigest(),
            digest,
        )
        self.assertEqual((backup / "key.env").read_text(), "SECRET=kept")

    def test_native_cli_forwarding_with_fake_executables(self):
        tools = self.base / "tools"
        tools.mkdir()
        script = """#!/usr/bin/env python3
import json, os, pathlib, sys
args = sys.argv[1:]
pathlib.Path(os.environ['DK_CAPTURE']).write_text(json.dumps(args))
if '--output-last-message' in args:
    pathlib.Path(args[args.index('--output-last-message')+1]).write_text('native result')
    print(json.dumps({'model': os.environ.get('DK_REPORTED', 'unbenchmarked-native')}))
else:
    print(json.dumps({'result':'native result','model':os.environ.get('DK_REPORTED','unbenchmarked-native')}))
"""
        for binary in ["codex", "claude"]:
            path = tools / binary
            path.write_text(script)
            path.chmod(0o700)
        self.env["PATH"] = str(tools) + os.pathsep + self.env["PATH"]
        self.env["DK_CAPTURE"] = str(self.base / "capture")
        for adapter in ["codex", "claude-code"]:
            with self.subTest(adapter=adapter):
                self.config["profiles"]["new-model"] = {
                    "adapter": adapter,
                    "model": "unbenchmarked-native",
                    "roles": ["builder"],
                    "parameters": {"effort": "high"},
                }
                self.save()
                self.run_profile()
                args = json.loads((self.base / "capture").read_text())
                self.assertEqual(
                    args[args.index("--model") + 1], "unbenchmarked-native"
                )
                if adapter == "codex":
                    self.assertEqual(args[args.index("--sandbox") + 1], "read-only")
                else:
                    self.assertEqual(args[args.index("--tools") + 1], "")
                self.assertEqual(
                    json.loads((self.base / "answer.metrics.json").read_text())[
                        "model_identity_source"
                    ],
                    "provider-reported",
                )
                for f in self.base.glob("answer*"):
                    f.unlink()
                self.env["DK_REPORTED"] = "wrong-model"
                self.run_profile(rc=70)
                self.assertFalse((self.base / "answer").exists())
                (self.base / "answer.error.json").unlink()
                self.env.pop("DK_REPORTED")
        self.assertEqual(Handler.requests, [])

    def test_existing_http_adapter_receives_new_model(self):
        tools = self.base / "tools"
        tools.mkdir()
        fake = tools / "curl"
        fake.write_text("""#!/usr/bin/env python3
import json, pathlib, sys
args=sys.argv[1:]
request=json.loads(pathlib.Path(args[args.index('--data-binary')+1][1:]).read_text())
assert request['model']=='new-deepseek-model'
assert request['reasoning_effort']=='high'
pathlib.Path(args[args.index('-o')+1]).write_text(json.dumps({'model':request['model'],'choices':[{'message':{'content':'result'}}]}))
print('200',end='')
""")
        fake.chmod(0o700)
        self.env["PATH"] = str(tools) + os.pathsep + self.env["PATH"]
        self.env["DK_TEST_SECRET"] = "simulated-key"
        self.config["profiles"]["new-model"] = {
            "adapter": "deepseek-api",
            "model": "new-deepseek-model",
            "roles": ["builder"],
            "credential_env": "DK_TEST_SECRET",
            "parameters": {"effort": "high"},
        }
        self.save()
        self.run_profile()
        self.assertEqual(
            json.loads((self.base / "answer.metrics.json").read_text())[
                "requested_model"
            ],
            "new-deepseek-model",
        )

    def test_current_preset_excludes_gemini(self):
        (self.base / "config.json").unlink()
        config = json.loads(self.command("delegation-config", "show").stdout)
        self.assertFalse(
            any(p["adapter"] == "agy" for p in config["profiles"].values())
        )
        route = json.loads(
            self.command("delegation-route", "resolve", "--lane", "scout").stdout
        )
        self.assertFalse(any(p["adapter"] == "agy" for p in route["choices"]))
        self.assertEqual(Handler.requests, [])

    def test_project_config_is_not_loaded(self):
        (self.base / "config.json").unlink()
        self.env.pop("DELEGATION_CONFIG_FILE")
        self.env["XDG_CONFIG_HOME"] = str(self.base / "xdg")
        (self.base / "work/config.json").write_text("malformed")
        r = subprocess.run(
            [str(ROOT / "bin/delegation-config"), "validate"],
            cwd=self.base / "work",
            env=self.env,
            capture_output=True,
        )
        self.assertEqual(r.returncode, 0)


unittest.main()
