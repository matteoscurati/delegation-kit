---
name: model-routing
description: How and when to delegate coding work across models — pick the right lane (cheap execution, senior review, explicit judgement, or dual super-judgement), size the reviewer to the work, and know when a manual gate is required. Use when deciding whether to spawn a subagent, which model/effort to hand a task, how to route a code review, or when to escalate. Also covers reaching Codex from Claude.
---

# Model-routing: which model does which job

You are orchestrating coding work across several models. A strong model plans and
judges; cheaper ones execute. Route by these rules. The dated evidence snapshot
and lane mapping live in `model-routing.md` plus `config/model-evidence.json` at
the kit root. Use `delegation-evidence lane <lane>` when installed; evidence is
advisory and the versioned routing gate remains authoritative.
Use `delegation-route resolve --lane <lane>` for the operational decision. It is
read-only and never dispatches a model.
For native Claude/Codex agents, the lead must resolve first; invoking an
explicit-only profile is the manual selection event. GLM/Gemini/Kimi/Grok/Qwen runners enforce the
same graph directly and refuse drift.

## When to delegate at all
- Default to solving simple, well-scoped work **directly**. Do not spawn a
  subagent for a routine single-file change.
- Delegate the clear-spec, mechanical, or high-volume work (bulk implementation,
  migrations, data crunching, extraction) to the cheap execution lane.
- Reach for multi-agent orchestration only on an explicit decision, never on
  autopilot. In an orchestration/ultra mode, let the orchestrator fan out — don't
  add a second manual delegation layer on top.

## The lanes
- **Execution / routine review (cheap):** bulk implementation, migrations, tests,
  extraction, repo mapping, and the **default** diff/bug-review lane.
- **Senior review / taste / security:** security-adjacent code (route here
  directly), user-facing surfaces (UI, copy, API design), material correctness
  review, and the escalation target for the cheap lane.
- **Judgement:** Fable `xhigh` for architecture/trade-offs/synthesis or Sol `high`
  for technical feasibility/repository fit/failure modes. Both are
  `manual-qualified`, explicit-only, thinking-not-typing profiles.
- **Super-judgement:** only for exceptional, difficult-to-reverse decisions.
  Fable and Sol reason independently, cross-review after both verdicts exist, and
  the lead decides. Never trigger it automatically.

An optional external candidate such as GLM-5.2 earns one of these lanes only
after its versioned evaluation gate allows that exact role. GLM clerk/scout are
provisional and require `--allow-provisional`; builder is a blocked candidate and
reviewer is disabled. An installed CLI or visible model name is not qualification.

Kimi K3 is provisional for `clerk`, `scout`, `builder`, and `frontend-builder` at
`max`; senior is a blocked candidate, while reviewer and judgement are disabled.
Provisional dispatch requires `--allow-provisional`. Provider quota failures are
temporary runtime failures, not quality evidence.

Qwen3.8 Max Preview is a blocked candidate. Token Plan availability is only a
runtime fact; it cannot enter a candidate set until exact local lane evidence
promotes both the central and executable gates.
Its `policy-annotation` entry, like the corresponding Kimi, GLM, and Grok
entries, is an allowlisted evaluation-only candidate and not an operational
route.

Gemini 3.6 Flash is provisional only for `scout` at `medium` through `agy`.
Builder and frontend-builder at `high` remain blocked; reviewer and judgement
are disabled. Dispatch requires an explicit decision and
`--allow-provisional`. It is a prompt-only bridge: put the required tracked-file
excerpts into the brief. It uses an isolated temporary home/workspace, retains
only macOS Keychain access for OAuth, and denies every tool namespace.

Grok 4.5 is provisional for `builder` and `frontend-builder` at `high` through
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
- **Size the reviewer to the work, not to a general leaderboard.** A diff the cheap
  lane wrote against a plan the strong model authored is reviewed by the *mid*
  model that already has the context. Reserve the top model as reviewer only when
  its gradient is required: high-level design/taste, synthesis across attempts, or
  independently checking something it produced.
- **Route review by content, not by habit** — send security/auth/payments/
  migrations/user-facing to the senior lane; keep routine bug-hunting on the cheap
  lane (often cheaper *and* higher-recall there).
- **Escalation ladder:** cheap → senior → judgement. Never retry the same failure
  on an unsuitable cheap worker twice — escalate. Security never delegates
  downward: it starts on the senior lane.
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
