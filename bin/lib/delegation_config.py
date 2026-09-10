"""User configuration and technical adapter registry; never imports project config."""

import json
import os
import re
import shutil
import tempfile
from pathlib import Path
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[2]
REVIEW_ROLES = {"reviewer", "routine-review", "material-review", "security"}
TEXT_ROLES = {
    "builder",
    "clerk",
    "scout",
    "reviewer",
    "senior",
    "judgement",
    "policy-annotation",
}
# Capabilities are code-owned, not writable profile claims.
ADAPTERS = {
    "deepseek-api": (
        "deepseek",
        TEXT_ROLES,
        {"effort", "max_tokens", "timeout"},
        {"read-only", "text-patch"},
    ),
    "token-plan-openai": (
        "qwen",
        TEXT_ROLES,
        {"effort", "max_tokens", "timeout"},
        {"read-only", "text-patch"},
    ),
    "openai-compatible": (
        "openai-compatible",
        TEXT_ROLES,
        {"max_tokens", "timeout"},
        {"read-only", "text-patch"},
    ),
    "kimi-code-cli": (
        "kimi",
        {"clerk", "scout", "builder", "frontend-builder", "policy-annotation"},
        {"effort"},
        {"sandboxed-worktree"},
    ),
    "claude-zai": (
        "glm",
        {"clerk", "scout", "builder", "reviewer", "policy-annotation"},
        {"effort"},
        {"native-tool-policy"},
    ),
    "grok-build-cli": (
        "grok",
        {"builder", "frontend-builder", "policy-annotation"},
        {"effort"},
        {"sandboxed-worktree"},
    ),
    "agy": (
        "gemini",
        {"scout", "builder", "frontend-builder", "reviewer", "judgement"},
        {"effort"},
        {"read-only", "text-patch"},
    ),
    "codex": (None, TEXT_ROLES | REVIEW_ROLES, {"effort"}, {"native-profile"}),
    "claude-code": (None, TEXT_ROLES | REVIEW_ROLES, {"effort"}, {"native-profile"}),
}
EFFORTS = {
    "kimi-code-cli": {"max"},
    "claude-zai": {"max"},
    "grok-build-cli": {"high"},
    "agy": {"medium", "high"},
    "deepseek-api": {"minimal", "low", "medium", "high", "xhigh", "max"},
    "token-plan-openai": {"minimal", "low", "medium", "high", "xhigh", "max"},
    "codex": {"none", "minimal", "low", "medium", "high", "xhigh", "max"},
    "claude-code": {"low", "medium", "high", "xhigh", "max"},
}


def config_path():
    return (
        Path(
            os.environ.get("DELEGATION_CONFIG_FILE")
            or Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config")))
            / "delegation-kit/config.json"
        )
        .expanduser()
        .absolute()
    )


def read(path):
    def pairs(items):
        result = {}
        for k, v in items:
            if k in result:
                raise ValueError("duplicate JSON key")
            result[k] = v
        return result

    return json.loads(
        Path(path).read_text(),
        object_pairs_hook=pairs,
        parse_constant=lambda _: (_ for _ in ()).throw(
            ValueError("invalid JSON number")
        ),
    )


def preset(strict=False, source=None):
    """The shipped preset (config/presets.json), or the profiles imported from a
    legacy routing-gates.json snapshot when migrating a pre-0.24 install."""
    if source is None:
        profiles = read(ROOT / "config/presets.json")["profiles"]
    else:
        old = read(source)
        profiles = {}
        for key, p in old["profiles"].items():
            profiles[key] = {
                "adapter": p["harness"],
                "model": p["model"],
                "family": old.get("model_families", {}).get(p["model"]),
                "roles": list(p["lanes"]),
                "parameters": {"effort": p["effort"]},
            }
    return {
        "schema_version": 1,
        "review_policy": "cross-family" if strict else "optional",
        "profiles": profiles,
    }


