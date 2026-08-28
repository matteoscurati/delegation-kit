# Delegation lane discipline (installed by delegation-kit)

Usage-aware routing for driving coding work across models from Claude Code. A
resident **lead** owns the work; bounded builders implement; a reviewer from a
different model family checks every delegated result; and **judgement** models
enter only in short bursts. This file is the always-loaded policy; the
  `model-routing` skill carries the decision procedure and `model-routing.md` carries
  the dated evidence snapshot and lane mapping.

> **Adapt this to your setup.** The model names below (`opus`/`sonnet`/`fable` on
> Claude; the reference numbers) are the author's. Swap them for your own tiers —
> see `ADAPTING.md`. The *structure* (lead / builder / cross-family reviewer /
> judgement, escalation, verification) is the transferable part.

## Lanes (reference mapping — author's models)

- **Lead = the capable-but-not-metered model** (author: **Opus 5 @ xhigh**).
  Owns requirements, decisions, integration, verification, the final response.
  Resident. Drop to medium effort for routine coordination.
- **Judgement = Fable 5 at max or Sol at max**, selected explicitly. Fable emphasizes
  architecture, trade-offs, and synthesis; Sol emphasizes repository fit,
  technical feasibility, failure modes, and verifiability. **Two touches per
  feature, max — a plan up front, a verdict/synthesis at the end**; only a crossed
  commitment boundary (workers contradicting beyond their brief, a subtask failing
  verification twice, a judgment call outside the success criteria, or the plan
  changing structurally mid-run) buys a third, and spending it is never silent.
  Terse structured output. Never typing, never babysitting workers, never resident;
  reserve for architecture-moving decisions and the high-value calls where its
  gradient pays. Installable as `fable-judge` and the Codex `sol-judge` profile.
  `super-judgement` pairs them only after an explicit decision: independent
  verdicts first, cross-review second, final authority stays with the lead.
- **Small non-builder work = Sonnet 5 or Luna.** Sonnet clerk/scout/reviewer and
  `luna-clerk` handle only very small bounded extraction, read-only mapping, log
  summaries, and routine review. They never implement.
- **High-level builder and reviewer = Opus 5 or Terra, both at max.** Editing
  uses `opus-builder` / `terra-builder`; review uses the separate read-only
  `opus-reviewer` / `terra-reviewer` profiles. Sonnet has no builder profile.
- **Every delegated result gets cross-family review.** Resolve the appropriate
  review lane with `--producer-profile`; the router excludes the producer's
  entire family. Sol remains an advanced read-only default when it is
  cross-family; Sonnet may review only very small routine work. Architecture
  decisions remain explicit Fable/Sol judgement, and user-facing taste remains
  the lead's responsibility.

## Named profiles (installed to `~/.claude/agents/`)

| profile | model / effort | use for |
|---|---|---|
| `sonnet-clerk` | sonnet / low | very small extraction, inventories, log/test summaries |
| `sonnet-scout` | sonnet / low | very small read-only repo trace |
| `sonnet-reviewer` | sonnet / medium | very small routine correctness review |
| `opus-builder` | claude-opus-5 / max | bounded implementation with acceptance checks |
| `opus-reviewer` | claude-opus-5 / max | read-only review of non-Anthropic output |
| `fable-judge` | fable / max | judgement: plan up front + final verdict/synthesis (two-touch) |

### Optional evaluated GLM executor

GLM-5.3-Flash is staged only through the installed `glm-executor` skill and the
isolated Claude→Z.AI backend, keyed by `ZAI_API_KEY` or the 600-mode key the
installer stored. The exact candidate tuple is `glm-5.3-flash/max`; clerk,
scout, and builder remain candidate/blocked until the versioned local pack
passes. Reviewer is disabled and policy annotation remains a separate blocked
evaluation-only lane. Official launch evidence, Coding Plan access, and the
earlier ox-alpha diagnostic do not transfer qualification across transports.
Historical GLM-5.2 and GLM-5.3 receipts remain evidence only. Never silently
substitute another model, bypass the gate, or promote an unevaluated lane.

