---
name: orchestrate
description: >-
  Run a task too big for one pass as a lead-executor-advisor loop — plan, fan the
  work out across cheap parallel workers, verify each result against its own
  criteria, and have the expensive model judge the plan up front and the ship at
  the end. Use when the user says "too big for one pass", "fan this out",
  "orchestrate across a model team", "run the advisor-worker loop", or asks to
  parallelize research/generation across many subtasks. NOT for single-file edits,
  work one pass handles, or when you are already inside a Workflow/ultra run (that
  is the orchestrator already — no double fan-out).
---

# Orchestrate: run the lead-executor-advisor loop

You are the **Lead** of your model team. You own the hot path: frame, plan,
delegate, verify, synthesize. You never do executor-level grunt work yourself, and
the judgement model judges — it never types. This skill operationalizes the lanes
in `CLAUDE.delegation.md` into one repeatable loop.

**Models are knobs.** The lanes are the durable part; the model IDs are the
author's reference mapping (`model-routing.md`). One rule survives every
generation: the advisor is the strongest reasoning you can reach, the executor the
cheapest that passes verification.

## The team (mapped to the kit's lanes)

- **Lead** (you; author: Opus @ xhigh, resident): frames criteria, plans waves,
  dispatches briefs, verifies every result, synthesizes. Enters the metered lane
  only in short bursts.
- **Small non-builder workers** (Sonnet clerk/scout/reviewer or `luna-clerk`):
  only very small deterministic or read-only subtasks. They never edit.
- **Builders** (`opus-builder` or Codex `terra-builder`, both at `max`): one
  bounded implementation subtask each, with explicit file ownership and checks.
  Dispatch with the format in `references/worker-brief.md`.
- **Cross-family reviewers** (`opus-reviewer` / Codex `terra-reviewer`, both at
  `max`, plus eligible Sonnet/Sol profiles): every delegated result is checked by
  a different model family. Resolve with producer identity and verify reviewer
  availability before dispatch.
- **Advisor**, split by content (this is the kit's improvement over a single
  advisor — route by the policy): **Judgement** (author: Fable via `fable-judge`
  or Sol via `sol-judge`, two-touch) for plan
  critique and ship/synthesis. Material technical/security review goes to any
  eligible advanced read-only cross-family reviewer; user-facing taste stays with the lead. Consult
  format in `references/advisor-consult.md`.
- **Super-judgement** is an explicit, exceptional pair: Fable and Sol reason
  independently, cross-review only after both verdicts exist, and the lead makes
  the final decision. Follow `references/dual-judgement.md`; never trigger it
  automatically.

The economics are the point: small lanes handle only bounded non-builder work;
max-effort Opus/Terra own high-level build/review work; judgement appears only
where it changes a decision. Family independence is never traded for cost.

## Dispatch with native primitives, not a shell worker-pool

Claude Code already gives you deterministic fan-out — use it instead of hand-rolled
background subshells:

- **Workflow tool** — the default for real fan-out: `parallel`/`pipeline`, schema
  returns, per-agent isolation (`isolation:'worktree'` when workers edit in
  parallel). The orchestrator *is* the loop; encode waves as pipeline stages.
- **Agent tool** — Sonnet profiles for very small non-builder calls;
  `opus-builder` for Claude-side edits.
- **Codex bridge** — only to reach a different model family within the resolved
  small non-builder, builder, or review role. Harden every raw `codex exec` /
  `claude -p` dispatch per the bridge section of `CLAUDE.delegation.md` (brief on a
  temp file, non-zero exit or empty output = failed dispatch, one output file per
  worker).
- **Gated external candidates** — use GLM, Gemini, Kimi, or Grok only through their executor
  skill and only when that runner's gate allows the requested lane. A provisional
  lane additionally requires the runner's explicit `--allow-provisional` flag.
  Qualification on one lane never promotes a neighboring one. This rule applies
  equally to operational workers, material review, and Judgement.
  Gemini 3.7 has no operational lane: its scout/medium and editing/high entries
  are blocked candidates. Grok 4.6 is provisional only for
  builder and frontend-builder at high. Qwen3.8-Max is provisional only for
  builder at xhigh, and returns a patch rather than editing a worktree. Manifest-bound
  `policy-annotation` candidates are evaluation-only and never count as
  operational routes.
  **Concurrency of the gated lanes:** Kimi workers can run in parallel only
  when every dispatch passes `--oauth shared` — the default serializes on the
  kit lock, so a wave of default-mode Kimi workers is one success and N-1
  instant exit-75s. Treat a GLM coding-plan key as roughly one in-flight
  request: cap GLM at one worker per key per wave unless the owner has
  measured a higher ceiling, and on exit 75 read the diagnostic's `reason` —
  `rate_limited` retries with backoff, `quota_exhausted` waits for
  `next_flush_time`.

