# Usage-aware collaboration (installed by delegation-kit)

> **Adapt to your setup.** The profile names below (`luna-clerk` / `terra-scout` /
> `terra-builder` / `sol-reviewer`) and their models are the author's reference
> mapping — swap them for your own tiers (see `ADAPTING.md`). The *structure* is
> the transferable part.

- Default to solving simple, well-scoped work directly. Do not create subagents for a routine single-file change.
- The lead owns requirements, decisions, integration, verification, and the final response.
- For genuinely separable work, use at most two direct workers by default. Give each a bounded task, explicit file ownership, and a concise return format. Never allow recursive delegation.
- Prefer `luna-clerk` for deterministic inventory, extraction, transformation, and test-log summaries; `terra-scout` for read-only repository mapping; `terra-builder` for a bounded implementation with clear acceptance checks; and `sol-reviewer` only for a material final correctness or security review.
- When the native subagent tool cannot select a model, use the matching ephemeral CLI profile: `codex exec --ephemeral -p luna-clerk`, `terra-scout`, `terra-builder`, or `sol-reviewer`. Do not claim a native worker is cheaper unless its model is actually pinned.
- Avoid double fan-out: in Ultra mode, let Ultra orchestrate and do not add a second manual delegation layer. Ultra is exceptional, not the default.
- Escalate Luna to Terra, or Terra to Sol, when the task becomes ambiguous or high risk. Do not repeatedly retry an unsuitable cheap worker.
- Workers should return distilled evidence, changed paths, checks run, and unresolved risks—not raw logs or broad essays.

## Optional evaluated GLM executor

GLM-5.2 is available only through the installed `glm-executor` skill and only
for a lane that `delegation-glm check --json` lists in `qualified_lanes`. The
bridge pins the exact model and an evaluated `high`/`max` effort, prefers Kilo
Coding Plan, and uses the isolated Claude→Z.AI fallback only when an explicit
`ZAI_API_KEY` is present. If the runtime or lane gate is absent, keep using the
incumbent profile; never silently substitute another model.

## Reaching Claude from Codex (cross-provider bridge)

The lanes above route among OpenAI models. Reach across to Claude when it earns it:

- **Taste** — user-facing UI, copy, or API-shape work, where a high-taste model
  (Claude Opus) produces better results than the local lanes.
- **Independent second opinion** — a review from a *different model family* catches
  correctness/security bugs the local lanes correlate on and miss. Worth it on
  material or security-sensitive diffs.
- **Bucket-aware offload** — if Codex usage is tight and the Claude subscription has
  spare capacity, push suitable volume across.

**How — headless Claude Code CLI** (verified flags). Always name **both** the model
family/tier (`--model`) **and** the reasoning effort (`--effort`) — don't inherit
defaults blindly:

```sh
# read-only review / analysis (no edits):
claude -p "<self-contained prompt>" --model opus --effort high --permission-mode plan

# let it edit:
claude -p "<self-contained prompt>" --model sonnet --effort medium --permission-mode acceptEdits

# give it a role (reviewer / taste), or a structured output:
claude -p "<prompt>" --model opus --effort high --permission-mode plan \
  --append-system-prompt "You are a senior security reviewer. Report findings only."
# ...or define a named agent inline: --agents '<json>'
# ...or machine-readable: --output-format stream-json
```

- **Model + effort:** `--model opus|sonnet|<full-id>` picks the family/tier;
  `--effort low|medium|high|xhigh|max` sets the depth (available levels depend on
  the model). Reserve `opus` for taste/security/material review, `sonnet` for
  high-volume execution; scale effort to blast radius, not prestige.
- **Context (it starts fresh):** the Claude process does **not** see this Codex
  session. It *does* share the filesystem — run it from the repo root so it reads
  the same working tree (it auto-loads that repo's `CLAUDE.md`); widen its view
  with `--add-dir <path>`; reference files **by path** instead of pasting them.
  There is **no Codex→Claude history handoff** (the `codex@openai-codex` plugin is
  Claude→Codex only), so put everything else the task needs into the prompt.
- **Harden each dispatch:** a prompt carries quotes, backticks, and newlines — write
  it to a temp file and pass `"$(cat "$f")"`, never splice it raw into the command
  (shell injection, arg-mangling). A run that exits non-zero *or* returns empty
  failed — retry or escalate, don't accept a blank as a pass (`set -o pipefail`,
  check `$?`). For parallel calls give each its own output file and read them in
  dispatch order. The shared tree is context you want — run from the repo root, don't
  scrub it away.
- **Discipline:** don't claim the bridge is cheaper unless the target Claude model
  actually fits the task. Treat its output as **unverified until checked**, same as
  any delegation.
