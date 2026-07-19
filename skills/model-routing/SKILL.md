---
name: model-routing
description: How and when to delegate coding work across models — pick the right lane (cheap execution vs senior review vs expensive judgement), size the reviewer to the work, and know what only the most expensive model should do. Use when deciding whether to spawn a subagent, which model/effort to hand a task, how to route a code review, or when to escalate. Also covers reaching Codex from Claude.
---

# Model-routing: which model does which job

You are orchestrating coding work across several models. A strong model plans and
judges; cheaper ones execute. Route by these rules. The full scored table
(cost / intelligence / taste per model) lives in `model-routing.md` (installed
alongside this skill, or at the kit root) — read it for the numbers; this skill is
the decision procedure.

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
- **Judgement (most expensive):** planning, task breakdown, cross-attempt
  synthesis, and the final ship go/no-go — thinking, not typing. Enter it in short
  bursts; never keep it resident coordinating workers.

An optional external candidate such as GLM-5.2 earns one of these lanes only
after its versioned evaluation gate passes for that exact role. If
`delegation-glm check --json` lists the lane, use the `glm-executor` skill; an
installed CLI or visible model name alone is not qualification.
The shipped 2026-07 GLM-5.2 gate qualifies only clerk/high and scout/high; it
explicitly rejects builder and reviewer, and refuses any effort it did not pin.
Always defer to the installed gate if a later evaluation supersedes this
snapshot.

Kimi K3 is provisional for `clerk`, `scout`, `builder`, and `senior`; the shipped
gate qualifies these through the native Kimi Code CLI at effort `max`. `reviewer`
and `judgement` remain disabled. Provider quota failures are temporary runtime
failures, not evidence that changes the quality qualification.
Use the `kimi-executor` skill only when `delegation-kimi check --json` lists the
requested lane. A working CLI, visible model name, or qualification on one
lane never promotes another; if the gate rejects it, keep the incumbent.

## Sizing and escalation
- **Size the reviewer to the work, not to the top of the table.** A diff the cheap
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
- When axes conflict for anything that ships: **intelligence > taste > cost**.
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
