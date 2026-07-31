# Supported-agent compatibility

This page records functional compatibility separately from routing
qualification. A successful smoke proves that the installed interface can run
the exact model, effort, tools, and lane contract tested here. It does not
promote a provisional or candidate lane.

## Verified snapshot

The matrix below was verified on macOS on 2026-07-31 with Codex CLI `0.146.0`
and Claude Code `2.1.220`. Numeric vendor versions are provenance only wherever
the runner uses capability probing.

| Surface | Profiles or lanes | Result |
|---|---|---|
| Claude Code named agents | `sonnet-clerk`, `sonnet-scout`, `sonnet-builder`, `sonnet-reviewer`, `opus-reviewer`, `fable-judge` | All six returned role-appropriate semantic results with the configured Sonnet 5, Opus 5, or Fable 5 model. Builder changed only its assigned disposable file; read-only roles left the fixture clean. |
| Codex ephemeral profiles | `luna-clerk`, `terra-scout`, `terra-builder`, `sol-reviewer`, `sol-judge` | All five returned role-appropriate semantic results with the configured model, effort, and sandbox. Builder changed only its assigned disposable file. |
| Codex native profiles | the same five roles under `~/.codex/agents/` | Model, effort, sandbox, role declarations, and installed bytes match the shipped definitions. |
| GLM-5.2 | `clerk`, `scout` | Semantic smokes passed. Both lanes remain provisional and require `--allow-provisional`; builder remains blocked. |
| Gemini 3.6 Flash | `scout` | The prompt-only semantic smoke passed. The lane remains provisional and requires `--allow-provisional`; builder lanes remain blocked. |
| Kimi K3 | `clerk`, `scout`, `builder`, `frontend-builder` | Capability, sandbox, pin/tamper, signal, timeout, OAuth-finalization, and diagnostics regressions passed. All operational lanes remain provisional and explicit-only. |
| Grok 4.5 | `builder`, `frontend-builder` | Both semantic edit smokes passed in disposable repositories and stayed within assigned files. Both lanes remain provisional and require `--allow-provisional`. |
| Qwen3.8 Max Preview | normal operational lanes | Correctly failed closed with exit `78` and no output artifact. It remains candidate/blocked; runtime availability is not qualification. |
| Claude↔Codex bridge | both directions | `doctor.sh --ping` completed both real round trips. |

The full doctor result for this snapshot was `41 OK, 0 WARN, 0 FAIL`. The seven
documented regression suites passed, including 33 central routing checks and 6
Epoch ZIP checks. A two-pass installation into empty temporary Claude/Codex
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
tests/routing-gates.sh
tests/epoch-zip.sh
tests/glm-runner-diagnostics.sh
tests/gemini-runner-diagnostics.sh
tests/kimi-runner.sh
tests/grok-runner.sh
tests/qwen-runner.sh
./doctor.sh --ping
git diff --check
```

For semantic verification, use disposable Git repositories and
role-appropriate prompts: deterministic extraction for clerks, flow tracing for
scouts, one bounded edit for builders, concrete bug detection for reviewers,
and a reversible architecture decision for judges. Verify exact model identity,
scope, output meaning, and worktree changes—not merely process exit.
