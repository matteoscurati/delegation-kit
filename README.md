# delegation-kit

**User-directed model delegation for Claude Code and Codex — with fail-closed
governance, not autopilot.**

delegation-kit gives your coding agents a governed way to hand bounded work to
other models: cheap lanes for small support tasks, max-effort builders for
implementation, and a mandatory cross-family review of every delegated result.
The defining rule: **the kit never dispatches on its own.** Every delegation is
named or explicitly authorized by you, per request — the assistant proposes,
you decide.

It ships as a **reference implementation**: the author's concrete models
(`sonnet`/`opus`/`fable` on Claude; `luna`/`terra`/`sol` on Codex), six gated
external executors (GLM · Kimi · Grok · Qwen · DeepSeek · Gemini), a dated
evidence snapshot, and fail-closed routing gates. The *structure* is the
transferable part — swap the models for your own tiers with
[`ADAPTING.md`](./ADAPTING.md).

```
User ──chooses/authorizes──> Lead ──dispatches──> Executor lane
                               │                      │
                               └──verifies + cross-family review──┘
```

## Why

Multi-agent delegation has three recurring failure modes, and delegation-kit is
built against each of them:

1. **Agents that dispatch other agents on their own authority** — token bills
   grow, nobody approved it. Here every dispatch is user-directed, enforced by
   fail-closed routing gates rather than polite prose.
2. **Ungoverned routing** — "use whatever model is available". Here a lane
   exists only after a versioned, evidence-backed gate says so, and every
   runner re-validates the complete decision graph before dispatch.
3. **Unverified output** — delegated diffs shipped unread. Here a sufficiently
   capable model from a *different* family must review every delegated result,
   and the lead runs the real checks.

## Quick start

Requirements: macOS, `jq`, `git`. Claude Code and/or Codex for the native
lanes; external runners need their own credentials (the installer asks once,
stores keys mode-600, never copies them silently from another tool).

```sh
git clone https://github.com/matteoscurati/delegation-kit
cd delegation-kit
./install.sh        # or --claude-only / --codex-only
./doctor.sh         # verify everything is wired (add --ping for a live round-trip)
```

Or, Claude-only, via the plugin marketplace:

```
/plugin marketplace add matteoscurati/delegation-kit
/plugin install delegation-kit
```

