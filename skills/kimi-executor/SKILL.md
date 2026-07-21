---
name: kimi-executor
description: >-
  Dispatch a provisional Kimi K3 lane through delegation-kimi after an explicit
  decision. Never use it before the evaluation gate or as a silent fallback.
---

# Kimi K3 executor bridge

Kimi K3 is an optional external executor available through native Kimi Code
(`kimi-code/k3`, effort `max`).

Before every dispatch, run `delegation-kimi check --json`. Require the native
backend and the requested lane in `provisional_lanes`, then pass
`--allow-provisional`. The gate permits `clerk`, `scout`, `builder`, and
`frontend-builder`; senior is blocked, while reviewer and judgement are disabled.
Provider quota exhaustion is exit 75 and never
triggers a silent substitution.

The gate points to exact rows in the dated external snapshot. Inspect them with
`delegation-evidence lane <lane>`; they support the owner decision but never
replace the local runtime, scope, and permission checks enforced below.

Write a self-contained worker brief to a file, then run:

```sh
delegation-kimi run \
  --lane <clerk|scout|builder|frontend-builder> --allow-provisional \
  --backend auto --effort auto --prompt-file "$brief" \
  --output "$result" --metrics "$metrics" --workdir "$repo"
```

Create the output and metrics parent directories before dispatch. For every
read-only lane, keep them outside the worktree; the runner rejects in-worktree
paths, symlinks, canonical path collisions, and unqualified effort overrides.
There is no public evaluation bypass. `auto` and `native` both resolve to the
native Kimi Code backend; there is no fallback to select.

All lanes except `builder` and `frontend-builder` are read-only. Kimi Code 0.26 cannot combine
headless prompt mode with `--plan` and bare prompt mode auto-approves writes, so
the native backend runs with an isolated HOME/TMP and uses macOS `sandbox-exec`
to deny every write outside runner-owned scratch space; it fails closed on
platforms without that guard. The builder uses native prompt mode, which Kimi
Code 0.26 runs with action approvals in headless mode.

Exit 69 means the requested runtime/model/authentication is unavailable, exit
70 means dispatch or output validation failed, exit 75 is temporary/rate-limit
failure, and exit 78 means the lane did not pass evaluation. Route deliberately
to a documented incumbent after any failure. Treat K3 output as unverified and
exercise the deliverable before accepting it.
