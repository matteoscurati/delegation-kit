# delegation-kit

Teach **Claude Code** and **Codex** how and when to delegate coding work across
models — small non-builder lanes handle bounded support work, max-effort builder
lanes implement, and a sufficiently capable model from another family reviews
every delegated result — with a symmetric bridge so each can reach the other.

It ships as a **reference implementation**: the author's concrete models
(`sonnet`/`opus`/`fable` on Claude; `luna`/`terra`/`sol` on Codex), a dated
external-evidence snapshot, and fail-closed local gates. Swap the models for your own tiers with
[`ADAPTING.md`](./ADAPTING.md) — the *structure* is the transferable part.

## Current release: 0.18.0

Version 0.18.0 adds safe parallel Grok Build dispatch through an explicit
shared-OAuth generation, while retaining serialized OAuth as the default and
keeping every Grok lane provisional/explicit-only. Serialized and shared runs
both persist refresh rotation atomically; external login wins conflicts and
malformed state fails closed. The exact two-worker live smoke returned `PONG`
twice without worktree edits and left ambient/shared credential state aligned.

Version 0.17.0 reserves Sonnet and Luna for very small,
non-builder tasks. Opus 5 and GPT-5.6 Terra are high-level builders and
reviewers, both pinned to `max`; editing and read-only review use separate
profiles. Every delegated result must be reviewed by another model family, with
producer identity supplied to the fail-closed router. Explicit judgement remains
with Fable and Sol both at `max`. These owner decisions do not
retroactively qualify a model or rewrite earlier release evidence.

Version 0.16.0 adds a guarded official-API bridge for DeepSeek V4 Pro at
`max`. Its prompt-only `builder` lane is provisional and explicit-only after
one exact live smoke; it has no tools or worktree access, and every other lane
remains blocked. The release also re-pins the fail-closed Antigravity bridge to
Gemini 3.7 Flash without inheriting Gemini 3.6 qualification: the current
runtime cannot attest the exact 3.7 inventory and OAuth session, so Gemini has
no operational lane. In both cases, runtime availability remains distinct from
qualification.

Version 0.15.0 makes `glm-5.3` / `claude-zai` / `max` the sole operational
GLM tuple and makes GPT-5.6 Sol at `high` Codex's default material reviewer.
The final max-only GLM runner passed all nine no-retry requalification attempts
with every builder checker green; clerk and scout remain qualified explicit-only
and builder remains provisional explicit-only. The preregistered comparison
still records `high` as its efficiency winner: `max` is the owner's later
operational choice, not a rewritten benchmark result. `sol-reviewer` is a
role-scoped provisional default because no exact review precision/recall row
exists, while `sol-judge`, judgement, and `super-judgement` remain manual and
explicit-only.

Version 0.14.0 replaces the active Grok 4.5 route with Grok 4.6 at the same
provisional `builder` and `frontend-builder` lanes and pinned `high` effort. The
runner now keeps requested model, effective content model, and every
`modelUsage` participant distinct: known substitutions fail closed, while a
strict evaluation without separately surfaced content identity is `VOID`.
Current CursorBench, FrontierCode, APEX, and preliminary WebDev results are
recorded as contextual evidence only because none matches the hardened Grok
Build tuple. The installer removes the stale 4.5 gate during upgrades, retains
a compatible archived CLI only after the complete 4.6 gate graph is installed,
and the authenticated installed runtime returned `PONG` on Grok Build 0.2.114.

Version 0.13.2 settles two loose ends from the 0.13.x pair. The Agent Arena row
for Gemini 3.6 Flash was recorded from an automated capture that read every
effect as positive, because the board encodes direction as a coloured triangle
rather than a character; read visually, the model is negative on every effect,
including **-6.70% steerability** — the scout lane's own supporting metric. And
`skills/qwen-executor` now tells the brief to demand `a/` and `b/` diff header
prefixes, because without them a correct patch fails a bare `git apply` and
reads like a wrong answer. No routing decision moves.

Version 0.13.1 makes the Gemini lane reachable over SSH. `agy` abandons the
macOS Keychain for a file-based token store whenever it sees the SSH session
markers, while `delegation-gemini` supplies credentials the other way — by
symlinking the user's Keychain into the isolated home — so from an SSH session a
signed-in user was reported as signed out and the lane failed closed with exit
69 no matter how many times they logged in. The runner now clears those markers
for every `agy` call that can touch credentials; on a local session they are
unset already, so nothing changes there. No routing decision moves.

