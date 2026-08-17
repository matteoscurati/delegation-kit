---
name: gemini-executor
description: >-
  Inspect or evaluate the staged Gemini 3.7 Flash route through the installed
  Antigravity CLI. Never bypass its gate or silently change model,
  effort, backend, or permissions.
---

# Gemini 3.7 Flash executor

Gemini 3.7 Flash is a staged external executor reached through the installed
`agy` CLI and its user-managed Google OAuth session. Before dispatch, run
`delegation-gemini check --json`.

No operational lane is currently exposed. `scout` at medium plus `builder` and
`frontend-builder` at high are blocked candidates; reviewer and judgement are
disabled. The official launch confirms the model and supported thinking levels,
but the current local Antigravity session cannot attest exact inventory or
OAuth. The previous Gemini 3.6 smoke does not transfer.

The bridge is deliberately **prompt-only**. Antigravity's headless permission
requests cannot be approved safely per process, and
`--dangerously-skip-permissions` is forbidden. Before dispatch, use the lead's
read-only tools to select the relevant tracked files and put the necessary
excerpts, paths, question, and expected return format into one self-contained
brief. Do not merely tell Gemini to inspect the repository: this lane does not
approve filesystem, shell, network, MCP, subagent, or editing tools.
The `--workdir` argument identifies the caller's source repository for input
validation, but `agy` itself starts in an empty temporary workspace so future
changes to Antigravity's workspace auto-allow behavior cannot expose that
repository.
The runner starts `agy` with a fresh temporary `HOME`, carrying across only
macOS Keychain access required by the existing OAuth session. It creates a
private Antigravity policy that denies every filesystem, command, URL, and MCP
tool namespace, so global hooks, MCPs, plugins, memories, and permission grants
are not loaded. It also forces terminal sandboxing and remains in plan mode
during evaluation runs.

For a deliberate controlled evaluation only, run:

```sh
delegation-gemini run --lane scout --effort auto --evaluation \
  --backend auto --prompt-file "$brief" --output "$result" --workdir "$repo"
```

`auto` resolves to the `agy` backend and the effort pinned by the gate. Ordinary
dispatch remains refused until both gates are promoted. The runner uses plan
mode for every evaluation and refuses every unapproved
lane/model/effort tuple. It never falls back to a neighboring Gemini variant,
another provider, or another model.

Exit 69 means the runtime or OAuth session is unavailable; exit 70 means
dispatch or output validation failed; exit 75 means a temporary provider or
rate-limit failure; exit 78 means the lane or effort is not dispatchable.
Attempted dispatch failures write a sanitized `<output>.error.json`.

Raw stdout and stderr are deleted by default. For a deliberate diagnostic run,
pass an existing non-symlink `--debug-dir <path>`; failure artifacts are private
and sensitive and must never be committed. Treat all successful output as
unverified until the lead checks its evidence and conclusions.
