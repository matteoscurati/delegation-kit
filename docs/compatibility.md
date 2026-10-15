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

The 0.27.0 release was verified on **2026-10-13** on macOS 26.5.1 with
ambient Codex CLI `0.162.1` and ambient Claude Code `2.1.296`: all 13
regression suites green in 42 seconds here and in 80 seconds on the macOS CI
runner, where every `HTTPServer` bind used to stall on a reverse-DNS lookup
until the router and the test fakes stopped asking for one (the new `router`
suite runs the 46
tests of `tests/router.py` — the `tiered-v1` policy table, configuration
validation, `check`/`decide` and the loopback server against a fake provider:
each profile receives only its own key and no canary key reaches any output,
decider failures and prompt injection cannot steer the route, broken streams
end with a router chunk naming the failure, a profile `timeout` cuts a slow
non-stream answer as 504 within the deadline, odd provider shapes never
corrupt a stream, a refusal before the body closes the connection, an
allow-listed origin gets CORS, `[::1]` binds, receipts hold no prompt text
and survive `uninstall.sh`, the server writes nothing to stderr, a native
profile is bridged through `delegation-run` against fake `codex`/`claude`
executables (read-only role, transcript, mapped exit codes, one-event
stream), the four service deciders each speak their wire format to a fake
service and land in the same signals, and `eval` scores a decider against
the baseline without dispatching; the doctor and install-marker suites cover
the "Model router" section, the installed command, catalog, prompt and
receipts backup),
ShellCheck at `-S warning`, ruff, the eight Node tests, the ten-check version
gate, a reinstall from the release commit and static doctor at `53 OK, 0 WARN,
0 FAIL` with the Grok runtime line present and the router reported as
`not configured — optional`. One no-spend probe was run against the real
DeepSeek and Qwen Token Plan endpoints with fake keys from a temporary
configuration: `check` resolved the pool, `decide --decider none`
landed on the default as undecidable, `serve` listed the pool and `auto` on
`/v1/models`, and a `model: auto` request came back `401
provider-key-rejected` naming the default profile after the decider's own key
was rejected, with no key in the response or in the single log line. No model
inference was executed for this release; the live probes of the 0.25.0 pass
stand.

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
