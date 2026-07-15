# Delegation lane discipline (installed by delegation-kit)

Usage-aware routing for driving coding work across models from Claude Code. A
resident **lead** owns the work and enters the expensive **judgement** model only
in short bursts; a cheap **executor** does the volume; a **senior** lane handles
taste, security, and escalation. This file is the always-loaded policy; the
`model-routing` skill carries the decision procedure and `model-routing.md` carries
the scored table.

> **Adapt this to your setup.** The model names below (`opus`/`sonnet`/`fable` on
> Claude; the reference numbers) are the author's. Swap them for your own tiers —
> see `ADAPTING.md`. The *structure* (lead / executor / senior / judgement,
> escalation, verification) is the transferable part.

## Lanes (reference mapping — author's models)

- **Lead = the capable-but-not-metered model** (author: **Opus 4.8 @ xhigh**).
  Owns requirements, decisions, integration, verification, the final response.
  Resident. Drop to medium effort for routine coordination.
- **Judgement = the most expensive model** (author: **Fable 5**). **Two touches per
  feature, max — a plan up front, a verdict/synthesis at the end**; only a crossed
  commitment boundary (workers contradicting beyond their brief, a subtask failing
  verification twice, a judgment call outside the success criteria, or the plan
  changing structurally mid-run) buys a third, and spending it is never silent.
  Terse structured output. Never typing, never babysitting workers, never resident;
  reserve for architecture-moving decisions and the high-value calls where its
  gradient pays. Installable as the `fable-judge` profile.
- **Executor + routine reviewer = the cheap-and-capable model** (author:
  **Sonnet 5**, via the `sonnet-*` profiles). Bulk implementation, migrations,
  tests, extraction, repo mapping, and the **default** diff/bug-review lane.
- **Senior review / taste / security = the high-taste model** (author: **Opus 4.8**,
  via `opus-reviewer`). Security-adjacent work routed here **directly**; user-facing
  taste (UI, copy, API design); escalation target for the executor.

## Named profiles (installed to `~/.claude/agents/`)

| profile | model / effort | use for |
|---|---|---|
| `sonnet-clerk` | sonnet / low | extraction, inventories, log/test summaries, transforms |
| `sonnet-scout` | sonnet / low | read-only repo mapping / exploration |
| `sonnet-builder` | sonnet / medium | bounded implementation with acceptance checks |
| `sonnet-reviewer` | sonnet / medium | routine correctness/bug review (the default) |
| `opus-reviewer` | opus / high | security / taste / material review + escalation |
| `fable-judge` | fable / xhigh | judgement: plan up front + final verdict/synthesis (two-touch) |

### Optional evaluated GLM executor

GLM-5.2 may replace an executor profile only through the installed
`glm-executor` skill. Require `delegation-glm check --json` to report the exact
lane in `qualified_lanes`; otherwise it is unavailable, even if Kilo or Claude
can list the model. The bridge pins GLM-5.2 and its supported `high`/`max` effort,
prefers Kilo Coding Plan, and permits the isolated Claude→Z.AI path only with an
explicit `ZAI_API_KEY`. Never silently substitute another model or promote an
unevaluated lane.

## Rules

- **Effort:** executor low for well-specified mechanical work, medium when
  ambiguous or for routine review; senior medium by default, high for
  security/hard design, low for triage. Scale to ambiguity and blast radius, never
  to prestige.
- **Route review by content, not habit** — security/auth/payments/migrations/
  user-facing → senior; routine bug-hunting stays on the executor (often cheaper
  *and* higher-recall there). Size the reviewer to the work, not to the top of the
  table.
- **Escalation ladder:** executor miss/ambiguity → senior → judgement. Never retry
  the same failure on the executor twice — escalate. Security never delegates
  downward: it starts on the senior lane. (Standing rule: judge the output, not the
  price tag.)
- **Verification:** no executor diff ships unread, and a check must **exercise the
  deliverable** — run the command, read the output; grepping a README, testing
  something adjacent, or printing True while exiting zero proves nothing.
  User-facing/security → senior reads it; pure mechanical → executor self-checks at
  low effort, senior spot-checks. The judgement model only re-checks what it
  produced or a multi-attempt synthesis — don't spend it verifying the executor.
- **No double fan-out:** in an orchestration/ultra mode, let the orchestrator fan
  out; don't add a second manual delegation layer. Workers return distilled
  evidence (changed paths, checks run, unresolved risks), not raw logs or essays.
- **Degraded mode:** a lane with no reachable model/bridge → the lead plays it, every
  affected result labeled `[DEGRADED: <lane>]`, one lane max; with two or more gone
  there is no team, so say so and work as ordinary single-model.
- **Delegated output is unverified until you check it.** **Tie-breakers:**
  intelligence > taste > cost; and `cost` is per *task*, not per token.

## Reaching Codex from Claude (cross-provider bridge)

