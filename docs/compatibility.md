# Supported-agent compatibility

This page records functional compatibility separately from routing
qualification. A successful smoke proves that the installed interface can run
the exact model, effort, tools, and lane contract tested here. It does not
promote a provisional or candidate lane.

## Verified snapshot

The matrix below was verified on macOS 26.5.1 with Codex CLI `0.146.0` and
Claude Code `2.1.220`. Numeric vendor versions are provenance only wherever the
runner uses capability probing.

It carries two dates. The rows 0.13.0 and 0.13.1 touched — the Codex ephemeral
and native profiles, Gemini 3.6 Flash, and the bridge — were re-verified on
**2026-08-05**. Every other row is carried from **2026-08-03** because neither
release changed its runner, transport, or pinned tuple; each such row states its
own date where the run itself was dated.

The Gemini row was previously recorded as unverifiable on the belief that the
`agy` OAuth session had expired. It had not: the session was valid in the login
keychain the whole time, and `agy` was ignoring it because this machine drives
the kit over SSH. That is what 0.13.1 fixes, and the row is now a real passing
run rather than an absence.

| Surface | Profiles or lanes | Result |
|---|---|---|
| Claude Code named agents | `sonnet-clerk`, `sonnet-scout`, `sonnet-builder`, `sonnet-reviewer`, `opus-reviewer`, `fable-judge` | All six returned role-appropriate semantic results with the configured Sonnet 5, Opus 5, or Fable 5 model. Builder changed only its assigned disposable file; read-only roles left the fixture clean. |
| Codex ephemeral profiles | `luna-clerk`, `terra-scout`, `terra-builder`, `sol-reviewer`, `sol-judge` | Re-verified 2026-08-05 for the three profiles 0.13.0 re-pinned, after reinstalling so the installed bytes carried the new efforts. `luna-clerk` at `max` aggregated a five-line inventory to the correct per-item totals in the requested order; `terra-scout` at `medium` mapped `src/` and named the `app → util` import direction; `terra-builder` at `max` turned a red acceptance check green and its diff touched **only** `target.py`. Both read-only profiles left the fixture clean. `sol-reviewer` and `sol-judge` are unchanged at `high` and carry their 2026-08-03 result. |
| Codex native profiles | the same five roles under `~/.codex/agents/` | Model, effort, sandbox, role declarations, and installed bytes match the shipped definitions; re-checked 2026-08-05 after the re-pin, with `luna-clerk` at `max`, `terra-scout` at `medium`, and `terra-builder` at `max` in both the agent and the ephemeral-profile copies. |
| GLM-5.2 | `clerk`, `scout`, `builder` | The exact `claude-zai/high` comparison completed three no-retry attempts per provider and lane. Clerk and scout are qualified explicit-only; builder passed all checkers and is provisional explicit-only. |
| Gemini 3.6 Flash | `scout` | Re-verified 2026-08-05 from an SSH session, after 0.13.1 stopped the SSH markers from diverting `agy` off the Keychain: `check` reports `ready`, and two prompt-only `scout` dispatches returned correct answers at exit 0 through the ordinary invocation, with no output file or partial artifact left behind on the earlier refusals. Before the fix the same lane failed closed with exit 69 regardless of how often the user signed in. The lane remains provisional and requires `--allow-provisional`; builder lanes remain blocked. The runner reads the OAuth session from the login keychain, so it needs that keychain unlocked. |
| Kimi K3 | `clerk`, `scout`, `builder`, `frontend-builder` | Capability, sandbox, pin/tamper, signal, timeout, OAuth-finalization, and diagnostics regressions passed, including the shared-OAuth concurrency cases (parallel overlap, deferred publish, external-login conflict). The live two-parallel `--oauth shared` smoke against the real CLI passed on 2026-08-04: two concurrent scouts completed, the vendor rotated the OAuth token through the symlinked shared generation mid-run, and the publish restored a valid ambient credential. All operational lanes remain provisional; `builder` and `frontend-builder` are `preferred-explicit` as of 0.13.0 and `clerk`/`scout` stay `explicit-only`, and every one of them still requires `--allow-provisional`. |
| Grok 4.5 | `builder`, `frontend-builder` | Both semantic edit smokes passed in disposable repositories and stayed within assigned files. Both lanes remain provisional and `preferred-explicit` as of 0.13.0, and both still require `--allow-provisional`. |
| Qwen3.8-Max | `builder` | `GET /models` listed both `qwen3.8-max` and `qwen3.8-max-preview`, and a completion pinned to the unsuffixed id returned `.model == "qwen3.8-max"` at `xhigh`. A 20-check smoke passed: six gate refusals with the documented exit codes and no artifact, then a real dispatch whose unified diff applied with `git apply`, stayed inside its assigned file, and turned a red acceptance suite green. The lane is provisional explicit-only and requires `--allow-provisional`; every other lane still fails closed with exit `78`. |
| Claude↔Codex bridge | both directions | `doctor.sh --ping` completed both real round trips. |

The full doctor result for this snapshot was `43 OK, 0 WARN, 0 FAIL` with
`--ping` on 2026-08-05, and both live round trips returned. The ten regression
suites passed through `./run-tests.sh` in 51s of wall clock — the figure moves
with machine load, so treat it as one observation rather than a bound. They include 37 central routing checks, 14
install-marker checks, 8 version-surface checks, and 6 Epoch ZIP checks. Every suite except `doctor.sh --ping` also runs in CI on each pull
request; the ping stays local because it needs authenticated Claude and Codex
CLIs. A two-pass installation into empty temporary Claude/Codex
homes produced one guarded policy block per host and byte-identical agents,
profiles, skills, runners, and gates.

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
