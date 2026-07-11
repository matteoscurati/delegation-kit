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
| 5 subagent profiles | `agents/*.md` | `sonnet-clerk` · `sonnet-scout` · `sonnet-builder` · `sonnet-reviewer` · `opus-reviewer` (model+effort pinned) |
| routing skill | `skills/model-routing/` | surfaces the decision procedure when you delegate |
| lane discipline | `@import` in `CLAUDE.md` | always-loaded policy ([`claude/CLAUDE.delegation.md`](./claude/CLAUDE.delegation.md)) |

**Codex** (`~/.codex/`)
| piece | where | what |
|---|---|---|
| 4 native profiles | `agents/*.toml` | `luna-clerk` · `terra-scout` · `terra-builder` · `sol-reviewer` |
| 4 ephemeral profiles | `*.config.toml` | for `codex exec --ephemeral -p <name>` |
| collaboration policy | appended to `AGENTS.md` | usage-aware routing **+ a Codex→Claude bridge** |
| config snippet | printed for manual merge | `[agents]` fan-out caps + lead defaults |

The shared scored table (cost / intelligence / taste per model) lives in
[`model-routing.md`](./model-routing.md).

## Install

**Universal (both tools, does everything):**
```sh
git clone https://github.com/matteoscurati/delegation-kit
cd delegation-kit
./install.sh            # or --claude-only / --codex-only
```
Idempotent, backs up before editing, and prints the Codex config snippet (it never
auto-edits `config.toml`). Keep the checkout where it is — Claude's `@import` points
at it, so `git pull` updates the policy live. Remove with `./uninstall.sh`.

Then verify the bridge is actually **wired** (not just written) with `./doctor.sh` —
it checks both CLIs, auth, the installed profiles *and* the always-loaded policy
blocks, and the Codex sandbox/network posture. `./doctor.sh --ping` also does a live
round-trip in both directions. The failure it catches is silent: profiles present
but a policy block missing means the bridge never fires.

**Claude-only, one command (plugin):**
```
/plugin marketplace add matteoscurati/delegation-kit
/plugin install delegation-kit
```
This installs the 5 agents + the skill. It does **not** register the `CLAUDE.md`
policy prose or the Codex side — run `./install.sh` for those.

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
