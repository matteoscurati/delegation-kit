import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import delegation_credentials
from delegation_credentials import load_env_file, unreachable


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
        kimi = {"adapter": "kimi-code-cli", "model": "kimi-k3.1-pro"}

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


class EnvFileTests(unittest.TestCase):
    """The personal `.env` beside the configuration file."""

    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.dir = Path(temp.name)
        patch = mock.patch.dict(
            os.environ, {"DELEGATION_CONFIG_FILE": str(self.dir / "config.json")}
        )
        patch.start()
        self.addCleanup(patch.stop)

    def write(self, text, mode=0o600):
        path = self.dir / ".env"
        path.write_text(text)
        path.chmod(mode)
        return path

    def test_fills_what_the_environment_lacks_and_never_overrides(self):
        self.write(
            "# keys\n"
            "export A_KEY='quoted'\n"
            'B_KEY="double"\n'
            "C_KEY=plain\n"
            "C_KEY=second spelling ignored\n"
            "EMPTY_KEY=\n"
            "not a line\n"
        )
        environ = {"C_KEY": "from the shell"}
        self.assertEqual(sorted(load_env_file(environ)), ["A_KEY", "B_KEY"])
        self.assertEqual(
            environ, {"A_KEY": "quoted", "B_KEY": "double", "C_KEY": "from the shell"}
        )

    def test_ignored_when_others_can_read_it_or_it_is_a_symlink(self):
        self.write("A_KEY=x\n", mode=0o644)
        self.assertEqual(load_env_file({}), [])
        real = self.dir / "real.env"
        real.write_text("A_KEY=x\n")
        real.chmod(0o600)
        (self.dir / ".env").unlink()
        (self.dir / ".env").symlink_to(real)
        self.assertEqual(load_env_file({}), [])
