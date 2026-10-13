"""The router pipeline for one chat body, and the `check` report.

route() never dispatches the chosen profile; it only decides and discloses.
The server dispatches after route() when the user runs `serve`."""

from delegation_config import catalog, profile_meta
from delegation_router import (
    choose,
    disclosure,
    features,
    normalize,
    pool_meta,
    prefilter,
    pretags,
    skip_reason,
)
from delegation_router_deciders import build


def router_block(c):
    r = c.get("router")
    if not r:
        raise ValueError("router not configured")
    return r


def route(
    c,
    body,
    decider_kind=None,
    input_mode=None,
    ceiling=None,
    mode=None,
    opener=None,
    env=None,
):
    """Run the pipeline. Returns (router object, choice, feats, blocked)."""
    r = router_block(c)
    cat = catalog()
    pool = pool_meta(c, cat)
    by_key = {m["profile"]: m for m in pool}
    feats = features(body)
    ceiling = r.get("max_cost_usd") if ceiling is None else ceiling
    eligible, blocked = prefilter(pool, feats, ceiling, r["default"])
    default_meta = by_key[r["default"]]
    decider_cfg = r.get("decider", {"kind": "llm"})
    kind = decider_kind or decider_cfg.get("kind", "llm")
    mode = mode or r.get("mode", "route")
    input_mode = input_mode or decider_cfg.get("input", "excerpt")
    decider = build(
        kind,
        c,
        decider_cfg,
        lambda k, p: profile_meta(k, p, cat),
        opener=opener,
        env=env,
    )
    decider_meta = None
    if kind == "llm":
        key = decider_cfg.get("profile", r["default"])
        decider_meta = by_key.get(key) or profile_meta(key, c["profiles"][key], cat)
    skipped = skip_reason(eligible, default_meta, decider_meta, feats)
    if skipped or kind == "none":
        decision = {
            "decider": {"id": decider.id, "version": decider.version},
            "signals": [],
            "latency_ms": 0,
            "cost_usd": 0.0,
        }
        skipped = skipped if kind != "none" else None
    else:
        decision = decider.decide(body, feats, input_mode)
    verdict = normalize(decision["signals"])
    for tag, value in pretags(feats).items():
        verdict["tags"][tag] = max(verdict["tags"][tag], value)
    choice = choose(verdict, eligible, default_meta, feats)
    out = disclosure(c, feats, verdict, choice, decision, blocked, skipped, mode)
    if decision.get("reason"):
        out["decider"]["reason"] = decision["reason"]
    if mode == "shadow" and choice["profile"] != r["default"]:
        out["shadow"] = dict(out["chosen"])
        out["chosen"] = {
            "profile": default_meta["profile"],
            "model": default_meta["model"],
            "tier": default_meta.get("tier"),
            "reasoning_effort": None,
        }
        out["reasons"].append("shadow mode → default dispatched, choice recorded")
        choice = dict(
            choice,
            profile=default_meta["profile"],
            model=default_meta["model"],
            tier=default_meta.get("tier"),
            reasoning_effort=None,
        )
    return out, choice, feats, blocked


def explicit(c, profile_key, body):
    """A request that names a pool profile itself: no decider, full disclosure."""
    r = router_block(c)
    if profile_key not in r["pool"]:
        raise KeyError(profile_key)
    cat = catalog()
    meta = profile_meta(profile_key, c["profiles"][profile_key], cat)
    feats = features(body)
    choice = {
        "profile": meta["profile"],
        "model": meta["model"],
        "tier": meta.get("tier"),
        "reasoning_effort": None,
        "reasons": ["explicit profile → no decider"],
        "undecidable": False,
    }
    verdict = normalize([])
    decision = {"decider": {"id": "none", "version": "explicit"}, "signals": []}
    out = disclosure(c, feats, verdict, choice, decision, [], None, "explicit")
    out["undecidable"] = False
    return out, choice, feats, []


def check(c):
    r = c.get("router")
    result = {
        "schema_version": 1,
        "read_only": True,
        "automatic_dispatch": False,
        "requires_user_direction": True,
        "authorization_granted": False,
        "valid": True,
        "catalog_version": catalog()["catalog_version"],
        "enabled": bool(r),
    }
    if not r:
        result["summary"] = (
            "router not configured; add a router block (schema_version 2) to enable it"
        )
        return result
    pool = pool_meta(c)
    warnings = []
    for m in pool:
        if m["tier"] is None:
            warnings.append(m["profile"] + ": no tier declared; usable only as default")
        if m["price"] is None:
            warnings.append(
                m["profile"] + ": no per-token price; ranked last within its tier"
            )
    decider = dict(r.get("decider", {"kind": "llm"}))
    decider.setdefault("kind", "llm")
    if decider["kind"] == "llm":
        decider.setdefault("profile", r["default"])
    decider.setdefault("input", "excerpt")
    result.update(
        listen=r.get("listen", "127.0.0.1:4141"),
        mode=r.get("mode", "route"),
        default=r["default"],
        decider=decider,
        max_cost_usd=r.get("max_cost_usd"),
        receipts=r.get("receipts", False),
        pool=[
            {
                key: m[key]
                for key in (
                    "profile",
                    "model",
                    "adapter",
                    "tier",
                    "code",
                    "price",
                    "context",
                    "metadata_source",
                )
            }
            for m in pool
        ],
        warnings=warnings,
    )
    return result