### Optional Gemini 3.7 Flash executor

Gemini 3.7 Flash is staged only through `gemini-executor` and
`delegation-gemini`, using the authenticated Antigravity CLI (`agy`). No lane is
operational yet: scout at `medium` and builder/frontend-builder at `high` are
blocked candidates; reviewer and judgement are disabled. The current local
session cannot attest exact model inventory or OAuth, and the old Gemini 3.6
smoke does not transfer. Runtime/model listing is not qualification, and the
runner never changes model, effort, backend, or
lane silently. Dispatches are prompt-only: embed all relevant file excerpts in
the brief. Never use `--dangerously-skip-permissions` or grant headless
filesystem, shell, network, MCP, subagent, or editing tools. The runner starts
`agy` with an empty temporary workspace and home, carries across only macOS
Keychain access for OAuth, and explicitly denies every tool namespace.

### Optional provisional DeepSeek V4 Pro builder

DeepSeek V4 Pro is available only through `deepseek-executor` and
`delegation-deepseek`, pinned to the official OpenAI-compatible API at effort
`max`. Only `builder` is provisional and explicit-only; require an explicit
decision and `--allow-provisional`. The bridge is prompt-only and text-only:
embed the relevant file excerpts, request a patch, and let the lead apply and
verify it. One live exact-tuple patch smoke proved provider identity and effort
acceptance, not builder qualification. Clerk, scout, reviewer, senior, and
policy annotation remain blocked candidates; judgement is disabled. Never copy
another tool's key silently or substitute another model, effort, backend, or
lane.

### Optional gated Kimi model

Kimi K3 is provisional for `clerk`, `scout`, `builder`, and `frontend-builder`
only through the installed `kimi-executor` skill, using the native Kimi Code CLI
at effort `max`. CLI compatibility is determined by capabilities, not by an
exact version; the observed version is provenance only. Every lane uses an
isolated minimal config, allowlisted environment, ephemeral `--agent-file`, and
macOS sandbox. Read-only lanes expose Read/Glob/Grep/TodoList; builders add
scoped editing tools. Grep runs through a digest-pinned `rg` copied into a
sandbox-unwritable exec directory, while Bash, Web, MCP, skills, subagents,
Plan, and every other executable stay
blocked. Builders are confined to their canonical worktree. Compatibility
requires `--agent-file`, `stream-json`, a valid isolated config, K3, and
effective `max`; the installer never runs `kimi update`. Senior is blocked, and
reviewer/judgement remain disabled. `policy-annotation` is candidate/blocked
only for a manifest-bound evaluation at the exact Kimi K3/max tuple; it never
adds an operational route or qualifies broad judgement.
Require an explicit decision and `--allow-provisional` before dispatch.
Kimi K3 is not scored or qualified merely because a CLI can reach it. If the gate
or runtime is absent, keep the incumbent; never silently substitute a model,
effort, or neighboring lane. Dispatches serialize by default; parallel Kimi
workers each need the explicit `--oauth shared` flag, which shares one
runner-owned OAuth generation so the vendor CLI's own lock coordinates
refreshes. Exit 69 covers runtime/login/entitlement/quota,
75 covers overload/5xx/timeout/OAuth conflict (including a busy or superseded
shared OAuth session), 70 covers sandbox/output/
unclassified failure, 78 covers authorization, and 130 is caller cancellation.

### Optional provisional Qwen3.8-Max builder

Qwen3.8-Max is installed only through `qwen-executor` and `delegation-qwen`,
pinned to `qwen3.8-max` on the Qwen Cloud Token Plan OpenAI-compatible backend
at `xhigh`. Only `builder` is promoted, as provisional and explicit-only:
require an explicit routing decision and `--allow-provisional`. That promotion
is an owner decision, not measured capability — no DeepSWE or Terminal-Bench v2
row exists for this model, so both builder required metrics are unmet.

