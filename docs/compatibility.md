# Supported-agent compatibility

This page records functional compatibility separately from routing
qualification. A successful smoke proves that the installed interface can run
the exact model, effort, tools, and lane contract tested here. It does not
promote a provisional or candidate lane.

## Verified snapshot

The 0.18.0 release-candidate gate was verified on **2026-08-27** on macOS
26.5.1 with Codex CLI `0.149.1` and Claude Code `2.1.246`. It passed all 12
regression suites in 52 seconds, including 59 central routing checks, plus
ShellCheck, evidence validation, and the eight-check version gate. The exact
Grok shared-OAuth smoke described below ran two workers concurrently and left
the ambient credential aligned. The candidate was then installed from the
reviewed checkout: changed runner/gates/skills matched source byte-for-byte,
`doctor.sh --ping --ping-grok` reported `57 OK, 0 WARN, 0 FAIL`, Grok returned
`PONG`, and both Claude bridge directions remained reachable. A fresh reinstall
from the merged/tagged commit remains a post-release requirement. Numeric
vendor versions are provenance only wherever the runner uses capability probing.

The role-oriented semantic matrix below was last exercised in full on
**2026-08-05**, in one pass, against a single disposable fixture carrying a
real off-by-one (`rolling_max` iterating `range(len(values) - size)`), a
five-row CSV to aggregate, and an untyped CSS component. Read-only lanes had to
describe or diagnose it; builder lanes had to turn the red acceptance check
green in their own worktree copy. The 0.17.0 release gate did not claim to
re-run unchanged semantic rows: it refreshed the install, routing, regression,
and live bridge observations reported below.

The earlier Gemini 3.6 Flash smoke is historical evidence for a different exact
model tuple. Gemini 3.7 Flash does not inherit it: the current `agy` runtime
cannot attest the new model inventory and OAuth session, so the new bridge
remains staged and fail-closed.

## 0.17.0 native routing change

The 0.17.0 release retires `sonnet-builder` and `terra-scout`. Sonnet/Luna are
restricted to very small non-builder work. Opus and Terra now each have a
max-effort editing builder and a separate read-only reviewer profile. The old
`opus-reviewer/high` semantics are replaced by `opus-reviewer/max` with a
mandatory cross-family constraint; `terra-reviewer/max` is new. The historical
2026-08-05 semantic rows below remain evidence for the profiles that existed at
that time; they do not qualify the new builder or reviewer profiles.

The central router now requires producer identity for routine, material, and
security review, then excludes every reviewer in that model family. Static
availability is not inferred: the caller must verify runtime/auth for the
remaining sufficiently capable candidates and stop if none is reachable.
Single-host installs can therefore lack a usable reviewer for their own model
family; this is a blocker, not permission for producer self-review. The Opus
security route also preserves the declared possibility that Anthropic substitutes
Opus 4.8 on classifier-flagged cyber requests, so exact Opus 5 identity must be
verified separately when required.
The new `opus-reviewer/max` and `terra-reviewer/max` profiles have structural,
installation, sandbox, and routing proof in the release candidate; no new held-out
semantic reviewer pack was run, so both review routes remain provisional.
The read-only `sol-judge` profile is now pinned to `max` on an explicit owner
effort decision while remaining manually qualified and explicit-only. Its exact
max coding row is contextual rather than judgement evidence.
The Fable judge likewise moves from `xhigh` to `max`; an authenticated 2026-08-18
runtime probe accepted the exact request and surfaced `canonicalModel:
claude-fable-5`, but did not test judgement quality.

On 2026-08-17 the installed named `opus-builder` profile passed a disposable
one-line scoped-edit smoke at the explicitly requested `claude-opus-5` / `max`
tuple. It touched only the assigned tracked file, passed `git diff --check`, and
the result's usage record surfaced `canonicalModel: claude-opus-5`. This is one
low-confidence compatibility/scope observation, not a held-out repeated builder
qualification, so the lane remains provisional. The 0.17.0 release candidate
passed all 12 regression suites in 52 seconds, including 59 central routing
checks. Its post-install doctor result was `56 OK, 0 WARN, 0 FAIL` with
authenticated Claude-to-Codex and Claude endpoint round-trip pings; the
unavailable optional Gemini and DeepSeek runtimes remained informational and
fail-closed.

## Historical semantic matrix

