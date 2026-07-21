# Model routing for orchestrated coding

Delegation policy for driving coding work across several models — a strong one
plans and judges, cheaper ones execute. It answers one question: **which model
does which job.**

> **Evidence, not inherited scores.** Routing is based on a dated snapshot of
> recent public benchmarks plus a small local compatibility check. Keep model,
> harness, effort, and lane distinct: a strong WebDev result is not a reviewer
> qualification, and an available runtime is not evidence of quality.
>
> **Using this in the [delegation kit](./README.md)?** The snapshot below is a
> worked reference. See [`ADAPTING.md`](./ADAPTING.md) to map its evidence to
> your own available variants, plans, and lane thresholds.

## Current evidence snapshot

The machine-readable source is
[`config/model-evidence.json`](./config/model-evidence.json); the method and source
links are in [`evaluation/README.md`](./evaluation/README.md). Inspect it with:

```sh
bin/delegation-evidence check
bin/delegation-evidence lane builder
bin/delegation-evidence lane reviewer --json
bin/delegation-route check
bin/delegation-route resolve --lane judgement --json
bin/delegation-route resolve --lane super-judgement --json
```

The 2026-07-21 snapshot uses Artificial Analysis Coding Agent Index v1.2 for
end-to-end coding, Agent Arena for real-world reliability, Code Arena WebDev for
frontend preference, and SWE-PRBench/Martian for review. It stores raw metrics
rather than compressing unrelated capabilities into subjective 1–10 scores.

| exact model + harness + effort | coding index | DeepSWE | Terminal-Bench | repo Q&A | API cost/task |
|---|---:|---:|---:|---:|---:|
| GPT-5.6 Sol + Codex, max | 61 | 69% | 88% | 27% | $7.08 |
| Fable 5 + Claude Code, max | 59 | 66% | 83% | 29% | $11.72 |
| Kimi K3 + Kimi Code CLI, max | 57 | 64% | 84% | 23% | $3.18 |
| GPT-5.6 Terra + Codex, max | 57 | 67% | 84% | 21% | $2.76 |
| Opus 4.8 + Claude Code, max | 55 | 56% | 79% | 30% | $7.70 |
| GPT-5.6 Luna + Codex, max | 54 | 63% | 80% | 18% | $1.57 |
| GLM-5.2 + Claude Code, reported default | 40 | 29% | 72% | 19% | $6.51 |

These are API-equivalent costs, not subscription-bucket economics. Agent Arena
and WebDev rows live in the JSON because their variants often differ from the
coding-index variants; the kit never silently merges `max`, `xhigh`, `high`, or
`reported-default`.

The operational gate separates exact evidence from contextual evidence. Exact
requires the same model, harness, and effort and must be relevant to the lane;
nearby variants and general coding scores for reviewer/judgement remain context.
`delegation-route table` exposes both counts plus local sample confidence.

Where published, the JSON also records the exact installed Codex efforts: Luna
`low`, Terra `low`/`medium`, and Sol `high`. Exact current rows for several
installed Claude efforts are not published in this snapshot, so their nearby
variants remain contextual evidence rather than profile-level validation.

Evidence maps to lanes, not to one global ranking:

- **Clerk/scout:** repository Q&A first; cost, tool reliability, and steerability
  support the decision.
- **Builder:** both DeepSWE and Terminal-Bench. WebDev Elo can support a separate
  frontend-builder decision only.
- **Reviewer:** precision and recall from SWE-PRBench or Martian. No coding or
  WebDev score substitutes for this; the current snapshot has no exact-model
  review rows, so public evidence alone qualifies no reviewer.
- **Senior/judgement:** real-world steerability and user outcomes are supporting
  evidence. Judgement remains manual-only; security-sensitive work needs its own
  evaluation.

External evidence never edits a routing gate. The gate records the owner decision,
and the local smoke proves only runtime/auth, tool use, permissions, scope, and
output contracts for the exact production runner.

## Reasoning effort per model

Effort levels each model exposes (Claude `effort:` / Codex `model_reasoning_effort`). Author's mapping — verify for your models; the deeper tiers live only on the frontier reasoners.

| model | supported effort |
|---|---|
| fable-5 | low · medium · high · xhigh · max |
| opus-4.8 | low · medium · high · xhigh |
| gpt-5.6-sol | low · medium · high |
| gpt-5.6-terra | low · medium · high |
| gpt-5.6-luna | low · medium · high |
| sonnet-5 | low · medium · high |
| gpt-5.5 | low · medium · high |
| glm-5.2 | high · max |
| kimi-k3 | max |

Kimi K3 is provisional: the 2026-07-16 run was truncated by provider quota. Its
valid subset and exact public rows support controlled `clerk`, `scout`, `builder`,
and `frontend-builder` use with `--allow-provisional`; `senior` is only a blocked
candidate. The installed gate remains authoritative for the exact tuple.

## Judgement and super-judgement

Fable `xhigh` and Sol `high` are both manually qualified for judgement by an
explicit owner decision, not by an automatic benchmark threshold. Fable focuses
on architecture, trade-offs, and synthesis; Sol focuses on repository fit,
technical feasibility, failure modes, and verifiability. Inspect the decision with
`delegation-route resolve --lane judgement`.