(See also [npm package](#npm-package) below for an `npx` installer.)

## How delegation works

Delegation is **user-directed and per dispatch**. The flow is always the same:

```sh
# 1. Discover — read-only, never dispatches
delegation-route resolve --lane builder --json
#    → {"choices": [...], "requires_user_direction": true, "automatic_dispatch": false}

# 2. You choose — name the profile, or authorize the lead to pick from .choices
#    "Use terra-builder for <task>."
#    "Delegate <task> to a builder; show me the profiles first."

# 3. Validate — still read-only
delegation-route resolve --lane builder --selected-profile terra-builder --json

# 4. Dispatch — only now
codex exec --ephemeral -p terra-builder "<bounded, user-authorized task>" </dev/null
```

Prompt patterns that authorize a dispatch:

- `Use terra-builder for <task>.` — names the exact profile.
- `Delegate <task> to a builder; show me the available profiles before dispatch.`
- `You may choose one builder from the displayed choices for <task>.`

Task complexity, an installed skill, or a previous authorization is **not**
authorization. Retries and cross-family reviews are dispatches too: each needs
its own approval unless your request named that finite set.

## What's in the box

**Claude Code** (`~/.claude/`)

| piece | where | what |
|---|---|---|
| 6 subagent profiles | `agents/*.md` | `sonnet-clerk` · `sonnet-scout` · `sonnet-reviewer` (very small, non-builder) · `opus-builder` (`max`, editing) · `opus-reviewer` (`max`, read-only cross-family) · `fable-judge` |
| routing skill | `skills/model-routing/` | the decision procedure, loaded only on an explicit delegation request |
| orchestrate skill | `skills/orchestrate/` | the fan-out loop; the user-approved finite dispatch list is the budget |
| external executor skills | `skills/{glm,gemini,kimi,grok,qwen,deepseek}-executor/` | dispatch only gate-allowed lanes; provisional use is explicit |
| user-direction guard | guarded block in `CLAUDE.md` | the always-loaded rule: no standing permission to delegate |

**Codex** (`~/.codex/`)

| piece | where | what |
|---|---|---|
| 5 native profiles | `agents/*.toml` | `luna-clerk` · `terra-builder` (`max`, editing) · `terra-reviewer` (`max`, read-only cross-family) · `astra-reviewer` (`high`, read-only cross-family) · `astra-judge` (`high`, explicit judgement) |
| 5 ephemeral profiles | `*.config.toml` | for `codex exec --ephemeral -p <name>` |
| user-direction guard | guarded block in `AGENTS.md` | same rule, Codex side |

**CLI commands** (`~/.local/bin/`, shared by both hosts)

| command | role |
|---|---|
| `delegation-route` | the read-only router: `check` · `lane` · `profile` · `resolve [--selected-profile]` · `table`. Never dispatches. |
| `delegation-evidence` / `delegation-epoch` | dated benchmark snapshot and the Epoch AI ZIP importer (advisory; never edits a gate) |
| `delegation-schema` | deterministic Claude/Codex structured-output transport compiler |
| `delegation-{glm,gemini,kimi,grok,qwen,deepseek}` | the six gated external runners — each re-validates the full decision graph before every check/run |
| `delegation-executor-contract` | validates the shared executor contract (permission classes, model identity, usage accounting, exit codes) |
| `delegation-patch-verify` | read-only safety verification for text-patch lane output; never applies a patch |

Versioned gates live under `~/.local/share/delegation-kit/`; credentials are
stored mode-600 and are never imported silently from another tool.

## The lanes

| lane | who | notes |
|---|---|---|
| **clerk / scout** | Sonnet, Luna, GLM-5.3-Flash | very small bounded extraction, repo mapping, read-only support |
| **builder / frontend-builder** | Opus 5, GPT-5.6 Terra (both `max`); provisional: Kimi K3, Grok 4.6, Qwen, DeepSeek, GLM | bounded implementation; text-only lanes return a patch the lead applies |
| **routine-review / material-review / security** | Opus, Terra, Sol, Sonnet (tiny work only) | mandatory cross-family review — never the producer's family |
| **judgement / super-judgement** | Fable `max`, Sol `max` | manual-qualified, explicit-only, two-touch |

A lane becomes operational only through a versioned gate backed by exact
benchmark evidence plus a local runtime/scope smoke. Provisional lanes also
require your explicit decision plus the runner's `--allow-provisional` flag.
Blocked is blocked: no silent substitution, no runtime-availability shortcuts.

## Governance model

- **User-directed activation** — `config/routing-gates.json` carries an
  `activation_policy` (`mode: user-directed`, `scope: per-dispatch`,
  `automatic_dispatch: false`). Every operational selection is
  `explicit-only`; there are no default or fallback routes.
- **Evidence-backed qualification** — each lane's status (`qualified`,
  `provisional`, `manual-qualified`, `candidate`, `disabled`) is bound to dated
  benchmark rows plus local smokes. Frozen evaluation artifacts are historical
  records and are never rewritten.
- **Fail-closed runners** — every external runner validates the central gate
  against its own executable gate before every check/run and refuses drift.
- **Common executor contract** — one vocabulary across the six families:
  permission classes (`read-only` / `text-patch` / `worktree-edit`), model
  identity (requested vs effective vs billing), usage accounting, and the
  64/69/70/75/78/130 exit codes. The contract describes and validates; each
  runner remains the sole enforcement authority.
- **Read-only patch trust boundary** — text-patch lane output passes through
  `delegation-patch-verify` (confinement, strip-level certainty, read-only
  attestation). The lead, and only the lead, applies and tests.

## Current release: 0.22.0

Version 0.20.0 makes delegation **user-directed**: every dispatch must be
selected or explicitly authorized by you, enforced by the routing gates — the
selection vocabulary is now closed at `explicit-only` / `blocked`, the router
exposes `choices` and validates `--selected-profile`, and the resident
policies on both hosts carry the no-standing-permission guard. It also adds
`delegation-patch-verify`, the read-only trust boundary for text-patch lanes,
and ships `npx delegation-kit` for one-command installs. See
[`CHANGELOG.md`](./CHANGELOG.md) for details and full history.
Version 0.22.0 migrates the Codex review/judgement lanes to **GPT-6 Astra**
(`gpt-6-astra` at `high`) in a new `openai-gpt6` family, following OpenAI's
2026-09-03 launch. Version 0.21.0 migrated the judgement lane to Fable 5.1;
version 0.20.1 fixed the npm wrapper's `--skip-doctor` flag.

## Documentation

| doc | contents |
|---|---|
| [`CHANGELOG.md`](./CHANGELOG.md) | every release, newest first |
| [`docs/compatibility.md`](./docs/compatibility.md) | supported-agent matrix, verified snapshots, host-specific rules |
| [`docs/external-executors.md`](./docs/external-executors.md) | the external-executor contract and the patch verifier |
| [`model-routing.md`](./model-routing.md) | the evidence-backed routing policy and current snapshot |
| [`evaluation/README.md`](./evaluation/README.md) | evidence methodology and qualification workflow |
| [`ADAPTING.md`](./ADAPTING.md) | map the roles to *your* models and plans |

## Testing

```sh
./run-tests.sh          # every regression suite, in parallel (~1 min)
./doctor.sh --ping      # live bridge round-trip (costs a few tokens)
git diff --check
```

The suite covers routing-gate drift (65 checks), the executor contract (267),
the patch verifier (113), install/doctor integrity, and one diagnostics suite
per runner. CI runs shellcheck, version consistency, and the full suite on
every pull request.

## Cross-provider bridge

- **Claude → Codex**: prefer the [`codex@openai-codex`
  plugin](https://github.com/openai/codex-plugin-cc) for interactive work
  (`codex:codex-rescue` agent; user-run `/codex:review`, `/codex:transfer`);
  `codex exec --ephemeral -p <profile>` for programmatic dispatch.
- **Codex → Claude**: headless `claude -p` with pinned `--model`/`--effort`,
  through the builder, reviewer, or very-small non-builder profiles — hardened
  procedure in [`codex/AGENTS.md`](./codex/AGENTS.md). CLI-only; no reverse plugin.

Both directions pass context through the **shared working tree**, not the
conversation. The only history-preserving handoff is `/codex:transfer`
(user-run).

## npm package

Install the kit without cloning manually:

```sh
npx delegation-kit           # runs the universal installer interactively
npx delegation-kit --claude-only
npx delegation-kit --codex-only
```

The npm package is a thin wrapper over this repository's installer: `npx`
clones the checked-out release, verifies its integrity, and runs
`./install.sh` with your flags. Nothing is copied into `node_modules`; all
installed artifacts are the same files, links, and guarded blocks described
above, and `./uninstall.sh` (also available as `npx delegation-kit --uninstall`)
removes them.

## Adapt & license

Different models or plans? [`ADAPTING.md`](./ADAPTING.md) maps every role to a
model/effort slot and shows how to re-derive the numbers. MIT — see
[`LICENSE`](./LICENSE).
