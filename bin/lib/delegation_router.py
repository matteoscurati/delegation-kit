"""Local model router: request features, deterministic pre-filter, signal
normalization and the tiered-v1 policy. Everything here is pure; the network
lives in the deciders and in the server."""

import json
import math
import os
import re

from delegation_config import (
    ADAPTERS,
    ROUTER_HTTP_ADAPTERS,
    catalog,
    data_home,
    profile_meta,
)

POLICY_ID = "tiered-v1"
POLICY_VERSION = "2026-10-13"
ROUTER_VERSION = "1"
TAGS = ("code", "math", "long", "rare", "tools")
LONG_TOKENS = 20000
DEFAULT_OUTPUT_TOKENS = 1024
DECISION_TOKENS = 450
TIER_RANK = {"small": 0, "mid": 1, "frontier": 2}
CONFIDENCE_FLOOR = 0.55
TAG_THRESHOLD = 0.6
# The policy's cut points on the 0..1 difficulty scale and on p_needs_strong.
# The evaluation harness sweeps them; serve uses these.
CUTS = {"frontier": 0.75, "small": 0.375, "p_strong": 0.7}
EXCERPT_LIMIT = 4000
LAST_USER_LIMIT = 2048
SYSTEM_HEAD_LIMIT = 1000
FULL_LIMIT = 32000
ENDPOINTS = {
    "deepseek-api": "https://api.deepseek.com/v1/chat/completions",
    "token-plan-openai": "https://token-plan.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1/chat/completions",
}
KEY_FILES = {
    "deepseek-api": ("deepseek.env", "DEEPSEEK_API_KEY"),
    "token-plan-openai": ("qwen-token-plan.env", "QWEN_TOKEN_PLAN_API_KEY"),
}


# ---- request features --------------------------------------------------------


def text_of(content):
    """Visible text of a message content; images are not text."""
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "\n".join(
            part.get("text", "")
            for part in content
            if isinstance(part, dict) and part.get("type") in {None, "text"}
        )
    return ""


def has_image(content):
    return isinstance(content, list) and any(
        isinstance(part, dict) and str(part.get("type", "")).startswith("image")
        for part in content
    )


def features(body):
    messages = body.get("messages") if isinstance(body.get("messages"), list) else []
    chars = 0
    images = False
    last_user = ""
    for m in messages:
        if not isinstance(m, dict):
            continue
        text = text_of(m.get("content"))
        chars += len(text)
        images = images or has_image(m.get("content"))
        if m.get("role") == "user":
            last_user = text
    tools = body.get("tools") or body.get("functions") or []
    tool_chars = len(json.dumps(tools)) if tools else 0
    max_tokens = body.get("max_tokens") or body.get("max_completion_tokens")
    if type(max_tokens) is not int or max_tokens < 1:
        max_tokens = None
    response_format = body.get("response_format")
    return {
        "est_tokens": (chars + tool_chars) // 4,
        "turns": len(messages),
        "has_tools": bool(tools),
        "has_images": images,
        "wants_json": isinstance(response_format, dict)
        and response_format.get("type") in {"json_object", "json_schema"},
        "has_numbers": bool(re.search(r"\d", last_user)),
        "max_tokens": max_tokens,
    }


