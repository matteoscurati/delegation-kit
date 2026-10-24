"""User configuration and technical adapter registry; never imports project config."""

import json
import os
import re
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
        {"effort", "max_tokens", "timeout"},
        {"read-only", "text-patch"},
    ),
    "kimi-code-cli": (
        "kimi",
        {"clerk", "scout", "builder", "frontend-builder", "policy-annotation"},
        {"effort", "timeout"},
        {"sandboxed-worktree"},
    ),
    "muse-code-cli": (
        "muse",
        {
            "clerk",
            "scout",
            "reviewer",
            "builder",
            "frontend-builder",
            "policy-annotation",
        },
        {"effort", "timeout", "contributor_mode"},
        {"sandboxed-worktree"},
    ),
    "claude-zai": (
        "glm",
        {"clerk", "scout", "builder", "reviewer", "policy-annotation"},
        {"effort", "timeout"},
        {"native-tool-policy"},
    ),
    "grok-build-cli": (
        "grok",
        {"builder", "frontend-builder", "policy-annotation"},
        {"effort", "timeout"},
        {"sandboxed-worktree"},
    ),
    "agy": (
        "gemini",
        {"scout", "builder", "frontend-builder", "reviewer", "judgement"},
        {"effort", "timeout"},
        {"read-only", "text-patch"},
    ),
    "codex": (
        None,
        TEXT_ROLES | REVIEW_ROLES,
        {"effort", "timeout"},
        {"native-profile"},
    ),
    "claude-code": (
        None,
        TEXT_ROLES | REVIEW_ROLES,
        {"effort", "timeout"},
        {"native-profile"},
    ),
}


EFFORTS = {
    "kimi-code-cli": {"max"},
    "muse-code-cli": {"minimal", "low", "medium", "high", "xhigh", "max"},
    "claude-zai": {"max"},
    "grok-build-cli": {"high"},
    "agy": {"medium", "high"},
    "deepseek-api": {"minimal", "low", "medium", "high", "xhigh", "max"},
    "token-plan-openai": {"minimal", "low", "medium", "high", "xhigh", "max"},
    # Sent as `reasoning_effort` only when the profile declares it.
    "openai-compatible": {"minimal", "low", "medium", "high", "xhigh", "max"},
    "codex": {"none", "minimal", "low", "medium", "high", "xhigh", "max"},
    "claude-code": {"low", "medium", "high", "xhigh", "max"},
}
# Reasoning settings from weakest to strongest, across adapters.


EFFORT_ORDER = ("none", "minimal", "low", "medium", "high", "xhigh", "max")
# Routing metadata a profile may declare for itself. Everything else about an
# adapter stays code-owned; these are user statements, like `family`.


TIERS = ("small", "mid", "frontier")


PROFILE_ROUTING_FIELDS = {"tier", "code", "price", "context", "json_mode"}
# The adapters the router calls over HTTP itself, and the only ones an llm
# decider may use; a native pool profile goes through delegation-run instead.


ROUTER_HTTP_ADAPTERS = {"openai-compatible", "deepseek-api", "token-plan-openai"}


ROUTER_DECIDERS = {"none", "llm", "sage", "jev", "dipylon", "classifier"}


DECIDER_FIELDS = {
    "kind",
    "profile",
    "input",
    "timeout",
    "url",
    "credential_env",
    "model",
    "price",
}
# Deciders that call a service of their own rather than one of the profiles.


SERVICE_DECIDERS = {"sage", "jev", "dipylon", "classifier"}


ROUTER_FIELDS = {
    "listen",
    "pool",
    "default",
    "decider",
    "max_cost_usd",
    "receipts",
    "allow_origins",
    "mode",
}


LOOPBACK_HOSTS = {"localhost", "127.0.0.1", "::1"}


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


def preset(strict=False):
    """The shipped preset (config/presets.json) as a fresh personal configuration."""
    return {
        "schema_version": 2,
        "review_policy": "cross-family" if strict else "optional",
        "profiles": read(ROOT / "config/presets.json")["profiles"],
    }


def _number(value):
    return type(value) in (int, float) and value == value and value >= 0


