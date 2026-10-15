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
suite runs the 64
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
service and land in the same signals, `eval` scores a decider against
the baseline without dispatching, and the catalog's band rule, row parsing,
matching, refresh, key file and local overlay are covered without network; the doctor and install-marker suites cover
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
was rejected, with no key in the response or in the single log line. One
authorized `delegation-router catalog refresh` ran against the Artificial
Analysis API with the user's key (700 rows; 24 of 25 catalog models matched
by slug or alias, Haiku 4.5 absent from the board) and the same call with
`--shipped` wrote the catalog this release carries. Two decision services
were probed live through `delegation-router decide`, with the user's keys
read from the environment in a subshell and never printed: Levanto Sage
(`levanto-sage-v1.4`; three prompts, 0.8–2.0 s, $0.00003 per decision and
$0.0012 when its reasoning fired on the hard one; the first attempt exposed
that Sage lists `{level, probability}` objects, which the parser now reads)
and TypeSafe Jev (`jev-1.13.0`; two prompts, ~250 ms, ~$0.00002 per
decision). Both rated a rename as difficulty 0.7 with `code` ≈ 0.84–1.0 and
a race-condition design question as 1.6–1.7 with "needs a frontier model"
≈ 0.01–0.09; Sage tagged the latter `rare` 0.98, Jev's digit heuristic
tagged `LIMIT 1` as math until the heuristic was made arithmetic-shaped.
The `llm` decider was then probed through the kit's own key files on three
prompts each: DeepSeek V4.1 Flash (`deepseek-flash+46002df5`, 1.0–1.2 s,
$0.00012–0.00015 per decision, 26–43 output tokens; the first attempt, with
thinking enabled, spent 56 of 60 output tokens reasoning and cut the JSON
off, which is why the decision now asks with thinking disabled and 120
tokens of room) and Qwen3.8 Max (5–10 s, $0.0014–0.0025, 135–299 output
tokens even at `minimal` effort). Both rated the rename 1, the race
condition 2 ("classic SELECT-then-UPDATE race; SKIP LOCKED") and the
percentage question 1 with `math`. Dipylon was not probed: no local service
was running. No pool model was dispatched; the live probes of the 0.25.0
pass stand.

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