def excerpt(body, mode="excerpt"):
    """What a decider is allowed to see. `excerpt` is the default: the head of
    the system prompt, the last user turn, counts and tool names; never images.
    `full` is an explicit opt-in."""
    messages = body.get("messages") if isinstance(body.get("messages"), list) else []
    if mode == "full":
        parts = []
        for m in messages:
            if isinstance(m, dict):
                parts.append(str(m.get("role", "")) + ": " + text_of(m.get("content")))
        return "\n\n".join(parts)[:FULL_LIMIT]
    system = ""
    last_user = ""
    for m in messages:
        if not isinstance(m, dict):
            continue
        if m.get("role") == "system" and not system:
            system = text_of(m.get("content"))[:SYSTEM_HEAD_LIMIT]
        if m.get("role") == "user":
            last_user = text_of(m.get("content"))
    if len(last_user) > LAST_USER_LIMIT:
        last_user = (
            last_user[: LAST_USER_LIMIT * 3 // 4]
            + " […] "
            + last_user[-LAST_USER_LIMIT // 4 :]
        )
    tools = body.get("tools") if isinstance(body.get("tools"), list) else []
    names = []
    for t in tools:
        if not isinstance(t, dict):
            continue
        function = t.get("function")
        name = function.get("name") if isinstance(function, dict) else t.get("name")
        if isinstance(name, str):
            names.append(name)
    meta = "turns: %d; system prompt: %s; tools: %s" % (
        len(messages),
        "yes" if system else "no",
        ", ".join(n for n in names if n) or "none",
    )
    text = meta + "\n\n"
    if system:
        text += "system (head):\n" + system + "\n\n"
    text += "latest user request:\n" + last_user
    return text[:EXCERPT_LIMIT]


# ---- pool, prices, pre-filter ------------------------------------------------


def pool_meta(c, cat=None):
    cat = cat if cat is not None else catalog()
    r = c["router"]
    return [profile_meta(key, c["profiles"][key], cat) for key in r["pool"]]


def count(value):
    """A token count as the provider or the caller sent it, or None."""
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    return int(value) if value >= 0 else None


def estimate_cost(meta, in_tokens, out_tokens):
    """USD for one exchange, or None when the price or a count is unknown."""
    price = meta.get("price")
    in_tokens, out_tokens = count(in_tokens), count(out_tokens)
    if not price or in_tokens is None or out_tokens is None:
        return None
    return in_tokens * price["in"] / 1e6 + out_tokens * price["out"] / 1e6


def rank_cost(meta, feats):
    cost = estimate_cost(
        meta, feats["est_tokens"], feats["max_tokens"] or DEFAULT_OUTPUT_TOKENS
    )
    return math.inf if cost is None else cost


def prefilter(pool, feats, ceiling, default_key):
    """Deterministic eligibility: no network, no judgement. The default profile
    is never blocked by a missing tier, because it is the fallback."""
    eligible, blocked = [], []
    for meta in pool:
        reason = None
        if meta["adapter"] not in ADAPTERS:
            reason = "adapter not routable"
        elif meta["adapter"] not in ROUTER_HTTP_ADAPTERS and (
            feats["has_tools"] or feats["has_images"] or feats.get("wants_json")
        ):
            reason = "native profile: no tools, images or JSON mode"
        elif meta["tier"] is None and meta["profile"] != default_key:
            reason = "no tier declared"
        elif (
            meta["context"]
            and feats["est_tokens"] + (feats["max_tokens"] or DEFAULT_OUTPUT_TOKENS)
            > meta["context"]
        ):
            reason = "context too small"
        elif feats.get("wants_json") and meta.get("json_mode") is False:
            reason = "no JSON mode"
        else:
            cost = estimate_cost(
                meta, feats["est_tokens"], feats["max_tokens"] or DEFAULT_OUTPUT_TOKENS
            )
            if ceiling is not None and cost is not None and cost > ceiling:
                reason = "estimated cost above ceiling"
        if reason:
            blocked.append({"profile": meta["profile"], "reason": reason})
        else:
            eligible.append(meta)
    return eligible, blocked


def skip_reason(eligible, default_meta, decider_meta, feats):
    """Why a model decider would be wasted on this request, or None. A decision
    can save money (a cheaper profile than the default) or buy capability (a
    higher tier than the default); it is skipped only when it can do neither."""
    if len(eligible) <= 1:
        return "one eligible profile"
    default_rank = TIER_RANK.get(default_meta.get("tier"), -1)
    if any(TIER_RANK.get(m.get("tier"), -1) > default_rank for m in eligible):
        return None
    out_tokens = feats["max_tokens"] or DEFAULT_OUTPUT_TOKENS
    cheapest = min(
        (
            c
            for c in (
                estimate_cost(m, feats["est_tokens"], out_tokens) for m in eligible
            )
            if c is not None
        ),
        default=None,
    )
    default_cost = estimate_cost(default_meta, feats["est_tokens"], out_tokens)
    if (
        decider_meta is not None
        and decider_meta.get("price")
        and default_cost is not None
        and cheapest is not None
    ):
        saving = default_cost - cheapest
        decision = DECISION_TOKENS * decider_meta["price"]["in"] / 1e6
        if saving < 10 * decision:
            return "nothing to save"
    return None


# ---- signals → verdict → choice ---------------------------------------------


def normalize(signals):
    """Reduce any decider's signals to one verdict. difficulty is 0..1;
    p_needs_strong is a probability when a decider gives one; tags are
    probabilities per tag; confidence is the weakest confidence seen."""
    difficulty = None
    p_strong = None
    tags = {t: 0.0 for t in TAGS}
    confidences = []
    for s in signals or []:
        kind = s.get("kind")
        if kind == "scale":
            low, high = s.get("range", [0, 4])
            if high > low and s.get("expectation") is not None:
                difficulty = (s["expectation"] - low) / (high - low)
            if s.get("distribution"):
                threshold = low + 0.75 * (high - low)
                p_strong = sum(
                    d["p"] for d in s["distribution"] if d["level"] >= threshold
                )
            confidences.append(s.get("confidence", 1.0))
        elif kind == "tags":
            for t, p in (s.get("tags") or {}).items():
                if t in tags:
                    tags[t] = max(tags[t], float(p))
        elif kind == "yesno":
            p = float(s.get("p", 0.0))
            p_strong = max(p_strong or 0.0, p)
            confidence = s.get("confidence")
            confidences.append(
                abs(p - 0.5) * 2 if confidence is None else float(confidence)
            )
        elif kind == "score":
            levels = s.get("levels") or []
            if len(levels) > 1 and s.get("value") is not None:
                difficulty = float(s["value"]) / (len(levels) - 1)
            confidences.append(s.get("confidence", 1.0))
        elif kind == "choice":
            confidences.append(s.get("confidence", 1.0))
    undecidable = difficulty is None and p_strong is None
    return {
        "difficulty": difficulty,
        "p_needs_strong": p_strong,
        "tags": tags,
        "confidence": min(confidences) if confidences else 0.0,
        "undecidable": undecidable,
    }


def pretags(feats):
    return {
        "long": 1.0 if feats["est_tokens"] > LONG_TOKENS else 0.0,
        "tools": 1.0 if feats["has_tools"] else 0.0,
    }


def _needed_tier(verdict, cuts=CUTS):
    """The weakest tier the verdict allows. `code` never raises the tier: it
    narrows the candidates to code-capable profiles instead. math, rare and
    tools raise an easy request to mid; long always needs the frontier."""
    d = verdict["difficulty"]
    p = verdict["p_needs_strong"]
    tags = verdict["tags"]
    raising = max(tags[t] for t in ("math", "rare", "tools"))
    if (
        (d is not None and d >= cuts["frontier"])
        or (p is not None and p >= cuts["p_strong"])
        or tags["long"] >= TAG_THRESHOLD
    ):
        return "frontier"
    if d is not None and d < cuts["small"] and raising < TAG_THRESHOLD:
        return "small"
    if d is None and p is not None and p < 0.3 and raising < TAG_THRESHOLD:
        return "small"
    return "mid"


def _effort(verdict, tier):
    d = verdict["difficulty"]
    if d is not None and d >= 0.9:
        return "high"
    if tier == "small" and d is not None and d < 0.375:
        return "low"
    return None


def _usd(cost):
    return "unpriced" if cost == math.inf else "$%.4f" % cost


def _cheapest(candidates, feats):
    return sorted(candidates, key=lambda m: rank_cost(m, feats))[0]


def choose(verdict, eligible, default_meta, feats, cuts=CUTS):
    """tiered-v1: the policy that turns a verdict into one profile. Pure."""
    reasons = []

    def default(reason):
        reasons.append(reason)
        return {
            "profile": default_meta["profile"],
            "model": default_meta["model"],
            "tier": default_meta.get("tier"),
            "tier_source": default_meta.get("tier_source"),
            "reasoning_effort": None,
            "reasons": reasons,
            "undecidable": True,
        }

    if verdict["undecidable"]:
        return default("no usable signal → default")
    if verdict["confidence"] < CONFIDENCE_FLOOR:
        return default(
            "confidence %.2f < %.2f → default"
            % (verdict["confidence"], CONFIDENCE_FLOOR)
        )
    tags = verdict["tags"]
    needed = _needed_tier(verdict, cuts)
    if verdict["difficulty"] is not None:
        reasons.append("difficulty %.2f" % verdict["difficulty"])
    if verdict["p_needs_strong"] is not None:
        reasons.append("p_needs_strong %.2f" % verdict["p_needs_strong"])
    for t in TAGS:
        if tags[t] >= TAG_THRESHOLD:
            reasons.append("tag %s %.2f" % (t, tags[t]))
    candidates = []
    if tags["code"] >= TAG_THRESHOLD:
        candidates = [
            m
            for m in eligible
            if m.get("code")
            and m.get("tier")
            and TIER_RANK[m["tier"]] >= TIER_RANK[needed]
        ]
        if candidates:
            reasons.append("code → cheapest code-capable profile at tier ≥ %s" % needed)
    tier = needed
    while not candidates and tier is not None:
        candidates = [m for m in eligible if m.get("tier") == tier]
        if candidates:
            reasons.append("tier %s → cheapest eligible" % tier)
        else:
            tier = {"small": "mid", "mid": "frontier", "frontier": None}[tier]
            if tier:
                reasons.append("tier empty → escalate to %s" % tier)
    if not candidates:
        return default("no eligible profile at or above the needed tier → default")
    chosen = _cheapest(candidates, feats)
    reasons.append(
        "%s is %s (%s)"
        % (chosen["profile"], chosen.get("tier"), chosen.get("tier_source"))
    )
    reasons.append(
        "candidates: "
        + ", ".join(
            "%s %s" % (m["profile"], _usd(rank_cost(m, feats)))
            for m in sorted(candidates, key=lambda m: rank_cost(m, feats))
        )
        + " → "
        + chosen["profile"]
    )
    return {
        "profile": chosen["profile"],
        "model": chosen["model"],
        "tier": chosen.get("tier"),
        "tier_source": chosen.get("tier_source"),
        "reasoning_effort": _effort(verdict, chosen.get("tier")),
        "reasons": reasons,
        "undecidable": False,
    }


def native_lane(profile):
    """The role a native profile is dispatched on from the gateway: the first
    read-only role it declares and its adapter supports, a build role only
    when nothing else is declared, None when no role is usable."""
    from delegation_router_bridge import LANE_PREFERENCE

    supported = ADAPTERS[profile["adapter"]][1]
    for lane in LANE_PREFERENCE:
        if lane in profile.get("roles", []) and lane in supported:
            return lane
    return None


def verdict_from_signals(signals):
    """The verdict a disclosure describes, for re-choosing without a decider."""
    scale = signals.get("scale") or [0, 4]
    d = signals.get("difficulty")
    return {
        "difficulty": None if d is None else (d - scale[0]) / (scale[1] - scale[0]),
        "p_needs_strong": signals.get("p_needs_strong"),
        "tags": {t: float((signals.get("tags") or {}).get(t, 0.0)) for t in TAGS},
        "confidence": float(signals.get("confidence") or 0.0),
        "undecidable": d is None and signals.get("p_needs_strong") is None,
    }


# ---- credentials and endpoints -----------------------------------------------


def _key_from_file(path, var):
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
        return env.get(var) or _key_from_file(data_home() / "config" / filename, var)
    return None


def endpoint_for(profile):
    if profile["adapter"] == "openai-compatible":
        return profile["base_url"].rstrip("/") + "/chat/completions"
    return ENDPOINTS[profile["adapter"]]


def credential_required(profile):
    return profile["adapter"] != "openai-compatible" or "credential_env" in profile


# ---- disclosure --------------------------------------------------------------


def disclosure(c, feats, verdict, choice, decision, blocked, skipped, mode):
    r = c["router"]
    scale = [0, 4]
    signals = {
        "difficulty": None
        if verdict["difficulty"] is None
        else round(verdict["difficulty"] * (scale[1] - scale[0]) + scale[0], 2),
        "scale": scale,
        "tags": {t: round(v, 2) for t, v in verdict["tags"].items()},
        "p_needs_strong": None
        if verdict["p_needs_strong"] is None
        else round(verdict["p_needs_strong"], 2),
        "confidence": round(verdict["confidence"], 2),
    }
    out = {
        "version": ROUTER_VERSION,
        "mode": mode,
        "decider": decision.get("decider", {"id": "none", "version": "rules-only"}),
        "policy": {"id": POLICY_ID, "version": POLICY_VERSION},
        "signals": signals,
        "chosen": {
            "profile": choice["profile"],
            "model": choice["model"],
            "tier": choice["tier"],
            "tier_source": choice.get("tier_source"),
            "reasoning_effort": choice["reasoning_effort"],
        },
        "default": r["default"],
        "undecidable": choice["undecidable"],
        "reasons": list(choice["reasons"]),
        "blocked": blocked,
        "warnings": [],
        "features": {
            "est_tokens": feats["est_tokens"],
            "turns": feats["turns"],
            "tools": feats["has_tools"],
            "images": feats["has_images"],
        },
        "decision_latency_ms": decision.get("latency_ms", 0),
        "decision_cost_usd": decision.get("cost_usd", 0.0),
        "catalog_version": catalog()["catalog_version"],
    }
    if skipped:
        out["reasons"].insert(0, "decider skipped: " + skipped)
    if decision.get("error"):
        out["warnings"].append("decider failed: " + decision["error"])
    if decision.get("input"):
        out["decider"]["input"] = decision["input"]
    return out