def _price_ok(price):
    return price is None or (
        isinstance(price, dict)
        and set(price) == {"in", "out"}
        and _number(price["in"])
        and _number(price["out"])
        and price["in"] <= 100_000
        and price["out"] <= 100_000
    )


def _endpoint_ok(value):
    """HTTPS anywhere, HTTP on loopback only, no inline credentials."""
    if not isinstance(value, str) or any(ord(ch) < 33 for ch in value):
        return False
    url = urlsplit(value)
    if url.port is not None and not 1 <= url.port <= 65535:
        return False
    if not url.hostname or url.username or url.password or url.query or url.fragment:
        return False
    return url.scheme == "https" or (
        url.scheme == "http" and url.hostname in LOOPBACK_HOSTS
    )


def _origin_ok(value):
    """An exact browser origin: scheme and host only, HTTP on loopback only."""
    if not isinstance(value, str):
        return False
    url = urlsplit(value)
    if url.scheme not in {"http", "https"} or not url.hostname:
        return False
    if url.path or url.query or url.fragment:
        return False
    return url.scheme == "https" or url.hostname in LOOPBACK_HOSTS


LISTEN_PATTERN = re.compile(r"(localhost|127\.0\.0\.1|\[::1\]):[0-9]{1,5}")


def validate_listen(listen, field="router.listen"):
    """A loopback host:port with a usable port; the same rule for the
    configuration and for `serve --listen`."""
    if not isinstance(listen, str) or not LISTEN_PATTERN.fullmatch(listen):
        raise ValueError(field + " must be a loopback host:port")
    if not 1 <= int(listen.rsplit(":", 1)[1]) <= 65535:
        raise ValueError(field + " port out of range")
    return listen


def validate_routing_fields(p):
    """Optional per-profile routing declarations."""
    if "tier" in p and p["tier"] not in TIERS:
        raise ValueError("invalid tier (small|mid|frontier)")
    if "code" in p and type(p["code"]) is not bool:
        raise ValueError("invalid code flag")
    if "json_mode" in p and type(p["json_mode"]) is not bool:
        raise ValueError("invalid json_mode flag")
    if "context" in p and (
        type(p["context"]) is not int or not 1 <= p["context"] <= 100_000_000
    ):
        raise ValueError("invalid context")
    if "price" in p and not _price_ok(p["price"]):
        raise ValueError("invalid price (USD per million tokens: {in, out})")


def validate_router(c):
    """The router block is a user-declared rule set: pool, default, decider."""
    r = c.get("router")
    if r is None:
        return
    if not isinstance(r, dict) or set(r) - ROUTER_FIELDS:
        raise ValueError("unknown router field")
    if not isinstance(r.get("decider"), dict) or "kind" not in r["decider"]:
        raise ValueError(
            "router.decider is required: name the decision model "
            "(kind llm, sage, jev, dipylon, classifier or none)"
        )
    validate_listen(r.get("listen", "127.0.0.1:4141"))
    pool = r.get("pool")
    if (
        not isinstance(pool, list)
        or not pool
        or any(not isinstance(x, str) for x in pool)
        or len(set(pool)) != len(pool)
    ):
        raise ValueError("router.pool must be a nonempty list of distinct profile ids")
    for key in pool:
        if key not in c["profiles"]:
            raise ValueError("router.pool names an unknown profile: " + key)
    if r.get("default") not in pool:
        raise ValueError("router.default must be one of router.pool")
    decider = r["decider"]
    if set(decider) - DECIDER_FIELDS:
        raise ValueError("unknown router.decider field")
    kind = decider["kind"]
    if kind not in ROUTER_DECIDERS:
        raise ValueError("router.decider.kind is not a known decider")
    if kind == "llm":
        profile = decider.get("profile", r["default"])
        if profile not in c["profiles"]:
            raise ValueError("router.decider.profile names an unknown profile")
        if c["profiles"][profile]["adapter"] not in ROUTER_HTTP_ADAPTERS:
            raise ValueError("router.decider.profile must use an HTTP adapter")
    elif "profile" in decider:
        raise ValueError("router.decider.profile applies to the llm decider only")
    if kind in SERVICE_DECIDERS:
        if "url" in decider and not _endpoint_ok(decider["url"]):
            raise ValueError("router.decider.url must be HTTPS or loopback HTTP")
        if kind in {"dipylon", "classifier"} and "url" not in decider:
            raise ValueError("router.decider.url is required for " + kind)
    elif set(decider) & {"url", "credential_env", "model", "price"}:
        raise ValueError(
            "router.decider url/credential_env/model/price need a service decider"
        )
    if "credential_env" in decider and (
        not isinstance(decider["credential_env"], str)
        or not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", decider["credential_env"])
    ):
        raise ValueError("invalid router.decider.credential_env")
    if "model" in decider and (
        not isinstance(decider["model"], str)
        or not decider["model"]
        or any(ord(x) < 33 for x in decider["model"])
    ):
        raise ValueError("invalid router.decider.model")
    if "price" in decider and not _price_ok(decider["price"]):
        raise ValueError("invalid router.decider.price")
    if decider.get("input", "excerpt") not in {"excerpt", "full"}:
        raise ValueError("router.decider.input must be excerpt or full")
    if "timeout" in decider and (
        type(decider["timeout"]) is not int or not 1 <= decider["timeout"] <= 600
    ):
        raise ValueError("invalid router.decider.timeout")
    if "max_cost_usd" in r and (
        not _number(r["max_cost_usd"])
        or r["max_cost_usd"] <= 0
        or r["max_cost_usd"] > 1000
    ):
        raise ValueError("invalid router.max_cost_usd")
    if "receipts" in r and type(r["receipts"]) is not bool:
        raise ValueError("invalid router.receipts")
    if r.get("mode", "route") not in {"route", "shadow"}:
        raise ValueError("router.mode must be route or shadow")
    origins = r.get("allow_origins", [])
    if not isinstance(origins, list) or not all(_origin_ok(o) for o in origins):
        raise ValueError("router.allow_origins must list exact https origins")


