---
name: glm-executor
description: >-
  Dispatch a gate-approved GLM-5.3 lane through delegation-glm. Qualified lanes
  remain explicit-only; provisional lanes require an explicit
  --allow-provisional decision. Never use it as a silent fallback.
---

# GLM-5.3 executor bridge

GLM-5.3 is an optional external executor, not a native Claude or Codex model.
Before dispatch, run `delegation-glm check --json`. The current gate exposes
`clerk` and `scout` in `qualified_lanes`, but keeps them explicit-only rather
than making either an automatic default. `builder` is provisional after its
first exact local pack; use it only after an explicit decision and pass
`--allow-provisional`. Every operational lane is pinned to `max`; the evaluated
`high` tuple remains blocked after one builder attempt failed to modify its
fixture. Reviewer is disabled; policy annotation is candidate/blocked and may
run only through a separately allowlisted evaluation manifest.

Builder scope limit: the bridge dispatches the delegate at
`--permission-mode acceptEdits` with no settings sources, so it can only apply
in-workdir Edit/Write changes. It cannot execute shell commands — `pnpm`,
`node`, or any Bash call is denied in print mode — and the harness refuses
writes to files it treats as sensitive, such as `.npmrc`. Environment or
toolchain fixes that need exactly those actions are not routable to this lane;
the lead closes them. Observed 2026-08-04: a toolchain dispatch returned
analysis only (checks honestly marked unexecuted) for $0.88 and ~6.6 minutes.

The frozen 2026-08-14 comparison ran three no-retry attempts per lane at both
`high` and `max`. Max scored 1.0 in every lane and passed every builder checker;
clerk and scout qualified explicit-only, while builder stops at provisional.
Compared with the historical GLM-5.2/high pack it preserved quality while
roughly halving total elapsed time and provider-reported cost. Reviewer is not
dispatchable. The installed routing JSON remains
authoritative if a later versioned evaluation changes that set.
`delegation-evidence lane builder` shows the dated external rows: they provide
context, not a local harness score and not permission to widen the gate.

Write the self-contained worker brief to a file, then run:

```sh
delegation-glm run --lane <clerk|scout> --effort auto \
  --backend auto --prompt-file "$brief" --output "$result" --workdir "$repo"

delegation-glm run --lane builder --effort auto --allow-provisional \
  --backend auto --prompt-file "$brief" --output "$result" --workdir "$repo"
```

`auto` and `claude-zai` both resolve to the isolated Claude→Z.AI backend, which
needs a key: `ZAI_API_KEY` in the environment, else the 600-mode key the
installer stored. Keep `--effort auto`; an explicit effort the gate did not pin
is refused (78), and only an `--evaluation` run may measure a new combination.
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
