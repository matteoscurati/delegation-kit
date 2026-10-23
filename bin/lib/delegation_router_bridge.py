"""Native profiles in the router pool: one `delegation-run` per request.

A profile on a native adapter (codex, claude-code, claude-zai, kimi-code-cli,
grok-build-cli, agy) has no chat-completions endpoint. The router renders the
conversation as a prompt file, runs the kit's own dispatcher on a read-only
role in an empty temporary workdir, and turns the answer file back into one
chat completion. Every limit the dispatcher enforces — the profile's
`timeout`, identity checks, OAuth locks, sandboxes — stays where it is: the
bridge reads the receipt, it does not reimplement the runner.

A dispatch outlives nothing that asked for it. The dispatcher runs in a
process group of its own; when the client hangs up or `serve` stops, the
whole group — dispatcher, runner, the CLI it started — is asked to stop and,
after STOP_GRACE seconds, killed."""

import json
import os
import shutil
import signal
import subprocess
import tempfile
import threading
import time
from pathlib import Path

from delegation_config import ROOT
from delegation_router_policy import count

# Roles in the order a chat gateway prefers them: analysis first, never a
# worktree edit when a read-only role exists. The profile must declare the
# role and the adapter must support it.
LANE_PREFERENCE = (
    "clerk",
    "scout",
    "reviewer",
    "judgement",
    "senior",
    "policy-annotation",
    "routine-review",
    "material-review",
    "security",
    "builder",
    "frontend-builder",
)


STOP_GRACE = 10  # seconds a stopped dispatch gets to clean up (locks, temp homes)
POLL = 0.5  # seconds between checks that the request still wants an answer
# Dispatches in flight, so a stopping server can end the ones its request
# threads have not ended yet.
RUNNING = set()
RUNNING_LOCK = threading.Lock()


class BridgeFailure(Exception):
    def __init__(self, status, code, retryable=False, **extra):
        super().__init__(code)
        self.status = status
        self.code = code
        self.retryable = retryable
        self.extra = extra


def transcript(body):
    """The conversation as one prompt. A single user turn is passed verbatim;
    anything else becomes a role-labelled transcript. Images are not text and
    tools are refused before this point."""
    from delegation_router_policy import text_of

    messages = [m for m in body.get("messages", []) if isinstance(m, dict)]
    if len(messages) == 1 and messages[0].get("role") == "user":
        return text_of(messages[0].get("content"))
    parts = []
    for m in messages:
        role = str(m.get("role", "user"))
        parts.append("[" + role + "]\n" + text_of(m.get("content")))
    return "\n\n".join(parts)


def failure_for(rc, error):
    """Map a dispatcher exit code and its sanitized diagnostic to a gateway
    error. The diagnostic never carries provider payloads; its `reason` does."""
    reason = str((error or {}).get("reason") or "")
    if rc == 75:
        if reason == "timeout":
            return BridgeFailure(504, "timeout", True)
        if "lock" in reason or "rate" in reason:
            return BridgeFailure(429, "provider-rate-limited", True, reason=reason)
        return BridgeFailure(502, "provider-unavailable", True, reason=reason)
    if rc == 69:
        if reason == "missing_credentials":
            return BridgeFailure(401, "provider-key-missing")
        return BridgeFailure(502, "provider-unavailable", False, reason=reason)
    if rc == 70:
        if reason == "provider_identity_mismatch":
            return BridgeFailure(502, "provider-identity-mismatch")
        return BridgeFailure(502, "provider-failed", False, reason=reason)
    if rc == 78:
        return BridgeFailure(
            400, "no-usable-candidate", reason="role or effort unsupported"
        )
    if rc == 130:
        return BridgeFailure(502, "provider-interrupted", True)
    return BridgeFailure(
        502, "bridge-failed", False, exit_code=rc, reason=reason or None
    )


def _group_alive(pgid):
    try:
        os.killpg(pgid, 0)
        return True
    except (ProcessLookupError, PermissionError):
        return False


def end(procs, grace=STOP_GRACE):
    """SIGTERM to each dispatcher's process group, SIGKILL to whatever is
    left of them after `grace` seconds. The leaders are reaped as they go, so
    a group that is gone is not kept alive by its own zombie."""
    for proc in procs:
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except (ProcessLookupError, PermissionError):
            pass
    deadline = time.monotonic() + grace
    while time.monotonic() < deadline:
        for proc in procs:
            proc.poll()
        if not any(_group_alive(proc.pid) for proc in procs):
            return
        time.sleep(0.1)
    for proc in procs:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except (ProcessLookupError, PermissionError):
            pass
        proc.wait()


