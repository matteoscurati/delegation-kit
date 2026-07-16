---
name: kimi-executor
description: >-
  Dispatch an evaluated and qualified Kimi K3 lane through delegation-kimi.
  Use only when model routing selects K3 and the exact lane/backend combination
  is qualified. Never use it before the evaluation gate or as a silent fallback.
---

# Kimi K3 executor bridge

Kimi K3 is an optional external executor available through native Kimi Code
(`kimi-code/k3`, effort `max`) or Kilo's Kimi For Coding provider
(`kimi-for-coding/k3`, effort `high` or `max`).

Before every dispatch, run `delegation-kimi check --json`. Require the intended
backend to be available and the requested lane to appear in `qualified_lanes`.
The versioned routing JSON is authoritative. The shipped provisional gate enables
`clerk`, `scout`, `builder`, and `senior`, preferring Kilo `high` with native
`max` as an alternative. `reviewer` and `judgement` remain disabled. Provider
quota exhaustion is exit 75 and never triggers a silent backend substitution.

Write a self-contained worker brief to a file, then run:

```sh
delegation-kimi run \
  --lane <clerk|scout|builder|reviewer|senior|judgement> \
  --backend auto --effort auto --prompt-file "$brief" \
  --output "$result" --metrics "$metrics" --workdir "$repo"
```

For every read-only lane, keep `--output` and `--metrics` outside the worktree;
the runner rejects in-worktree paths and symlinks before dispatch.

Use `--evaluation` only inside the controlled evaluation harness; it bypasses
qualification, not availability, authentication, exact-model, effort, or
read-only checks. `auto` follows the preferred backend order in the gate.
Selecting `native` or `kilo` explicitly never falls back.

All lanes except `builder` are read-only. Kimi Code 0.26 cannot combine
headless prompt mode with `--plan` and bare prompt mode auto-approves writes, so
the native backend enforces read-only access below the model with macOS
`sandbox-exec`; it fails closed on platforms without that guard. Kilo uses its
`plan` agent. The builder uses native prompt mode (which Kimi Code 0.26 runs
with action approvals in headless mode) or Kilo's `code` agent with automatic
approvals.

Exit 69 means the requested runtime/model/authentication is unavailable, exit
70 means dispatch or output validation failed, exit 75 is temporary/rate-limit
failure, and exit 78 means the lane did not pass evaluation. Route deliberately
to a documented incumbent after any failure. Treat K3 output as unverified and
exercise the deliverable before accepting it.