The lane is text-only: the chat-completions transport has no tools, no terminal,
and cannot edit a worktree, so it returns a patch the lead applies and verifies.
It is also prompt-only — embed the relevant file excerpts in the brief, because
paths alone reach nothing. Prefer an editing builder (Grok Build, Kimi Code) when
the task genuinely needs autonomous edits.

Subscription access, a valid key, or a smoke test is not qualification. Every
other lane stays blocked until exact local evaluation promotes both routing
gates, and a refused builder never justifies substituting a neighbouring lane.
Never use `--evaluation` for ordinary work; it cannot be combined with
`--allow-provisional`. The only evaluation-capable lane is manifest-bound
`policy-annotation` at the exact Qwen/xhigh tuple; it cannot promote or mutate a
gate or qualify broad judgement, and its previous manifest is void after the
rename from `qwen3.8-max-preview`.

### Optional Grok 4.6 builder

Grok 4.6 is provisional for `builder` and `frontend-builder` only through
`grok-executor` and `delegation-grok`, using Grok Build CLI at effort `high`.
Require an explicit routing decision and `--allow-provisional`. The runner pins
the exact model/effort tuple, capability-probes the CLI, extracts only `.text`,
uses an ephemeral HOME without memory, subagents, web, plugins, MCP,
compatibility imports, or updates,
and requires the custom `delegation-kit` sandbox to attest enforcement.
Permission mode is `dontAsk`, with only file edits explicitly allowed; terminal
execution is not exposed and the lead runs verification. Runs have 40-turn and
15-minute limits. Any CLI version is accepted when those capabilities pass; the
observed version is provenance only. An optional digest-checked private archive
preserves the selected bytes independently of PATH; use
`delegation-grok pin --force` for deliberate replacement. No other Grok lane is exposed, and failure
never authorizes silent fallback.
OAuth runs serialize by default and persist validated refreshes atomically.
Parallel Grok workers must each pass `--oauth shared`; they use one
runner-owned generation so the vendor auth lock coordinates refresh while
workspaces, prompt state, and output remain isolated. External `grok login`
supersedes the generation, and evaluations are always serialized.
`policy-annotation` at `high` is the only evaluation-only exception: it is
candidate/blocked, requires an allowlisted manifest and the read-only sandbox,
and cannot create an operational route.

### Evidence-backed qualification

Use `delegation-evidence lane <lane>` to inspect the current external snapshot.
It reports coverage for the exact model+harness+effort row but never qualifies a
lane or edits a gate. Builder needs DeepSWE plus Terminal-Bench; WebDev applies
only to frontend work; reviewer needs review precision and recall. Runtime/auth
and a small local scope/permission smoke remain mandatory.
Use `delegation-route resolve --lane judgement` or `super-judgement` for the
central manual gate. The router reports decisions but never dispatches.
Before spawning a native profile, require it in the relevant
default/fallback/explicit group. Invoking an explicit-only profile is the manual
selection event; never spawn a blocked profile. External runners enforce the
central graph directly before runtime/auth checks.

For `routine-review`, `material-review`, and `security`, resolution without a
producer identity is invalid. Use, for example,
`delegation-route resolve --lane material-review --producer-profile terra-builder`.
The returned `excluded_same_family` list is an audit trail, not a fallback pool.
Verify runtime/auth for the returned reviewers; if none is available, stop rather
than letting the producer family review itself.
For the Opus security route, Anthropic may substitute Opus 4.8 when its safety
classifier flags a cyber request. The router exposes this under
`provider_fallback`; inspect surfaced content-model identity or use Anthropic's
CVP when exact Opus 5 identity is mandatory.

## Rules

