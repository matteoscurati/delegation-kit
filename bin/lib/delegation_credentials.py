"""Where a profile's credential and endpoint come from.

Profiles never hold a key: `credential_env` names a variable, and the kit's
own key files under the data home (mode 600, one NAME=value line) cover the
adapters that have one. A key file readable by group or others is ignored,
not read."""

import os
import re

from delegation_config import data_home


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


def key_from_file(path, var):
    try:
        if path.is_symlink() or not path.is_file():
            return None
        mode = path.stat().st_mode & 0o777
        if mode & 0o077:
            return None
        for line in path.read_text().splitlines():
            m = re.match(r"\s*(?:export\s+)?" + re.escape(var) + r"=(.*)$", line)
            if m:
                value = m.group(1).strip()
                if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
                    value = value[1:-1]
                return value or None
    except OSError:
        return None
    return None


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
