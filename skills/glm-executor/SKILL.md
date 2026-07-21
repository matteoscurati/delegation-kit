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
Exit 69 means unavailable; exit 78 means the lane or effort did not pass
evaluation. In either case, route deliberately to a documented incumbent rather
than pretending GLM ran. Treat all returned output as unverified and exercise the
deliverable before accepting it.
