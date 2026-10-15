"""`delegation-router serve`: an OpenAI-compatible endpoint on loopback.

The user started it and declared pool, default and decider; the server
chooses only inside that pool, discloses the choice in every response, and
never retries, falls back or widens the pool. It logs nothing: not requests,
not errors, never a credential."""

import http.client
import json
import os
import re
import signal
import socket
import socketserver
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit

from delegation_config import ROUTER_HTTP_ADAPTERS, catalog, kit_version
from delegation_router import (
    DEFAULT_OUTPUT_TOKENS,
    count,
    credential_for,
    credential_required,
    data_home,
    endpoint_for,
    estimate_cost,
    native_lane,
    pool_meta,
)
from delegation_router_bridge import BridgeFailure, dispatch
from delegation_router_pipeline import explicit, route, router_block

MAX_BODY = 4 * 1024 * 1024
MAX_RESPONSE = 4 * 1024 * 1024
MAX_EVENT = 64 * 1024
READ_SIZE = 64 * 1024
CONNECT_TIMEOUT = 20
IDLE_TIMEOUT = 30  # between stream events; a non-stream answer is never cut
MAX_IN_FLIGHT = 16
EXPOSED_HEADERS = (
    "X-Router-Profile, X-Router-Model, X-Router-Tier, X-Router-Effort, "
    "X-Router-Decider, X-Router-Policy, X-Router-Difficulty, X-Router-Confidence, "
    "X-Router-Undecidable, X-Router-Latency-Ms, X-Router-Mode, "
    "X-Router-Model-Mismatch, X-Router-Error, Retry-After"
)
KEY_SHAPED = re.compile(r"\b(?:sk-[A-Za-z0-9_-]{8,}|[A-Za-z0-9_-]{32,})\b")


def redact(text):
    return KEY_SHAPED.sub("[redacted]", str(text))[:500]


class RouterFailure(Exception):
    def __init__(self, status, code, retryable=False, **extra):
        super().__init__(code)
        self.status = status
        self.code = code
        self.retryable = retryable
        self.extra = extra


def map_upstream_error(status, raw, headers):
    """Provider failures keep their meaning, lose their payload."""
    message = ""
    try:
        parsed = json.loads(raw)
        error = parsed.get("error") if isinstance(parsed, dict) else None
        if isinstance(error, dict):
            message = str(error.get("message") or error.get("code") or "")
        elif isinstance(error, str):
            message = error
    except (ValueError, AttributeError):
        message = ""
    if status in (401, 403):
        return RouterFailure(401, "provider-key-rejected")
    if status == 429:
        extra = {}
        retry_after = headers.get("Retry-After")
        if retry_after and re.fullmatch(r"[0-9]{1,6}", retry_after.strip()):
            extra["retry_after"] = retry_after.strip()
        return RouterFailure(429, "provider-rate-limited", True, **extra)
    if 500 <= status <= 599:
        return RouterFailure(502, "provider-unavailable", True)
    return RouterFailure(
        status if 400 <= status <= 499 else 502,
        "provider-rejected-request",
        False,
        message=redact(message) if message else None,
    )


def upstream_body(body, profile, choice, stream):
    out = {k: v for k, v in body.items() if k != "router"}
    out["model"] = profile["model"]
    out["stream"] = bool(stream)
    if stream:
        options = (
            out.get("stream_options")
            if isinstance(out.get("stream_options"), dict)
            else {}
        )
        out["stream_options"] = dict(options, include_usage=True)
    params = profile.get("parameters", {})
    if "max_tokens" in params and not (
        out.get("max_tokens") or out.get("max_completion_tokens")
    ):
        out["max_tokens"] = params["max_tokens"]
    effort = choice.get("reasoning_effort") or params.get("effort")
    if profile["adapter"] == "deepseek-api":
        # The runner always enables thinking; here the caller may have said
        # otherwise, and the caller's own request wins.
        out.setdefault("thinking", {"type": "enabled"})
        if effort:
            out["reasoning_effort"] = effort
    elif profile["adapter"] == "token-plan-openai" and effort:
        out["reasoning_effort"] = effort
    return out


