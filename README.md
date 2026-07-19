# delegation-kit

Teach **Claude Code** and **Codex** how and when to delegate coding work across
models — a cheap lane executes, a senior lane reviews taste/security, an expensive
lane does judgement — with a symmetric bridge so each can reach the other.

It ships as a **reference implementation**: the author's concrete models
(`sonnet`/`opus`/`fable` on Claude; `luna`/`terra`/`sol` on Codex) and measured
numbers, wired up and ready to run. Swap the models for your own tiers with
[`ADAPTING.md`](./ADAPTING.md) — the *structure* is the transferable part.

## What it installs

**Claude Code** (`~/.claude/`)
| piece | where | what |
|---|---|---|
| 6 subagent profiles | `agents/*.md` | `sonnet-clerk` · `sonnet-scout` · `sonnet-builder` · `sonnet-reviewer` · `opus-reviewer` · `fable-judge` (judgement lane) (model+effort pinned) |
| routing skill | `skills/model-routing/` | surfaces the decision procedure when you delegate |
| orchestrate skill | `skills/orchestrate/` | the fan-out loop — plan → delegate to workers → verify → advisor judges plan + ship |
| optional GLM skill | `skills/glm-executor/` | dispatches only evaluation-qualified GLM-5.2 lanes through the guarded runner |
| optional Kimi skill | `skills/kimi-executor/` | exposes Kimi K3 only where its versioned gate qualifies the exact lane/backend/effort |
| lane discipline | `@import` in `CLAUDE.md` | always-loaded policy ([`claude/CLAUDE.delegation.md`](./claude/CLAUDE.delegation.md)) |

**Codex** (`~/.codex/`)
| piece | where | what |
|---|---|---|
| 4 native profiles | `agents/*.toml` | `luna-clerk` · `terra-scout` · `terra-builder` · `sol-reviewer` |
| 4 ephemeral profiles | `*.config.toml` | for `codex exec --ephemeral -p <name>` |
| collaboration policy | appended to `AGENTS.md` | usage-aware routing **+ a Codex→Claude bridge** |
| optional GLM skill | `skills/glm-executor/` | same fail-closed GLM-5.2 executor path |
| optional Kimi skill | `skills/kimi-executor/` | same fail-closed provisional Kimi K3 path |
| config snippet | printed for manual merge | `[agents]` fan-out caps + lead defaults |

The universal installer also adds the `delegation-glm` and `delegation-kimi`
commands under `~/.local/bin`, with versioned routing gates under
`~/.local/share/delegation-kit/`. The shipped
2026-07 evaluation qualifies only `clerk` and `scout`, both routed at `high`,
through the isolated Claude→Z.AI backend. `builder` and `reviewer` remain
disabled. The runner refuses every unqualified lane and every effort the gate did
not pin, and also refuses execution unless at least one of Claude Code or Codex is
installed; it is an agent option, not a standalone GLM client. The installer asks
for the Z.AI API key and stores it in `~/.local/share/delegation-kit/config/zai.env`
(mode 600); an explicit `ZAI_API_KEY` in the environment overrides it.

Kimi K3 is installed as a **provisional coding model**. The gate enables `clerk`,
`scout`, `builder`, and `senior` through the native Kimi Code CLI at effort
`max`. `reviewer` and `judgement` remain disabled. Provider quota exhaustion
returns exit 75 without silently falling back or changing the quality
qualification. `delegation-kimi check --json` is the source of truth; CLI
availability or a provider model listing is not enough.

The shared scored table (cost / intelligence / taste per model) lives in
[`model-routing.md`](./model-routing.md).

GLM-5.2's scored row and routing limits come from a pre-publication high/max
evaluation against the incumbent profiles, with promotion decided separately
for each lane. The repository ships only the resulting versioned gate; the GLM
evaluation harness, test fixtures, raw outputs, and reports are kept outside the
public package.

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

Then verify the bridge is actually **wired** (not just written) with `./doctor.sh` —
it checks both CLIs, auth, the installed profiles *and* the always-loaded policy
blocks, and the Codex sandbox/network posture. `./doctor.sh --ping` also does a live
round-trip in both directions; `--ping-glm` and `--ping-kimi` separately ping the
first evaluation-qualified lane and skip when no lane is qualified. The failure it
catches is silent: profiles present but a policy block missing means the bridge
never fires.

**Claude-only, one command (plugin):**
```
/plugin marketplace add matteoscurati/delegation-kit
/plugin install delegation-kit
```
This installs the 6 agents plus the `model-routing`, `orchestrate`, and guarded
`glm-executor` and `kimi-executor` skills. It does not install either external
model runner/gate, register the
`CLAUDE.md` policy prose, or install the Codex side — run `./install.sh` for those.

## How it works

- **Lead** owns the work and enters the **judgement** model only in short bursts
  (a plan up front, a verdict at the end) — thinking, not typing.
- **Executor** (cheap) does the volume and the *default* routine review.
- **Senior** handles security (routed directly), user-facing taste, and escalation.
- **Route review by content, not habit**; **size the reviewer to the work**;
  escalate cheap → senior → judgement, never retry an unsuitable cheap worker twice.
- Tie-breakers: **intelligence > taste > cost**, and **`cost` is per task, not per
  token** — a chatty cheap model can still be cheapest to finish the job.

## Cross-provider bridge

- **Claude → Codex**: for interactive/context-preserving work prefer the
  [`codex@openai-codex` plugin](https://github.com/openai/codex-plugin-cc) — the
  `codex:codex-rescue` agent (agent-invokable), plus the user-run slash commands
  `/codex:review` and `/codex:transfer` (suggest them; the assistant can't invoke
  them); for programmatic/parallel work drive a GPT lane with
  `codex exec --ephemeral -p <profile>` (or `-m <model> -c model_reasoning_effort=<level>`).
  Both in [`claude/CLAUDE.delegation.md`](./claude/CLAUDE.delegation.md).
- **Codex → Claude**: call `claude -p "<prompt>" --model opus|sonnet --effort <level>`
  for taste, an independent-family second-opinion review, or bucket-aware offload
  (in [`codex/AGENTS.md`](./codex/AGENTS.md)). CLI-only — no reverse plugin exists.

Both directions pass context through the **shared working tree**, not the
conversation: run the child in the repo root and reference files by path. The only
history-preserving handoff is `/codex:transfer` (Claude → Codex, a user-run command).

## Adapt & license

Different models or plans? [`ADAPTING.md`](./ADAPTING.md) maps every role to a
model/effort slot and shows how to re-derive the numbers. MIT — see
[`LICENSE`](./LICENSE).
