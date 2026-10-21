# Compatibility and release verification

This page records what was observed, on which machine and day, before each
tag. A passing check shows that what was tested ran; it qualifies no model and
grants nothing (which model to use is
[your choice](user-configuration.md)). Each release replaces the snapshot
below with the numbers observed after running the
[gates](#reproduce-the-integration-gates). Snapshots 0.16 through 0.26 live in
`CHANGELOG.md` and in this file's history.

## Verified snapshot

**0.30.4, checked on 2026-10-21** on macOS 26.5.1 with Claude Code
`2.1.306` and Codex CLI `0.163.0`.

- **Offline**: the 13 suites green in 51 seconds (the router suite at 79
  tests; the installer suite at 18, one new for files a release no longer
  ships, which fails against the 0.30.3 installer), ShellCheck at
  `-S warning` on the files CI collects, ruff, the eleven Node tests and the
  version gate.
- **Install and doctor**: a reinstall from the release branch removed the
  two library modules earlier releases had left (`delegation_router.py`,
  `delegation_router_catalog.py`) and the empty orchestrate reference;
  `delegation-router check` ran from the pruned install. Static `doctor.sh`
  reports `55 OK, 6 WARN, 0 FAIL`; the six warnings are the configured
  pool's native profiles (no tools, images or JSON mode through the router).
- **Catalog**: `catalog refresh --shipped` again on 2026-10-21, nothing
  changed since 0.30.3.
- **Live**: none new for this release. The latest live checks, each
  authorized, are recorded below with their dates: MiniMax-M3.1-Flash with
  its key in the personal `.env` (2026-10-20), the DeepSeek Flash decider's
  half points and `decide --lane` (2026-10-19), Claude Opus 5.5 at `max`
  (2026-10-19), Sage, Jev and the `llm` deciders (2026-10-15).

### Earlier releases

Newest first. "Suites" means the 13 regression suites; every live call was
authorized and no key was printed.

- **0.30.3** (2026-10-21, Claude Code `2.1.306`): documentation and one
  `check` warning; suites in 214 s (79 router tests), ShellCheck, ruff, Node
  tests, version gate;
  doctor `55 OK, 6 WARN, 0 FAIL`, and without a personal configuration it
  named the missing keys file and reported four FAILs without stopping.
  Catalog refreshed, nothing changed.
- **0.30.2** (2026-10-20, Claude Code `2.1.304`): suites in 49 s (79 router
  tests), ShellCheck, ruff, Node tests, version gate; doctor `55 OK, 6 WARN,
  0 FAIL`, and without a personal configuration it no longer stopped on an
  unset variable. Catalog refreshed: MiniMax-M3.1-Flash 42.4 → 42.7, still
  `mid`.
- **0.30.1** (2026-10-20): docs and guard wording only; suites and version
  gate pass. MiniMax-M3.1-Flash dispatched once with its key only in the
  personal `.env`: `PONG` in 3 s, `provider_reported_model`
  `MiniMax-M3.1-Flash` (`provider-reported`), 214 input / 14 output tokens.
- **0.30.0** (2026-10-20): suites (new personal `.env` tests), ShellCheck,
  ruff, version gate. The reinstall created `~/.config/delegation-kit/.env`
  from `.env.example`, mode 600; an `openai-compatible` MiniMax profile with
  its key only there was reachable in `check`. Doctor `55 OK, 6 WARN, 0 FAIL`
  (new line: the keys file's mode and variable count).
- **0.29.1** (2026-10-19): catalog only. MiniMax-M3.1-Flash replaced
  MiniMax-M3, matched by slug at 42.4 (`mid`, $0.15/$0.60); 24 of 25 placed;
  everything else unchanged since 2026-10-17. Suites and version gate pass.
- **0.29.0** (2026-10-19): suites (75 router tests), ShellCheck, ruff, Node
  tests, version gate. Eight-profile pool all reachable, runner checks
  0.04–3 s (Kimi longest); doctor `54 OK, 6 WARN, 0 FAIL`. From a source
  checkout the GLM runner's key file was not found and `check` reported it
  unreachable. Live: two `decide --lane builder` calls to the DeepSeek Flash
  decider, nothing dispatched: a rename rated 0 →
  `glm53-flash-max-builder` (cheapest of five builders), a Go deadlock 2.5
  (minimum 43.6) → `kimi-k3`, the three profiles without the role blocked;
  0.8–1.1 s each.
- **0.28.0** (2026-10-19): suites (70 router tests), ShellCheck, ruff, Node
  tests, version gate; doctor `54 OK, 2 WARN, 0 FAIL` (`luna-clerk`,
  `opus-reviewer`: native limits). Live: four `decide --raw` calls to the
  DeepSeek Flash decider, no pool profile dispatched: a rename 0 (`code`), a
  contract summary 1, a Go worker-pool deadlock 2.5 (`code`), a four-colour
  proof 3.5 (`math`, `rare`); 0.8–1.1 s, about $0.00014 each; minimums 0, 0,
  43.6, 49.6. README routes checked against `choose()` with the shipped
  presets.
- **0.27.2** (2026-10-19, Claude Code `2.1.303`): suites (installer PATH
  warning asserted both ways), ShellCheck, ruff, Node tests, version gate;
  doctor `53 OK, 0 WARN, 0 FAIL` with `opus-builder` and `opus-reviewer`
  pinned to `claude-opus-5-5/max`. Live: `delegation-run --profile
  opus-reviewer --lane routine-review` answered `PONG` in 3 s; receipt
  `requested_model: claude-opus-5-5`, `model_identity_source: requested-only`
  (Claude Code's JSON result names no model). README routing example checked
  against `choose()`.
- **0.27.1** (2026-10-17): npm wrapper only; suites, ShellCheck, ruff and the
  eleven Node tests pass, three of them new for `--ref`.
- **0.27.0** (2026-10-15, re-checked 2026-10-17; Codex CLI `0.163.0`, Claude
  Code `2.1.302`): suites in 46 s (about 80 s on macOS CI), 64 router tests,
  ShellCheck, ruff, eight Node tests, ten-check version gate; reinstall and
  `doctor.sh --ping` `55 OK, 0 WARN, 0 FAIL`, router `not configured —
  optional`. `catalog refresh`: 700 rows, 24 of 25 models matched by slug or
  alias; re-run with `--shipped` on 2026-10-17, placements and prices as on
  2026-10-15. Deciders measured (below). A no-spend probe of `serve` against
  the real DeepSeek and Qwen endpoints with fake keys returned
  `401 provider-key-rejected` naming the default profile, with no key in the
  response or in the single log line. Dipylon was not probed (no local
  service running); no pool model was dispatched.

## Decider measurements

Live, 2026-10-15 (0.27.0), each call authorized.

| decider | version | prompts | latency | cost per decision |
|---|---|---|---|---|
| Levanto Sage | `levanto-sage-v1.4` | 3 | 0.8–2.0 s short; 7–13 s on a 900-token excerpt | ≈ $0.00003 short; ≈ $0.005 long (fanout billed 0 and ~500 output tokens with `reasoning: "off"`) |
| TypeSafe Jev | `jev-1.13.0` | 2 | ~250 ms | ~$0.00002 |
| `llm`, DeepSeek V4.1 Flash (kit key file) | — | 3 | 1.0–1.2 s | $0.00012–0.00015 |
| `llm`, Qwen3.8 Max (kit key file) | — | 3 | 5–10 s, still reasoning at `minimal` | $0.0014–0.0025 |

What they rated: a rename 0.7–1.0 with `code`; a race-condition design
question 1.6–1.7 (Sage, Jev; Sage adds `rare` 0.98) and 2.0 (DeepSeek, Qwen:
"classic SELECT-then-UPDATE race, SKIP LOCKED"); a percentage question 1 with
`math`. "Needs a frontier model" was ≈ 0.01–0.09 everywhere. The deciders
agree with each other and rate the race condition lower than a human would,
which is why `eval` on a golden set exists.

## Host-specific boundaries

### Codex profiles

Use the shipped ephemeral profiles with:

```sh
codex exec --ephemeral -p <profile> "<self-contained prompt>" </dev/null
```

Do not add `--ignore-user-config`: Codex then ignores the selected `-p` profile
as well and can silently use the ambient base model. Treat the model, effort,
and sandbox shown in the invocation banner as part of the smoke assertion.
Ephemeral profiles carry no role prose, so the prompt must be bounded and
self-contained; native agent profiles carry their role through
`developer_instructions`.

### Claude Code agents

The clerk and scout agents expose Bash, to inspect Git state and run
read-only search or test commands; the reviewers and the judge do not. For
those two, read-only is role discipline plus the parent's permissions, not
Codex's OS-enforced read-only sandbox: run them on a clean worktree and check
`git diff` and `git status` afterwards.

For headless checks outside the current repository, pass the canonical
fixture path through `--add-dir`; macOS `/var` and `/private/var` aliases can
otherwise make an allowed temporary fixture look like a different path.
`--output-format json` does not settle model identity: its result names no
model (0.27.2 above).

External runners: see [Executors](external-executors.md) for `check --json`
and exit codes.

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
