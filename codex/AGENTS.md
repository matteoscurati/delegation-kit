# Usage-aware collaboration (installed by delegation-kit)

> **Adapt to your setup.** The profile names below (`luna-clerk` / `terra-scout` /
> `terra-builder` / `sol-reviewer` / `sol-judge`) and their models are the author's reference
> mapping — swap them for your own tiers (see `ADAPTING.md`). The *structure* is
> the transferable part.

- Default to solving simple, well-scoped work directly. Do not create subagents for a routine single-file change.
- The lead owns requirements, decisions, integration, verification, and the final response.
- For genuinely separable work, use at most two direct workers by default. Give each a bounded task, explicit file ownership, and a concise return format. Never allow recursive delegation.
- Prefer `luna-clerk` for deterministic inventory, extraction, transformation, and test-log summaries; `terra-scout` for read-only repository mapping; `terra-builder` for a bounded implementation; `sol-reviewer` for material review; and `sol-judge` for explicit technical judgement.
- When the native subagent tool cannot select a model, use the matching ephemeral CLI profile. `sol-judge` is read-only and explicit-only; it never edits, delegates, merges, or deploys.
- Avoid double fan-out: in Ultra mode, let Ultra orchestrate and do not add a second manual delegation layer. Ultra is exceptional, not the default.
- Escalate Luna to Terra, or Terra to Sol, when the task becomes ambiguous or high risk. Do not repeatedly retry an unsuitable cheap worker.
- Workers should return distilled evidence, changed paths, checks run, and unresolved risks—not raw logs or broad essays.

## Optional evaluated GLM executor

GLM-5.2 is available only through the installed `glm-executor` skill. The current
gate lists `clerk` and `scout` in `qualified_lanes`, with explicit-only
selection. Builder is provisional after its first exact local pack and requires
an explicit decision plus `--allow-provisional`. The bridge runs only through the isolated Claude→Z.AI
backend, keyed by `ZAI_API_KEY` or the 600-mode key the installer stored. Prefer
the incumbent for costly edits unless the provisional builder lane was selected deliberately. If the runtime or
lane gate is absent, keep using the incumbent profile; never silently substitute.
`policy-annotation` at `high` is a separate candidate/blocked lane available
only through an allowlisted read-only evaluation manifest. It never adds an
operational route or qualifies broad judgement.

## Optional Gemini 3.6 Flash executor

Gemini 3.6 Flash is available only through `gemini-executor` and
`delegation-gemini`, using the authenticated Antigravity CLI (`agy`). The initial
gate permits only `scout` at `medium`, provisionally and with an explicit
`--allow-provisional` decision. Builder and frontend-builder at `high` are
blocked candidates; reviewer and judgement are disabled. A visible model name,
OAuth session, launch benchmark, or smoke test is not qualification. Never
silently change the exact model, effort, backend, or lane. The bridge is
prompt-only: include all needed file excerpts in the brief, and never enable
`--dangerously-skip-permissions` or assume headless tools can read the repo.
The runner starts `agy` with an empty temporary workspace and home, carries
across only macOS Keychain access for OAuth, and explicitly denies every tool
namespace.

## Evidence-backed qualification

Use `delegation-evidence lane <lane>` to inspect the dated external snapshot.
Evidence is lane-specific and advisory: DeepSWE/Terminal-Bench support builder,
WebDev supports only frontend-builder, and reviewer requires review precision and
recall. The command cannot mutate a routing gate. Runtime/auth and a small local
scope/permission smoke remain mandatory for the exact production variant.
Use `delegation-route resolve --lane <lane>` for the central operational decision.
Before spawning a native profile, require it to appear in the appropriate
default/fallback/explicit group. Invoking an explicit-only native profile is the
manual selection event; blocked profiles must not be spawned. External runners
enforce the same central graph in code before every check or dispatch.

## Judgement

Fable `xhigh` and `sol-judge` (Sol `high`) are manually qualified, explicit-only
judges. Fable covers architecture, trade-offs, and synthesis; Sol covers technical
feasibility, repository fit, failure modes, and verifiability. For an explicitly
approved `super-judgement`, they reason independently before cross-reviewing each
other; the lead keeps final authority. Never trigger the pair automatically.

## Optional gated Kimi model

