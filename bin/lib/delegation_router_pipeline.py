"""The router pipeline for one chat body, and the `check` report.

route() never dispatches the chosen profile; it only decides and discloses.
The server dispatches after route() when the user runs `serve`."""

from delegation_catalog import catalog, profile_meta
from delegation_config import ROUTER_HTTP_ADAPTERS, SERVICE_DECIDERS, row
from delegation_router_policy import (
    CUTS,
    choose,
    disclosure,
    features,
    native_lane,
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


def takes_lane(c, key, lane):
    """The check `delegation-run` makes before it dispatches a profile on a
    role: the profile declares the role and its adapter implements it."""
    profile = c["profiles"][key]
    return (
        lane in profile["roles"]
        and row(key, profile, lane, c)["technical_compatibility"]
    )


def route(
    c,
    body,
    decider_kind=None,
    input_mode=None,
    ceiling=None,
    mode=None,
    opener=None,
    env=None,
    cuts=None,
    raw=False,
    lane=None,
    reach=None,
):
    """Run the pipeline. Returns (router object, choice, feats, blocked).

    `lane` (decide only) narrows the pool to the profiles that take that role,
    so a delegated task is recommended a profile `delegation-run` will run on
    it; a decision that lands on a default without the role recommends
    nothing.

    `reach` maps pool profiles to why this machine cannot dispatch them (see
    `delegation_credentials.reachability`); those are set aside before the
    decision, like a context too small, and listed under `blocked`."""
    r = router_block(c)
    cat = catalog()
    pool = pool_meta(c, cat)
    full = {m["profile"]: m for m in pool}
    lane_blocked = []
    if reach:
        lane_blocked = [
            {"profile": m["profile"], "reason": "unreachable: " + reach[m["profile"]]}
            for m in pool
            if reach.get(m["profile"])
        ]
        pool = [m for m in pool if not reach.get(m["profile"])]
    if lane is not None:
        takes = [m for m in pool if takes_lane(c, m["profile"], lane)]
        if not takes:
            raise ValueError(
                "no %spool profile takes the %s role"
                % ("reachable " if lane_blocked else "", lane)
            )
        lane_blocked += [
            {"profile": m["profile"], "reason": "does not take the %s role" % lane}
            for m in pool
            if m not in takes
        ]
        pool = takes
    by_key = {m["profile"]: m for m in pool}
    feats = features(body)
    ceiling = r.get("max_cost_usd") if ceiling is None else ceiling
    eligible, blocked = prefilter(pool, feats, ceiling, r["default"])
    blocked = lane_blocked + blocked
    default_meta = full[r["default"]]
    decider_cfg = r["decider"]
    kind = decider_kind or decider_cfg["kind"]
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
    elif kind != "none":
        decider_meta = {"price": decider.price}
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
    choice = choose(verdict, eligible, default_meta, feats, cuts or CUTS)
    if lane is not None and choice["profile"] not in by_key:
        why = (
            "is unreachable (%s)" % reach[choice["profile"]]
            if reach and reach.get(choice["profile"])
            else "does not take the %s role" % lane
        )
        raise ValueError(
            "%s; the default %s %s, so there is no recommendation: choose a "
            "profile by hand" % (choice["reasons"][-1], choice["profile"], why)
        )
    out = disclosure(c, feats, verdict, choice, decision, blocked, skipped, mode)
    if lane is not None:
        out["lane"] = lane
        out["chosen"]["capabilities"] = row(
            choice["profile"], c["profiles"][choice["profile"]], lane, c
        )["capabilities"]
    if decision.get("reason"):
        out["decider"]["reason"] = decision["reason"]
    if raw and "raw" in decision:
        # The service's own answer, for checking what the signals were read
        # from; never in a served response, only on `decide --raw`.
        out["decider"]["raw"] = decision["raw"]
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


def explicit(c, profile_key, body, ceiling=None):
    """A request that names a pool profile itself: no decider, full disclosure.
    The context and cost rules still apply; only the tier rule does not, since
    nothing is being chosen."""
    r = router_block(c)
    if profile_key not in r["pool"]:
        raise KeyError(profile_key)
    cat = catalog()
    meta = profile_meta(profile_key, c["profiles"][profile_key], cat)
    feats = features(body)
    ceiling = r.get("max_cost_usd") if ceiling is None else ceiling
    _eligible, blocked = prefilter([meta], feats, ceiling, profile_key)
    choice = {
        "profile": meta["profile"],
        "model": meta["model"],
        "tier": meta.get("tier"),
        "tier_source": meta.get("tier_source"),
        "reasoning_effort": None,
        "reasons": ["explicit profile → no decider"],
        "undecidable": False,
    }
    verdict = normalize([])
    decision = {"decider": {"id": "none", "version": "explicit"}, "signals": []}
    out = disclosure(c, feats, verdict, choice, decision, blocked, None, "explicit")
    out["undecidable"] = False
    return out, choice, feats, blocked


def describe_decider(c, r):
    """The decision model as the user declared it, defaults filled in, no
    secret values: what `check`, `serve` and doctor show first."""
    decider = dict(r["decider"])
    if decider["kind"] == "llm":
        key = decider.setdefault("profile", r["default"])
        profile = c["profiles"][key]
        decider["model"] = profile["model"]
        decider["adapter"] = profile["adapter"]
        decider.setdefault("timeout", 3)
    elif decider["kind"] in SERVICE_DECIDERS:
        from delegation_router_deciders import SERVICE_DEFAULTS

        defaults = SERVICE_DEFAULTS[decider["kind"]]
        for key in ("url", "credential_env", "model", "price"):
            if key in defaults and key not in decider:
                decider[key] = defaults[key]
        decider.setdefault("timeout", defaults["timeout"])
    decider.setdefault("input", "excerpt")
    return decider


def decider_line(decider):
    kind = decider["kind"]
    if kind == "none":
        return "decider: none — rules only; every request goes to the default"
    if kind == "llm":
        return "decider: llm — profile %s (%s/%s), input %s, timeout %ss" % (
            decider["profile"],
            decider["adapter"],
            decider["model"],
            decider["input"],
            decider["timeout"],
        )
    parts = [decider.get("url") or "url not set"]
    if decider.get("credential_env"):
        parts.append("key " + decider["credential_env"])
    if decider.get("model"):
        parts.append("model " + decider["model"])
    parts.append("timeout %ss" % decider.get("timeout"))
    return "decider: %s — %s" % (kind, ", ".join(parts))


def reach_keys(c):
    """The profiles whose reachability matters: the pool and an llm decider."""
    r = c["router"]
    keys = list(r["pool"])
    decider = r["decider"]
    if decider.get("kind") == "llm":
        key = decider.get("profile", r["default"])
        if key not in keys:
            keys.append(key)
    return keys


def check(c, reach=None):
    r = c.get("router")
    result = {
        "schema_version": 1,
        "read_only": True,
        "automatic_dispatch": False,
        "requires_user_direction": True,
        "authorization_granted": False,
        "valid": True,
        "catalog_version": catalog()["catalog_version"],
        "catalog_source": catalog().get("catalog_source", "shipped"),
        "enabled": bool(r),
    }
    if not r:
        result["summary"] = (
            "router not configured; a router block naming a decider and the "
            "profiles it governs enables it"
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
        if m["adapter"] not in ROUTER_HTTP_ADAPTERS:
            lane = native_lane(c["profiles"][m["profile"]])
            if lane is None:
                warnings.append(m["profile"] + ": native profile with no routable role")
            else:
                m["lane"] = lane
                warnings.append(
                    m["profile"]
                    + ": native profile, bridged through delegation-run on the %s role; "
                    "no tools, images or JSON mode, one event when streaming" % lane
                )
    for key, why in (reach or {}).items():
        if not why:
            continue
        if key == r["default"]:
            warnings.append(
                "%s: the default is unreachable on this machine (%s); a request "
                "that lands on it is refused as no-usable-candidate" % (key, why)
            )
        elif key in r["pool"]:
            warnings.append(
                "%s: unreachable on this machine (%s); the router sets it aside"
                % (key, why)
            )
        else:
            warnings.append(
                "%s: the decider is unreachable on this machine (%s); every "
                "request goes to the default" % (key, why)
            )
    for m in pool:
        if reach is not None:
            m["reachable"] = not reach.get(m["profile"])
    decider = describe_decider(c, r)
    result.update(
        decider=decider,
        summary="%s governs %d profiles, default %s"
        % (decider_line(decider), len(pool), r["default"]),
        pool=[
            {
                key: m[key]
                for key in (
                    "profile",
                    "model",
                    "adapter",
                    "tier",
                    "tier_source",
                    "score",
                    "code",
                    "price",
                    "context",
                    "metadata_source",
                    "lane",
                    "reachable",
                )
                if key in m
            }
            for m in pool
        ],
        default=r["default"],
        listen=r.get("listen", "127.0.0.1:4141"),
        mode=r.get("mode", "route"),
        max_cost_usd=r.get("max_cost_usd"),
        receipts=r.get("receipts", False),
        warnings=warnings,
    )
    return result
