"""The router's policy: request features, the deterministic pre-filter,
signal normalization, `floor-v1` and the disclosure. Everything here is
pure; the network lives in the deciders, the bridge and the server."""

import json
import math
import re

from delegation_config import ADAPTERS, EFFORT_ORDER, ROUTER_HTTP_ADAPTERS
from delegation_catalog import bar as catalog_bar, catalog, profile_meta


POLICY_ID = "floor-v1"


POLICY_VERSION = "2026-10-19"


ROUTER_VERSION = "1"


TAGS = ("code", "math", "long", "rare", "tools")
# Numbers that look like something to compute with — an operator, a percent,
# a currency, a decimal — rather than a port, a line number or `LIMIT 1`.


NUMERIC = re.compile(
    r"\d[\d,.]*\s*[%×x*/+\-^=]\s*\d"  # 17 % of 2,340 · 3 * 4 · 2^10
    r"|[€$£¥]\s?\d"  # a currency amount
    r"|\d\s?%"  # a percentage
    r"|\b\d+\.\d+\b"  # a decimal
)


LONG_TOKENS = 20000


DEFAULT_OUTPUT_TOKENS = 1024


DECISION_TOKENS = 450


CONFIDENCE_FLOOR = 0.55


TAG_THRESHOLD = 0.6
# Where the minimum score bends, on the 0..1 difficulty scale (a 0–4 rating
# divided by 4): up to `free` (1 of 4) no minimum; at `mid` (2 of 4) the
# bottom of the mid band; from `frontier` (3 of 4) the bottom of the frontier
# band; in between, in proportion. A yes/no "needs a strong model" maps to
# the frontier from `p_strong`, to mid from `p_weak`, to no minimum below.
# The evaluation harness sweeps `frontier`; serve uses these.


CUTS = {"free": 0.25, "mid": 0.5, "frontier": 0.75, "p_strong": 0.7, "p_weak": 0.3}


# The bands of a catalog without a tiering block: tiers only, as ranks.
RANK_BAR = {"mid": 1.0, "frontier": 2.0}


EXCERPT_LIMIT = 4000


LAST_USER_LIMIT = 2048


SYSTEM_HEAD_LIMIT = 1000


FULL_LIMIT = 32000


