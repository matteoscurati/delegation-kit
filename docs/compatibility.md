# Supported-agent compatibility

This page records functional compatibility separately from routing
qualification. A successful smoke proves that the installed interface can run
the exact model, effort, tools, and lane contract tested here. It does not
promote a provisional or candidate lane.

## Verified snapshot

The matrix below was verified on macOS 26.5.1 with Codex CLI `0.146.0` and
Claude Code `2.1.220`. Numeric vendor versions are provenance only wherever the
runner uses capability probing.

Every row below was exercised on **2026-08-05**, in one pass, against a single
disposable fixture carrying a real off-by-one (`rolling_max` iterating
`range(len(values) - size)`), a five-row CSV to aggregate, and an untyped CSS
component. Read-only lanes had to describe or diagnose it; builder lanes had to
turn the red acceptance check green in their own worktree copy. Nothing here is
carried forward from an earlier snapshot.

The Gemini row was previously recorded as unverifiable on the belief that the
`agy` OAuth session had expired. It had not: the session was valid in the login
keychain the whole time, and `agy` was ignoring it because this machine drives
the kit over SSH. That is what 0.13.1 fixes, and the row is now a real passing
run rather than an absence.

| Surface | Profiles or lanes | Result |
|---|---|---|
| Claude Code named agents | `sonnet-clerk`, `sonnet-scout`, `sonnet-builder`, `sonnet-reviewer`, `opus-reviewer`, `fable-judge` | All six role-appropriate. Clerk aggregated the CSV correctly; scout mapped the module and spotted the contract mismatch; `sonnet-reviewer` named the off-by-one precisely; `opus-reviewer` named it *and* separately raised the edge cases the check leaves uncovered (`size == len(values)`, `size <= 0`, empty input) plus the unspecified README contract — the differentiation the senior lane exists for; `fable-judge` returned a verdict with its rejected alternative and accepted risk. Read-only roles left the fixture clean. |
| Codex ephemeral profiles | `luna-clerk`, `terra-scout`, `terra-builder`, `sol-reviewer`, `sol-judge` | All five role-appropriate at their pinned efforts, after reinstalling so the installed bytes carried the 0.13.0 re-pin. `luna-clerk` at `max` aggregated correctly; `terra-scout` at `medium` mapped the module and flagged the conflict; `sol-reviewer` at `high` named the off-by-one; `sol-judge` at `high` returned the right verdict with reasoning; `terra-builder` at `max` turned the check green with a one-line diff touching **only** `src/window.py`. The four read-only profiles left the fixture clean. |
| Codex native profiles | the same five roles under `~/.codex/agents/` | Model, effort, sandbox, role declarations, and installed bytes match the shipped definitions, with `luna-clerk` at `max`, `terra-scout` at `medium`, and `terra-builder` at `max` in both the agent and the ephemeral-profile copies. |
| GLM-5.2 | `clerk`, `scout`, `builder` | All three passed at `claude-zai/high`, dispatched serially because the coding plan is effectively concurrency-1 per key. Clerk aggregated correctly, scout produced a correct map, builder turned the check green with a one-line diff confined to `src/window.py`. Clerk and scout are qualified explicit-only; builder is provisional explicit-only. |
| Gemini 3.6 Flash | `scout` | Re-verified 2026-08-05 from an SSH session, after 0.13.1 stopped the SSH markers from diverting `agy` off the Keychain: `check` reports `ready`, and two prompt-only `scout` dispatches returned correct answers at exit 0 through the ordinary invocation, with no output file or partial artifact left behind on the earlier refusals. Before the fix the same lane failed closed with exit 69 regardless of how often the user signed in. The lane remains provisional and requires `--allow-provisional`; builder lanes remain blocked. The runner reads the OAuth session from the login keychain, so it needs that keychain unlocked. |
| Kimi K3 | `clerk`, `scout`, `builder`, `frontend-builder` | All four passed at native `max`. Clerk aggregated correctly; scout mapped the module and located the off-by-one by line; builder turned the check green confined to `src/window.py`; frontend-builder made the CSS component theme-aware through `prefers-color-scheme`, editing only `style.css`. The capability, sandbox, pin/tamper, signal, timeout, OAuth-finalization, and diagnostics regressions pass, including the shared-OAuth concurrency cases, and the live two-parallel `--oauth shared` smoke passed 2026-08-04 with a real mid-run token rotation. All operational lanes remain provisional; `builder` and `frontend-builder` are `preferred-explicit` as of 0.13.0 while `clerk`/`scout` stay `explicit-only`, and every one still requires `--allow-provisional`. |
| Grok 4.5 | `builder`, `frontend-builder` | Both passed at `grok-build/high` in disposable worktrees and stayed inside their assigned files: builder turned the check green with a one-line diff, frontend-builder produced an equivalent `prefers-color-scheme` treatment touching only `style.css`. Both lanes remain provisional and `preferred-explicit` as of 0.13.0, and both still require `--allow-provisional`. |
| Qwen3.8-Max | `builder` | Passed at `token-plan-openai/xhigh`. The lane is text-only, so the brief carried the file contents and the runner returned a unified diff, semantically correct on the first attempt. Left to itself the model emits `--- src/window.py` / `+++ src/window.py` without the conventional `a/`/`b/` prefixes, so a bare `git apply` — which defaults to `-p1` and strips one component — looks for `window.py` and fails on a patch that is actually correct; `-p0` applies it cleanly. Asking for prefixed headers in the brief fixes it at the source: re-dispatched with that instruction, the model returned `--- a/src/window.py` and the patch applied with a **bare `git apply`**, check printing `PASS`. `skills/qwen-executor` now carries that wording. The lane is provisional explicit-only and requires `--allow-provisional`; every other lane still fails closed with exit `78`. |
| Claude↔Codex bridge | both directions | `doctor.sh --ping` completed both real round trips. |

The full doctor result for this snapshot was `44 OK, 0 WARN, 0 FAIL` with
`--ping` on 2026-08-05, and both live round trips returned. The ten regression
suites passed through `./run-tests.sh` in 51s of wall clock — the figure moves
with machine load, so treat it as one observation rather than a bound. They include 37 central routing checks, 14
install-marker checks, 8 version-surface checks, and 6 Epoch ZIP checks. Every suite except `doctor.sh --ping` also runs in CI on each pull
request; the ping stays local because it needs authenticated Claude and Codex
CLIs. A two-pass installation into empty temporary Claude/Codex
homes produced one guarded policy block per host and byte-identical agents,
profiles, skills, runners, and gates.

**Smoke the installed runners, not the ones in the checkout.** The key-bearing
lanes resolve their credential file relative to their own root:
`delegation-glm` reads `$ROOT/config/zai.env` and `delegation-qwen` reads
`$ROOT/config/qwen-token-plan.env`. For the installed copy that is the data
home, where the installer wrote them at mode 600; for a git checkout it is
`config/`, which is gitignored and normally empty. Running `./bin/delegation-glm
check` from the checkout therefore reports `ZAI_API_KEY is unset` and looks
exactly like a missing entitlement. It is not — it is the wrong root. Export the
key, point `DELEGATION_GLM_KEY_FILE` at the real file, or just invoke the
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