def disclosure_headers(out):
    chosen = out["chosen"]
    decider = out["decider"]
    signals = out["signals"]
    pairs = [
        ("X-Router-Profile", chosen["profile"]),
        ("X-Router-Model", chosen["model"]),
        ("X-Router-Tier", chosen.get("tier")),
        ("X-Router-Effort", chosen.get("reasoning_effort")),
        ("X-Router-Decider", "%s/%s" % (decider.get("id"), decider.get("version"))),
        ("X-Router-Policy", "%s/%s" % (out["policy"]["id"], out["policy"]["version"])),
        ("X-Router-Difficulty", signals.get("difficulty")),
        ("X-Router-Confidence", signals.get("confidence")),
        ("X-Router-Undecidable", "1" if out["undecidable"] else "0"),
        ("X-Router-Latency-Ms", out.get("decision_latency_ms")),
        ("X-Router-Mode", out.get("mode")),
    ]
    return [(k, str(v)) for k, v in pairs if v is not None]


class RouterServer(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    def __init__(self, address, config, env=None):
        if ":" in address[0]:
            self.address_family = socket.AF_INET6
        super().__init__(address, Handler)
        self.config = config
        self.env = os.environ if env is None else env
        self.in_flight = threading.BoundedSemaphore(MAX_IN_FLIGHT)
        self.receipts_lock = threading.Lock()
        self.started = time.time()
        self.catalog = catalog()
        self.pool = {m["profile"]: m for m in pool_meta(config, self.catalog)}

    def server_bind(self):
        # http.server resolves the bound address back to a name on every bind
        # (socket.getfqdn): a reverse-DNS lookup that stalls for seconds on a
        # host with a slow resolver. A loopback server has no use for a name.
        socketserver.TCPServer.server_bind(self)
        self.server_name = self.server_address[0]
        self.server_port = self.server_address[1]

    def handle_error(self, request, client_address):
        # socketserver would print a traceback to stderr; this server never
        # writes about a request.
        pass


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "delegation-router"
    sys_version = ""

    def log_message(self, *args):
        pass

    def version_string(self):
        return self.server_version

    # ---- plumbing ------------------------------------------------------------

    def setup(self):
        super().setup()
        self.body_consumed = False
        self.headers_sent = False
        # Set once a choice is made, so a failure after it still discloses it.
        self.router_headers = ()

    def allowed_origin(self):
        origin = self.headers.get("Origin")
        allowed = self.server.config["router"].get("allow_origins", [])
        return origin if origin and origin in allowed else None

    def cors_headers(self):
        origin = self.allowed_origin()
        if not origin:
            return []
        return [
            ("Access-Control-Allow-Origin", origin),
            ("Access-Control-Expose-Headers", EXPOSED_HEADERS),
            ("Vary", "Origin"),
        ]

    def start_response(self, status, headers):
        self.send_response(status)
        for key, value in list(headers) + self.cors_headers():
            self.send_header(key, value)
        if self.close_connection:
            self.send_header("Connection", "close")
        self.end_headers()
        self.headers_sent = True

    def send_json(self, status, payload, headers=()):
        data = json.dumps(payload).encode()
        self.start_response(
            status,
            [
                ("Content-Type", "application/json"),
                ("Content-Length", str(len(data))),
                ("Cache-Control", "no-store"),
                *headers,
            ],
        )
        self.wfile.write(data)

    def fail(self, failure, headers=()):
        if not self.body_consumed:
            # Whatever is left of the request would be parsed as the next one.
            self.close_connection = True
        error = {"code": failure.code, "retryable": failure.retryable}
        error.update({k: v for k, v in failure.extra.items() if v is not None})
        extra = list(headers) + [("X-Router-Error", failure.code)]
        if "retry_after" in failure.extra:
            extra.append(("Retry-After", failure.extra["retry_after"]))
        self.send_json(failure.status, {"error": error}, extra)

    def read_body(self):
        length = self.headers.get("Content-Length")
        if not length or not re.fullmatch(r"[0-9]{1,9}", length):
            raise RouterFailure(411, "length-required")
        if int(length) > MAX_BODY:
            raise RouterFailure(413, "size-limit")
        raw = self.rfile.read(int(length))
        self.body_consumed = True
        try:
            body = json.loads(raw)
        except ValueError:
            raise RouterFailure(400, "invalid-json")
        if not isinstance(body, dict) or not isinstance(body.get("messages"), list):
            raise RouterFailure(400, "invalid-request")
        return body

    def check_origin(self):
        if self.headers.get("Origin") and not self.allowed_origin():
            raise RouterFailure(403, "browser-denied")

    # ---- OPTIONS (CORS preflight for an allow-listed origin) ------------------

    def do_OPTIONS(self):
        self.body_consumed = True  # a preflight carries no body
        if not self.allowed_origin():
            return self.fail(RouterFailure(403, "browser-denied"))
        self.start_response(
            204,
            [
                ("Access-Control-Allow-Methods", "GET, POST, OPTIONS"),
                (
                    "Access-Control-Allow-Headers",
                    "Content-Type, Authorization, X-Router-Max-Cost-USD",
                ),
                ("Access-Control-Max-Age", "600"),
                ("Content-Length", "0"),
            ],
        )

    # ---- GET -----------------------------------------------------------------

    def do_GET(self):
        self.body_consumed = True  # a GET body, if any, is not read: close after
        self.close_connection = True
        r = self.server.config["router"]
        if self.path == "/v1/health":
            self.send_json(
                200,
                {
                    "status": "ok",
                    "version": kit_version(),
                    "mode": r.get("mode", "route"),
                    "uptime_s": int(time.time() - self.server.started),
                },
            )
        elif self.path == "/v1/models":
            data = [
                {
                    "id": m["profile"],
                    "object": "model",
                    "owned_by": m["adapter"],
                    "router": {
                        "model": m["model"],
                        "tier": m["tier"],
                        "price": m["price"],
                    },
                }
                for m in self.server.pool.values()
            ]
            data.append(
                {"id": "auto", "object": "model", "owned_by": "delegation-router"}
            )
            self.send_json(200, {"object": "list", "data": data})
        else:
            self.fail(RouterFailure(404, "not-found"))

    # ---- POST ----------------------------------------------------------------

    def do_POST(self):
        if self.path != "/v1/chat/completions":
            return self.fail(RouterFailure(404, "not-found"))
        admitted = False
        try:
            self.check_origin()
            body = self.read_body()
            if not self.server.in_flight.acquire(blocking=False):
                raise RouterFailure(429, "busy", True)
            admitted = True
            self.handle_chat(body)
        except RouterFailure as failure:
            self.respond_failure(failure, self.router_headers)
        except Exception:  # noqa: BLE001 — never log: it may carry request details
            self.respond_failure(RouterFailure(502, "router-unavailable"))
        finally:
            if admitted:
                self.server.in_flight.release()

    def respond_failure(self, failure, headers=()):
        if self.headers_sent:
            # A status line inside a body would corrupt the stream: just end it.
            self.close_connection = True
            return
        try:
            self.fail(failure, headers)
        except OSError:
            pass

    def handle_chat(self, body):
        c = self.server.config
        r = router_block(c)
        ceiling = r.get("max_cost_usd")
        header_ceiling = self.headers.get("X-Router-Max-Cost-USD")
        if header_ceiling:
            if not re.fullmatch(r"[0-9]+(\.[0-9]+)?", header_ceiling.strip()):
                raise RouterFailure(400, "invalid-cost-ceiling")
            ceiling = float(header_ceiling)
            if not 0 < ceiling <= 1000:
                raise RouterFailure(400, "invalid-cost-ceiling")
        model = body.get("model")
        started = time.monotonic()
        if model == "auto":
            out, choice, feats, blocked = route(
                c, body, ceiling=ceiling, env=self.server.env
            )
        elif isinstance(model, str) and model in r["pool"]:
            out, choice, feats, blocked = explicit(c, model, body, ceiling=ceiling)
        else:
            raise RouterFailure(404, "unknown-model")
        for item in blocked:
            if item["profile"] == choice["profile"]:
                if item["reason"] == "estimated cost above ceiling":
                    meta = self.server.pool[choice["profile"]]
                    estimated = estimate_cost(
                        meta,
                        feats["est_tokens"],
                        feats["max_tokens"] or DEFAULT_OUTPUT_TOKENS,
                    )
                    raise RouterFailure(
                        400,
                        "cost-ceiling",
                        estimated_usd=round(estimated, 6)
                        if estimated is not None
                        else None,
                        ceiling_usd=ceiling,
                    )
                raise RouterFailure(400, "no-usable-candidate", reason=item["reason"])
        profile = c["profiles"][choice["profile"]]
        stream = bool(body.get("stream"))
        meta = self.server.pool[choice["profile"]]
        extra_headers = disclosure_headers(out)
        self.router_headers = extra_headers
        if profile["adapter"] not in ROUTER_HTTP_ADAPTERS:
            return self.relay_native(
                body, out, meta, profile, choice, extra_headers, started, stream
            )
        token = credential_for(profile, self.server.env)
        if credential_required(profile) and not token:
            raise RouterFailure(401, "provider-key-missing", profile=choice["profile"])
        payload = json.dumps(upstream_body(body, profile, choice, stream)).encode()
        headers = {
            "Content-Type": "application/json",
            "Accept": "text/event-stream" if stream else "application/json",
        }
        if token:
            headers["Authorization"] = "Bearer " + token
        total = profile.get("parameters", {}).get("timeout")
        deadline = time.monotonic() + total if total else None
        url = urlsplit(endpoint_for(profile))
        connection = (
            http.client.HTTPSConnection
            if url.scheme == "https"
            else http.client.HTTPConnection
        )(url.hostname, url.port, timeout=CONNECT_TIMEOUT)
        try:
            try:
                connection.connect()
                # The connect timeout has done its job; from here the only
                # limits are the profile's deadline and, when streaming, the
                # idle limit between events. A slow answer is not a failure.
                # Keep the socket: http.client forgets it once a provider
                # answers with Connection: close, while the response still
                # reads from it.
                sock = connection.sock
                sock.settimeout(
                    self.wait_limit(deadline, IDLE_TIMEOUT if stream else None)
                )
                connection.request(
                    "POST", url.path or "/", body=payload, headers=headers
                )
                response = connection.getresponse()
            except socket.timeout:
                raise RouterFailure(
                    504 if deadline else 502,
                    "timeout" if deadline else "provider-unavailable",
                    True,
                    profile=choice["profile"],
                )
            except (OSError, http.client.HTTPException):
                raise RouterFailure(
                    502, "provider-unavailable", True, profile=choice["profile"]
                )
            if response.status != 200:
                raw = self.read_bounded(response, sock, deadline, out)
                failure = map_upstream_error(response.status, raw, response.headers)
                failure.extra["profile"] = choice["profile"]
                raise failure
            relay = self.relay_stream if stream else self.relay_json
            relay(response, sock, out, meta, profile, extra_headers, started, deadline)
        finally:
            connection.close()

    # ---- native profiles: one delegation-run per request ------------------------

    def relay_native(self, body, out, meta, profile, choice, headers, started, stream):
        """A native adapter answers through the kit's dispatcher. Non-stream by
        nature: a stream request gets the whole answer as one event."""
        key = choice["profile"]
        lane = native_lane(profile)
        if lane is None:
            raise RouterFailure(
                400, "no-usable-candidate", profile=key, reason="no routable role"
            )
        out["delegation_run"] = {"lane": lane}
        if stream:
            self.start_response(
                200,
                [
                    ("Content-Type", "text/event-stream"),
                    ("Cache-Control", "no-store"),
                    ("Transfer-Encoding", "chunked"),
                    *headers,
                ],
            )
        try:
            answer = dispatch(key, body, lane, self.server.env)
        except BridgeFailure as failure:
            out["delegation_run"].update(
                {k: v for k, v in failure.extra.items() if v is not None}
            )
            if not stream:
                raise RouterFailure(
                    failure.status,
                    failure.code,
                    failure.retryable,
                    profile=key,
                    **{k: v for k, v in failure.extra.items() if v is not None},
                )
            self.settle(out, meta, profile, {}, None, started, 502)
            self.end_stream(out, profile, failure.code, failure.retryable)
            return
        self.settle(
            out, meta, profile, answer["usage"], answer["reported"], started, 200
        )
        if answer["cost_usd"] is not None:
            out["cost_usd"] = answer["cost_usd"]
        out["delegation_run"].update(
            {
                "exit_code": 0,
                "duration_ms": answer["duration_ms"],
                "model_identity_source": answer["identity_source"],
                "receipt": answer["receipt"],
            }
        )
        completion_id = "chatcmpl-router-" + uuid.uuid4().hex[:12]
        if stream:
            chunk = {
                "id": completion_id,
                "object": "chat.completion.chunk",
                "created": int(time.time()),
                "model": profile["model"],
                "choices": [
                    {
                        "index": 0,
                        "delta": {"role": "assistant", "content": answer["content"]},
                        "finish_reason": "stop",
                    }
                ],
            }
            try:
                self.write_chunk(b"data: " + json.dumps(chunk).encode() + b"\n\n")
            except OSError:
                return
            self.end_stream(out, profile, None, False)
            return
        completion = {
            "id": completion_id,
            "object": "chat.completion",
            "created": int(time.time()),
            "model": profile["model"],
            "choices": [
                {
                    "index": 0,
                    "message": {"role": "assistant", "content": answer["content"]},
                    "finish_reason": "stop",
                }
            ],
            "router": out,
        }
        if out.get("usage"):
            completion["usage"] = {
                "prompt_tokens": out["usage"].get("prompt_tokens") or 0,
                "completion_tokens": out["usage"].get("completion_tokens") or 0,
            }
        extra = list(headers)
        if out["mismatch"]:
            extra.append(("X-Router-Model-Mismatch", "1"))
        self.send_json(200, completion, extra)

    def end_stream(self, out, profile, failure, retryable):
        """The closing router chunk, [DONE] and the chunked terminator."""
        final = {
            "id": "chatcmpl-router",
            "object": "chat.completion.chunk",
            "created": int(time.time()),
            "model": profile["model"],
            "choices": [],
            "router": out,
        }
        if failure:
            final["error"] = {"code": failure, "retryable": retryable}
        try:
            self.write_chunk(b"data: " + json.dumps(final).encode() + b"\n\n")
            self.write_chunk(b"data: [DONE]\n\n")
            self.wfile.write(b"0\r\n\r\n")
            self.wfile.flush()
        except OSError:
            pass

    # ---- relays --------------------------------------------------------------

    @staticmethod
    def wait_limit(deadline, idle):
        """Socket timeout for the next wait: the smaller of the idle limit and
        what is left of the profile's deadline; None when neither applies."""
        remaining = (
            None if deadline is None else max(deadline - time.monotonic(), 0.001)
        )
        if idle is None:
            return remaining
        return idle if remaining is None else min(idle, remaining)

    def read_bounded(self, response, sock, deadline, out):
        """Read a whole non-stream body within the size cap and the deadline."""
        chunks, size = [], 0
        while True:
            if deadline is not None and time.monotonic() > deadline:
                raise RouterFailure(
                    504, "timeout", True, profile=out["chosen"]["profile"]
                )
            sock.settimeout(self.wait_limit(deadline, None))
            try:
                piece = response.read(READ_SIZE)
            except socket.timeout:
                raise RouterFailure(
                    504, "timeout", True, profile=out["chosen"]["profile"]
                )
            except (OSError, http.client.HTTPException):
                raise RouterFailure(
                    502, "upstream-interrupted", True, profile=out["chosen"]["profile"]
                )
            if not piece:
                return b"".join(chunks)
            size += len(piece)
            if size > MAX_RESPONSE:
                raise RouterFailure(
                    502, "upstream-too-large", profile=out["chosen"]["profile"]
                )
            chunks.append(piece)

    def settle(self, out, meta, profile, usage, reported, started, status):
        usage = {k: count(v) for k, v in usage.items()} if usage else {}
        out["usage"] = usage
        cost = estimate_cost(
            meta, usage.get("prompt_tokens"), usage.get("completion_tokens")
        )
        out["cost_usd"] = None if cost is None else round(cost, 8)
        out["provider_reported_model"] = reported
        out["mismatch"] = bool(
            reported
            and reported != profile["model"]
            and reported not in profile.get("aliases", [])
        )
        out["latency_ms"] = int((time.monotonic() - started) * 1000)
        out["upstream_status"] = status
        self.write_receipt(out)
        return out

    def relay_json(
        self, response, sock, out, meta, profile, headers, started, deadline
    ):
        raw = self.read_bounded(response, sock, deadline, out)
        try:
            data = json.loads(raw)
            if not isinstance(data, dict):
                raise ValueError
        except ValueError:
            raise RouterFailure(
                502, "upstream-format", profile=out["chosen"]["profile"]
            )
        usage = data.get("usage") if isinstance(data.get("usage"), dict) else {}
        reported = data.get("model") if isinstance(data.get("model"), str) else None
        self.settle(out, meta, profile, usage, reported, started, 200)
        data["router"] = out
        extra = list(headers)
        if out["mismatch"]:
            extra.append(("X-Router-Model-Mismatch", "1"))
        self.send_json(200, data, extra)

    def relay_stream(
        self, response, sock, out, meta, profile, headers, started, deadline
    ):
        self.start_response(
            200,
            [
                ("Content-Type", "text/event-stream"),
                ("Cache-Control", "no-store"),
                ("Transfer-Encoding", "chunked"),
                *headers,
            ],
        )
        usage = {}
        reported = None
        done = False
        failure = None
        last = b"\n"
        while True:
            if deadline and time.monotonic() > deadline:
                failure = "timeout"
                break
            try:
                sock.settimeout(self.wait_limit(deadline, IDLE_TIMEOUT))
                line = response.readline(MAX_EVENT + 1)
            except socket.timeout:
                failure = (
                    "timeout"
                    if deadline and time.monotonic() > deadline
                    else "stream-idle"
                )
                break
            except (OSError, http.client.HTTPException):
                failure = "stream-interrupted"
                break
            if not line:
                # EOF before [DONE]: the provider closed the stream early.
                failure = "stream-interrupted"
                break
            if len(line) > MAX_EVENT:
                failure = "stream-limit"
                break
            if not line.endswith(b"\n"):
                # EOF inside an event: the partial line is not forwarded.
                failure = "stream-interrupted"
                break
            stripped = line.strip()
            if stripped.startswith(b"data:"):
                payload = stripped[5:].strip()
                if payload == b"[DONE]":
                    done = True
                    break
                try:
                    chunk = json.loads(payload)
                    if isinstance(chunk, dict):
                        if isinstance(chunk.get("usage"), dict):
                            usage = chunk["usage"]
                        if isinstance(chunk.get("model"), str) and not reported:
                            reported = chunk["model"]
                except ValueError:
                    pass
            try:
                self.write_chunk(line)
                last = line
            except OSError:
                return
        status = 200 if done else 502
        self.settle(out, meta, profile, usage, reported, started, status)
        if last.strip():
            try:
                self.write_chunk(b"\n")
            except OSError:
                return
        self.end_stream(out, profile, failure, failure != "stream-limit")

    def write_chunk(self, data):
        self.wfile.write(("%x\r\n" % len(data)).encode() + data + b"\r\n")
        self.wfile.flush()

    def write_receipt(self, out):
        if not self.server.config["router"].get("receipts"):
            return
        line = {
            "ts": int(time.time()),
            "mode": out.get("mode"),
            "profile": out["chosen"]["profile"],
            "model": out["chosen"]["model"],
            "tier": out["chosen"].get("tier"),
            "decider": out["decider"].get("id"),
            "decider_version": out["decider"].get("version"),
            "difficulty": out["signals"].get("difficulty"),
            "tags": out["signals"].get("tags"),
            "undecidable": out["undecidable"],
            "usage": out.get("usage"),
            "cost_usd": out.get("cost_usd"),
            "decision_cost_usd": out.get("decision_cost_usd"),
            "latency_ms": out.get("latency_ms"),
            "status": out.get("upstream_status"),
        }
        path = data_home() / "router" / "receipts.jsonl"
        try:
            with self.server.receipts_lock:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.parent.chmod(0o700)
                with open(path, "a") as f:
                    f.write(json.dumps(line) + "\n")
                os.chmod(path, 0o600)
        except OSError:
            pass


def serve(config, listen=None, env=None):
    r = router_block(config)
    listen = listen or r.get("listen", "127.0.0.1:4141")
    host, port = listen.rsplit(":", 1)
    host = host.strip("[]")
    server = RouterServer((host, int(port)), config, env)

    def stop(*_):
        threading.Thread(target=server.shutdown, daemon=True).start()

    signal.signal(signal.SIGINT, stop)
    signal.signal(signal.SIGTERM, stop)
    print(
        "delegation-router: decider %s governs %s (default %s) — listening on http://%s:%d, mode %s"
        % (
            r["decider"]["kind"],
            ",".join(r["pool"]),
            r["default"],
            host,
            server.server_address[1],
            r.get("mode", "route"),
        ),
        flush=True,
    )
    try:
        server.serve_forever()
    finally:
        server.server_close()
    return 0