EFFORT_ADAPTERS = {"deepseek-api", "token-plan-openai"}


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
        "has_numbers": bool(NUMERIC.search(last_user)),
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
    higher tier than the default); it is skipped only when it can do neither.
    One eligible profile that is not the default still needs the decision:
    without it the policy lands on the default, which is blocked."""
    if not eligible:
        return "no eligible profile"
    if len(eligible) == 1 and eligible[0]["profile"] == default_meta["profile"]:
        return "one eligible profile"
    bar = current_bar()
    default_score = score_of(default_meta, bar)
    default_score = -1.0 if default_score is None else default_score
    if any((score_of(m, bar) or -1.0) > default_score for m in eligible):
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


def current_bar():
    """The mid and frontier scores of the catalog in effect."""
    return catalog_bar(catalog().get("tiering")) or RANK_BAR


def score_of(meta, bar):
    """A profile's score: measured, else the bottom of its tier's band."""
    if meta.get("score") is not None:
        return meta["score"]
    return {"small": 0.0, "mid": bar["mid"], "frontier": bar["frontier"]}.get(
        meta.get("tier")
    )


def _between(d, low, high, at_low, at_high):
    if high <= low:
        return at_high
    return at_low + (d - low) / (high - low) * (at_high - at_low)


def minimum_score(verdict, bar, cuts=CUTS):
    """The weakest score the verdict allows. `code` never raises it: it
    narrows the candidates to code-capable profiles instead. math, rare and
    tools raise it to the mid band; long to the frontier band."""
    d = verdict["difficulty"]
    p = verdict["p_needs_strong"]
    tags = verdict["tags"]
    floors = []
    if d is not None:
        if d >= cuts["frontier"]:
            floors.append(bar["frontier"])
        elif d >= cuts["mid"]:
            floors.append(
                _between(d, cuts["mid"], cuts["frontier"], bar["mid"], bar["frontier"])
            )
        elif d > cuts["free"]:
            floors.append(_between(d, cuts["free"], cuts["mid"], 0.0, bar["mid"]))
        else:
            floors.append(0.0)
    if p is not None:
        if p >= cuts["p_strong"]:
            floors.append(bar["frontier"])
        elif p >= cuts["p_weak"]:
            floors.append(bar["mid"])
        else:
            floors.append(0.0)
    need = max(floors) if floors else 0.0
    if max(tags[t] for t in ("math", "rare", "tools")) >= TAG_THRESHOLD:
        need = max(need, bar["mid"])
    if tags["long"] >= TAG_THRESHOLD:
        need = max(need, bar["frontier"])
    return round(need, 1)


def _effort(verdict, chosen):
    """The reasoning setting for this request on the chosen profile, or None
    for the profile's own. `high` is a floor for the hardest requests and
    never lowers a declared `xhigh` or `max` (the setting the profile's rung
    was measured at); `low` is the documented saving on an easy request at
    the small rung. Only for adapters the server forwards the setting to."""
    if chosen.get("adapter") not in EFFORT_ADAPTERS:
        return None
    d = verdict["difficulty"]
    declared = chosen.get("effort")
    if d is not None and d >= 0.9:
        rank = EFFORT_ORDER.index
        if declared in EFFORT_ORDER and rank(declared) > rank("high"):
            return None
        return "high"
    if chosen.get("tier") == "small" and d is not None and d < 0.375:
        return "low"
    return None


def _usd(cost):
    return "unpriced" if cost == math.inf else "$%.4f" % cost


def _cheapest(candidates, feats):
    return sorted(candidates, key=lambda m: rank_cost(m, feats))[0]


def choose(verdict, eligible, default_meta, feats, cuts=CUTS, bar=None):
    """floor-v1: the policy that turns a verdict into one profile — the
    cheapest eligible profile whose score reaches the request's minimum. Pure
    but for reading the catalog's bands when `bar` is not given."""
    bar = bar or current_bar()
    reasons = []

    def default(reason):
        reasons.append(reason)
        return {
            "profile": default_meta["profile"],
            "model": default_meta["model"],
            "tier": default_meta.get("tier"),
            "tier_source": default_meta.get("tier_source"),
            "score": score_of(default_meta, bar),
            "minimum_score": None,
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
    need = minimum_score(verdict, bar, cuts)
    if verdict["difficulty"] is not None:
        reasons.append("difficulty %.2f" % verdict["difficulty"])
    if verdict["p_needs_strong"] is not None:
        reasons.append("p_needs_strong %.2f" % verdict["p_needs_strong"])
    for t in TAGS:
        if tags[t] >= TAG_THRESHOLD:
            reasons.append("tag %s %.2f" % (t, tags[t]))
    reasons.append(
        "minimum score %.1f (mid from %.1f, frontier from %.1f)"
        % (need, bar["mid"], bar["frontier"])
    )
    if not eligible:
        return default("no eligible profile → default")

    def clears(m):
        score = score_of(m, bar)
        return score is not None and score >= need

    candidates = []
    if tags["code"] >= TAG_THRESHOLD:
        candidates = [m for m in eligible if m.get("code") and clears(m)]
        if candidates:
            reasons.append("code → cheapest code-capable profile scoring ≥ %.1f" % need)
    if not candidates:
        candidates = [m for m in eligible if clears(m)]
        if candidates:
            reasons.append("cheapest profile scoring ≥ %.1f" % need)
    if candidates:
        chosen = _cheapest(candidates, feats)
    else:
        scored = [m for m in eligible if score_of(m, bar) is not None]
        if not scored:
            return default("no eligible profile has a score → default")
        coders = [m for m in scored if m.get("code")]
        if tags["code"] >= TAG_THRESHOLD and coders:
            scored = coders
        chosen = max(scored, key=lambda m: (score_of(m, bar), -rank_cost(m, feats)))
        candidates = [chosen]
        reasons.append(
            "no profile reaches %.1f → the strongest eligible: %s"
            % (need, chosen["profile"])
        )
    reasons.append(
        "%s scores %.1f, %s (%s)"
        % (
            chosen["profile"],
            score_of(chosen, bar),
            chosen.get("tier"),
            chosen.get("tier_source"),
        )
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
        "score": score_of(chosen, bar),
        "minimum_score": need,
        "reasoning_effort": _effort(verdict, chosen),
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
            "score": choice.get("score"),
            "reasoning_effort": choice["reasoning_effort"],
        },
        "minimum_score": choice.get("minimum_score"),
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