| Surface | Profiles or lanes | Result |
|---|---|---|
| Claude Code named agents | `sonnet-clerk`, `sonnet-scout`, `sonnet-builder`, `sonnet-reviewer`, `opus-reviewer`, `fable-judge` | All six role-appropriate. Clerk aggregated the CSV correctly; scout mapped the module and spotted the contract mismatch; `sonnet-reviewer` named the off-by-one precisely; `opus-reviewer` named it *and* separately raised the edge cases the check leaves uncovered (`size == len(values)`, `size <= 0`, empty input) plus the unspecified README contract — the differentiation the senior lane exists for; `fable-judge` returned a verdict with its rejected alternative and accepted risk. Read-only roles left the fixture clean. |
| Codex ephemeral profiles | `luna-clerk`, `terra-scout`, `terra-builder`, `sol-reviewer`, `sol-judge` | All five role-appropriate at their pinned efforts, after reinstalling so the installed bytes carried the 0.13.0 re-pin. `luna-clerk` at `max` aggregated correctly; `terra-scout` at `medium` mapped the module and flagged the conflict; `sol-reviewer` at `high` named the off-by-one; `sol-judge` at `high` returned the right verdict with reasoning; `terra-builder` at `max` turned the check green with a one-line diff touching **only** `src/window.py`. The four read-only profiles left the fixture clean. |
| Codex native profiles | the same five roles under `~/.codex/agents/` | Model, effort, sandbox, role declarations, and installed bytes match the shipped definitions, with `luna-clerk` at `max`, `terra-scout` at `medium`, and `terra-builder` at `max` in both the agent and the ephemeral-profile copies. |
| GLM-5.3/max | `clerk`, `scout`, `builder` | The exact high/max comparison ran serially with three no-retry attempts per lane on one frozen runner. Both efforts scored 1.0 in all nine attempts and every builder checker passed. The owner subsequently selected max as the sole operational effort. Clerk and scout are qualified explicit-only and builder is provisional explicit-only; 5.2 and 5.3/high remain solely as frozen historical receipts and have no gate or profile. |
| GLM-5.3-Flash/max | `clerk`, `scout`, `builder` | The exact v4 pack passed 9/9 no-retry attempts at score 1.0, all 204 assistant events carried the exact Flash identity, every terminal `modelUsage` had the sole canonical first-party Flash participant, and every builder checker passed. Clerk/scout are qualified explicit-only; builder is provisional explicit-only. V1-v3 remain terminal and are not relabelled. |
| Gemini 3.7 Flash | none (staged candidates) | The bridge is re-pinned to the new model, but the current local Antigravity session cannot attest exact inventory or OAuth. The previous 3.6 scout smoke is historical and does not transfer. Scout/medium and editing/high stay candidate/blocked; the runner remains prompt-only with an isolated workspace/home and explicit tool denials. |
| Kimi K3 | `clerk`, `scout`, `builder`, `frontend-builder` | All four passed at native `max`. Clerk aggregated correctly; scout mapped the module and located the off-by-one by line; builder turned the check green confined to `src/window.py`; frontend-builder made the CSS component theme-aware through `prefers-color-scheme`, editing only `style.css`. The capability, sandbox, pin/tamper, signal, timeout, OAuth-finalization, and diagnostics regressions pass, including the shared-OAuth concurrency cases, and the live two-parallel `--oauth shared` smoke passed 2026-08-04 with a real mid-run token rotation. All operational lanes remain provisional; `builder` and `frontend-builder` are `preferred-explicit` as of 0.13.0 while `clerk`/`scout` stay `explicit-only`, and every one still requires `--allow-provisional`. |
| Grok 4.6 | `builder`, `frontend-builder` | Introduced at `grok-build/high` on an explicit owner replacement decision. Current public builder and WebDev rows are contextual because their harnesses differ from the installed CLI. The final 2026-08-27 exact-runner concurrency smoke launched two `--oauth shared` workers simultaneously with distinct run-owned sandbox profiles: both returned `PONG` in about five seconds, attested their own sandbox event, left separate workspaces untouched, and finished with ambient/shared credential hashes aligned. The provider did not separately expose the effective content model, so this is operational compatibility evidence rather than strict identity qualification. Both lanes remain provisional and `preferred-explicit` and require `--allow-provisional`. |
| Qwen3.8-Max | `builder` | Passed at `token-plan-openai/xhigh`. The lane is text-only, so the brief carried the file contents and the runner returned a unified diff, semantically correct on the first attempt. Left to itself the model emits `--- src/window.py` / `+++ src/window.py` without the conventional `a/`/`b/` prefixes, so a bare `git apply` — which defaults to `-p1` and strips one component — looks for `window.py` and fails on a patch that is actually correct; `-p0` applies it cleanly. Asking for prefixed headers in the brief fixes it at the source: re-dispatched with that instruction, the model returned `--- a/src/window.py` and the patch applied with a **bare `git apply`**, check printing `PASS`. `skills/qwen-executor` now carries that wording. The lane is provisional explicit-only and requires `--allow-provisional`; every other lane still fails closed with exit `78`. |
| DeepSeek V4 Pro | `builder` | Passed one live exact official-API patch smoke at `max`: the response identified `deepseek-v4-pro`, accepted `reasoning_effort=max`, returned valid structured output, diagnosed the deterministic off-by-one bug, and produced the expected result. The 0.16.0 release candidate was then installed byte-for-byte and its installed runner returned exact `PONG` at the same tuple. The installer intentionally did not copy a key from another tool; the release smoke supplied it only to that process. This is a text-only provisional/explicit-only owner route, not a held-out builder qualification; all other lanes remain blocked. |
| Claude↔Codex bridge | both directions | On 2026-08-17, `doctor.sh --ping` returned `PONG` for the Claude→Codex round-trip and accepted the configured model and effort at the Claude endpoint used by the Codex→Claude path. |

