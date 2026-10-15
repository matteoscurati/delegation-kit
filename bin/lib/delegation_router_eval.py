"""`delegation-router eval`: an offline measure of one decider against the
rules-only baseline, on a golden set the user assembled.

The set lives outside the repository. Each JSONL line is one item:

  {"id": "...", "prompt": "...", "paraphrases": ["..."],
   "outcomes": {"<profile>": {"correct": true, "cost_usd": 0.0031}},
   "oracle": {"cheapest_correct": "<profile>"}}        # optional

`outcomes` records what each pool profile did on that prompt when it was run
(by the user, elsewhere): whether the answer was right and what it cost. The
harness never dispatches a pool profile; it only asks the decider — once per
prompt and paraphrase — and looks the chosen profile up in `outcomes`. Calling
the decider is the user's choice: the command names it."""

import json
import statistics

from delegation_config import ROUTER_DECIDERS
from delegation_router_policy import (
    CUTS,
    choose,
    pool_meta,
    prefilter,
    verdict_from_signals,
)
from delegation_router_pipeline import route

CURVE = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9]
GATE = {
    "accuracy_drop_max": 0.02,
    "cost_ratio_max": 0.8,
    "optimal_selection_min": 0.40,
    "robustness_min": 0.85,
    "latency_p95_ms_max": {"default": 300, "dipylon": 1200, "llm": 1500},
    "undecidable_max": 0.15,
    "decision_cost_share_max": 0.10,
}


def read_items(path):
    items = []
    with open(path) as f:
        for number, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            item = json.loads(line)
            if (
                not isinstance(item, dict)
                or not isinstance(item.get("prompt"), str)
                or not isinstance(item.get("outcomes"), dict)
            ):
                raise ValueError("item %d: prompt and outcomes are required" % number)
            item.setdefault("id", "item-%d" % number)
            item.setdefault("paraphrases", [])
            items.append(item)
    if not items:
        raise ValueError("no items")
    return items


def oracle_for(item):
    declared = item.get("oracle") or {}
    if declared.get("cheapest_correct"):
        return declared["cheapest_correct"]
    correct = [
        (o.get("cost_usd") if o.get("cost_usd") is not None else float("inf"), key)
        for key, o in item["outcomes"].items()
        if o.get("correct")
    ]
    return min(correct)[1] if correct else None


def percentile(values, p):
    if not values:
        return None
    ordered = sorted(values)
    index = min(len(ordered) - 1, max(0, round(p * (len(ordered) - 1))))
    return ordered[index]


def evaluate(c, items, decider_kind, input_mode=None, opener=None, env=None):
    """Decide every prompt once; score against outcomes; sweep the frontier cut."""
    r = c["router"]
    pool = pool_meta(c)
    by_key = {m["profile"]: m for m in pool}
    default_meta = by_key[r["default"]]
    decisions = []
    decider = None
    for item in items:
        for index, text in enumerate([item["prompt"], *item["paraphrases"]]):
            body = {"messages": [{"role": "user", "content": text}]}
            # Always the decider's own choice: under `mode: shadow` route()
            # would hand back the default and the measure would be of nothing.
            out, choice, feats, _blocked = route(
                c,
                body,
                decider_kind=decider_kind,
                input_mode=input_mode,
                mode="route",
                opener=opener,
                env=env,
            )
            decider = out["decider"]
            decisions.append(
                {
                    "item": item["id"],
                    "paraphrase": index,
                    "chosen": choice["profile"],
                    "tier": choice.get("tier"),
                    "undecidable": out["undecidable"],
                    "latency_ms": out["decision_latency_ms"],
                    "decision_cost_usd": out["decision_cost_usd"] or 0.0,
                    "signals": out["signals"],
                    "feats": feats,
                }
            )
    report = {
        "decider": {k: decider.get(k) for k in ("id", "version")} if decider else None,
        "items": len(items),
        "prompts": len(decisions),
        "metrics": score(items, decisions, default_meta["profile"]),
        # The rules-only baseline: the default on every prompt, no decider
        # call, so no decision cost or latency of its own.
        "baseline": score(
            items,
            [
                dict(
                    d,
                    chosen=default_meta["profile"],
                    tier=default_meta.get("tier"),
                    undecidable=True,
                    latency_ms=0,
                    decision_cost_usd=0.0,
                )
                for d in decisions
            ],
            default_meta["profile"],
        ),
    }
    report["curve"] = curve(items, decisions, pool, default_meta)
    report["gate"] = gate(report, decider_kind)
    return report