def validate(c):
    if not isinstance(c, dict) or set(c) - {
        "schema_version",
        "review_policy",
        "profiles",
        "router",
    }:
        raise ValueError("unknown configuration field")
    if type(c.get("schema_version")) is not int or c.get("schema_version") not in {
        1,
        2,
    }:
        raise ValueError("unsupported config schema_version")
    if c.get("review_policy") not in {"optional", "required", "cross-family"}:
        raise ValueError("invalid review_policy")
    if not isinstance(c.get("profiles"), dict) or not c["profiles"]:
        raise ValueError("profiles must be a nonempty object")
    for key, p in c["profiles"].items():
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", key):
            raise ValueError("invalid profile id")
        if (
            not isinstance(p, dict)
            or set(p)
            - {
                "adapter",
                "model",
                "family",
                "roles",
                "parameters",
                "base_url",
                "credential_env",
                "aliases",
            }
            - PROFILE_ROUTING_FIELDS
        ):
            raise ValueError(
                "unknown profile field (credentials and capability overrides are forbidden)"
            )
        validate_routing_fields(p)
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
        # Whether Meta may train on what a Muse Code run sends; off unless set.
        if "contributor_mode" in params and params["contributor_mode"] not in {
            "on",
            "off",
        }:
            raise ValueError("invalid contributor_mode")
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
            if not _endpoint_ok(p.get("base_url", "")):
                raise ValueError(
                    "invalid base_url: HTTPS, or HTTP on loopback; "
                    "inline credentials forbidden"
                )
        elif "base_url" in p:
            raise ValueError("base_url requires openai-compatible")
        if "credential_env" in p and p["adapter"] not in {
            "openai-compatible",
            "deepseek-api",
            "token-plan-openai",
        }:
            raise ValueError("this adapter uses native credential storage")
    validate_router(c)
    return c


def kit_version():
    """The installed marker when running from an install root, else the checkout."""
    for name in ("installed-version.json", "package.json"):
        try:
            return json.loads((ROOT / name).read_text())["version"]
        except (OSError, ValueError, KeyError, TypeError):
            continue
    return "unknown"


def data_home():
    return Path(
        os.environ.get(
            "DELEGATION_DATA_HOME", str(Path.home() / ".local/share/delegation-kit")
        )
    )


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
    c = validate(preset(strict))
    atomic(path, c)
    return {
        "preserved": False,
        "file": str(path),
        "review_policy": c["review_policy"],
        "summary": "Review is optional by default. Existing technical restrictions remain.",
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