Version 0.13.0 re-pins the three Codex executor lanes above the effort cliff and
orders the external builders by evidence. A probe of the provider showed the
reasoning-effort enum is per model and reaches `max` on the GPT-5.6 family, so
`luna-clerk` moves to `max`, `terra-scout` to `medium`, and `terra-builder` to
`max` — each landing on an effort that already has an exact benchmark row, and
each fixing a lane that was pinned where the model collapses (`gpt-5.6-luna` at
`low` scores 15% on the clerk required metric). In that release, Kimi K3 and
the then-current Grok 4.5 became
`preferred-explicit` on `builder`, the only two carrying both builder required
metrics on an exact production tuple; `preferred-explicit` now actually orders
first in `delegation-route resolve`, which it previously did not. The evidence
snapshot gains 65 dated rows, and `delegation-evidence check` no longer swallows
a schema or reference failure.

Version 0.12.0 adds the opt-in `--oauth shared` mode to `delegation-kimi`,
letting several agents dispatch Kimi lanes in parallel by sharing one
runner-owned OAuth generation that the vendor CLI's own cross-process lock
coordinates — verified live against the real CLI, including a mid-run token
rotation — while the serialized default stays byte-for-byte unchanged. It also
teaches `delegation-glm` to distinguish retryable 429s (`rate_limited`) from
exhausted quota windows (`quota_exhausted`, with the reset epoch in
`next_flush_time`). No routing gate changes.

Version 0.11.0 makes the repository verify itself. Until now nothing checked a
pull request and nothing checked a release except the person cutting it. CI now
runs shellcheck, a version-surface check, and the full regression suite on every
pull request; `install.sh` records what it installed so `doctor.sh` can report a
stale install; and `run-tests.sh` runs the suites in parallel on one machine.
Routing decisions are unchanged from 0.10.0, which repinned the Qwen bridge to
`qwen3.8-max` and promoted its text-only `builder` lane to
provisional/explicit-only behind `--allow-provisional`. See
[`docs/compatibility.md`](./docs/compatibility.md) and
[`CHANGELOG.md`](./CHANGELOG.md).

## What it installs

**Claude Code** (`~/.claude/`)
| piece | where | what |
|---|---|---|
| 6 subagent profiles | `agents/*.md` | `sonnet-clerk` · `sonnet-scout` · `sonnet-reviewer` (very small, non-builder) · `opus-builder` (`max`, editing) · `opus-reviewer` (`max`, read-only cross-family) · `fable-judge` |
| routing skill | `skills/model-routing/` | surfaces the decision procedure when you delegate |
| orchestrate skill | `skills/orchestrate/` | the fan-out loop — plan → delegate to workers → verify → advisor judges plan + ship |
| optional GLM skill | `skills/glm-executor/` | dispatches only gate-allowed GLM lanes; provisional use is explicit |
| optional Gemini skill | `skills/gemini-executor/` | Antigravity-backed Gemini 3.7 Flash; staged and fail-closed pending exact runtime proof |
| optional Kimi skill | `skills/kimi-executor/` | exposes only exact gate-allowed Kimi lane/backend/effort tuples |
| provisional Grok skill | `skills/grok-executor/` | Grok Build-backed builder and frontend-builder at pinned high effort |
| provisional Qwen skill | `skills/qwen-executor/` | Token Plan Qwen3.8-Max builder; text-only, provisional use is explicit |
| provisional DeepSeek skill | `skills/deepseek-executor/` | official-API DeepSeek V4 Pro/max builder; text-only, provisional use is explicit |
| lane discipline | `@import` in `CLAUDE.md` | always-loaded policy ([`claude/CLAUDE.delegation.md`](./claude/CLAUDE.delegation.md)) |

