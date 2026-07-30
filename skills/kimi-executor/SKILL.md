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
`policy-annotation` is candidate/blocked only for a manifest-bound evaluation
at the exact Kimi K3/max tuple; it never creates an operational route or
qualifies broad architecture/trade-off judgement.
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

Every lane runs with a minimal isolated HOME/TMP that imports authentication but
not ambient hooks, services, plugins, or configuration. The child environment is
an allowlist, ambient HOME file contents are unreadable, and terminal execution
is replaced by a no-op shell; the Kimi provider remains reachable for inference.
Because Kimi may rotate OAuth refresh tokens, native dispatches serialize access
to the credential snapshot. After the child exits, the parent validates and
atomically persists a changed `credentials/kimi-code.json`; it does not expose
the ambient file to the model process. Do not run `kimi login` concurrently
with dispatch. If the parent observes an external credential replacement, it
refuses to overwrite it and returns exit 75; callers should retry after login
finishes.
CLI compatibility is determined from capabilities: the runtime must
expose structured output, the exact `kimi-code/k3` model, OAuth credentials, and
`max` as both supported and effective default effort. The observed CLI version
is recorded only as provenance.

`clerk` and `scout` are filesystem-read-only: macOS `sandbox-exec` permits writes
only in runner-owned scratch. `builder` and `frontend-builder` may write only in
the canonical worktree plus scratch. All lanes fail closed without the OS guard,
and workdir cannot be `/` or the user's HOME. This is a filesystem and process
boundary, not a claim that model output is trusted; inspect every result and diff.

Exit 69 means the requested runtime/model/authentication is unavailable, exit
70 means dispatch or output validation failed, exit 75 is temporary/rate-limit
failure, and exit 78 means the lane did not pass evaluation. Route deliberately
to a documented incumbent after any failure. Treat K3 output as unverified and
exercise the deliverable before accepting it.
