# delegation-kit

Teach **Claude Code** and **Codex** how and when to delegate coding work across
models — a cheap lane executes, a senior lane reviews taste/security, an expensive
lane does judgement — with a symmetric bridge so each can reach the other.

It ships as a **reference implementation**: the author's concrete models
(`sonnet`/`opus`/`fable` on Claude; `luna`/`terra`/`sol` on Codex), a dated
external-evidence snapshot, and fail-closed local gates. Swap the models for your own tiers with
[`ADAPTING.md`](./ADAPTING.md) — the *structure* is the transferable part.

## Current release: 0.5.0

Version 0.5.0 replaces the senior, taste, material-review, and security profile
with exact `claude-opus-5` at `high` effort. The routing gate records the local
runtime smokes and exposes Anthropic's documented, provider-controlled fallback
to Opus 4.8 for flagged cyber requests, so callers do not mistake the requested
model for a guaranteed runtime identity. The doctor now validates both model and
effort on the active profile.

## What it installs

**Claude Code** (`~/.claude/`)
| piece | where | what |
|---|---|---|
| 6 subagent profiles | `agents/*.md` | `sonnet-clerk` · `sonnet-scout` · `sonnet-builder` · `sonnet-reviewer` · `opus-reviewer` · `fable-judge` (judgement lane) (model+effort pinned) |
| routing skill | `skills/model-routing/` | surfaces the decision procedure when you delegate |
| orchestrate skill | `skills/orchestrate/` | the fan-out loop — plan → delegate to workers → verify → advisor judges plan + ship |
| optional GLM skill | `skills/glm-executor/` | dispatches only gate-allowed GLM lanes; provisional use is explicit |
| optional Gemini skill | `skills/gemini-executor/` | Antigravity-backed Gemini 3.6 Flash scout; provisional use is explicit |
| optional Kimi skill | `skills/kimi-executor/` | exposes only exact gate-allowed Kimi lane/backend/effort tuples |
| provisional Grok skill | `skills/grok-executor/` | Grok Build-backed builder and frontend-builder at pinned high effort |
| blocked Qwen skill | `skills/qwen-executor/` | Token Plan candidate; no normal dispatch before evaluation |
| lane discipline | `@import` in `CLAUDE.md` | always-loaded policy ([`claude/CLAUDE.delegation.md`](./claude/CLAUDE.delegation.md)) |

**Codex** (`~/.codex/`)
| piece | where | what |
|---|---|---|
| 5 native profiles | `agents/*.toml` | `luna-clerk` · `terra-scout` · `terra-builder` · `sol-reviewer` · `sol-judge` |
| 5 ephemeral profiles | `*.config.toml` | for `codex exec --ephemeral -p <name>` |
| collaboration policy | appended to `AGENTS.md` | usage-aware routing **+ a Codex→Claude bridge** |
| optional GLM skill | `skills/glm-executor/` | same fail-closed GLM-5.2 executor path |
| optional Gemini skill | `skills/gemini-executor/` | same fail-closed Gemini 3.6 Flash executor path |
| optional Kimi skill | `skills/kimi-executor/` | same fail-closed provisional Kimi K3 path |
| provisional Grok skill | `skills/grok-executor/` | same fail-closed Grok 4.5 builder path |
| blocked Qwen skill | `skills/qwen-executor/` | same fail-closed Qwen3.8 preview candidate path |
| config snippet | printed for manual merge | `[agents]` fan-out caps + lead defaults |

The universal installer also adds `delegation-glm`, `delegation-gemini`, `delegation-kimi`,
`delegation-grok`, `delegation-qwen`,
`delegation-evidence`, the ZIP-only `delegation-epoch` importer, and the read-only
central router `delegation-route` under
`~/.local/bin`, with versioned gates under `~/.local/share/delegation-kit/`.
GLM `clerk` and `scout` are provisional and require `--allow-provisional`;
builder is a blocked candidate and reviewer is disabled. The runner refuses every
blocked lane and every effort the gate did not pin, and also refuses execution unless at least one of Claude Code or Codex is
installed; it is an agent option, not a standalone GLM client. The installer asks
for the Z.AI API key and stores it in `~/.local/share/delegation-kit/config/zai.env`
(mode 600); an explicit `ZAI_API_KEY` in the environment overrides it.
Failed GLM dispatches write a sanitized `<output>.error.json` that distinguishes
runtime exit, malformed streams, model mismatch, missing/empty results, auth, and
rate limits. Raw events and stderr are deleted unless an existing private
directory is explicitly supplied with `--debug-dir`; those artifacts are
sensitive and must not be committed.

