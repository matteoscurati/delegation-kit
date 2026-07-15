---
name: glm-executor
description: >-
  Dispatch a qualified executor lane to GLM-5.2 through delegation-glm. Use
  only when model-routing selects GLM for clerk, scout, builder, or routine
  reviewer work and the local availability check reports that exact lane as
  qualified. Never use it before the evaluation gate or as a silent fallback.
---

# GLM-5.2 executor bridge

GLM-5.2 is an optional external executor, not a native Claude or Codex model.
Before dispatch, run `delegation-glm check --json` and require both an available
Claude/Codex host, an available backend, and the requested lane in
`qualified_lanes`.

The shipped 2026-07 gate enables `clerk` at `high` and `scout` at `max` on both
backends. It does not enable `builder` or `reviewer`. The installed routing JSON
remains authoritative if a later versioned evaluation changes that set.

Write the self-contained worker brief to a file, then run:

```sh
delegation-glm run --lane <clerk|scout|builder|reviewer> --effort auto \
  --backend auto --prompt-file "$brief" --output "$result" --workdir "$repo"
```

`auto` prefers the Kilo Coding Plan backend and falls back to an isolated Claude
Code process only when `ZAI_API_KEY` is set. Exit 69 means unavailable; exit 78
means the lane did not pass evaluation. In either case, route deliberately to a
documented incumbent rather than pretending GLM ran. Treat all returned output
as unverified and exercise the deliverable before accepting it.
