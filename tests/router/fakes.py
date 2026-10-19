"""Fakes and fixtures shared by the router suite: a recording chat-completions
provider, a decision service, a loopback server without reverse DNS, the
policy's metadata rows and a configured-kit fixture."""

import json
import os
import subprocess
import tempfile
import threading
import time
import unittest
from pathlib import Path
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from socketserver import TCPServer

from router import ROOT


class LoopbackServer(ThreadingHTTPServer):
    """ThreadingHTTPServer without the reverse-DNS lookup http.server does on
    bind: that lookup stalls for seconds per server on a CI runner."""

    daemon_threads = True

    def server_bind(self):
        TCPServer.server_bind(self)
        self.server_name = self.server_address[0]
        self.server_port = self.server_address[1]

    def handle_error(self, request, client_address):
        pass  # a client that gave up mid-reply is expected in the timeout tests


class Provider(BaseHTTPRequestHandler):
    """A fake chat-completions provider that records every request."""

    requests = []
    reply = {"choices": [{"message": {"content": "ok"}}]}
    status = 200

    def log_message(self, *args):
        pass

    stream_lines = None
    reply_headers = {}
    reply_fn = None

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        type(self).requests.append((self.path, body, self.headers.get("Authorization")))
        if type(self).reply_fn is not None:
            type(self).reply = type(self).reply_fn(body)
        if body.get("stream") and type(self).stream_lines is not None:
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.end_headers()
            for line in type(self).stream_lines:
                self.wfile.write(line)
                self.wfile.flush()
                time.sleep(0.01)
            return
        self.send_response(type(self).status)
        self.send_header("Content-Type", "application/json")
        for key, value in type(self).reply_headers.items():
            self.send_header(key, value)
        self.end_headers()
        self.wfile.write(json.dumps(type(self).reply).encode())


class Service(BaseHTTPRequestHandler):
    """A fake decision service (Sage, Jev, Dipylon or a classifier)."""

    requests = []
    reply = {}
    status = 200

    def log_message(self, *args):
        pass

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        type(self).requests.append((self.path, body, dict(self.headers)))
        self.send_response(type(self).status)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(type(self).reply).encode())


def meta(
    profile,
    tier,
    price_in,
    price_out,
    code=True,
    context=128000,
    effort=None,
    score=None,
):
    # An adapter the server forwards `reasoning_effort` to, so the policy's
    # effort column is observable.
    return {
        "profile": profile,
        "model": profile + "-model",
        "adapter": "deepseek-api",
        "effort": effort,
        "tier": tier,
        "score": score,
        "code": code,
        "price": {"in": price_in, "out": price_out} if price_in is not None else None,
        "context": context,
        "json_mode": True,
    }


SMALL = meta("small", "small", 0.2, 1.2)
MID = meta("mid", "mid", 2.0, 12.0)
FRONTIER = meta("frontier", "frontier", 10.0, 50.0)
POOL = [SMALL, MID, FRONTIER]
FEATS = {"est_tokens": 500, "max_tokens": None, "has_tools": False, "has_images": False}


def verdict(difficulty=None, p=None, confidence=0.8, **tags):
    v = {t: 0.0 for t in ("code", "math", "long", "rare", "tools")}
    v.update(tags)
    return {
        "difficulty": difficulty,
        "p_needs_strong": p,
        "tags": v,
        "confidence": confidence,
        "undecidable": difficulty is None and p is None,
    }


