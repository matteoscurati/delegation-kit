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

The snapshot observed through 2026-07-28 uses Artificial Analysis Coding Agent
Index v1.3 for end-to-end coding, Agent Arena for real-world reliability, Code
Arena WebDev for frontend preference, SWE-PRBench/Martian for review, and
CursorBench, FrontierCode, FrontierSWE, APEX-SWE, OpenBench, and Epoch's ZIP as
separately labeled context. It stores raw metrics rather than compressing
unrelated capabilities into subjective 1–10 scores.

| current exact model + harness + effort | coding index | DeepSWE | Terminal-Bench | repo Q&A | API cost/task |
|---|---:|---:|---:|---:|---:|
| Claude Opus 5 + Claude Code, xhigh (lead) | 67 | 60% | 85% | 55% | $8.23 |
| GPT-5.6 Sol + Codex, high | 64 | 65% | 83% | 45% | $4.14 |
| Grok 4.5 + Grok Build, high | 64 | 60% | 85% | 48% | $2.59 |
| Claude Opus 5 + Claude Code, high | 63 | 61% | 80% | 49% | $3.80 |
| Kimi K3 + Kimi Code CLI, max | 61 | 64% | 84% | 37% | $3.18 |
| GPT-5.6 Terra + Codex, medium | 48 | 46% | 69% | 28% | $0.90 |
| GLM-5.2 + Claude Code, reported default | 43 | 29% | 72% | 29% | $6.51 |
| GPT-5.6 Terra + Codex, low | 37 | 30% | 58% | 23% | $0.48 |
| GPT-5.6 Luna + Codex, low | 25 | 10% | 50% | 15% | $0.21 |

These are API-equivalent costs, not subscription-bucket economics. Agent Arena
and WebDev rows live in the JSON because their variants often differ from the
coding-index variants; the kit never silently merges `max`, `xhigh`, `high`, or
`reported-default`.

The operational gate separates exact evidence from contextual evidence. Exact
requires the same model, harness, and effort and must be relevant to the lane;
nearby variants and general coding scores for reviewer/judgement remain context.
`delegation-route table` exposes both counts plus local sample confidence.

The JSON now records current exact installed rows for Luna `low`, Terra
`low`/`medium`, Sol `high`, Opus 5 `xhigh`/`high`, Kimi K3 `max`, and Grok 4.5
`high`. The 2026-07-28 index adds the lead lane's own tuple: Opus 5 through
Claude Code at `xhigh` enters at 67, jointly ahead of Codex Sol `max`, with the
highest repo-Q&A score on the board (55%) at $8.23 per task. Opus 5 `max` is
recorded alongside it at 66 as non-installed context. Those rows measure coding,
not review precision/recall, so they remain insufficient to qualify senior or
security work. Fable `xhigh` has exact-variant FrontierCode evidence but no
judgement benchmark. Sonnet's CursorBench and WebDev rows use different
harnesses. GLM's public rows still do not match the production Claude→Z.AI
bridge.

The reviewer lane still has zero qualifying rows. Martian's online tracker
refreshed through 2026-07-28 (3,990 scored PRs), but it ranks review *products*
— Greptile, Codex Connector, CodeRabbit, Claude — not a model at a named effort,
so it cannot satisfy `review.precision_pct`/`review.recall_pct` for any lane.

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
| opus-5 | low · medium · high · xhigh · max |
| gpt-5.6-sol | low · medium · high |
| gpt-5.6-terra | low · medium · high |
| gpt-5.6-luna | low · medium · high |
| sonnet-5 | low · medium · high |
| gpt-5.5 | low · medium · high |
| glm-5.2 | high · max |
| kimi-k3 | max |
| gemini-3.6-flash | medium (scout provisional) · high (editing candidate) |
| qwen3.8-max-preview | xhigh (candidate; evaluation only) |
| grok-4.5 | high (builder and frontend-builder provisional) |

Kimi K3 is provisional: the 2026-07-16 run was truncated by provider quota. Its
valid subset and exact public rows support controlled `clerk`, `scout`, `builder`,
and `frontend-builder` use with `--allow-provisional`; `senior` is only a blocked
candidate. The installed gate remains authoritative for the exact tuple.

Qwen3.8 Max Preview is a blocked Token Plan candidate. The July 25 audit found
no exact row in Artificial Analysis, Arena, WebDev, OpenBench, or Epoch's ZIP,
and the July 28 re-check of Agent Arena (42 models) and WebDev (19 labs) still
found none — both boards list Qwen3.7, not 3.8. The subscription and runner
establish availability only; there is no exact public benchmark or local lane
evaluation in this repository yet. Normal dispatch is therefore refused.

Gemini 3.6 Flash is reachable through the authenticated Antigravity CLI. Its
public evidence consists of CursorBench scores at `medium` (51.2) and `high`
(53.5), a preliminary WebDev result (1527 ±13), and — new on 2026-07-27 — a
first Agent Arena row. That Arena row rests on 2,194 sessions, so its intervals
swamp the estimates (net improvement 0.61% ±2.95%) and it moves nothing. All
are contextual because they use Cursor/Arena rather than the production `agy`
harness. Only the exact
`gemini-3.6-flash-medium` scout tuple is provisional and requires
`--allow-provisional`; high-effort editing lanes remain blocked pending scoped
local evaluation. Runtime discovery is compatibility evidence, not qualification.
The Antigravity bridge is prompt-only: the lead supplies selected file excerpts
in the brief. The runner uses an empty temporary workspace and home, retains
only macOS Keychain access for OAuth, and explicitly denies every tool namespace.

Grok 4.5 is provisional for `builder` and `frontend-builder` through Grok Build
CLI at `high`. The exact Artificial Analysis coding row supports builder; the
WebDev and OpenBench rows are contextual support. The owner promotion is
explicit, and the local run proves only runtime, JSON extraction, scoped writes,
and sandbox compatibility. Dispatch still requires `--allow-provisional`; the
runner capability-probes the CLI, isolates HOME, disables plugins/MCP/imported
config, requires an attested custom sandbox, and caps turns and wall time. The
observed version is provenance only; an optional digest-checked private archive
preserves the exact user-selected bytes independently of PATH.

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
- **Route security-adjacent work to Opus 5 directly.** Anthropic states that
  flagged cyber requests in Claude Code may fall back from Opus 5 to Opus 4.8
  by default. The gate declares this provider fallback explicitly: the security
  lane requests Opus 5 but is not exact-variant guaranteed when the classifier
  fires. Inspect surfaced model identity or use Anthropic's CVP where exact
  identity is mandatory. The broader claim that benign defensive work is
  routinely caught is unconfirmed; do not over-route on it.
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
Grok 4.5 is provisional for `builder` and `frontend-builder` through Grok Build
CLI at `high`; builder is explicit-only and frontend-builder is
preferred-explicit. The runner capability-probes the CLI and optionally archives
the selected bytes privately with a digest, so a vendor update cannot silently
replace them. CLI version is provenance only. No Grok reviewer, senior, or
judgement lane exists.
Qwen3.8 Max Preview remains blocked for every normal lane until a controlled
`--evaluation` run records lane-specific evidence and both gates are updated.
