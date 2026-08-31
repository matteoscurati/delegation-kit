---
name: glm-executor
description: Use only when the current user explicitly selects a GLM lane or asks to inspect GLM choices. Never dispatch GLM as an automatic fallback.
---

# GLM-5.3-Flash executor bridge

## User direction is required

This skill grants no standing permission to call another model. The current user
must select the exact lane/profile, or explicitly authorize the lead to choose
from `delegation-route resolve` choices. Authorization is per dispatch and does
not silently carry to retries, reviewers, advisors, or additional workers.


GLM-5.3-Flash is an optional external executor, not a native Claude or Codex
model. Before dispatch, run `delegation-glm check --json`. The gate is pinned
to `glm-5.3-flash` / `claude-zai` / `max`: clerk and scout are qualified
explicit-only, while builder is provisional explicit-only and requires an
explicit decision plus `--allow-provisional`. Reviewer is disabled and policy
annotation remains a separate blocked evaluation-only candidate.

Builder scope limit: the bridge dispatches the delegate at
`--permission-mode acceptEdits` with no settings sources, so it can only apply
in-workdir Edit/Write changes. It cannot execute shell commands — `pnpm`,
`node`, or any Bash call is denied in print mode — and the harness refuses
writes to files it treats as sensitive, such as `.npmrc`. Environment or
toolchain fixes that need exactly those actions are not routable to this lane;
the lead closes them. Observed 2026-08-04: a toolchain dispatch returned
analysis only (checks honestly marked unexecuted) for $0.88 and ~6.6 minutes.

The 2026-08-29 Flash v4 pack passed 9/9 no-retry attempts at score 1.0.
All 204 assistant events carried the exact Flash identity, every terminal
`modelUsage` contained the sole canonical first-party Flash participant, and
every builder checker passed. Earlier v1-v3 runs remain terminal and are not
relabelled. The installed routing JSON remains authoritative.
`delegation-evidence lane builder` shows the dated external rows: they provide
context, not a local harness score and not permission to widen the gate.

Write the self-contained worker brief to a file, then run:

```sh
delegation-glm run --lane <clerk|scout> --effort auto \
  --backend auto --prompt-file "$brief" --output "$result" --workdir "$repo"

delegation-glm run --lane builder --effort auto --allow-provisional \
  --backend auto --prompt-file "$brief" --output "$result" --workdir "$repo"
```

The isolated Claude→Z.AI backend needs a key: `ZAI_API_KEY` in the environment,
else the 600-mode key the installer stored. Keep `--effort auto` for ordinary
work so the max-only gate remains authoritative; another explicit effort is
refused (78).
The capability probe has a ten-second fail-closed timeout. For a deliberate
diagnostic with a separately verified native Claude Code binary, set
`DELEGATION_GLM_CLAUDE_BIN` to its absolute executable path; this changes
runtime provenance, so never use it to evade a failed capability check.
That flag also supports manifest-bound clerk/scout/builder qualification when
the versioned gate marks the lane evaluation-eligible, but
requires `--evaluation-manifest`; never use it for ordinary work.
Exit 69 means unavailable; exit 78 means the lane or effort did not pass
evaluation. Exit 70 means dispatch or result extraction failed; exit 75 means a
temporary provider or rate-limit failure. Every attempted dispatch failure writes
a sanitized `<output>.error.json` with a stable `phase` and `reason`, without
prompt, response, tool, or provider-message content. Inspect that file before
deciding whether to retry or escalate. Two 429 shapes are distinguished:
reason `rate_limited` (concurrency or request-rate pressure) is worth a
backed-off retry, while reason `quota_exhausted` carries the window-reset
epoch in `next_flush_time` and retrying before that instant is guaranteed
waste. Assume the coding-plan key allows roughly one in-flight request:
Z.AI publishes no concurrency number, community measurements on Pro found a
cap of 1, and the plan's own tiers only promise Max > Pro > Lite — so cap
parallel GLM workers at one per key unless you have measured your own tier.

Raw events and stderr are deleted by default. For a deliberate local diagnostic
run, pass an existing, non-symlink `--debug-dir <path>`; on failure the runner
creates a mode-700 child directory containing mode-600 artifacts. Treat them as
sensitive and never commit them. In every failure case, route deliberately to a
documented incumbent rather than pretending GLM ran. Treat all returned output
as unverified and exercise the deliverable before accepting it.