Gemini 3.6 Flash uses the installed, user-authenticated Antigravity CLI (`agy`).
Only `scout` at `medium` is provisional and requires `--allow-provisional`;
builder and frontend-builder at `high` remain blocked candidates, while reviewer
and judgement are disabled. The runner never substitutes another Gemini variant
or treats OAuth/model listing as qualification. This bridge is prompt-only:
the lead must embed the relevant tracked-file excerpts in the brief, because
headless filesystem and other tool permissions are never auto-approved. `agy`
starts with an empty temporary workspace and home; only macOS Keychain access
is carried across for OAuth, while all tool namespaces are explicitly denied.

Kimi K3 is installed as a **provisional coding model**. Its gate permits explicit
`clerk`, `scout`, `builder`, and `frontend-builder` runs at `max`; senior is a
blocked candidate, reviewer/judgement remain disabled, and `policy-annotation`
is candidate/blocked for manifest-bound evaluation only. It never creates an
operational route or qualifies architecture/trade-off judgement. Provider quota exhaustion
returns exit 75 without silently falling back or changing the quality
qualification. Provisional runs require `--allow-provisional`; CLI
availability or a provider model listing is not enough. CLI compatibility is
determined from capabilities: structured output, the exact `kimi-code/k3`
model, OAuth, and `max` as the supported/effective effort are required, while
the observed version is provenance only. The runner imports
only authentication into a minimal isolated HOME, scrubs the environment,
disables terminal execution, and hides ambient HOME contents. macOS
`sandbox-exec` limits read-only lanes to scratch writes and builder lanes to
worktree-plus-scratch writes; every lane fails closed when that guard is
unavailable.

Grok 4.5 is installed as a **provisional builder** through Grok Build CLI.
`builder` and `frontend-builder` are available only at effort `high`, after an
explicit decision and `--allow-provisional`. The runner pins the model, extracts
only the public `text` field from JSON output, capability-probes the resolved
CLI, and caps runs at 40 turns and 15 minutes. An ephemeral HOME disables
memory, subagents, web, plugins, MCP, compatibility imports, and automatic updates. The custom
`delegation-kit` sandbox must attest OS enforcement before output is published;
the permission mode is `dontAsk`, with only file edits explicitly allowed; the
terminal tool is not exposed.
The lead remains responsible for running tests and every command after review.
Failures expose sanitized metadata by default, with raw debug artifacts only
through explicit `--debug-dir`. No other Grok lane is exposed.

Because the vendor CLI auto-updates and prunes its own download cache,
`delegation-grok pin` can archive the currently compatible build in
`$DATA_HOME/grok-cli/current/` with a recorded SHA-256. The runner resolves
`DELEGATION_GROK_BIN`, then that private archive, then `grok` on PATH. Any
version is accepted when it exposes the required interface, authenticated
`grok-4.5` inventory, isolation state, structured output, and sandbox
attestation; the observed version is provenance only. `install.sh` archives the
compatible build automatically when available. A digest mismatch fails closed
rather than running changed bytes.

```sh
delegation-grok pin
delegation-grok check --json
delegation-grok run --lane builder --allow-provisional \
  --effort auto --backend auto --prompt-file "$brief" \
  --output "$result" --metrics "$metrics" --workdir "$repo"
```

Qwen3.8 Max Preview is installed as a **blocked candidate**, pinned to the
Qwen Cloud Token Plan OpenAI-compatible endpoint and `xhigh`. Its dedicated
`sk-sp-` key is stored separately and never imported silently from another tool.
Runtime availability is not qualification; `--evaluation` is reserved for a
manifest-bound controlled local qualification run at the exact pinned tuple; it
never promotes or mutates a gate.

The evidence-backed routing policy lives in [`model-routing.md`](./model-routing.md).
Its raw, dated model+harness+effort snapshot is
[`config/model-evidence.json`](./config/model-evidence.json), with source and lane
methodology in [`evaluation/README.md`](./evaluation/README.md). The universal
installer exposes it as `delegation-evidence`; external evidence is advisory and
cannot mutate a routing gate.

Epoch AI's public benchmark data is consumed only from its downloadable ZIP:

```sh
delegation-epoch check
delegation-epoch evidence --model gpt-5.6-sol --benchmark deepswe
```