If a GPT/Codex model earns a lane, drive it from Claude. Two paths — pick by whether
you need it interactive/context-preserving or programmatic:

**Preferred for interactive work — the `codex@openai-codex` plugin** (install:
`/plugin marketplace add openai/codex-plugin-cc` then `/plugin install codex@openai-codex`):
- the `codex:codex-rescue` **agent** — agent-invokable; a bounded fire-and-forward to Codex.
- `/codex:review` · `/codex:adversarial-review` — read-only Codex review of the diff.
  **User-run slash commands** (you can't invoke them) — surface them to the user.
- **`/codex:transfer`** — hands the current Claude session off as a *resumable Codex
  thread*, the one path that actually **preserves conversation context** across the
  boundary. Also **user-run — suggest it, don't invoke it**; recommend it when the
  handoff needs the discussion so far, not just files.

**Programmatic / parallel / Workflow — raw `codex exec`.** Always pin **model +
effort**, don't inherit the Codex default:
- Ephemeral profile (pins both **when the profile is installed** — else it silently
  runs the base default model; see the mis-pin caveat below): `codex exec --ephemeral
  -p <profile> "<prompt>" </dev/null`. The *profile* sets the sandbox — `terra-builder`
  pins `workspace-write`, so don't reach for it on a read-only task.
- Inline override: `codex exec -m gpt-5.6-luna -c model_reasoning_effort=low -s read-only "<prompt>" </dev/null`.
  **Default to `-s read-only`** for review/analysis; add `-s workspace-write` only to let
  it edit; always redirect stdin from `/dev/null`.
- Machine-readable return: add `--json` (JSONL events) or `-o <file>` (final message
  only) — **raw stdout is polluted with hook chatter**, so don't parse it directly.
- Inside Workflow scripts, wrap it in a thin `{model:'sonnet', effort:'low'}` agent
  that shells out and returns the cleaned output.

**Harden every dispatch** (a prompt is arbitrary text, a run can fail silently):
- **Brief on a file, never spliced into the command.** A prompt carries quotes,
  backticks, `$(…)`, and newlines; interpolated raw into the command line that is
  shell injection and arg-mangling. Write it to a temp file and pass it as one quoted
  expansion — `codex exec --ephemeral -p <profile> "$(cat "$f")" </dev/null` — or, on
  the API/JSON path, build the payload with `jq --rawfile`. The `</dev/null` still
  guards the hang; `-p`/`--model` still pin the lane.
- **Make failure detectable, not silent.** A dispatch that exits non-zero *or* leaves
  an empty `-o` file failed — retry once down the ladder or ESCALATE, never accept a
  blank as a pass. In a shell fan-out use `set -o pipefail` and check `$?` per call.
- **A mis-pin is not a failure signal.** A mistyped or not-yet-installed `-p <profile>`
  does not error — Codex layers a non-existent config and runs the *base default model*
  (exit 0, real output), silently routing bulk work onto the expensive lane. Neither
  signal above catches it: confirm the profile is installed
  (`ls "$CODEX_HOME/<profile>.config.toml"`) or read the run's model banner.
- **One output file per parallel worker, read in dispatch order.** N calls sharing one
  stdout hand you interleaved output; give each its own `-o <file>`. (A Workflow's
  per-agent return already does this — the note is for raw parallel `codex exec`.)

**Context (each `codex exec` starts fresh):** it shares your working tree but not
your conversation. Run it from the repo root (it auto-loads that repo's `AGENTS.md`)
and reference files **by path** rather than pasting; put the rest into a
self-contained prompt. The shared tree is context you *want* — don't scrub it into an
empty dir; the isolation that matters is per-dispatch (a fresh self-contained prompt
and its own output file), not the cwd. If you need the discussion carried over,
suggest the user run `/codex:transfer` (it's user-run — you can't invoke it). Use the
bridge for a cheap high-volume lane or an independent second opinion from a different
model family; treat its output as **unverified until checked**.

---

## Reference numbers (author's, point-in-time — re-derive yours)

Not law — a worked example, measured on the author's work and plans as of
**2026-07**. Your models, plans, and numbers differ; see `ADAPTING.md`.

- **Efficiency (cost per finished task, measured/published):** the cheap lane is
  cheapest *per task* even when more verbose (author's cheapest reviewer ~$0.13–0.21/
  task vs the judgement model ~$3.12/task). Price spans ~10× across the table;
  tokens-per-task only ~1.5× — so verbosity doesn't reorder the ranking.
- **Routine review:** the cheap reviewer measured *cheaper and higher-recall* than
  the senior model on routine bug-hunting — hence "route review by content."
- **Judgement model billing:** the author's most expensive model bills as metered
  usage credits (real money per call) — the reason it is two-touches-only.
- **Subscription buckets:** on the author's Claude plan the executor drains a
  *separate* weekly bucket from the lead/judgement models — so pushing volume to
  the executor spares the shared pool. Check whether your plan meters the same way.
