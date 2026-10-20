"""Where a profile's credential and endpoint come from.

Profiles never hold a key: `credential_env` names a variable. A variable
comes from the environment, else from the personal `.env` beside the
configuration file, else — for the adapters that have one — from the kit's
own key file under the data home. Every file is NAME=value lines, parsed and
never sourced, and ignored when it is a symlink or readable by group or
others."""

import json
import os
import re
import shutil
import subprocess
from concurrent.futures import ThreadPoolExecutor

from delegation_config import (
    ADAPTERS,
    ROOT,
    ROUTER_HTTP_ADAPTERS,
    config_path,
    data_home,
)


ENDPOINTS = {
    "deepseek-api": "https://api.deepseek.com/v1/chat/completions",
    "token-plan-openai": "https://token-plan.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1/chat/completions",
}


KEY_FILES = {
    "deepseek-api": ("deepseek.env", "DEEPSEEK_API_KEY"),
    "token-plan-openai": ("qwen-token-plan.env", "QWEN_TOKEN_PLAN_API_KEY"),
}
# The adapters the server forwards a per-request `reasoning_effort` to. An
# openai-compatible endpoint takes none, and a bridged native profile runs at
# its own setting; the policy discloses an effort only where it is applied.


ENV_LINE = re.compile(r"\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$")


def env_values(path):
    """The NAME=value pairs of one key file, first spelling of a name wins;
    {} when the file is absent, a symlink, or readable by group or others.
    Lines are parsed, never executed; an empty value is no value."""
    try:
        if path.is_symlink() or not path.is_file():
            return {}
        if path.stat().st_mode & 0o077:
            return {}
        values = {}
        for line in path.read_text().splitlines():
            m = ENV_LINE.match(line)
            if not m or m.group(1) in values:
                continue
            value = m.group(2).strip()
            if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
                value = value[1:-1]
            if value:
                values[m.group(1)] = value
        return values
    except OSError:
        return {}


def key_from_file(path, var):
    return env_values(path).get(var)


def env_file():
    """The personal `.env`, beside the configuration file. Never one in a
    project: a key in a worktree is one `git add` away from a commit."""
    return config_path().parent / ".env"


def load_env_file(environ=None):
    """Fill the environment from the personal `.env`; a variable that is
    already set wins. Returns the names it set (never their values)."""
    environ = os.environ if environ is None else environ
    loaded = []
    for name, value in env_values(env_file()).items():
        if not environ.get(name):
            environ[name] = value
            loaded.append(name)
    return loaded


def credential_for(profile, env=None):
    """The bearer token for an HTTP profile, by variable name or kit key file;
    None when the profile needs none (local endpoints) or none is available."""
    env = os.environ if env is None else env
    adapter = profile["adapter"]
    if "credential_env" in profile:
        return env.get(profile["credential_env"]) or None
    if adapter in KEY_FILES:
        filename, var = KEY_FILES[adapter]
        return env.get(var) or key_from_file(data_home() / "config" / filename, var)
    return None


def endpoint_for(profile):
    if profile["adapter"] == "openai-compatible":
        return profile["base_url"].rstrip("/") + "/chat/completions"
    return ENDPOINTS[profile["adapter"]]


def credential_required(profile):
    return profile["adapter"] != "openai-compatible" or "credential_env" in profile


# The native adapters the kit drives without a runner of its own: the CLI on
# PATH is all that can be checked without a model call.
NATIVE_BINARIES = {"codex": "codex", "claude-code": "claude"}


RUNNER_CHECK_TIMEOUT = 20


def unreachable(profile, env=None):
    """Why this machine cannot dispatch the profile right now, or None.

    Read-only and without a model call: the key for an HTTP profile, the
    named variable `delegation-run` requires, `<runner> check --json` for a
    native runner, the CLI on PATH for codex and claude-code. A login that
    lapses afterwards still fails at dispatch, with its own error."""
    env = os.environ if env is None else env
    adapter = profile["adapter"]
    if "credential_env" in profile and not env.get(profile["credential_env"]):
        return "no %s" % profile["credential_env"]
    if adapter in ROUTER_HTTP_ADAPTERS:
        if credential_required(profile) and not credential_for(profile, env):
            filename, var = KEY_FILES.get(adapter, (None, "a key"))
            return "no %s%s" % (
                var,
                " and no %s key file" % filename if filename else "",
            )
        return None
    if adapter in NATIVE_BINARIES:
        binary = NATIVE_BINARIES[adapter]
        if shutil.which(binary, path=env.get("PATH")):
            return None
        return "no `%s` on PATH" % binary
    runner = ROOT / "bin" / ("delegation-" + ADAPTERS[adapter][0])
    try:
        proc = subprocess.run(
            [str(runner), "check", "--json"],
            capture_output=True,
            text=True,
            timeout=RUNNER_CHECK_TIMEOUT,
            env=env,
        )
        report = json.loads(proc.stdout)
    except (OSError, subprocess.TimeoutExpired, ValueError):
        return "`%s check` failed" % runner.name
    if report.get("selected_backend") in (None, "none"):
        reasons = [
            str(b.get("reason"))
            for b in (report.get("backends") or {}).values()
            if isinstance(b, dict) and not b.get("available") and b.get("reason")
        ]
        return ("; ".join(reasons) or "no backend available")[:200]
    return None


def reachability(c, keys, env=None):
    """`unreachable()` for each profile key, checked in parallel: a native
    runner's check can take seconds."""
    keys = list(keys)
    with ThreadPoolExecutor(max_workers=max(1, min(8, len(keys)))) as pool:
        reasons = list(pool.map(lambda k: unreachable(c["profiles"][k], env), keys))
    return dict(zip(keys, reasons))
