---
name: grok-executor
description: >-
  Dispatch the explicitly promoted Grok 4.5 builder or frontend-builder lane
  through the installed Grok Build CLI. Never bypass its gate or silently
  change model, effort, backend, permissions, or lane.
---

# Grok 4.5 builder executor

Grok 4.5 is provisionally available for `builder` and `frontend-builder` through
the native Grok Build CLI at reasoning effort `high`.

Before every dispatch, run `delegation-grok check --json`. Require
`selected_backend == "grok-build"` and the requested lane in
`provisional_lanes`, then make an explicit routing decision and pass
`--allow-provisional`. No other lane is exposed.

Write a bounded, self-contained implementation brief to a file and run:

```sh
delegation-grok run \
  --lane <builder|frontend-builder> --allow-provisional \
  --backend auto --effort auto --prompt-file "$brief" \
  --output "$result" --metrics "$metrics" --workdir "$repo"
```

The runner pins Grok Build CLI `0.2.111`, `grok-4.5`, effort `high`, JSON output,
40 turns, and a 15-minute wall timeout. It uses an ephemeral HOME, disables
memory, subagents, web tools, plugins, MCP, compatibility imports, and automatic
updates, and requires the custom OS-enforced `delegation-kit` sandbox to attest
successful enforcement before publishing output. Permission mode is `dontAsk`,
with only file edits explicitly allowed; the terminal tool is not exposed. The
lead runs all tests and commands after inspecting the diff.

Failures write only a sanitized `<output>.error.json`. Raw provider output and
stderr are retained only when the caller explicitly supplies an existing private
`--debug-dir`; those artifacts may contain sensitive prompt or model data.

Treat the returned text and all worktree edits as unverified. Inspect the diff,
run the acceptance checks yourself, and preserve unrelated user changes. Exit
69 means runtime/model/authentication unavailable, 70 means dispatch or output
validation failed, 75 means timeout or temporary/rate-limit failure, and 78
means the gate refused the tuple. Never silently substitute a neighboring model
or lane.