- **Effort and role are pinned:** the Opus and Terra builder/reviewer profiles all
  run at `max`; reviewer profiles are read-only. `luna-clerk` stays at `max` because Luna collapses at low on the exact
  evidence row, but remains limited to very small deterministic work. Sonnet keeps
  low for clerk/scout and medium for tiny routine review. Never turn Sonnet or Luna
  into a builder.
- **Cross-family review is mandatory:** every delegated result is reviewed by an
  operational reviewer from a different family. Very small work uses
  `routine-review`; implementation uses `material-review`; security-shaped work
  uses `security`. A model never reviews its own output or output from a sibling
  model in the same family, even through a separate profile.
- **Picking among the external builders:** they are not interchangeable. Kimi K3
  and Grok 4.6 are `preferred-explicit` by explicit owner decision; GLM-5.3,
  Qwen3.8-Max, and DeepSeek V4 Pro stay plain `explicit-only`. Grok 4.6's current public rows use
  non-production harnesses, so they are contextual rather than exact. Preference
  is not qualification — every one of them still needs an explicit decision and
  `--allow-provisional`. For frontend work prefer Kimi over Grok on WebDev
  when current evidence supports it, and prefer any editing runner over Qwen, whose text-only
  transport returns a patch the lead must apply itself.
- **Escalation ladder:** small-lane miss or implementation need → Opus/Terra
  builder; review → an available eligible cross-family reviewer; architecture
  conflict → judgement. Never retry
  the same unsuitable small lane twice. (Standing rule: judge the output, not the
  price tag.)
- **Verification:** no executor diff ships unread, and a check must **exercise the
  deliverable** — run the command, read the output; grepping a README, testing
  something adjacent, or printing True while exiting zero proves nothing.
  Self-checks do not replace the required cross-family review.
  The judgement model only re-checks what it
  produced or a multi-attempt synthesis — don't spend it verifying the executor.
- **No double fan-out:** in an orchestration/ultra mode, let the orchestrator fan
  out; don't add a second manual delegation layer. Workers return distilled
  evidence (changed paths, checks run, unresolved risks), not raw logs or essays.
- **Degraded mode:** for a non-review lane with no reachable model/bridge, the
  lead may play it with every affected result labeled `[DEGRADED: <lane>]`, one
  lane max. A missing cross-family reviewer is never degradable to self-review:
  stop and report the blocker. With two or more non-review lanes gone there is
  no team, so say so and work as ordinary single-model.
- **Delegated output is unverified until you check it.** **Tie-breakers:**
  required lane evidence > deliverable quality > cost; and `cost` is per *task*,
  not per token.

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
- Inline override: `codex exec -m gpt-5.6-luna -c model_reasoning_effort=max -s read-only "<prompt>" </dev/null`.
  **Default to `-s read-only`** for review/analysis; add `-s workspace-write` only to let
  it edit; always redirect stdin from `/dev/null`.
- Machine-readable return: add `--json` (JSONL events) or `-o <file>` (final message
  only) — **raw stdout is polluted with hook chatter**, so don't parse it directly.
- Structured return: compile the normative schema first with
  `delegation-schema compile --provider codex --schema <schema.json>` and pass
  the derived file to `--output-schema`. The compiler removes dialect metadata,
  adds only unambiguous enum/const types, and refuses non-strict objects (every
  property required, `additionalProperties: false`). A `codex exec --help`
  check proves flag availability only; it is not a semantic schema preflight.
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
- **Treat JSONL as telemetry, not the final payload.** Intermediate agent
  messages may not satisfy the final output schema. Validate the final `-o`
  artifact, and keep the model banner/structured events as separate routing
  evidence.

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

## Evidence discipline

The reference snapshot is dated and machine-readable in
`config/model-evidence.json`; `delegation-evidence check` fails when it is stale.
Keep API cost/task separate from subscription buckets, keep variants exact, and
never infer reviewer or security quality from a general coding leaderboard. See
`evaluation/README.md` and `ADAPTING.md` before changing a routing gate.
