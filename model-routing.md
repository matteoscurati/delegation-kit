# Model routing for orchestrated coding

Delegation policy for driving coding work across several models. Small models
handle only very small non-builder work, dedicated max-effort builders
implement, and a sufficiently capable model from another family reviews every
delegated result before separate judgement lanes assess larger decisions. It
answers one question: **which model does which job.**

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
bin/delegation-route resolve --lane material-review --producer-profile terra-builder --json
bin/delegation-route resolve --lane judgement --json
bin/delegation-route resolve --lane super-judgement --json
```

The snapshot observed through 2026-08-17 uses Artificial Analysis Coding Agent
Index v1.3 for end-to-end coding, Agent Arena for real-world reliability, Code
Arena WebDev for frontend preference, SWE-PRBench/Martian for review, and
CursorBench, FrontierCode, FrontierSWE, APEX-SWE, OpenBench, and Epoch's ZIP as
separately labeled context. It stores raw metrics rather than compressing
unrelated capabilities into subjective 1–10 scores.

| retained exact model + harness + effort | coding index | DeepSWE | Terminal-Bench | repo Q&A | API cost/task |
|---|---:|---:|---:|---:|---:|
| Claude Opus 5 + Claude Code, xhigh (lead) | 67 | 60% | 85% | 55% | $8.23 |
| GPT-5.6 Sol + Codex, max (judge context) | 67 | 69% | 88% | 43% | $7.08 |
| Claude Opus 5 + Claude Code, max (builder) | 66 | 63% | 85% | 49% | $8.95 |
| GPT-5.6 Sol + Codex, high | 64 | 65% | 83% | 45% | $4.14 |
| Claude Opus 5 + Claude Code, high | 63 | 61% | 80% | 49% | $3.80 |
| GPT-5.6 Terra + Codex, max (builder) | 62 | 67% | 84% | 36% | $2.76 |
| Kimi K3 + Kimi Code CLI, max | 61 | 64% | 84% | 37% | $3.18 |
| GPT-5.6 Luna + Codex, max (small non-builder) | 59 | 63% | 80% | 33% | $1.57 |
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

The JSON retains exact observations for Luna `low`/`max`, Terra
`low`/`medium`/`max`, Sol `high`/`max`, Opus 5 `high`/`xhigh`/`max`, Kimi K3 `max`,
and the historical Grok 4.5
`high` tuple. Grok 4.5 is no longer operational; Grok 4.6 currently has only
contextual rows because CursorBench, FrontierCode, APEX, and WebDev use other
harnesses. The 2026-07-28 index adds the lead lane's own tuple: Opus 5 through
Claude Code at `xhigh` enters at 67, jointly ahead of Codex Sol `max`, with the
highest repo-Q&A score on the board (55%) at $8.23 per task. Opus 5 `max` is
recorded alongside it at 66 and is now the installed Claude builder tuple.
Those rows measure coding, not review precision/recall, so they do not qualify
review or security work. Fable `max` has exact-variant coding evidence but no
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

The Codex rows were corrected on 2026-08-05: they previously stopped at `high`.
The enum is **per model**, not global — the provider rejects an unknown value by
enumerating that model's own accepted set. Verified by probe: `gpt-5.6-terra`
enumerates `none · minimal · low · medium · high · xhigh · max` and ran at
`high`, `xhigh`, and `max`; `gpt-5.6-sol` and `gpt-5.6-luna` both ran at `xhigh`
and `max`; `gpt-5.5` **refuses** `max` and enumerates a shorter set of its own.

| model | supported effort |
|---|---|
| fable-5 | low · medium · high · xhigh · max |
| opus-5 | low · medium · high · xhigh · max |
| gpt-5.6-sol | low · medium · high · xhigh · max |
| gpt-5.6-terra | none · minimal · low · medium · high · xhigh · max |
| gpt-5.6-luna | low · medium · high · xhigh · max |
| sonnet-5 | low · medium · high |
| gpt-5.5 | none · low · medium · high · xhigh (no `max`) |
| glm-5.3 | max (only installed and selectable GLM tuple) |
| kimi-k3 | max |
| gemini-3.7-flash | medium (scout candidate) · high (editing candidate) |
| deepseek-v4-pro | high · max (builder pinned to max, provisional) |
| qwen3.8-max | xhigh (builder provisional; every other lane candidate/disabled) |
| grok-4.6 | high (builder/frontend-builder provisional; policy annotation evaluation-only) |

Kimi K3 is provisional: the 2026-07-16 run was truncated by provider quota. Its
valid subset and exact public rows support controlled `clerk`, `scout`, `builder`,
and `frontend-builder` use with `--allow-provisional`; `senior` is only a blocked
candidate. The installed gate remains authoritative for the exact tuple.

Qwen3.8-Max left preview on 2026-08-02: Model Studio now lists the unsuffixed
`qwen3.8-max` across five regions, and a local Token Plan probe on 2026-08-03
confirmed the endpoint serves it at `xhigh` (the `-preview` id still resolves in
parallel). The pin moved to `qwen3.8-max` on that runtime attestation.

`builder` is **provisional and explicit-only** on an owner decision, not on
measured capability. The evidence position is unchanged from the July audits:
no exact row in Artificial Analysis, Arena, WebDev, OpenBench, or Epoch's ZIP,
and the 2026-08-03 re-check of the Artificial Analysis coding-agent board and
Terminal-Bench 2.1 still found none — so **both** builder required metrics
(`coding.deep_swe_pass_pct`, `coding.terminal_bench_v2_pass_pct`) remain unmet.
Alibaba has published no benchmark table for the model. Dispatch therefore needs
`--allow-provisional`, and every other lane stays refused.

Two limits ride with that lane. The Token Plan transport is chat-completions
only: it cannot edit a worktree, so `builder` returns a patch the lead applies
and verifies — it is not an autonomous editing agent like Grok Build or Kimi.
And the previously allowlisted `policy-annotation` evaluation manifest was bound
to the `qwen3.8-max-preview` tuple; it is void after the rename and must be
regenerated before any evaluation run.

Gemini 3.7 Flash is staged through the authenticated Antigravity CLI. Google's
launch reports DeepSWE 65.3%, FrontierCode 43.6%, and WebDev Elo 1588, but these
are first-party mixed-harness claims rather than evidence for production `agy`.
The current local session cannot attest exact model inventory or OAuth, so the
previous Gemini 3.6 smoke is not inherited: scout/medium and both editing/high
lanes remain candidate/blocked. Runtime discovery is compatibility evidence,
not qualification.
The Antigravity bridge is prompt-only: the lead supplies selected file excerpts
in the brief. The runner uses an empty temporary workspace and home, retains
only macOS Keychain access for OAuth, and explicitly denies every tool namespace.

DeepSeek V4 Pro is pinned to the official OpenAI-compatible API at `max`.
DeepSeek officially exposes only `high` and `max` thinking; low/medium map to
high and xhigh maps to max. One live exact-tuple smoke returned the exact
`deepseek-v4-pro` identity, accepted `reasoning_effort=max`, and produced a
correct structured off-by-one patch. That is enough for an owner-selected
**provisional, explicit-only, text-only builder**, not qualification. The
provider Terminal-Bench 2.0 claim uses another harness, no DeepSWE row exists,
and WebDev supports frontend work only. All other lanes stay blocked.

Grok 4.6 is provisional for `builder` and `frontend-builder` through Grok Build
CLI at `high`. Current CursorBench, FrontierCode, APEX, and preliminary WebDev
rows support the owner replacement decision, but all use non-production
harnesses and remain contextual. Dispatch still requires `--allow-provisional`; the
runner capability-probes the CLI, isolates HOME, disables plugins/MCP/imported
config, requires an attested custom sandbox, and caps turns and wall time. The
observed version is provenance only; an optional digest-checked private archive
preserves the exact user-selected bytes independently of PATH.
The separate `policy-annotation` candidate uses that same highest supported
effort only through an allowlisted read-only evaluation manifest. It is absent
from all operational route groups and cannot qualify judgement automatically.

## Judgement and super-judgement

Fable `max` and Sol `max` are both manually qualified for judgement by an
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

- **Sonnet and Luna are very-small non-builder lanes.** Use them only for tightly
  bounded clerk, scout, or routine-review work. They do not implement changes.
- **Opus and Terra build and review at `max`.** Editing uses `terra-builder` or
  `opus-builder`; review uses the separate read-only `terra-reviewer` or
  `opus-reviewer`. Their coding rows support the owner routing decision, not
  reviewer qualification, so all reviewer lanes remain provisional.
- **Cross-family review is mandatory.** Every delegated result must be reviewed
  by a sufficiently capable available model outside the producer's family. Run
  `delegation-route resolve --lane <routine-review|material-review|security>
  --producer-profile <profile>`. The command fails without producer identity and
  reports same-family profiles under `excluded_same_family`.
- **Sol remains an advanced default only when cross-family.** `sol-reviewer/high`
  is excluded for Terra, Luna, Sol, or any other OpenAI-family producer. Opus is
  excluded for Anthropic-family output. If every returned reviewer is
  unavailable, stop rather than weakening the family boundary.
- **These role boundaries are limits.** A failed Sonnet/Luna task escalates to
  the appropriate builder or reviewer; it never turns the small lane into a
  builder. Judge every output independently of price.
- **When to delegate at all.** Default to handling work inline. Delegate the
  clear-spec implementation to Opus/Terra and only very small non-builder work
  to Sonnet/Luna; reach for multi-agent orchestration only on an explicit
  decision, never on autopilot.
- **A long or open-ended run is bottlenecked by unknowns, not intelligence.** The
  burn is the un-tuned prompt that drifts into a second and third attempt. Spend
  cheap tokens up front to surface the unknowns — a *blindspot pass* on unfamiliar
  ground, an interview one question at a time (prioritize answers that would change
  the architecture), a plan that leads with the decisions most likely to move
  (data models, interfaces, UX) before any code. Point at reference source instead
  of describing in prose. Keep an implementation-notes log of deviations during the
  run, and quiz yourself on the diff before merge. Each is cheaper than the re-run
  it prevents.
- **Delegated output is unverified until independently reviewed.** Lead checks
  and producer self-checks do not replace cross-family review. Never ship or
  build on a delegated diff or finding without both exercising it and completing
  the resolved review.
- **Cost is a tie-breaker only.** Required lane evidence and deliverable quality
  come first; then domain-specific taste/reliability evidence; then cost.
- **`cost` is per *task*, not per token.** A model that burns more tokens at a
  lower price can still finish the job cheapest — measured, `gpt-5.6-luna` is the
  cheapest per completed task, verbosity included. Don't up-tier to "save tokens";
  price the task, not the token.
- **Size review by materiality after filtering family.** Sonnet may review a very
  small routine result. Opus/Terra at `max` and Sol at `high` may review material
  or security-sensitive work when their family differs from the producer.
- **Keep provider fallback visible.** On classifier-flagged cyber requests,
  Anthropic may substitute Opus 4.8 for the requested Opus 5 security reviewer.
  The route reports this as `provider_fallback`; inspect surfaced content-model
  identity or use Anthropic's CVP when the exact variant is mandatory.
- **Judgement models do thinking, not typing.** Fable handles architecture,
  trade-offs, and synthesis; Sol handles technical feasibility, repository fit,
  failure modes, and verifiability. Neither produces the diff when selected as a
  judge. Use the pair only through the explicit super-judgement protocol.
- **Anything user-facing** (UI, copy, API design) remains a lead-owned taste
  decision; implementation can then be assigned to a max-effort builder.

## The orchestrator pattern

The concrete shape most of this reduces to:

1. The lead reads the codebase, writes the plan, and breaks it into tasks.
2. Sonnet/Luna handle only very small non-builder support; Opus/Terra at `max`
   implement bounded tasks.
3. The router filters reviewers by producer family; an eligible, available
   different-family model performs the read-only review before integration.

Judgement remains an explicit Fable/Sol decision and never silently turns into
implementation.

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

The frozen 2026-08-14 exact comparison measured both efforts; the owner later
selected GLM-5.3/`claude-zai`/`max` as the sole operational tuple.
Clerk and scout are qualified explicit-only; builder passed its first repeated
GLM-5.3 pack and remains provisional explicit-only, so it still requires
`--allow-provisional`. GLM-5.2/high and GLM-5.3/high remain only in frozen
historical receipts, with no executable gate or selectable profile. Reviewer
remains disabled. Builder runs at
`--permission-mode acceptEdits` with no settings sources: the delegate can only
apply in-workdir Edit/Write changes — it cannot run shell commands, and the
harness refuses writes to sensitive files such as `.npmrc`. Environment and
toolchain fixes are therefore not routable to GLM builder; the lead closes them
(observed 2026-08-04, when such a dispatch returned analysis only). Kimi K3 is provisional for `clerk`, `scout`, `builder`, and
`frontend-builder`; senior is a blocked candidate, while reviewer and judgement
remain disabled. Other provisional bridge runs require `--allow-provisional`.
Grok 4.6 is provisional for `builder` and `frontend-builder` through Grok Build
CLI at `high`; both lanes are `preferred-explicit`. The runner capability-probes the CLI and optionally archives
the selected bytes privately with a digest, so a vendor update cannot silently
replace them. CLI version is provenance only. No Grok reviewer, senior, or
judgement lane exists.
Qwen3.8-Max is provisional for `builder` only, explicit-only at `xhigh`, and
requires `--allow-provisional`. It is text-only and returns a patch rather than
editing a worktree. Every other Qwen lane stays blocked until a controlled
`--evaluation` run records lane-specific evidence and both gates are updated.
DeepSeek V4 Pro is likewise a text-only, explicit-only provisional builder,
pinned to the official API at `max`; all neighbouring lanes stay blocked.
Gemini 3.7 Flash is installed as a fail-closed candidate graph with no
operational lane until the exact Antigravity identity/auth smoke succeeds.