def validate(c):
    if not isinstance(c, dict) or set(c) - {
        "schema_version",
        "review_policy",
        "profiles",
    }:
        raise ValueError("unknown configuration field")
    if type(c.get("schema_version")) is not int or c.get("schema_version") != 1:
        raise ValueError("unsupported config schema_version")
    if c.get("review_policy") not in {"optional", "required", "cross-family"}:
        raise ValueError("invalid review_policy")
    if not isinstance(c.get("profiles"), dict) or not c["profiles"]:
        raise ValueError("profiles must be a nonempty object")
    for key, p in c["profiles"].items():
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", key):
            raise ValueError("invalid profile id")
        if not isinstance(p, dict) or set(p) - {
            "adapter",
            "model",
            "family",
            "roles",
            "parameters",
            "base_url",
            "credential_env",
            "aliases",
        }:
            raise ValueError(
                "unknown profile field (credentials and capability overrides are forbidden)"
            )
        if p.get("adapter") not in ADAPTERS:
            raise ValueError("unsupported adapter")
        if (
            not isinstance(p.get("model"), str)
            or not p["model"]
            or any(ord(x) < 32 for x in p["model"])
        ):
            raise ValueError("invalid model")
        if p["adapter"] != "openai-compatible" and not re.fullmatch(
            r"[A-Za-z0-9][A-Za-z0-9._:/@+-]*", p["model"]
        ):
            raise ValueError("invalid native model identifier")
        if "family" in p and (not isinstance(p["family"], str) or not p["family"]):
            raise ValueError("invalid family")
        if (
            not isinstance(p.get("roles"), list)
            or not p["roles"]
            or any(not isinstance(x, str) for x in p["roles"])
            or len(set(p["roles"])) != len(p["roles"])
        ):
            raise ValueError("invalid roles")
        params = p.get("parameters", {})
        if not isinstance(params, dict) or set(params) - ADAPTERS[p["adapter"]][2]:
            raise ValueError("unsupported adapter parameter")
        if "effort" in params and params["effort"] not in EFFORTS.get(
            p["adapter"], set()
        ):
            raise ValueError("unsupported effort")
        for param, maximum in [("timeout", 86400), ("max_tokens", 1000000)]:
            if param in params and (
                type(params[param]) is not int or not 1 <= params[param] <= maximum
            ):
                raise ValueError("invalid " + param)
        if "aliases" in p and (
            not isinstance(p["aliases"], list)
            or any(
                not isinstance(x, str) or not x or any(ord(ch) < 32 for ch in x)
                for x in p["aliases"]
            )
        ):
            raise ValueError("invalid aliases")
        if "credential_env" in p and not re.fullmatch(
            r"[A-Za-z_][A-Za-z0-9_]*", p["credential_env"]
        ):
            raise ValueError("invalid credential variable name")
        if p["adapter"] == "openai-compatible":
            url = urlsplit(p.get("base_url", ""))
            if url.port is not None and not 1 <= url.port <= 65535:
                raise ValueError("invalid endpoint port")
            if (
                not url.hostname
                or url.username
                or url.password
                or url.query
                or url.fragment
                or any(ord(ch) < 33 for ch in p.get("base_url", ""))
            ):
                raise ValueError("invalid base_url; inline credentials forbidden")
            if url.scheme != "https" and not (
                url.scheme == "http"
                and url.hostname in {"localhost", "127.0.0.1", "::1"}
            ):
                raise ValueError("remote endpoints require HTTPS")
        elif "base_url" in p:
            raise ValueError("base_url requires openai-compatible")
        if "credential_env" in p and p["adapter"] not in {
            "openai-compatible",
            "deepseek-api",
            "token-plan-openai",
        }:
            raise ValueError("this adapter uses native credential storage")
    return c


def load():
    path = config_path()
    return validate(read(path) if path.exists() else preset())