Kimi K3 is provisionally usable for `clerk`, `scout`, `builder`, and `frontend-builder`
through the installed `kimi-executor` skill, using the native Kimi Code CLI at
effort `max`, only with `--allow-provisional`. CLI compatibility is determined
by capabilities, not by an exact version; the observed version is provenance
only. Every lane uses an isolated minimal config, allowlisted environment,
an ephemeral `--agent-file`, and a macOS sandbox. The read-only agent exposes
only Read/Glob/Grep/TodoList; builders add scoped editing tools. Grep executes a
digest-pinned `rg` copied into a sandbox-unwritable exec directory, while Bash,
Web, MCP, skills, subagents,
Plan, and every other executable remain blocked. Builders are confined to their
canonical worktree. Compatibility requires `--agent-file`, `stream-json`, a
valid isolated configuration, K3, and effective `max`; the CLI version is
provenance only. The installer never runs `kimi update`.
Senior is blocked; reviewer and judgement remain disabled.
`policy-annotation` is candidate/blocked only for a manifest-bound evaluation
at the exact Kimi K3/max tuple; it never adds an operational route or qualifies
broad judgement. Installed
runtimes and visible model names are not qualification. If the exact gate is
absent, keep the incumbent profile; never silently substitute another model,
effort, or lane. Dispatches serialize by default; parallel Kimi workers each
need the explicit `--oauth shared` flag. Treat exit 69 as
runtime/login/entitlement/quota unavailable,
75 as overload/5xx/timeout/OAuth conflict (including a busy or superseded
shared OAuth session), 70 as sandbox/output/unclassified
failure, 78 as an unauthorized lane, and 130 as caller cancellation.

## Optional provisional Qwen3.8-Max builder

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

## Optional Grok 4.5 builder

Grok 4.5 is provisionally usable for `builder` and `frontend-builder` only
through the installed `grok-executor` skill and `delegation-grok`, using Grok
Build CLI at effort `high`. Require an explicit decision and
`--allow-provisional`. The runner capability-probes the CLI, pins model and
effort, extracts only `.text`, uses an ephemeral HOME without memory, subagents, web,
plugins, MCP, compatibility imports, or updates, and requires the custom
`delegation-kit` sandbox to attest enforcement. Permission mode is `dontAsk`,
with only file edits explicitly allowed; terminal execution is not exposed and
the lead runs verification. Runs have 40-turn and 15-minute limits. Any CLI
version is accepted when those capabilities pass; the observed version is
provenance only. An optional digest-checked private archive preserves the
selected bytes independently of PATH; use `delegation-grok pin --force` for
deliberate replacement. No other Grok lane is enabled, and failure never
triggers a silent substitution.
`policy-annotation` at `high` is the sole evaluation-only exception: it is
candidate/blocked, manifest-bound, removes editing tools, requires the
read-only sandbox, and creates no operational route.

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
claude -p "<self-contained prompt>" --model claude-opus-5 --effort high --permission-mode plan

# let it edit:
claude -p "<self-contained prompt>" --model sonnet --effort medium --permission-mode acceptEdits

# give it a role (reviewer / taste), or a structured output:
claude -p "<prompt>" --model claude-opus-5 --effort high --permission-mode plan \
  --append-system-prompt "You are a senior security reviewer. Report findings only."
# ...or define a named agent inline: --agents '<json>'
# ...or machine-readable: --output-format stream-json
```

- **Model + effort:** `--model claude-opus-5|sonnet|<full-id>` picks the family/tier;
  `--effort low|medium|high|xhigh|max` sets the depth (available levels depend on
  the model). Reserve `opus` for taste/security/material review, `sonnet` for
  high-volume execution; scale effort to blast radius, not prestige.
- **Context (it starts fresh):** the Claude process does **not** see this Codex
  session. It *does* share the filesystem — run it from the repo root so it reads
  the same working tree (it auto-loads that repo's `CLAUDE.md`); widen its view
  with `--add-dir <path>`; reference files **by path** instead of pasting them.
  There is **no Codex→Claude history handoff** (the `codex@openai-codex` plugin is
  Claude→Codex only), so put everything else the task needs into the prompt.
- **Preflight auth and structured output semantically:** run the provider-free
  `claude auth status` before a paid dispatch. On macOS, if a sanitized
  environment relies on Keychain credentials, retain `USER`; an allowlist that
  drops it can look logged out even when the interactive CLI works. Before
  passing `--json-schema`, run `delegation-schema compile --provider claude
  --schema <normative.json>` and pass that derived JSON. `claude --help` proves
  only that a flag exists, not that auth or the actual schema will work.
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
- **Identity and usage are separate evidence:** record the requested model, any
  explicitly surfaced effective content model, and every entry under
  `modelUsage` separately. The keys of `modelUsage` are observed billing/usage
  participants, not proof that each model authored the answer; safety fallback
  and internal classifiers may add models. Sum tokens and cost across all
  entries. If the provider does not distinguish the content model from internal
  models, exact model identity is unavailable; a strict identity evaluation is
  `VOID`, even if the prose answer looks valid.
