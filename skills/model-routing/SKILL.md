---
name: model-routing
description: How and when to delegate coding work across models — pick a small non-builder lane, a max-effort Opus/Terra builder, a cross-family reviewer, or explicit judgement, and know when a manual gate is required. Use when deciding whether to spawn a subagent, which model/effort to hand a task, how to route a code review, or when to escalate. Also covers reaching Codex from Claude.
---

# Model-routing: which model does which job

You are orchestrating coding work across several models. Route by the exact role
boundary first, then by evidence and cost. The dated evidence snapshot
and lane mapping live in `model-routing.md` plus `config/model-evidence.json` at
the kit root. Use `delegation-evidence lane <lane>` when installed; evidence is
advisory and the versioned routing gate remains authoritative.
Use `delegation-route resolve --lane <lane>` for the operational decision. Review
lanes additionally require `--producer-profile <profile>` or
`--producer-family <family>` so the router can exclude the producer's whole
model family. It is read-only and never dispatches a model.
For native Claude/Codex agents, the lead must resolve first; invoking an
explicit-only profile is the manual selection event. GLM/Gemini/Kimi/Grok/Qwen/DeepSeek runners enforce the
same graph directly and refuse drift.

## When to delegate at all
- Default to solving simple, well-scoped work **directly**. Do not spawn a
  subagent for a routine single-file change.
- Use Sonnet or Luna only for very small, non-builder clerk, scout, or routine
  review work. Do not route implementation to them.
- Route bounded implementation to Opus or Terra at `max`.
- Review every delegated result with a sufficiently capable available model from
  another family. If no eligible cross-family reviewer is reachable, stop.
- Reach for multi-agent orchestration only on an explicit decision, never on
  autopilot. In an orchestration/ultra mode, let the orchestrator fan out — don't
  add a second manual delegation layer on top.

## The lanes
- **Very small non-builder:** Sonnet/Luna for bounded extraction, repo mapping,
  and routine review only.
- **Builder:** Opus 5 or GPT-5.6 Terra at `max` through editing profiles.
- **Cross-family reviewer:** Opus 5 and Terra also review at `max` through
  separate read-only profiles. Sol/high remains an advanced read-only default
  where its OpenAI family differs from the producer; Sonnet handles only tiny
  routine review. The router removes every same-family candidate.
- **Judgement:** Fable `max` for architecture/trade-offs/synthesis or Sol `max`
  for technical feasibility/repository fit/failure modes. Both are
  `manual-qualified`, explicit-only, thinking-not-typing profiles.
- **Super-judgement:** only for exceptional, difficult-to-reverse decisions.
  Fable and Sol reason independently, cross-review after both verdicts exist, and
  the lead decides. Never trigger it automatically.

An optional external model such as GLM-5.3-Flash earns a lane only after its
versioned evaluation gate allows that exact role. The staged tuple is
`glm-5.3-flash/claude-zai/max`, but every lane is blocked because retained v2
evidence did not record separately surfaced effective content identity or
complete model usage. Historical GLM-5.3 results do not transfer.

Kimi K3 is provisional for `clerk`, `scout`, `builder`, and `frontend-builder` at
`max`; senior is a blocked candidate, while reviewer and judgement are disabled.
Provisional dispatch requires `--allow-provisional`. Provider quota failures are
runtime-availability failures, not quality evidence.

Qwen3.8-Max is provisional for `builder` only, explicit-only at `xhigh`, and
requires `--allow-provisional`. That promotion is an owner decision, not
measured capability: no DeepSWE or Terminal-Bench v2 row exists for the model.
The lane is text-only — it returns a patch the lead applies, and cannot edit a
worktree. Every other Qwen lane stays blocked until exact local lane evidence
promotes both the central and executable gates.
Its `policy-annotation` entry, like the corresponding Kimi, GLM, and Grok
entries, is an allowlisted evaluation-only candidate and not an operational
route.

Gemini 3.7 Flash is staged through `agy` with no operational lane. Scout at
`medium` and builder/frontend-builder at `high` remain blocked candidates;
reviewer and judgement are disabled. It is a prompt-only bridge: put the required tracked-file
excerpts into the brief. It uses an isolated temporary home/workspace, retains
only macOS Keychain access for OAuth, and denies every tool namespace.

DeepSeek V4 Pro is provisional for `builder` only, explicit-only at `max`, and
requires `--allow-provisional`. The official API runner is prompt-only and
text-only: it returns a patch the lead applies and verifies. One live exact
tuple smoke is compatibility evidence, not measured builder qualification; all
other lanes remain blocked.

Grok 4.6 is provisional for `builder` and `frontend-builder` at `high` through
Grok Build CLI. Dispatch requires an explicit decision and
`--allow-provisional`. The runner capability-probes the CLI, pins model and
effort, extracts only `.text`, uses an isolated HOME plus the attested custom
`delegation-kit` sandbox, and enforces turn and wall-clock limits. That CLI is
resolved from an optional digest-checked private archive before PATH. Its
observed version is provenance only; re-run `delegation-grok pin --force` to
deliberately replace the archived bytes. No other Grok lane is enabled.
The candidate/blocked `policy-annotation` exception is manifest-bound,
read-only, and cannot widen those operational lanes.

## Sizing and escalation
- **Size and separate the reviewer.** Sonnet may review only a very small routine
  result. Opus/Terra at `max` and Sol at `high` may review material or
  security-sensitive work, but only when their family differs from the producer.
- **Route review by content and producer family.** Use `routine-review` for tiny
  work, `material-review` for implementation, and `security` for security/auth/
  payments/migrations. Always pass producer identity; never select anything in
  `excluded_same_family`.
- **Inspect provider fallback metadata.** Anthropic may substitute Opus 4.8 for
  the requested Opus 5 reviewer on classifier-flagged cyber requests. When exact
  identity matters, inspect the surfaced content model or use Anthropic's CVP.
- **Escalation ladder:** small non-builder → builder or material reviewer →
  judgement. Never retry the same failure on an unsuitable worker twice.
- **Delegated output is unverified until you check it.** Never ship or build on a
  delegated diff or finding without reading it or reproducing the claim — and make
  the check **exercise the deliverable** (run the command, read the output);
  grepping a README, testing something adjacent, or printing True while exiting zero
  proves nothing.

## Tie-breakers
- When evidence conflicts: **required lane evidence > deliverable quality > cost**.
- **`cost` is per task, not per token.** A model that burns more tokens at a lower
  price can still finish the job cheapest.

## Reaching Codex from Claude (cross-provider)
If a GPT/Codex model earns a lane in your table, drive it from Claude. For
interactive or context-preserving work prefer the `codex@openai-codex` plugin: the
`codex:codex-rescue` agent (agent-invokable), plus the user-run slash commands
`/codex:review` and `/codex:transfer` — suggest these to the user, you can't invoke
them. `/codex:transfer` hands the session off as a resumable Codex thread, the only
path that carries the conversation across. For programmatic/parallel work use the
Codex CLI and pin
**both model and effort**: `codex exec --ephemeral -p <profile> "<prompt>" </dev/null`
(profile pins both) or `codex exec -m <model> -c model_reasoning_effort=<level> -s read-only "<prompt>" </dev/null`
(`-s workspace-write` to let it edit; add `--json`/`-o <file>` for a clean,
parseable return). Each `codex exec` starts fresh — run it from the repo root and
reference files by path. Use it for a cheap high-volume lane or an independent
second-opinion review from a different model family.