def score(items, decisions, default_key):
    by_id = {item["id"]: item for item in items}
    main = [d for d in decisions if d["paraphrase"] == 0]
    correct = costs = optimal = unknown = 0
    decision_cost = sum(d["decision_cost_usd"] for d in decisions)
    for d in main:
        outcome = by_id[d["item"]]["outcomes"].get(d["chosen"])
        if outcome is None:
            unknown += 1
            continue
        correct += 1 if outcome.get("correct") else 0
        costs += outcome.get("cost_usd") or 0.0
        optimal += 1 if d["chosen"] == oracle_for(by_id[d["item"]]) else 0
    scored = len(main) - unknown
    tiers = {}
    for d in decisions:
        tiers.setdefault(d["item"], {})[d["paraphrase"]] = d["tier"]
    pairs = [(t[0], t[k]) for t in tiers.values() for k in t if k != 0 and 0 in t]
    latencies = [d["latency_ms"] for d in decisions]
    return {
        "scored": scored,
        "unknown_outcomes": unknown,
        "accuracy": correct / scored if scored else None,
        "cost_usd": costs,
        "decision_cost_usd": round(decision_cost, 6),
        "optimal_selection_ratio": optimal / scored if scored else None,
        "robustness": (sum(1 for a, b in pairs if a == b) / len(pairs))
        if pairs
        else None,
        "undecidable_rate": sum(1 for d in decisions if d["undecidable"])
        / len(decisions),
        "latency_ms": {
            "p50": percentile(latencies, 0.5),
            "p95": percentile(latencies, 0.95),
            "mean": round(statistics.fmean(latencies), 1) if latencies else None,
        },
    }


def curve(items, decisions, pool, default_meta):
    """Re-choose every decision at each frontier cut, without a decider call."""
    points = []
    for cut in CURVE:
        cuts = dict(CUTS, frontier=cut, small=min(CUTS["small"], cut))
        rechosen = []
        for d in decisions:
            verdict = verdict_from_signals(d["signals"])
            eligible, _ = prefilter(pool, d["feats"], None, default_meta["profile"])
            choice = choose(verdict, eligible, default_meta, d["feats"], cuts)
            rechosen.append(dict(d, chosen=choice["profile"], tier=choice.get("tier")))
        s = score(items, rechosen, default_meta["profile"])
        points.append(
            {
                "frontier_cut": cut,
                "accuracy": s["accuracy"],
                "cost_usd": s["cost_usd"],
                "optimal_selection_ratio": s["optimal_selection_ratio"],
            }
        )
    return points


def gate(report, decider_kind):
    m, b = report["metrics"], report["baseline"]
    p95_limit = GATE["latency_p95_ms_max"].get(
        decider_kind, GATE["latency_p95_ms_max"]["default"]
    )
    saving = (b["cost_usd"] or 0.0) - (m["cost_usd"] or 0.0)
    checks = {
        "accuracy": m["accuracy"] is not None
        and b["accuracy"] is not None
        and m["accuracy"] >= b["accuracy"] - GATE["accuracy_drop_max"],
        "cost": b["cost_usd"] > 0
        and m["cost_usd"] <= GATE["cost_ratio_max"] * b["cost_usd"],
        "optimal_selection": (m["optimal_selection_ratio"] or 0.0)
        >= GATE["optimal_selection_min"],
        "robustness": m["robustness"] is None
        or m["robustness"] >= GATE["robustness_min"],
        "latency_p95": m["latency_ms"]["p95"] is not None
        and m["latency_ms"]["p95"] <= p95_limit,
        "undecidable": m["undecidable_rate"] <= GATE["undecidable_max"],
        "decision_cost": saving > 0
        and m["decision_cost_usd"] <= GATE["decision_cost_share_max"] * saving,
    }
    return {
        "accepted": all(checks.values()) and decider_kind in ROUTER_DECIDERS - {"none"},
        "checks": checks,
        "thresholds": dict(GATE, latency_p95_ms_max=p95_limit),
    }
