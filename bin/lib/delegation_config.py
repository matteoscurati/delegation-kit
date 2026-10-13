"""User configuration and technical adapter registry; never imports project config."""

import functools
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
        {"effort", "timeout"},
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
    "claude-zai": {"max"},
    "grok-build-cli": {"high"},
    "agy": {"medium", "high"},
    "deepseek-api": {"minimal", "low", "medium", "high", "xhigh", "max"},
    "token-plan-openai": {"minimal", "low", "medium", "high", "xhigh", "max"},
    "codex": {"none", "minimal", "low", "medium", "high", "xhigh", "max"},
    "claude-code": {"low", "medium", "high", "xhigh", "max"},
}
# Routing metadata a profile may declare for itself. Everything else about an
# adapter stays code-owned; these are user statements, like `family`.
TIERS = ("small", "mid", "frontier")
PROFILE_ROUTING_FIELDS = {"tier", "code", "price", "context", "json_mode"}
# The router pool accepts the HTTP adapters only in this release; native CLI
# profiles need a non-streaming bridge that arrives later.
ROUTER_HTTP_ADAPTERS = {"openai-compatible", "deepseek-api", "token-plan-openai"}
ROUTER_DECIDERS = {"none", "llm"}
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


def preset(strict=False, source=None):
    """The shipped preset (config/presets.json), or the profiles imported from a
    legacy routing-gates.json snapshot when migrating a pre-0.24 install."""
    profiles = None
    if source is not None:
        # A legacy snapshot that does not parse or lacks the expected shape
        # falls back to the shipped preset instead of failing the install.
        try:
            old = read(source)
            profiles = {
                key: {
                    "adapter": p["harness"],
                    "model": p["model"],
                    "family": old.get("model_families", {}).get(p["model"]),
                    "roles": list(p["lanes"]),
                    "parameters": {"effort": p["effort"]},
                }
                for key, p in old["profiles"].items()
            }
        except (ValueError, KeyError, TypeError, AttributeError, OSError):
            profiles = None
    if not profiles:
        profiles = read(ROOT / "config/presets.json")["profiles"]
    return {
        "schema_version": 1,
        "review_policy": "cross-family" if strict else "optional",
        "profiles": profiles,
    }


def _number(value):
    return type(value) in (int, float) and value == value and value >= 0


def validate_routing_fields(p):
    """Optional per-profile routing declarations (schema 2)."""
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
    if "price" in p:
        price = p["price"]
        if price is not None and (
            not isinstance(price, dict)
            or set(price) != {"in", "out"}
            or not _number(price["in"])
            or not _number(price["out"])
            or price["in"] > 100_000
            or price["out"] > 100_000
        ):
            raise ValueError("invalid price (USD per million tokens: {in, out})")


LISTEN_PATTERN = re.compile(r"(localhost|127\.0\.0\.1|\[::1\]):[0-9]{1,5}")


def validate_router(c):
    """The router block is a user-declared rule set: pool, default, decider."""
    r = c.get("router")
    if r is None:
        return
    if c["schema_version"] < 2:
        raise ValueError("router requires schema_version 2")
    if not isinstance(r, dict) or set(r) - ROUTER_FIELDS:
        raise ValueError("unknown router field")
    listen = r.get("listen", "127.0.0.1:4141")
    if not isinstance(listen, str) or not LISTEN_PATTERN.fullmatch(listen):
        raise ValueError("router.listen must be a loopback host:port")
    if not 1 <= int(listen.rsplit(":", 1)[1]) <= 65535:
        raise ValueError("router.listen port out of range")
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
        if c["profiles"][key]["adapter"] not in ROUTER_HTTP_ADAPTERS:
            raise ValueError(
                "router.pool supports HTTP adapters only in this release: " + key
            )
    if r.get("default") not in pool:
        raise ValueError("router.default must be one of router.pool")
    decider = r.get("decider", {"kind": "llm"})
    if not isinstance(decider, dict) or set(decider) - {
        "kind",
        "profile",
        "input",
        "timeout",
    }:
        raise ValueError("unknown router.decider field")
    if decider.get("kind", "llm") not in ROUTER_DECIDERS:
        raise ValueError("router.decider.kind not available in this release")
    if decider.get("kind", "llm") == "llm":
        profile = decider.get("profile", r["default"])
        if profile not in c["profiles"]:
            raise ValueError("router.decider.profile names an unknown profile")
        if c["profiles"][profile]["adapter"] not in ROUTER_HTTP_ADAPTERS:
            raise ValueError("router.decider.profile must use an HTTP adapter")
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
    if not isinstance(origins, list) or any(
        not isinstance(o, str)
        or urlsplit(o).scheme not in {"http", "https"}
        or not urlsplit(o).hostname
        or urlsplit(o).path
        or urlsplit(o).query
        or urlsplit(o).fragment
        or (urlsplit(o).scheme == "http" and urlsplit(o).hostname not in LOOPBACK_HOSTS)
        for o in origins
    ):
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
        if not isinstance(p, dict) or set(p) - {
            "adapter",
            "model",
            "family",
            "roles",
            "parameters",
            "base_url",
            "credential_env",
            "aliases",
        } - (PROFILE_ROUTING_FIELDS if c["schema_version"] >= 2 else set()):
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
    validate_router(c)
    return c


@functools.lru_cache(maxsize=1)
def catalog():
    """Code-owned routing metadata for known model identifiers. Immutable for
    the life of a process, so read once."""
    return read(ROOT / "config/catalog.json")


def profile_meta(key, p, cat=None):
    """Routing metadata for one profile: the profile's own declarations win,
    the catalog fills the rest, unknown models stay without tier or price."""
    cat = cat if cat is not None else catalog()
    base = cat["models"].get(p["model"], {})
    declared = PROFILE_ROUTING_FIELDS & set(p)
    return {
        "profile": key,
        "model": p["model"],
        "adapter": p["adapter"],
        "family": p.get("family"),
        "tier": p["tier"] if "tier" in p else base.get("tier"),
        "code": p["code"] if "code" in p else base.get("code", False),
        "price": p["price"] if "price" in p else base.get("price"),
        "context": p["context"] if "context" in p else base.get("context"),
        "json_mode": p["json_mode"]
        if "json_mode" in p
        else base.get("json_mode", False),
        "effort": p.get("parameters", {}).get("effort"),
        "metadata_source": (
            "profile"
            if declared
            else ("catalog" if p["model"] in cat["models"] else "unknown")
        ),
        "catalog_version": cat["catalog_version"],
    }


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
