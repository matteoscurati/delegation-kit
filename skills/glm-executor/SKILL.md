---
name: glm-executor
description: >-
  Dispatch a gate-approved GLM-5.2 lane through delegation-glm. Provisional
  lanes require an explicit --allow-provisional decision. Never use it before
  the evaluation gate or as a silent fallback.
---

# GLM-5.2 executor bridge

GLM-5.2 is an optional external executor, not a native Claude or Codex model.
Before dispatch, run `delegation-glm check --json`. The current gate exposes
`clerk` and `scout` only in `provisional_lanes`; use them only after an explicit
decision and pass `--allow-provisional`. Builder is a blocked candidate.
`policy-annotation` at `high` is candidate/blocked and may be used only by a
pre-registered allowlisted evaluation manifest. It is read-only, cannot promote
itself, and does not qualify the general judgement lane.

The small local run is compatibility evidence, not enough for full qualification.
Builder and reviewer are not dispatchable. The installed routing JSON remains
authoritative if a later versioned evaluation changes that set.
`delegation-evidence lane builder` shows the dated external rows: they provide
context, not a local harness score and not permission to widen the gate.

Write the self-contained worker brief to a file, then run:

```sh
delegation-glm run --lane <clerk|scout> --effort auto --allow-provisional \
  --backend auto --prompt-file "$brief" --output "$result" --workdir "$repo"
```

`auto` and `claude-zai` both resolve to the isolated Claude→Z.AI backend, which
needs a key: `ZAI_API_KEY` in the environment, else the 600-mode key the
installer stored. Keep `--effort auto`; an explicit effort the gate did not pin
is refused (78), and only an `--evaluation` run may measure a new combination.
That flag is reserved for `policy-annotation` and requires
`--evaluation-manifest`; never use it for ordinary work.
Exit 69 means unavailable; exit 78 means the lane or effort did not pass
evaluation. Exit 70 means dispatch or result extraction failed; exit 75 means a
temporary provider or rate-limit failure. Every attempted dispatch failure writes
a sanitized `<output>.error.json` with a stable `phase` and `reason`, without
prompt, response, tool, or provider-message content. Inspect that file before
deciding whether to retry or escalate.

Raw events and stderr are deleted by default. For a deliberate local diagnostic
run, pass an existing, non-symlink `--debug-dir <path>`; on failure the runner
creates a mode-700 child directory containing mode-600 artifacts. Treat them as
sensitive and never commit them. In every failure case, route deliberately to a
documented incumbent rather than pretending GLM ran. Treat all returned output
as unverified and exercise the deliverable before accepting it.