class Fixture(unittest.TestCase):
    """A schema-2 config with three priced HTTP profiles over the fake provider."""

    @classmethod
    def setUpClass(cls):
        cls.server = LoopbackServer(("127.0.0.1", 0), Provider)
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()
        cls.service = LoopbackServer(("127.0.0.1", 0), Service)
        threading.Thread(target=cls.service.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        for server in (cls.server, cls.service):
            server.shutdown()
            server.server_close()

    @property
    def service_url(self):
        return "http://127.0.0.1:%d" % self.service.server_address[1]

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.env = {
            **os.environ,
            "DELEGATION_CONFIG_FILE": str(self.base / "config.json"),
            "DELEGATION_DATA_HOME": str(self.base / "data"),
            "SMALL_KEY": "sk-canary-small",
            "MID_KEY": "sk-canary-mid",
        }
        port = self.server.server_address[1]
        self.config = {
            "schema_version": 2,
            "review_policy": "optional",
            "profiles": {
                "small": {
                    "adapter": "openai-compatible",
                    "model": "small-model",
                    "roles": ["clerk"],
                    "base_url": "http://127.0.0.1:%d/v1" % port,
                    "credential_env": "SMALL_KEY",
                    "tier": "small",
                    "code": True,
                    "price": {"in": 0.2, "out": 1.2},
                    "json_mode": True,
                },
                "mid": {
                    "adapter": "openai-compatible",
                    "model": "mid-model",
                    "roles": ["builder"],
                    "base_url": "http://127.0.0.1:%d/v1" % port,
                    "credential_env": "MID_KEY",
                    "tier": "mid",
                    "code": True,
                    "price": {"in": 2, "out": 12},
                },
                "frontier": {
                    "adapter": "openai-compatible",
                    "model": "frontier-model",
                    "roles": ["judgement"],
                    "base_url": "http://127.0.0.1:%d/v1" % port,
                    "tier": "frontier",
                    "price": {"in": 10, "out": 50},
                },
            },
            "router": {
                "pool": ["small", "mid", "frontier"],
                "default": "mid",
                "decider": {"kind": "llm", "profile": "small", "timeout": 2},
            },
        }
        self.save()
        Provider.requests = []
        Provider.reply = {"choices": [{"message": {"content": "ok"}}]}
        Provider.status = 200
        Provider.stream_lines = None
        Provider.reply_headers = {}
        Provider.reply_fn = None
        Service.requests = []
        Service.reply = {}
        Service.status = 200
        (self.base / "prompt").write_text("Rename a variable in one file. " * 40)

    def save(self):
        (self.base / "config.json").write_text(json.dumps(self.config))

    def install_fake_native_cli(self):
        """`codex` and `claude` stand-ins on PATH: they capture what they were
        asked and answer from the environment (DK_REPORTED, DK_SLEEP, DK_EXIT)."""
        tools = self.base / "tools"
        tools.mkdir(exist_ok=True)
        script = """#!/usr/bin/env python3
import json, os, pathlib, sys, time
args = sys.argv[1:]
prompt = sys.stdin.read()
pathlib.Path(os.environ["DK_CAPTURE"]).write_text(json.dumps({"args": args, "prompt": prompt}))
time.sleep(float(os.environ.get("DK_SLEEP", "0")))
if os.environ.get("DK_EXIT"):
    sys.exit(int(os.environ["DK_EXIT"]))
reported = os.environ.get("DK_REPORTED", "native-model")
answer = "native answer to: " + prompt[:24]
if "--output-last-message" in args:
    pathlib.Path(args[args.index("--output-last-message") + 1]).write_text(answer)
    print(json.dumps({"model": reported}))
else:
    print(json.dumps({"result": answer, "model": reported}))
"""
        for binary in ("codex", "claude"):
            path = tools / binary
            path.write_text(script)
            path.chmod(0o700)
        self.env["PATH"] = str(tools) + os.pathsep + self.env["PATH"]
        self.env["DK_CAPTURE"] = str(self.base / "capture")
        self.config["profiles"]["native"] = {
            "adapter": "codex",
            "model": "native-model",
            "roles": ["builder", "clerk"],
            "tier": "frontier",
            "price": {"in": 8, "out": 40},
        }
        self.config["router"]["pool"].append("native")
        self.save()

    def captured(self):
        return json.loads((self.base / "capture").read_text())

    def run_cli(self, *args, rc=0):
        result = subprocess.run(
            [str(ROOT / "bin/delegation-router"), *args],
            env=self.env,
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, rc, result.stdout + result.stderr)
        return result


AA_ROWS = [
    {
        "id": "aa-opus-max",
        "slug": "claude-opus-5-5",
        "name": "Claude Opus 5.5 (Max, Default Fallback)",
        "model_creator": {"name": "Anthropic"},
        "evaluations": {
            "artificial_analysis_intelligence_index": 58,
            "artificial_analysis_coding_index": 61,
        },
        "pricing": {"price_1m_input_tokens": 4, "price_1m_output_tokens": 20},
    },
    {
        "id": "aa-opus-medium",
        "slug": "claude-opus-5-5-medium",
        "name": "Claude Opus 5.5 (Medium, Default Fallback)",
        "evaluations": {"artificial_analysis_intelligence_index": 51},
        "pricing": {"price_1m_input_tokens": 4, "price_1m_output_tokens": 20},
    },
    {
        "id": "aa-glm",
        "slug": "glm-5-3-flash",
        "name": "GLM-5.3-Flash",
        "evaluations": {"artificial_analysis_intelligence_index": 42},
        "pricing": {"price_1m_input_tokens": 0.2, "price_1m_output_tokens": 1.1},
    },
    {
        "id": "aa-qwen",
        "slug": "qwen3-8-max",
        "name": "Qwen3.8 Max (0902)",
        "evaluations": {"artificial_analysis_intelligence_index": 45},
        "pricing": {},
    },
    {
        "id": "aa-ds",
        "slug": "deepseek-v4-1-flash",
        "name": "DeepSeek V4.1 Flash (Max)",
        "evaluations": {"artificial_analysis_intelligence_index": 39},
    },
    {"id": "aa-noindex", "name": "Some Preview (high)", "evaluations": {}},
    {
        "id": "aa-tiny",
        "name": "Tiny Model",
        "evaluations": {"artificial_analysis_intelligence_index": 12},
    },
]