For exceptionally complex, high-blast-radius, difficult-to-reverse decisions,
`super-judgement` pairs them using `independent-then-cross-review`: both write an
independent verdict before seeing the other, then critique each other, and the
lead records the final decision. It requires an explicit choice, never dispatches
automatically, and never merges or deploys.

## How to apply

- **These are defaults, not limits.** Judge the output, not the price tag: if a
  cheaper model's result doesn't meet the bar, redo it on a smarter one. Escalating
  costs less than shipping mediocre work.
- **When to delegate at all.** Default to handling work inline. Delegate the
  clear-spec, mechanical, or high-volume stuff (bulk implementation, migrations,
  data crunching) to the cheap-and-capable lane; reach for a multi-agent
  orchestration only on an explicit decision, never on autopilot.
- **A long or open-ended run is bottlenecked by unknowns, not intelligence.** The
  burn is the un-tuned prompt that drifts into a second and third attempt. Spend
  cheap tokens up front to surface the unknowns — a *blindspot pass* on unfamiliar
  ground, an interview one question at a time (prioritize answers that would change
  the architecture), a plan that leads with the decisions most likely to move
  (data models, interfaces, UX) before any code. Point at reference source instead
  of describing in prose. Keep an implementation-notes log of deviations during the
  run, and quiz yourself on the diff before merge. Each is cheaper than the re-run
  it prevents.
- **Delegated output is unverified until you check it.** Never ship or build on a
  delegated diff or finding without reading it or reproducing the claim — polished
  output is not correct output.
- **Cost is a tie-breaker only.** Required lane evidence and deliverable quality
  come first; then domain-specific taste/reliability evidence; then cost.
- **`cost` is per *task*, not per token.** A model that burns more tokens at a
  lower price can still finish the job cheapest — measured, `gpt-5.6-luna` is the
  cheapest per completed task, verbosity included. Don't up-tier to "save tokens";
  price the task, not the token.
- **Size the reviewer to the work, not to the top of a general leaderboard.** The
  reviewer only needs to be *at least as capable* as what it reviews. A diff the cheap lane
  wrote against a plan the strong model authored is reviewed by the *mid* model
  that already has the context — you don't spend your most expensive model on a
  review it isn't uniquely needed for. Reserve the top model as reviewer for when
  its gradient is actually required: high-level design/taste judgement, synthesis
  across multiple attempts, or independently checking something it produced.
- **Judgement models do thinking, not typing.** Fable handles architecture,
  trade-offs, and synthesis; Sol handles technical feasibility, repository fit,
  failure modes, and verifiability. Neither produces the diff when selected as a
  judge. Use the pair only through the explicit super-judgement protocol.
- **Route security-adjacent work to the reasoning model directly.** Anthropic's
  classifier reroutes blocked prompts to Opus 4.8 anyway, so a security-shaped
  Fable call either reroutes or comes back thinner — start on Opus and skip the
  tax. (The broader "benign defensive work gets caught too" claim is unconfirmed
  by Anthropic; don't over-route on it.)
- **Anything user-facing** (UI, copy, API design) needs a high-taste model.
- **The cheap mid model has no first-class lane of its own** in this policy — use
  it as the driver/wrapper (the thin agents that shell out to the cheap execution
  lane), not the model you hand a hard task to.

## The orchestrator pattern

The concrete shape most of this reduces to:

1. The strong model reads the codebase, writes the plan, breaks it into tasks.
2. Sub-agents on cheaper models execute each task.
3. The strong model reviews the merged result.

You pay premium prices for *judgement*, twice (plan + review), and plan-included
prices for the keystrokes in between.

## Before a model earns a lane

1. **Select the exact production variant.** Model, harness, effort, backend, and
   permissions are part of the identity. Never inherit a neighboring variant's
   score.
2. **Inspect lane-specific evidence.** Run `delegation-evidence lane <lane>`.
   Builder needs DeepSWE plus Terminal-Bench; reviewer needs review precision and
   recall; WebDev Elo applies only to frontend work.
3. **Pre-commit the decision.** Name the incumbent, threshold, fallback, and
   provisional/qualified outcome before inspecting a new local run.
4. **Run a small local compatibility smoke.** Check runtime/auth, tool use,
   permission boundaries, scoped edits, output contracts, and concurrency where
   relevant. This smoke does not re-score general model quality.
5. **Record the owner decision in the versioned gate.** External evidence never
   mutates a decision. `status` records evidence confidence; `selection` records
   whether a profile is default, fallback, explicit-only, or blocked.
6. **Refresh or disable.** A stale evidence snapshot (currently >45 days) blocks
   new qualification decisions until its live sources are checked again.

The current GLM gate keeps `clerk` and `scout` provisional and makes builder a
blocked candidate. Kimi K3 is provisional for `clerk`, `scout`, `builder`, and
`frontend-builder`; senior is a blocked candidate, while reviewer and judgement
remain disabled. Provisional bridge runs require `--allow-provisional`.
