import json
import socket
import subprocess
import threading
import time
import urllib.error
import urllib.request

from router import ROOT
from router.fakes import (
    Fixture,
    LoopbackServer,
    Provider,
)


class ServerTests(Fixture):
    """`serve` on a free loopback port, exercised over real HTTP."""

    def setUp(self):
        super().setUp()
        with socket.socket() as probe:
            probe.bind(("127.0.0.1", 0))
            self.port = probe.getsockname()[1]
        self.config["router"]["listen"] = "127.0.0.1:%d" % self.port
        self.save()
        self.start()

    def start(self):
        self.proc = subprocess.Popen(
            [str(ROOT / "bin/delegation-router"), "serve"],
            env=self.env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        self.addCleanup(self.stop)
        for _ in range(200):
            try:
                self.get("/v1/health")
                return
            except (urllib.error.URLError, ConnectionError):
                time.sleep(0.05)
        self.fail("server did not start")

    def stop(self):
        if self.proc.poll() is None:
            self.proc.terminate()
            try:
                self.proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.proc.kill()
        self.stdout, self.stderr = self.proc.communicate()

    def restart(self):
        self.stop()
        self.start()

    host = "127.0.0.1"

    def url(self, path):
        return "http://%s:%d%s" % (self.host, self.port, path)

    def get(self, path):
        with urllib.request.urlopen(self.url(path), timeout=5) as response:
            return json.loads(response.read()), dict(response.headers)

    def post(self, body, headers=None, raw=False):
        request = urllib.request.Request(
            self.url("/v1/chat/completions"),
            data=json.dumps(body).encode(),
            headers={"Content-Type": "application/json", **(headers or {})},
            method="POST",
        )
        try:
            with urllib.request.urlopen(request, timeout=10) as response:
                data = response.read()
                return (
                    response.status,
                    data if raw else json.loads(data),
                    dict(response.headers),
                )
        except urllib.error.HTTPError as error:
            return error.code, json.loads(error.read()), dict(error.headers)

    @staticmethod
    def chat(model, text="hi", **extra):
        return {
            "model": model,
            "messages": [{"role": "user", "content": text}],
            **extra,
        }

    def test_health_and_models_without_provider_calls(self):
        health, _ = self.get("/v1/health")
        self.assertEqual(health["status"], "ok")
        models, _ = self.get("/v1/models")
        self.assertEqual(
            [m["id"] for m in models["data"]], ["small", "mid", "frontier", "auto"]
        )
        self.assertEqual(Provider.requests, [])

    def test_auto_decides_forwards_with_the_chosen_key_and_discloses(self):
        Provider.reply = {
            "choices": [
                {
                    "message": {
                        "content": '{"difficulty": 1, "tags": ["code"], "reason": "rename"}'
                    }
                }
            ],
            "usage": {"prompt_tokens": 300, "completion_tokens": 20},
        }
        prompt = "Rename a variable in one file. " * 40
        status, data, headers = self.post(
            self.chat("auto", prompt, router={"ignored": True})
        )
        self.assertEqual(status, 200, data)
        self.assertEqual(data["router"]["chosen"]["profile"], "small")
        self.assertEqual(headers["X-Router-Profile"], "small")
        self.assertEqual(headers["X-Router-Model"], "small-model")
        self.assertTrue(headers["X-Router-Decider"].startswith("llm/small-model+"))
        self.assertEqual(headers["X-Router-Undecidable"], "0")
        self.assertEqual(headers["X-Router-Mode"], "route")
        self.assertNotIn("raw", data["router"]["decider"])  # never in a served response
        self.assertEqual(data["router"]["usage"]["prompt_tokens"], 300)
        self.assertAlmostEqual(data["router"]["cost_usd"], (300 * 0.2 + 20 * 1.2) / 1e6)
        self.assertFalse(data["router"]["mismatch"])
        self.assertEqual(data["choices"][0]["message"]["content"][0], "{")
        decision, forward = Provider.requests
        self.assertEqual(decision[2], "Bearer sk-canary-small")
        self.assertEqual(forward[2], "Bearer sk-canary-small")
        self.assertEqual(forward[1]["model"], "small-model")
        self.assertEqual(forward[1]["messages"][0]["content"], prompt)
        self.assertNotIn("router", forward[1])
        self.assertFalse(forward[1]["stream"])
        self.assertNotIn("sk-canary", json.dumps([data, headers]))

    def test_explicit_profile_skips_the_decider(self):
        status, data, headers = self.post(self.chat("frontier"))
        self.assertEqual(status, 200, data)
        self.assertEqual(headers["X-Router-Profile"], "frontier")
        self.assertEqual(headers["X-Router-Mode"], "explicit")
        self.assertEqual(data["router"]["decider"]["id"], "none")
        self.assertEqual(len(Provider.requests), 1)
        self.assertIsNone(Provider.requests[0][2])  # frontier declares no credential

    def test_reported_model_mismatch_is_disclosed_not_fatal(self):
        Provider.reply = {
            "model": "other-model",
            "choices": [{"message": {"content": "ok"}}],
        }
        status, data, headers = self.post(self.chat("frontier"))
        self.assertEqual(status, 200)
        self.assertTrue(data["router"]["mismatch"])
        self.assertEqual(data["router"]["provider_reported_model"], "other-model")
        self.assertEqual(headers["X-Router-Model-Mismatch"], "1")

    def test_refusals_never_reach_a_provider(self):
        for name, body, headers, status, code in [
            ("unknown model", self.chat("nope"), {}, 404, "unknown-model"),
            (
                "browser origin",
                self.chat("auto"),
                {"Origin": "http://127.0.0.1:9"},
                403,
                "browser-denied",
            ),
            (
                "cost ceiling",
                self.chat("auto"),
                {"X-Router-Max-Cost-USD": "0.0000001"},
                400,
                "cost-ceiling",
            ),
            (
                "cost ceiling on a named profile",
                self.chat("frontier"),
                {"X-Router-Max-Cost-USD": "0.0000001"},
                400,
                "cost-ceiling",
            ),
            (
                "bad ceiling",
                self.chat("auto"),
                {"X-Router-Max-Cost-USD": "lots"},
                400,
                "invalid-cost-ceiling",
            ),
            ("not json", None, {}, 400, "invalid-json"),
        ]:
            with self.subTest(name):
                Provider.requests = []
                if body is None:
                    request = urllib.request.Request(
                        self.url("/v1/chat/completions"), data=b"{nope", method="POST"
                    )
                    with self.assertRaises(urllib.error.HTTPError) as caught:
                        urllib.request.urlopen(request, timeout=5)
                    with caught.exception as error:
                        got, data = error.code, json.loads(error.read())
                else:
                    got, data, _ = self.post(body, headers)
                self.assertEqual((got, data["error"]["code"]), (status, code))
                self.assertEqual(Provider.requests, [])

    def test_cost_ceiling_reports_estimate_and_ceiling(self):
        status, data, _ = self.post(
            self.chat("auto"), {"X-Router-Max-Cost-USD": "0.0000001"}
        )
        self.assertEqual(status, 400)
        self.assertEqual(data["error"]["ceiling_usd"], 1e-7)
        self.assertGreater(data["error"]["estimated_usd"], 1e-7)

    def test_provider_errors_are_mapped_and_redacted(self):
        for name, status, reply, headers, expect_status, code, retryable in [
            (
                "key rejected",
                401,
                {"error": {"message": "bad key sk-canary-small"}},
                {},
                401,
                "provider-key-rejected",
                False,
            ),
            (
                "rate limited",
                429,
                {"error": {"message": "slow down"}},
                {"Retry-After": "7"},
                429,
                "provider-rate-limited",
                True,
            ),
            ("outage", 503, {"error": "down"}, {}, 502, "provider-unavailable", True),
            (
                "bad request",
                400,
                {"error": {"message": "unsupported with sk-canary-small inside"}},
                {},
                400,
                "provider-rejected-request",
                False,
            ),
        ]:
            with self.subTest(name):
                Provider.status, Provider.reply, Provider.reply_headers = (
                    status,
                    reply,
                    headers,
                )
                got, data, out_headers = self.post(self.chat("frontier"))
                self.assertEqual(
                    (got, data["error"]["code"], data["error"]["retryable"]),
                    (expect_status, code, retryable),
                )
                self.assertEqual(data["error"]["profile"], "frontier")
                self.assertEqual(out_headers["X-Router-Error"], code)
                self.assertEqual(out_headers["X-Router-Profile"], "frontier")
                self.assertEqual(out_headers["Server"], "delegation-router")
                self.assertNotIn("sk-canary", json.dumps(data))
                if headers:
                    self.assertEqual(out_headers["Retry-After"], "7")
                if name == "bad request":
                    self.assertIn("[redacted]", data["error"]["message"])

    def test_missing_credential_fails_before_dispatch(self):
        self.env.pop("MID_KEY")
        self.restart()
        status, data, _ = self.post(self.chat("mid"))
        self.assertEqual(
            (status, data["error"]["code"], data["error"]["profile"]),
            (401, "provider-key-missing", "mid"),
        )
        self.assertEqual(Provider.requests, [])

    def test_auto_sets_aside_a_profile_this_machine_cannot_reach(self):
        # Without MID_KEY a 2 goes to the next profile that reaches 37.6
        # instead of failing on `mid`, and the response says why.
        self.env.pop("MID_KEY")
        self.restart()
        Provider.reply = {
            "choices": [{"message": {"content": '{"difficulty": 2, "tags": []}'}}],
            "usage": {"prompt_tokens": 300, "completion_tokens": 20},
        }
        status, data, headers = self.post(self.chat("auto", "Summarise this. " * 40))
        self.assertEqual(status, 200, data)
        self.assertEqual(headers["X-Router-Profile"], "frontier")
        self.assertIn(
            {"profile": "mid", "reason": "unreachable: no MID_KEY"},
            data["router"]["blocked"],
        )

    def test_a_key_kept_in_the_personal_env_file_is_used(self):
        # MID_KEY only in the .env beside the configuration: `mid` is reachable
        # and the forward carries that key.
        self.env.pop("MID_KEY")
        env_file = self.base / ".env"
        env_file.write_text("MID_KEY=sk-canary-mid\n")
        env_file.chmod(0o600)
        self.restart()
        status, data, headers = self.post(self.chat("mid"))
        self.assertEqual(status, 200, data)
        self.assertEqual(Provider.requests[-1][2], "Bearer sk-canary-mid")

    def test_stream_passthrough_ends_with_router_chunk_then_done(self):
        Provider.stream_lines = [
            b'data: {"id":"x","object":"chat.completion.chunk","model":"frontier-model","choices":[{"delta":{"content":"Hel"}}]}\n\n',
            b": keep-alive\n\n",
            b'data: {"id":"x","object":"chat.completion.chunk","choices":[{"delta":{"content":"lo"}}]}\n\n',
            b'data: {"id":"x","object":"chat.completion.chunk","choices":[],"usage":{"prompt_tokens":10,"completion_tokens":2}}\n\n',
            b"data: [DONE]\n\n",
        ]
        status, raw, headers = self.post(self.chat("frontier", stream=True), raw=True)
        self.assertEqual(status, 200)
        self.assertEqual(headers["Content-Type"], "text/event-stream")
        self.assertEqual(headers["X-Router-Profile"], "frontier")
        text = raw.decode()
        self.assertIn('"content":"Hel"', text)
        self.assertIn(": keep-alive", text)
        events = [line for line in text.split("\n") if line.startswith("data:")]
        self.assertEqual(events[-1], "data: [DONE]")
        final = json.loads(events[-2][5:])
        self.assertEqual(final["choices"], [])
        self.assertEqual(final["router"]["usage"]["completion_tokens"], 2)
        self.assertAlmostEqual(final["router"]["cost_usd"], (10 * 10 + 2 * 50) / 1e6)
        self.assertEqual(final["router"]["upstream_status"], 200)
        self.assertNotIn("error", final)
        forward = Provider.requests[-1][1]
        self.assertEqual(forward["stream_options"], {"include_usage": True})
        self.assertTrue(forward["stream"])

    def test_broken_streams_end_with_a_router_chunk_naming_the_failure(self):
        first = b'data: {"id":"x","object":"chat.completion.chunk","choices":[{"delta":{"content":"Hel"}}]}\n\n'
        for name, lines, code in [
            (
                "cut mid-line",
                [first, b'data: {"id":"x","object":"chat.completion.chu'],
                "stream-interrupted",
            ),
            ("closed without [DONE]", [first], "stream-interrupted"),
            (
                "oversized event",
                [first, b'data: {"pad":"' + b"x" * 70000 + b'"}\n\n'],
                "stream-limit",
            ),
        ]:
            with self.subTest(name):
                Provider.stream_lines = lines
                status, raw, _ = self.post(self.chat("frontier", stream=True), raw=True)
                self.assertEqual(status, 200)
                text = raw.decode()
                self.assertIn('"content":"Hel"', text)
                self.assertNotIn("xxxxxxxx", text)
                events = [line for line in text.split("\n") if line.startswith("data:")]
                self.assertEqual(events[-1], "data: [DONE]")
                final = json.loads(events[-2][5:])
                self.assertEqual(final["router"]["upstream_status"], 502)
                self.assertEqual(final["error"]["code"], code)

    def test_ipv6_loopback_listen(self):
        self.stop()
        self.config["router"]["listen"] = "[::1]:%d" % self.port
        self.save()
        self.host = "[::1]"
        self.start()
        health, _ = self.get("/v1/health")
        self.assertEqual(health["status"], "ok")

    def test_refusal_before_the_body_closes_the_connection(self):
        request = (
            "POST /v1/chat/completions HTTP/1.1\r\nHost: x\r\nOrigin: http://evil\r\n"
            "Content-Type: application/json\r\nContent-Length: 2\r\n\r\n{}"
        ).encode()
        with socket.create_connection(("127.0.0.1", self.port), timeout=5) as sock:
            sock.sendall(
                request + request
            )  # pipelined: the second must not be parsed from leftovers
            raw = b""
            while True:
                piece = sock.recv(65536)
                if not piece:
                    break
                raw += piece
        text = raw.decode()
        self.assertEqual(text.count("HTTP/1.1 "), 1)
        self.assertIn("HTTP/1.1 403", text)
        self.assertIn("connection: close", text.lower())
        self.assertEqual(Provider.requests, [])

    def raw_request(self, body=b"", extra=b""):
        head = (
            b"POST /v1/chat/completions HTTP/1.1\r\nHost: x\r\n"
            b"Content-Type: application/json\r\n" + extra
        )
        if body:
            head += b"Content-Length: " + str(len(body)).encode() + b"\r\n"
        return head + b"\r\n" + body

    @staticmethod
    def read_one(sock):
        """One HTTP response (status line, headers, body by Content-Length)."""
        raw = b""
        while b"\r\n\r\n" not in raw:
            piece = sock.recv(65536)
            if not piece:
                return raw
            raw += piece
        head, rest = raw.split(b"\r\n\r\n", 1)
        length = 0
        for line in head.split(b"\r\n"):
            if line.lower().startswith(b"content-length:"):
                length = int(line.split(b":", 1)[1])
        while len(rest) < length:
            piece = sock.recv(65536)
            if not piece:
                break
            rest += piece
        return head + b"\r\n\r\n" + rest[:length]

    def test_kept_alive_connection_answers_every_request(self):
        """An SDK reuses one connection: a failure after a success on it is
        still a full response, with that request's own disclosure."""
        ok = json.dumps(self.chat("frontier")).encode()
        with socket.create_connection(("127.0.0.1", self.port), timeout=5) as sock:
            sock.sendall(self.raw_request(ok))
            first = self.read_one(sock)
            self.assertIn(b"HTTP/1.1 200", first)
            self.assertIn(b"X-Router-Profile: frontier", first)
            sock.sendall(self.raw_request(json.dumps(self.chat("nope")).encode()))
            second = self.read_one(sock)
            self.assertIn(b"HTTP/1.1 404", second)
            self.assertIn(b"unknown-model", second)
            self.assertNotIn(b"X-Router-Profile", second)
            # a refusal before the body is read closes the connection
            sock.sendall(self.raw_request(b"{}", b"Origin: http://evil\r\n"))
            third = self.read_one(sock)
            self.assertIn(b"HTTP/1.1 403", third)
            self.assertIn(b"connection: close", third.lower())

    def test_single_eligible_profile_is_routed_not_refused(self):
        """The default is blocked and exactly one other profile fits: the
        decision still runs and lands on that profile."""
        self.config["profiles"]["mid"]["context"] = 100
        self.config["router"]["pool"] = ["small", "mid"]
        self.save()
        self.restart()
        Provider.reply = {
            "choices": [{"message": {"content": '{"difficulty": 1, "tags": []}'}}]
        }
        status, data, _ = self.post(self.chat("auto", "x" * 5000))
        self.assertEqual(status, 200, data)
        self.assertEqual(data["router"]["chosen"]["profile"], "small")
        self.assertIn(
            {"profile": "mid", "reason": "context too small"}, data["router"]["blocked"]
        )

    def test_non_latin1_model_id_still_gets_one_well_formed_response(self):
        self.config["profiles"]["frontier"]["model"] = "модель"
        self.save()
        self.restart()
        Provider.reply = {
            "model": "модель",
            "choices": [{"message": {"content": "ok"}}],
        }
        status, data, headers = self.post(self.chat("frontier"))
        self.assertEqual(status, 200, data)
        self.assertEqual(data["router"]["chosen"]["model"], "модель")
        self.assertFalse(data["router"]["mismatch"])
        self.assertEqual(
            headers["X-Router-Model"], "%D0%BC%D0%BE%D0%B4%D0%B5%D0%BB%D1%8C"
        )

    def test_allowed_origin_gets_cors_and_disclosure(self):
        self.config["router"]["allow_origins"] = ["http://localhost:5173"]
        self.save()
        self.restart()
        origin = {"Origin": "http://localhost:5173"}
        request = urllib.request.Request(
            self.url("/v1/chat/completions"), headers=origin, method="OPTIONS"
        )
        with urllib.request.urlopen(request, timeout=5) as response:
            self.assertEqual(response.status, 204)
            self.assertEqual(
                response.headers["Access-Control-Allow-Origin"], "http://localhost:5173"
            )
            self.assertIn("POST", response.headers["Access-Control-Allow-Methods"])
        status, data, headers = self.post(self.chat("frontier"), origin)
        self.assertEqual(status, 200, data)
        self.assertEqual(
            headers["Access-Control-Allow-Origin"], "http://localhost:5173"
        )
        self.assertIn("X-Router-Profile", headers["Access-Control-Expose-Headers"])
        status, data, _ = self.post(self.chat("frontier"), {"Origin": "http://other"})
        self.assertEqual((status, data["error"]["code"]), (403, "browser-denied"))

    def test_odd_provider_shapes_still_get_a_complete_answer(self):
        # usage with nulls in the final stream chunk: cost unknown, stream whole
        Provider.stream_lines = [
            b'data: {"choices":[{"delta":{"content":"Hi"}}]}\n\n',
            b'data: {"choices":[],"usage":{"prompt_tokens":null,"completion_tokens":"12"}}\n\n',
            b"data: [DONE]\n\n",
        ]
        status, raw, _ = self.post(self.chat("frontier", stream=True), raw=True)
        events = [line for line in raw.decode().split("\n") if line.startswith("data:")]
        self.assertEqual(events[-1], "data: [DONE]")
        final = json.loads(events[-2][5:])
        self.assertIsNone(final["router"]["cost_usd"])
        self.assertEqual(final["router"]["upstream_status"], 200)
        # malformed tools from the caller: routed, forwarded, answered
        Provider.stream_lines = None
        Provider.reply = {
            "choices": [{"message": {"content": '{"difficulty": 1, "tags": []}'}}],
            "usage": {"prompt_tokens": "300"},
        }
        status, data, _ = self.post(
            self.chat("auto", "Rename a variable. " * 40, tools=[{"function": "run"}])
        )
        self.assertEqual(status, 200, data)
        # tools are a deterministic pre-tag that raises the floor to mid
        self.assertEqual(data["router"]["chosen"]["profile"], "mid")
        self.assertEqual(data["router"]["signals"]["tags"]["tools"], 1.0)

    def test_profile_timeout_bounds_a_slow_non_stream_answer(self):
        class Slow(Provider):
            requests = []  # its late write must not land in the next test's record

            def do_POST(self):
                time.sleep(2)
                Provider.do_POST(self)

        slow = LoopbackServer(("127.0.0.1", 0), Slow)
        threading.Thread(target=slow.serve_forever, daemon=True).start()
        self.addCleanup(slow.server_close)
        self.addCleanup(slow.shutdown)
        self.config["profiles"]["frontier"]["base_url"] = (
            "http://127.0.0.1:%d/v1" % slow.server_address[1]
        )
        self.config["profiles"]["frontier"]["parameters"] = {"timeout": 1}
        self.save()
        self.restart()
        started = time.monotonic()
        status, data, headers = self.post(self.chat("frontier"))
        self.assertLess(time.monotonic() - started, 1.9)
        self.assertEqual(
            (status, data["error"]["code"], data["error"]["retryable"]),
            (504, "timeout", True),
        )
        self.assertEqual(headers["X-Router-Profile"], "frontier")

    def test_native_profile_is_bridged_through_delegation_run(self):
        self.install_fake_native_cli()
        self.restart()
        status, data, headers = self.post(self.chat("native", "Explain this function."))
        self.assertEqual(status, 200, data)
        self.assertEqual(
            data["choices"][0]["message"]["content"],
            "native answer to: Explain this function.",
        )
        self.assertEqual(data["object"], "chat.completion")
        self.assertEqual(headers["X-Router-Profile"], "native")
        run = data["router"]["delegation_run"]
        self.assertEqual(run["lane"], "clerk")  # the read-only role, not builder
        self.assertEqual(run["receipt"]["status"], "ready-for-integration")
        self.assertEqual(run["model_identity_source"], "provider-reported")
        self.assertFalse(data["router"]["mismatch"])
        self.assertIsNone(data["router"]["cost_usd"])  # a native CLI reports no usage
        captured = self.captured()
        self.assertEqual(captured["prompt"], "Explain this function.")
        self.assertEqual(
            captured["args"][captured["args"].index("--sandbox") + 1], "read-only"
        )
        self.assertEqual(
            captured["args"][captured["args"].index("--model") + 1], "native-model"
        )
        self.assertEqual(Provider.requests, [])
        # a conversation becomes a labelled transcript
        self.post(
            {
                "model": "native",
                "messages": [
                    {"role": "system", "content": "Be terse."},
                    {"role": "user", "content": "One"},
                    {"role": "assistant", "content": "Two"},
                    {"role": "user", "content": "Three"},
                ],
            }
        )
        self.assertEqual(
            self.captured()["prompt"],
            "[system]\nBe terse.\n\n[user]\nOne\n\n[assistant]\nTwo\n\n[user]\nThree",
        )

    def test_auto_can_choose_a_native_profile(self):
        self.install_fake_native_cli()
        self.restart()
        Provider.reply = {
            "choices": [{"message": {"content": '{"difficulty": 4, "tags": []}'}}]
        }
        status, data, _ = self.post(self.chat("auto", "Prove it. " * 40))
        self.assertEqual(status, 200, data)
        self.assertEqual(
            data["router"]["chosen"]["profile"], "native"
        )  # cheapest frontier
        self.assertEqual(data["router"]["delegation_run"]["lane"], "clerk")
        self.assertEqual(len(Provider.requests), 1)  # the decision only
        # tools, images or JSON output keep a native profile out of the running
        status, data, _ = self.post(
            self.chat(
                "native", "x", tools=[{"type": "function", "function": {"name": "f"}}]
            )
        )
        self.assertEqual((status, data["error"]["code"]), (400, "no-usable-candidate"))
        self.assertEqual(
            data["error"]["reason"], "native profile: no tools, images or JSON mode"
        )
        status, data, _ = self.post(
            self.chat(
                "auto", "Prove it. " * 40, response_format={"type": "json_object"}
            )
        )
        self.assertEqual(status, 200, data)
        self.assertEqual(data["router"]["chosen"]["profile"], "frontier")
        self.assertIn(
            {
                "profile": "native",
                "reason": "native profile: no tools, images or JSON mode",
            },
            data["router"]["blocked"],
        )

    def test_native_failures_are_mapped_from_the_dispatcher(self):
        self.install_fake_native_cli()
        self.config["profiles"]["native"]["parameters"] = {"timeout": 1}
        self.save()
        for name, env, status, code, retryable in [
            (
                "identity mismatch",
                {"DK_REPORTED": "other-model"},
                502,
                "provider-identity-mismatch",
                False,
            ),
            ("cli failure", {"DK_EXIT": "75"}, 502, "provider-unavailable", True),
            ("timeout", {"DK_SLEEP": "3"}, 504, "timeout", True),
        ]:
            with self.subTest(name):
                for key in ("DK_REPORTED", "DK_EXIT", "DK_SLEEP"):
                    self.env.pop(key, None)
                self.env.update(env)
                self.restart()
                got, data, headers = self.post(self.chat("native"))
                self.assertEqual(
                    (got, data["error"]["code"], data["error"]["retryable"]),
                    (status, code, retryable),
                )
                self.assertEqual(data["error"]["profile"], "native")
                self.assertEqual(headers["X-Router-Profile"], "native")

    def test_native_stream_is_one_event_then_the_router_chunk(self):
        self.install_fake_native_cli()
        self.restart()
        status, raw, headers = self.post(
            self.chat("native", "Hello there", stream=True), raw=True
        )
        self.assertEqual(status, 200)
        self.assertEqual(headers["Content-Type"], "text/event-stream")
        events = [
            json.loads(line[5:])
            for line in raw.decode().split("\n")
            if line.startswith("data:") and "[DONE]" not in line
        ]
        self.assertEqual(len(events), 2)
        self.assertEqual(
            events[0]["choices"][0]["delta"]["content"], "native answer to: Hello there"
        )
        self.assertEqual(events[1]["router"]["delegation_run"]["lane"], "clerk")
        self.assertEqual(events[1]["router"]["upstream_status"], 200)
        self.assertTrue(raw.decode().rstrip().endswith("data: [DONE]"))

    def test_receipts_record_decisions_without_prompt_text(self):
        self.config["router"]["receipts"] = True
        self.save()
        self.restart()
        secret = "SECRET PROMPT CONTENT 12345"
        status, _, _ = self.post(self.chat("frontier", secret))
        self.assertEqual(status, 200)
        path = self.base / "data/router/receipts.jsonl"
        self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        line = json.loads(path.read_text().splitlines()[-1])
        self.assertEqual((line["profile"], line["status"]), ("frontier", 200))
        self.assertNotIn(secret, path.read_text())
        self.config["router"]["receipts"] = False
        self.save()
        self.restart()
        self.post(self.chat("frontier", secret))
        self.assertEqual(len(path.read_text().splitlines()), 1)

    def test_server_prints_nothing_but_the_listening_line(self):
        Provider.status, Provider.reply = 500, {"error": "down"}
        self.post(self.chat("auto", "Rename a variable. " * 40))
        self.post(self.chat("nope"))
        self.stop()
        self.assertIn("listening on http://127.0.0.1:%d" % self.port, self.stdout)
        self.assertEqual(len(self.stdout.splitlines()), 1)
        self.assertEqual(self.stderr, "")
        self.assertNotIn("sk-canary", self.stdout)