**Codex** (`~/.codex/`)
| piece | where | what |
|---|---|---|
| 5 native profiles | `agents/*.toml` | `luna-clerk` · `terra-builder` (`max`, editing) · `terra-reviewer` (`max`, read-only cross-family) · `sol-reviewer` (`high`) · `sol-judge` (`max`, explicit judgement) |
| 5 ephemeral profiles | `*.config.toml` | for `codex exec --ephemeral -p <name>` |
| collaboration policy | appended to `AGENTS.md` | usage-aware routing **+ a Codex→Claude bridge** |
| optional GLM skill | `skills/glm-executor/` | staged fail-closed GLM-5.3-Flash/max executor path |
| optional Gemini skill | `skills/gemini-executor/` | same staged Gemini 3.7 Flash executor path |
| optional Kimi skill | `skills/kimi-executor/` | same fail-closed provisional Kimi K3 path |
| provisional Grok skill | `skills/grok-executor/` | same fail-closed Grok 4.6 builder path |
| provisional Qwen skill | `skills/qwen-executor/` | same fail-closed Qwen3.8-Max builder path |
| provisional DeepSeek skill | `skills/deepseek-executor/` | same fail-closed DeepSeek V4 Pro/max builder path |
| config snippet | printed for manual merge | `[agents]` fan-out caps + lead defaults |

The universal installer also adds `delegation-schema`, `delegation-glm`,
`delegation-gemini`, `delegation-kimi`, `delegation-deepseek`,
`delegation-grok`, `delegation-qwen`,
`delegation-evidence`, the ZIP-only `delegation-epoch` importer, and the read-only
central router `delegation-route` under
`~/.local/bin`, with versioned gates under `~/.local/share/delegation-kit/`.
GLM-5.3-Flash/max is staged as the sole GLM candidate. `clerk`, `scout`, and
`builder` are blocked until the exact Claude-to-Z.AI pack passes; reviewer is
disabled and policy annotation remains a separate blocked evaluation-only
candidate. Historical GLM-5.2 and GLM-5.3 receipts do not transfer to Flash.
The runner refuses every blocked lane and every effort the gate did not pin,
and also refuses execution unless at least one of Claude Code or Codex is
installed; it is an agent option, not a standalone GLM client. The installer asks
for the Z.AI API key and stores it in `~/.local/share/delegation-kit/config/zai.env`
(mode 600); an explicit `ZAI_API_KEY` in the environment overrides it.
Failed GLM dispatches write a sanitized `<output>.error.json` that distinguishes
runtime exit, malformed streams, model mismatch, missing/empty results, auth, and
rate limits — including `rate_limited` (retry with backoff) versus
`quota_exhausted`, which carries the window-reset epoch in `next_flush_time`.
Raw events and stderr are deleted unless an existing private
directory is explicitly supplied with `--debug-dir`; those artifacts are
sensitive and must not be committed.
The Claude Code capability probe times out fail-closed after ten seconds. A
diagnostic may point `DELEGATION_GLM_CLAUDE_BIN` at a separately verified native
binary; that path is runtime provenance, not permission to bypass the gate.

