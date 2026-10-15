# Compatibility and release verification

This page records functional compatibility: what the installed interfaces
were observed to do, on which machine, on which day. A successful smoke
proves that the exact model, effort, tools and role tested here ran; it
qualifies nothing and grants nothing. Which model to use stays a user choice
in the personal configuration, and the router chooses only inside the pool
the user declared.

Earlier snapshots (0.16 through 0.26) live in the `CHANGELOG.md` entries of
those releases and in this file's history; each release replaces the snapshot
below with the numbers actually observed before tagging.

## Verified snapshot

The 0.27.0 release was verified on **2026-10-15** on macOS 26.5.1 with
ambient Codex CLI `0.162.1` and ambient Claude Code `2.1.296`.

**Offline.** All 13 regression suites green in 45 seconds here and about
80 seconds on the macOS CI runner (where every `HTTPServer` bind had
stalled on a reverse-DNS lookup until the router and the test fakes stopped
asking for one). The `router` suite, `tests/router/`, runs 64 tests: the
`tiered-v1` policy table, configuration validation, the catalog's band rule,
row parsing, matching, refresh and local overlay, `check`/`decide`/`eval`
and the loopback server against fake providers and services — each profile
receives only its own key and no canary key reaches any output, decider
failures and prompt injection cannot steer the route, a single eligible
profile is routed rather than refused, broken streams end with a router
chunk naming the failure, a profile `timeout` cuts a slow answer as 504
within the deadline, a kept-alive connection gets a full answer to every
request, receipts hold no prompt text and survive `uninstall.sh`, a native
profile is bridged through `delegation-run` against fake `codex`/`claude`
executables, the four service deciders each speak their wire format, and
`eval` scores a decider against the baseline without dispatching.
ShellCheck at `-S warning`, ruff, the eight Node tests and the ten-check
version gate pass; a reinstall from the release commit and static doctor
report `53 OK, 0 WARN, 0 FAIL` with the router reported as `not configured —
optional`.

**Live, each call authorized, keys read from the environment and never
printed.**

- `delegation-router catalog refresh` against the Artificial Analysis API:
  700 rows; 24 of 25 catalog models matched by slug or alias (Haiku 4.5 is
  not on the board); the same call with `--shipped` wrote the catalog this
  release carries.
- Levanto Sage (`levanto-sage-v1.4`) on three prompts: 0.8–2.0 s on a short
  prompt, 7–13 s on a 900-token excerpt; its fanout mode billed 0 output
  tokens on the short prompt and ~500 on the long one with `reasoning:
  "off"` (≈ $0.00003 vs ≈ $0.005 per decision). The first attempt exposed
  that Sage lists `{level, probability}` objects, which the parser now reads.
- TypeSafe Jev (`jev-1.13.0`) on two prompts: ~250 ms, ~$0.00002 per
  decision.
- The `llm` decider through the kit's own key files, three prompts each:
  DeepSeek V4.1 Flash 1.0–1.2 s and $0.00012–0.00015 (with thinking
  enabled it had spent 56 of 60 output tokens reasoning and cut the JSON
  off, which is why the decision now asks with thinking disabled and 120
  tokens of room); Qwen3.8 Max 5–10 s and $0.0014–0.0025, still reasoning
  at `minimal`.
- What they said: a rename is difficulty 0.7–1.0 with `code`; a
  race-condition design question is 1.6–1.7 (Sage, Jev; Sage adds `rare`
  0.98) and 2.0 (DeepSeek, Qwen: "classic SELECT-then-UPDATE race, SKIP
  LOCKED"), with "needs a frontier model" ≈ 0.01–0.09 everywhere; a
  percentage question is 1 with `math`. Consistent with each other, and
  below what a human would give the race condition — the reason `eval` on
  a golden set exists.
- One no-spend probe of `serve` against the real DeepSeek and Qwen endpoints
  with fake keys: `401 provider-key-rejected` naming the default profile,
  no key in the response or in the single log line.

Dipylon was not probed (no local service running); no pool model was
dispatched; the live probes of the 0.25.0 pass stand.

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

Always run `check --json` immediately before dispatch. A role or effort the
adapter does not support fails with exit 78 rather than falling back to another
model, effort, backend, or host profile. Semantic smoke results change nothing
in the kit.

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