def row(key, p, role, c):
    _, roles, _, caps = ADAPTERS[p["adapter"]]
    compatible = role in roles
    return {
        "profile": key,
        "model": p["model"],
        "family": p.get("family"),
        "adapter": p["adapter"],
        "lane": role,
        "configuration_valid": True,
        "technical_compatibility": compatible,
        "capabilities": sorted(caps),
        "selection": "explicit-only" if compatible else "unsupported",
        "review_policy": c["review_policy"],
    }


def atomic(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temp = tempfile.mkstemp(prefix="." + path.name, dir=path.parent)
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(value, f, indent=2)
            f.write("\n")
        os.replace(temp, path)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)


def initialize(strict=False):
    path = config_path()
    if path.exists():
        return {
            "preserved": True,
            "file": str(path),
            "review_policy": load()["review_policy"],
        }
    data = Path(
        os.environ.get(
            "DELEGATION_DATA_HOME", str(Path.home() / ".local/share/delegation-kit")
        )
    )
    source = data / "config/routing-gates.json"
    backup = None
    if source.exists():
        backup = path.parent / "migration-v1-backup"
        backup.parent.mkdir(parents=True, exist_ok=True)
        if not backup.exists():
            shutil.copytree(data / "config", backup)
            backup.chmod(0o700)
        source = backup / "routing-gates.json"
    c = validate(preset(strict, source if source.exists() else None))
    atomic(path, c)
    return {
        "preserved": False,
        "file": str(path),
        "backup": str(backup) if backup else None,
        "review_policy": c["review_policy"],
        "summary": "Review is optional by default; evidence no longer blocks execution. Existing technical restrictions remain.",
    }


def review_state(policy, producer, reviewer=None, authorized=False, completed=False):
    if policy == "optional":
        return "not-required"
    if not authorized:
        return "pending-authorization"
    if reviewer is None:
        return "pending-reviewer"
    if policy == "cross-family" and (
        not producer.get("family")
        or not reviewer.get("family")
        or producer["family"] == reviewer["family"]
    ):
        return "pending-compatible-reviewer"
    return "complete" if completed else "pending-review"


def apply():
    """Generate host snippets in the user config directory, preserving local edits."""
    initialize()
    c = load()
    managed = config_path().parent / "managed"
    manifest = managed / "manifest.json"
    previous = read(manifest) if manifest.exists() else {}
    import hashlib

    hashes = {}
    preserved = []
    for key, p in c["profiles"].items():
        if p["adapter"] not in {"codex", "claude-code"}:
            continue
        if p["adapter"] == "codex":
            name = "codex/" + key + ".toml"
            content = (
                "model = "
                + json.dumps(p["model"])
                + "\nmodel_reasoning_effort = "
                + json.dumps(p.get("parameters", {}).get("effort", "high"))
                + '\nsandbox_mode = "read-only"\n'
            )
        else:
            name = "claude/" + key + ".md"
            content = (
                "---\nname: "
                + key
                + "\nmodel: "
                + json.dumps(p["model"])
                + "\neffort: "
                + json.dumps(p.get("parameters", {}).get("effort", "high"))
                + "\ntools: []\n---\nUse only for an explicitly authorized delegation. Return analysis or a textual patch. The lead verifies the result. Review follows the user configuration.\n"
            )
        target = managed / name
        target.parent.mkdir(parents=True, exist_ok=True)
        if (
            target.is_symlink()
            or target.exists()
            and hashlib.sha256(target.read_bytes()).hexdigest() != previous.get(name)
        ):
            preserved.append(name)
            hashes[name] = previous.get(name)
            continue
        target.write_text(content)
        target.chmod(0o600)
        hashes[name] = hashlib.sha256(content.encode()).hexdigest()
    atomic(manifest, hashes)
    atomic(managed / "profiles.json", c)
    return {
        "schema_version": 1,
        "managed_directory": str(managed),
        "preserved_user_edits": preserved,
        "review_policy": c["review_policy"],
    }