Structured-output schemas have two explicit layers: the checked-in normative
schema and a provider transport schema derived without editing the source.
`delegation-schema` removes unsupported dialect declarations for Claude and,
for Codex, infers only unambiguous literal types while enforcing strict object
requirements, the documented
[Structured Outputs subset](https://developers.openai.com/api/docs/guides/structured-outputs#supported-schemas),
and size/depth limits. It parses
strict JSON, preserves property order and literal data, and fails with exit 65
when a safe derivation is impossible. The Codex contract targets standard
Codex models; fine-tuned-model restrictions are outside this command.

```sh
delegation-schema check --provider claude --schema contract.json
delegation-schema compile --provider codex --schema contract.json >transport.json
delegation-schema verify --provider codex --schema contract.json \
  --transport transport.json
```

The GLM qualification runner uses the Claude compilation in memory before
dispatch. Historical schemas and frozen evaluation protocols are never
rewritten; a manifest still binds the normative file and the committed runner
source binds the compiler implementation.

The historical GLM-5.3 qualification used the public
[`glm-5.3-lane-comparison-v1` contract](./evaluation/glm-5.3-lane-comparison-v1/README.md).
Each attempt is pinned to `glm-5.3` / `claude-zai` / `high|max` and to hashes of the
prompt, contract, output schema, runner, runner commit, and fixture commit. The
private manifest must be allowlisted in private copies of both gates; raw packs
and results stay under ignored `eval/`. Three no-retry attempts per effort and
lane reuse the frozen GLM-5.2 fixtures as a direct baseline. The 2026-08-14
comparison selected `high`: both efforts scored 1.0 in all nine attempts and
passed every builder checker, while high used less elapsed time and
provider-reported cost. Clerk
and scout qualified explicit-only and builder moved only to provisional. A timeout,
missing output, identity mismatch, permission violation, or checker failure is
`VOID`, and the runner never promotes a route. Only a separately reviewed
aggregate that passes the preregistered thresholds may justify a public gate
change. The owner subsequently chose max as the sole operational effort; a
separate exact-runner max requalification passed 9/9 with every builder checker
green. This owner preference does not rewrite high as the comparison winner.

The replacement candidate uses the
[`glm-5.3-flash-lane-qualification-v1` contract](./evaluation/glm-5.3-flash-lane-qualification-v1/README.md).
It reuses the deterministic packs but requires fresh no-retry attempts at the
exact `glm-5.3-flash` / `claude-zai` / `max` tuple before any lane opens.

Gemini 3.7 Flash is staged through the installed Antigravity CLI (`agy`). Scout
at `medium` and builder/frontend-builder at `high` are blocked candidates;
reviewer and judgement are disabled. The current local session cannot attest
exact model inventory or OAuth, so no Gemini 3.6 route is inherited. The runner
never substitutes another Gemini variant or treats launch evidence as
qualification. This bridge is prompt-only:
the lead must embed the relevant tracked-file excerpts in the brief, because
headless filesystem and other tool permissions are never auto-approved. `agy`
starts with an empty temporary workspace and home; only macOS Keychain access
is carried across for OAuth, while all tool namespaces are explicitly denied.

DeepSeek V4 Pro is installed as a **provisional text-only builder** through the
official OpenAI-compatible API at `max`. One live exact-tuple smoke confirmed
provider identity, max-effort acceptance, and a correct deterministic patch;
that is compatibility evidence, not a held-out builder qualification. Dispatch
therefore requires an explicit decision and `--allow-provisional`:

```sh
delegation-deepseek run --lane builder --allow-provisional \
  --effort auto --backend auto --prompt-file "$brief" \
  --output "$result" --metrics "$metrics" --workdir "$repo"
```

The model sees only the supplied brief and cannot edit the worktree. The lead
applies and verifies returned patches. Every other DeepSeek lane remains
blocked, and credentials are accepted only from an explicit environment value
or the kit's private mode-600 key file; the installer never copies another
tool's key silently.

Kimi K3 is installed as a **provisional coding model**. Its gate permits explicit
`clerk`, `scout`, `builder`, and `frontend-builder` runs at `max`; senior is a
blocked candidate, reviewer/judgement remain disabled, and `policy-annotation`
is candidate/blocked for manifest-bound evaluation only. It never creates an
operational route or qualifies architecture/trade-off judgement. Provisional
runs require `--allow-provisional`; CLI
availability or a provider model listing is not enough. CLI compatibility is
determined from capabilities: `--agent-file`, `stream-json`, the exact
`kimi-code/k3` model, OAuth, a valid isolated configuration, and `max` as the
supported/effective effort are required, while the observed version is
provenance only. Update the vendor CLI explicitly with `kimi update`;
`install.sh` never changes it.

Each run receives an ephemeral agent file and duplicated `[tools]` restrictions.
`clerk` and `scout` expose only `Read`, `Glob`, `Grep`, and `TodoList`; builders
add `Write` and `Edit`, while `frontend-builder` also adds `ReadMediaFile`.
Web, MCP, skills, subagents, cron, background tasks, Plan, and Bash stay
disabled. Project `AGENTS.md` instructions remain loaded. The only executable
tool is `Grep`: `delegation-kimi pin-rg` archives a verified ripgrep binary,
its SHA-256, and the digests of non-system dependencies. Each invocation copies
those exact bytes into a separate runner-owned, sandbox-unwritable exec
directory, and `sandbox-exec` permits only Kimi,
`/usr/bin/true`, and that precise `rg`; shells, Git, arbitrary commands, and
ambient HOME reads remain denied. `install.sh` attempts the initial archive but
never replaces different bytes without an explicit `--force`.

Native invocations use an isolated `KIMI_CODE_HOME`, an allowlisted environment,
and an atomic OAuth lock. By default the lock spans the whole dispatch, so
concurrent runs serialize; `--oauth shared` instead keeps OAuth state in a
runner-owned generation under `$DELEGATION_DATA_HOME/kimi-shared-oauth`, lets
concurrent children coordinate refreshes through the vendor CLI's own oauth
lock, and holds the kit lock only to seed the generation and publish it back —
enabling parallel Kimi workers up to the account's own concurrency and quota.
After the child rotates a token, the parent validates
and atomically syncs only `credentials/kimi-code.json` back to the user-managed
Kimi store. `INT`/`TERM` stop the child, perform the final sync, release the lock,
and return 130. Do not run an external `kimi login` concurrently; a conflicting
credential change is a temporary failure that wins over any in-flight
delegation state. Operational runs are capped at 900
seconds and emit content-free heartbeats every 30 seconds; evaluation runs keep
their immutable manifest timeout, up to 1200 seconds.

On failure, `<output>.error.json` is canonical. `<output>.stderr` remains a
sanitized one-line receipt; detailed stderr/events are retained only under an
explicit existing private `--debug-dir`, with credential-like fields redacted.
The debug directory must stay outside every worktree. Exit 69 covers runtime, login,
entitlement, or quota; 70 covers sandbox, output, or unclassified dispatch; 75
covers overload, 5xx, timeout, or temporary OAuth conflict; 78 is an
unauthorized lane; and 130 is caller cancellation. This follows Kimi Code's
[error categories](https://www.kimi.com/code/docs/en/kimi-code/error-reference.html)
without turning provider availability into quality evidence.

```sh
kimi update
delegation-kimi pin-rg --from "$(command -v rg)"
delegation-kimi check --json
delegation-kimi run --lane scout --allow-provisional \
  --effort auto --backend auto --prompt-file "$brief" \
  --output "$result" --metrics "$metrics" --workdir "$repo"
```

Grok 4.6 is installed as a **provisional builder** through Grok Build CLI.
`builder` and `frontend-builder` are available only at effort `high`, after an
explicit decision and `--allow-provisional`. The runner pins the model, extracts
only the public `text` field from JSON output, capability-probes the resolved
CLI, and caps runs at 40 turns and 15 minutes. An ephemeral HOME disables
memory, subagents, web, plugins, MCP, compatibility imports, and automatic updates. The custom
`delegation-kit` sandbox must attest OS enforcement before output is published;
the permission mode is `dontAsk`, with only file edits explicitly allowed; the
terminal tool is not exposed.
OAuth is serialized by default and any refreshed credential is published back
atomically. `--oauth shared` instead keeps one runner-owned Grok generation
under `$DELEGATION_DATA_HOME/grok-shared-oauth`: concurrent workers use the
same `GROK_HOME`, the vendor auth lock coordinates refresh, and the kit lock is
held only to adopt the generation and publish it back. External `grok login`
always wins an optimistic-concurrency conflict. Evaluations remain serialized.
The lead remains responsible for running tests and every command after review.
Failures expose sanitized metadata by default, with raw debug artifacts only
through explicit `--debug-dir`. A separate `policy-annotation` candidate is
available only to an allowlisted evaluation manifest at the same highest
supported effort; it removes editing tools, requires the read-only sandbox, and
never becomes an operational route merely by running.

Because the vendor CLI auto-updates and prunes its own download cache,
`delegation-grok pin` can archive the currently compatible build in
`$DATA_HOME/grok-cli/current/` with a recorded SHA-256. The runner resolves
`DELEGATION_GROK_BIN`, then that private archive, then `grok` on PATH. Any
version is accepted when it exposes the required interface, authenticated
`grok-4.6` inventory, isolation state, structured output, and sandbox
attestation; the observed version is provenance only. `install.sh` archives the
compatible build automatically when available. A digest mismatch fails closed
rather than running changed bytes.

```sh
delegation-grok pin
delegation-grok check --json
delegation-grok run --lane builder --allow-provisional \
  --oauth shared \
  --effort auto --backend auto --prompt-file "$brief" \
  --output "$result" --metrics "$metrics" --workdir "$repo"
```

### Concurrent credential modes

Parallelism is provider-local; the kit never uses one global credential lock.

| Transport | Credential mode | Concurrent dispatch |
|---|---|---|
| Grok Build | rotating OAuth | explicit `--oauth shared`; serialized by default |
| Kimi Code | rotating OAuth | explicit `--oauth shared`; serialized by default |
| Gemini Antigravity | shared macOS Keychain | blocked until exact concurrent OAuth verification |
| GLM / Qwen / DeepSeek API | bearer API key | parallel; provider quotas still apply |
| Native Claude / Codex profiles | vendor-managed host credential store | governed by the vendor CLI and native agent fan-out limits |

Shared OAuth means shared **credential state**, not shared agent state: prompts,
workspaces, output, permissions, and runtime HOME remain per invocation. A
provider is never moved from subscription OAuth to an API endpoint merely to
gain concurrency, because that would change the measured harness and billing
identity.

Qwen3.8-Max is pinned to the Qwen Cloud Token Plan OpenAI-compatible endpoint at
`xhigh`. Its dedicated `sk-sp-` key is stored separately and never imported
silently from another tool. Only `builder` is promoted, as
**provisional / explicit-only** on an owner decision — no DeepSWE or
Terminal-Bench v2 row exists for this model, so both builder required metrics
are unmet and dispatch needs an explicit `--allow-provisional`:

```sh
delegation-qwen run --lane builder --allow-provisional \
  --effort auto --backend auto --prompt-file "$brief" \
  --output "$result" --metrics "$metrics" --workdir "$repo"
```

The transport is chat-completions only, so this lane **cannot edit a worktree**:
it returns a patch the lead applies and verifies. Every other lane stays a
blocked candidate — runtime availability is not qualification. `--evaluation` is
reserved for a manifest-bound controlled local qualification run at the exact
pinned tuple, cannot be combined with `--allow-provisional`, and never promotes
or mutates a gate.

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
It is the dispatch authority: GLM, Gemini, Kimi, Grok, Qwen, and DeepSeek validate it against their complete
backend gates before every check/run, and refuse drift. Exact and contextual
benchmark references are stored separately, and the generated table exposes
local sample size/confidence instead of treating legacy scores as comparable.
Review resolution is producer-aware and fail-closed:
`delegation-route resolve --lane material-review --producer-profile <profile>`
removes every reviewer from the producer's model family. Sol/high is the
provisional default when it remains cross-family; Opus/Terra max are read-only
fallback reviewers, and runtime availability must be verified before dispatch.
No exact review precision/recall row exists, so these routes remain provisional.
Fable `max` and Sol `max` are explicit, manually qualified judgement profiles.
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
cross-provider bridge available when using a single-host install: `--claude-only`
or `--codex-only` can leave no installed cross-family reviewer for work produced
by that host, in which case the mandatory review must stop rather than fall back
to self-review. Keep the checkout where it is — Claude's `@import` points
at it, so `git pull` updates the policy live. Remove with `./uninstall.sh`.

Then verify the bridge and evidence snapshot are actually **wired** (not just
written) with `./doctor.sh` —
it checks both CLIs, auth, the installed profiles *and* the always-loaded policy
blocks, and the Codex sandbox/network posture. `./doctor.sh --ping` also does a
live round-trip in both directions; `--ping-glm`, `--ping-kimi`, and
`--ping-grok` separately exercise their gated runtimes. The failure it catches
is silent: profiles present but a policy block missing means the bridge never
fires. The complete supported-agent matrix, semantic-smoke rules, and host
isolation differences are documented in
[`docs/compatibility.md`](./docs/compatibility.md).

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
and provisional `qwen-executor` skills. It does not install any external model
runner/gate, register the
`CLAUDE.md` policy prose, or install the Codex side — run `./install.sh` for those.

## How it works

- **Lead** owns the work and enters the **judgement** model only in short bursts
  (a plan up front, a verdict at the end) — thinking, not typing.
- **Small non-builder lanes** use Sonnet or Luna only for tightly bounded clerk,
  scout, and routine-review work.
- **Builder** uses Opus 5 or GPT-5.6 Terra, both pinned to `max`.
- **Reviewer** can use Opus/Terra at `max`, Sol at `high`, or Sonnet for tiny
  routine work—but never from the producer's family.
- **Route review by content and producer family**; verify reviewer availability;
  escalate small lane → builder/reviewer → judgement, never retry an unsuitable
  worker twice.
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
- **Codex → Claude**: call Opus 5 at `max` through its editing builder or
  read-only cross-family reviewer profile, or Sonnet only for very small
  non-builder work, following the hardened CLI procedure in
  [`codex/AGENTS.md`](./codex/AGENTS.md). CLI-only — no reverse plugin exists.

Both directions pass context through the **shared working tree**, not the
conversation: run the child in the repo root and reference files by path. The only
history-preserving handoff is `/codex:transfer` (Claude → Codex, a user-run command).

## Adapt & license

Different models or plans? [`ADAPTING.md`](./ADAPTING.md) maps every role to a
model/effort slot and shows how to re-derive the numbers. MIT — see
[`LICENSE`](./LICENSE).