### 0.16.0 release-integration record

The full 0.16.0 doctor result was `46 OK, 0 WARN, 0 FAIL` with `--ping` on
2026-08-17. The candidate install's version and recorded commit matched the checkout; the
Claude→Codex round-trip returned `PONG`, and the Claude endpoint accepted the
configured model and effort. The eleven regression suites passed through
`./run-tests.sh` in 52s of wall clock — the figure moves with machine load, so
treat it as one observation rather than a bound. They include 46 central
routing checks, 15 install-marker checks, 8 version-surface checks, and 6 Epoch
ZIP checks. The routing gate specifically verifies `sol-reviewer/high` as the
provisional default for `material-review` while leaving `sol-judge` and
judgement explicit-only. Every suite except `doctor.sh --ping` also runs in CI
on each pull request; the ping stays local because it needs authenticated
Claude and Codex CLIs. The 2026-08-05 full semantic pass additionally included
a two-pass installation into empty temporary Claude/Codex homes, which produced
one guarded policy block per host and byte-identical agents, profiles, skills,
runners, and gates.

**Smoke the installed runners, not the ones in the checkout.** The key-bearing
lanes resolve their credential file relative to their own root:
`delegation-glm` reads `$ROOT/config/zai.env`, `delegation-qwen` reads
`$ROOT/config/qwen-token-plan.env`, and `delegation-deepseek` reads
`$ROOT/config/deepseek.env`. For the installed copy that is the data
home, where the installer wrote them at mode 600; for a git checkout it is
`config/`, which is gitignored and normally empty. Running `./bin/delegation-glm
check` from the checkout therefore reports `ZAI_API_KEY is unset` and looks
exactly like a missing entitlement. It is not — it is the wrong root. Export the
key, point the runner's `DELEGATION_*_KEY_FILE` at the real file, or just invoke the
installed runner, which is what a caller uses anyway.

## Host-specific boundaries

### Codex profiles

Use the shipped ephemeral profiles with:

```sh
codex exec --ephemeral -p <profile> "<self-contained prompt>" </dev/null
```

Do not add `--ignore-user-config`: Codex then ignores the selected `-p` profile
as well and can silently use the ambient base model. Treat the model, effort,
and sandbox shown in the invocation banner as part of the smoke assertion.

Ephemeral profiles intentionally do not reproduce the native agent role prose.
The caller must provide a bounded, self-contained prompt. Native agent profiles
carry their role instructions through their `developer_instructions`.

### Claude Code agents

Claude read-only roles expose Bash so they can inspect Git state and run
read-only search or test commands. Their read-only behavior is therefore role
discipline plus the parent Claude permission configuration; it is not equivalent
to Codex's OS-enforced read-only sandbox. Run them against a clean worktree and
verify `git diff` and `git status` after the task.

For headless verification outside the current repository, pass the canonical
fixture path through `--add-dir`; macOS `/var` and `/private/var` aliases can
otherwise cause an allowed temporary fixture to be treated as a different path.
Use `--output-format json` when the test must assert the actual model identity.

### External runners

Always run `check --json` immediately before dispatch. Provisional lanes require
an explicit decision and `--allow-provisional`; candidate or blocked lanes must
fail rather than fall back to another model, effort, backend, or host profile.
Semantic smoke results never mutate a routing gate.

## Reproduce the integration gates

```sh
./run-tests.sh          # every suite under tests/, in parallel
./doctor.sh --ping
git diff --check
```

For semantic verification, use disposable Git repositories and
role-appropriate prompts: deterministic extraction for clerks, flow tracing for
scouts, one bounded edit for builders, concrete bug detection for reviewers,
and a reversible architecture decision for judges. Verify exact model identity,
scope, output meaning, and worktree changes—not merely process exit.