## The loop

1. **Frame.** State the deliverable and 3–5 checkable success criteria; if the task
   is too vague for that, ask one question and stop. Set a **budget** now (below).
   Check the lanes are reachable — executor profiles, the judgement model, the
   Codex bridge or gated external candidate if you'll use it (`doctor.sh`; use
   `--ping-glm`, `--ping-kimi`, or `--ping-grok` only for a live gated-lane
   check). A lane
   with no path → **degraded mode** (below), announced up front.
2. **Plan.** Decompose into self-contained subtasks with inputs (in-tree by path,
   everything else inline), acceptance criteria, and wave assignments that maximize
   parallelism.
3. **Plan review — mandatory consult #1 (Judgement).** Send the plan using
   `references/advisor-consult.md`. Revise; state what you changed and what you
   rejected. This is the cheapest place to catch a wrong decomposition.
4. **Delegate.** Dispatch each wave via `references/worker-brief.md`. **No double
   fan-out** — if you were invoked from inside a Workflow/ultra run, you are already
   the orchestrator; run the loop inline, don't nest another delegation layer.
5. **Verify and cross-review.** Check every result against its **own** acceptance criteria, and make
   the check **exercise the deliverable itself** — run the actual command, read the
   actual output. Grepping a README, testing something adjacent, printing True while
   exiting zero, or re-checking that a file exists proves nothing. Then resolve a
   review lane with the producer profile. Tiny work uses `routine-review`,
   implementation uses `material-review`, and security-sensitive work uses
   `security`. Dispatch only a returned, available reviewer from another family;
   self-check and lead verification do not replace this review. Verdict per result:
   **PASS**, **FIX** (redispatch naming the specific
   failure), or **ESCALATE**. Never silently accept a partial pass; never hand-patch
   a substantive failure — redispatch.
6. **Synthesize.** When all subtasks pass, assemble the deliverable. Resolve
   conflicts between worker outputs **explicitly**, never by averaging.
7. **Ship / taste pass — mandatory consult #2.** Send the draft for the final
   judgement: **Judgement** for synthesis and go/no-go; an eligible cross-family
   reviewer for material technical/security review; the lead owns user-facing taste. Apply or explicitly
   rebut each note.

## Commitment boundaries — when a touch past the mandatory two is justified

The judgement lane is two-touch by default (it is metered — real money per call).
Only a crossed boundary buys a third+ consult, and spending it is **never silent**
(log it on the status board):

- two worker results contradict each other beyond the provided brief;
- a subtask fails verification twice;
- a judgment call falls outside the stated success criteria;
- the plan must change structurally mid-run.

## Budget, status board, degraded mode

- **Budget** — set at the frame step, sized to the plan. A reasonable shape: ~2× the
  subtask count in executor dispatches (retries and bridge redispatches count), plus
  the 2 mandatory consults and any boundary consults. The cap isn't the point;
  spending past it is never silent — stop and report, or tell the user what more
  would cost and let them decide.
- **Status board** — print one line per subtask after each loop step: state
  (PENDING / DISPATCHED / PASS / FIX / ESCALATED), lane/path, retries. e.g.
  `W2: FIX → PASS | opus-builder→codex:terra-builder | 1 retry`.
- **Degraded mode** — for a non-review lane with no reachable model/bridge, the
  Lead may play it, with every affected section and the final result labeled
  `[DEGRADED: <lane>]` and the context-isolation caveat noted. A missing
  cross-family reviewer is never degradable to self-review: stop and report the
  blocker. At most one non-review lane; with two or more gone there is no team,
  so say so and proceed as ordinary single-model work.

## Finish

Stop at a verified deliverable, an exhausted budget, or a blocker that needs the
user. Return: the deliverable, the plan, a per-subtask verification ledger, advisor
notes applied and rejected, and remaining risks.
