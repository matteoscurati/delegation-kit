import json
import subprocess
import unittest
from unittest import mock

import delegation_credentials
from delegation_credentials import unreachable


class ReachTests(unittest.TestCase):
    """What `unreachable()` reads for each kind of adapter. The pipeline,
    `check`, `decide` and `serve` use it through the CLI and server suites."""

    def test_named_variable_and_kit_key_file(self):
        local = {
            "adapter": "openai-compatible",
            "model": "m",
            "base_url": "http://127.0.0.1:1/v1",
        }
        self.assertIsNone(unreachable(local, {}))  # a local endpoint needs no key
        named = dict(local, credential_env="OWN_KEY")
        self.assertEqual(unreachable(named, {}), "no OWN_KEY")
        self.assertIsNone(unreachable(named, {"OWN_KEY": "k"}))
        with mock.patch.object(
            delegation_credentials, "key_from_file", return_value=None
        ):
            self.assertEqual(
                unreachable({"adapter": "deepseek-api", "model": "deepseek-flash"}, {}),
                "no DEEPSEEK_API_KEY and no deepseek.env key file",
            )

    def test_native_cli_on_path(self):
        codex = {"adapter": "codex", "model": "gpt-5.6-luna"}
        self.assertEqual(
            unreachable(codex, {"PATH": "/nonexistent"}), "no `codex` on PATH"
        )

    def test_native_runner_check(self):
        kimi = {"adapter": "kimi-code-cli", "model": "kimi-k3"}

        def answer(report):
            return subprocess.CompletedProcess(
                [], 0, stdout=json.dumps(report), stderr=""
            )

        with mock.patch.object(
            subprocess, "run", return_value=answer({"selected_backend": "native"})
        ):
            self.assertIsNone(unreachable(kimi, {}))
        down = {
            "selected_backend": "none",
            "backends": {"native": {"available": False, "reason": "not logged in"}},
        }
        with mock.patch.object(subprocess, "run", return_value=answer(down)):
            self.assertEqual(unreachable(kimi, {}), "not logged in")
        with mock.patch.object(
            subprocess, "run", side_effect=subprocess.TimeoutExpired("x", 1)
        ):
            self.assertEqual(unreachable(kimi, {}), "`delegation-kimi check` failed")