def end_all(grace=STOP_GRACE):
    """End every dispatch still in flight: `serve` is stopping."""
    with RUNNING_LOCK:
        procs = list(RUNNING)
    if procs:
        end(procs, grace)


def _run(command, env, cwd, stop):
    """The dispatcher's exit code, or the reason `stop` gave for ending it
    (a client that hung up, a server that is stopping)."""
    proc = subprocess.Popen(
        command,
        env=env,
        cwd=cwd,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    with RUNNING_LOCK:
        RUNNING.add(proc)
    try:
        while True:
            try:
                return proc.wait(timeout=POLL), None
            except subprocess.TimeoutExpired:
                pass
            reason = stop() if stop else None
            if reason:
                end([proc])
                return proc.returncode, reason
    finally:
        with RUNNING_LOCK:
            RUNNING.discard(proc)


def dispatch(profile_key, body, lane, env, stop=None):
    """Run the profile once through `delegation-run`; return the answer and
    what the receipt says about it. Raises BridgeFailure. `stop` is asked
    every POLL seconds whether the answer is still wanted: it returns why
    not (`client-gone`, `router-stopping`) or None."""
    started = time.monotonic()
    tmp = Path(tempfile.mkdtemp(prefix="delegation-router-"))
    try:
        os.chmod(tmp, 0o700)
        prompt = tmp / "prompt.txt"
        prompt.write_text(transcript(body))
        os.chmod(prompt, 0o600)
        workdir = tmp / "work"
        workdir.mkdir(mode=0o700)
        output = tmp / "answer"
        command = [
            str(ROOT / "bin/delegation-run"),
            "--profile",
            profile_key,
            "--lane",
            lane,
            "--prompt-file",
            str(prompt),
            "--output",
            str(output),
            "--workdir",
            str(workdir),
        ]
        try:
            # No deadline here: the dispatcher applies the profile's own and
            # reports it as exit 75 with reason `timeout`.
            returncode, stopped = _run(command, env, str(tmp), stop)
        except OSError:
            raise BridgeFailure(
                502, "bridge-failed", False, reason="dispatcher not runnable"
            )
        duration_ms = int((time.monotonic() - started) * 1000)
        if stopped:
            raise BridgeFailure(
                503 if stopped == "router-stopping" else 499,
                stopped,
                stopped == "router-stopping",
                duration_ms=duration_ms,
            )
        if returncode != 0:
            error = _read_json(Path(str(output) + ".error.json"))
            failure = failure_for(returncode, error)
            failure.extra["duration_ms"] = duration_ms
            raise failure
        try:
            content = output.read_text()
        except OSError:
            raise BridgeFailure(502, "bridge-failed", False, reason="no answer file")
        metrics = _read_json(Path(str(output) + ".metrics.json")) or {}
        receipt = _read_json(Path(str(output) + ".result.json")) or {}
        tokens = (
            metrics.get("tokens") if isinstance(metrics.get("tokens"), dict) else {}
        )
        # Counts are relayed unless the runner says it has none
        # (`usage_reported: false`, Kimi) or they are all zero: no runner
        # writes `usage_reported: true`, it is the absence of a denial.
        usage = {}
        if metrics.get("usage_reported", True) and any(
            (count(tokens.get(k)) or 0) > 0 for k in ("input", "output")
        ):
            usage = {
                "prompt_tokens": tokens.get("input"),
                "completion_tokens": tokens.get("output"),
            }
        cost = metrics.get("provider_cost_usd")
        if metrics.get("subscription_backend"):
            cost = None  # a subscription seat has no per-call price
        return {
            "content": content,
            "usage": usage,
            "cost_usd": cost if isinstance(cost, (int, float)) and cost > 0 else None,
            "reported": metrics.get("provider_reported_model"),
            "identity_source": metrics.get("model_identity_source"),
            "receipt": {
                k: receipt.get(k)
                for k in ("review_policy", "review_status", "status", "dispatch_status")
            },
            "exit_code": 0,
            "duration_ms": duration_ms,
        }
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def _read_json(path):
    try:
        data = json.loads(path.read_text())
        return data if isinstance(data, dict) else None
    except (OSError, ValueError):
        return None