The importer downloads into memory, validates archive/CSV safety, preserves
source and license metadata, and emits normalized JSON to stdout or an explicit
output path. It never persists the ZIP, extracts a corpus into the checkout, or
edits `config/model-evidence.json` or a routing gate. The Airtable/`epochai`
client is intentionally out of scope.

The central decision file is [`config/routing-gates.json`](./config/routing-gates.json).
It is the dispatch authority: GLM, Gemini, Kimi, Grok, and Qwen validate it against their complete
backend gates before every check/run, and refuse drift. Exact and contextual
benchmark references are stored separately, and the generated table exposes
local sample size/confidence instead of treating legacy scores as comparable.
Fable `xhigh` and Sol `high` are explicit, manually qualified judgement profiles.
`super-judgement` pairs them as independent judges followed by cross-review; the
lead retains final authority and no dispatch, merge, or deploy is automatic.

## Install

**Universal (both tools, does everything):**
```sh
git clone https://github.com/matteoscurati/delegation-kit
cd delegation-kit
./install.sh            # or --claude-only / --codex-only
```
Idempotent, refreshes its guarded policy blocks, backs up before editing, and
prints the Codex config snippet (it never auto-edits `config.toml`). Keep the
checkout where it is — Claude's `@import` points
at it, so `git pull` updates the policy live. Remove with `./uninstall.sh`.

Then verify the bridge and evidence snapshot are actually **wired** (not just
written) with `./doctor.sh` —
it checks both CLIs, auth, the installed profiles *and* the always-loaded policy
blocks, and the Codex sandbox/network posture. `./doctor.sh --ping` also does a
live round-trip in both directions; `--ping-glm`, `--ping-kimi`, and
`--ping-grok` separately exercise their gated runtimes. The failure it catches
is silent: profiles present but a policy block missing means the bridge never
fires.

Run the fail-closed regression suite after changing a gate:

```sh
tests/routing-gates.sh
tests/epoch-zip.sh
tests/glm-runner-diagnostics.sh
tests/gemini-runner-diagnostics.sh
tests/kimi-runner.sh
tests/grok-runner.sh
tests/qwen-runner.sh
git diff --check
```

**Claude-only, one command (plugin):**
```
/plugin marketplace add matteoscurati/delegation-kit
/plugin install delegation-kit
```
This installs the 6 agents plus the `model-routing`, `orchestrate`, and guarded
`glm-executor`, `gemini-executor`, `kimi-executor`, provisional `grok-executor`,
and blocked `qwen-executor` skills. It does not install any external model
runner/gate, register the
`CLAUDE.md` policy prose, or install the Codex side — run `./install.sh` for those.

## How it works

- **Lead** owns the work and enters the **judgement** model only in short bursts
  (a plan up front, a verdict at the end) — thinking, not typing.
- **Executor** (cheap) does the volume and the *default* routine review.
- **Senior** handles security (routed directly), user-facing taste, and escalation.
- **Route review by content, not habit**; **size the reviewer to the work**;
  escalate cheap → senior → judgement, never retry an unsuitable cheap worker twice.
- Tie-breakers: **required lane evidence > deliverable quality > cost**, and
  **`cost` is per task, not per token** — a chatty cheap model can still be
  cheapest to finish the job.

## Cross-provider bridge

- **Claude → Codex**: for interactive/context-preserving work prefer the
  [`codex@openai-codex` plugin](https://github.com/openai/codex-plugin-cc) — the
  `codex:codex-rescue` agent (agent-invokable), plus the user-run slash commands
  `/codex:review` and `/codex:transfer` (suggest them; the assistant can't invoke
  them); for programmatic/parallel work drive a GPT lane with
  `codex exec --ephemeral -p <profile>` (or `-m <model> -c model_reasoning_effort=<level>`).
  Both in [`claude/CLAUDE.delegation.md`](./claude/CLAUDE.delegation.md).
- **Codex → Claude**: call `claude -p "<prompt>" --model claude-opus-5|sonnet --effort <level>`
  for taste, an independent-family second-opinion review, or bucket-aware offload
  (in [`codex/AGENTS.md`](./codex/AGENTS.md)). CLI-only — no reverse plugin exists.

Both directions pass context through the **shared working tree**, not the
conversation: run the child in the repo root and reference files by path. The only
history-preserving handoff is `/codex:transfer` (Claude → Codex, a user-run command).

## Adapt & license

Different models or plans? [`ADAPTING.md`](./ADAPTING.md) maps every role to a
model/effort slot and shows how to re-derive the numbers. MIT — see
[`LICENSE`](./LICENSE).
