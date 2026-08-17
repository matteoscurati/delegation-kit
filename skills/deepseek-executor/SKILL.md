---
name: deepseek-executor
description: Dispatch the explicitly promoted DeepSeek V4 Pro builder lane through the official API at max effort. Never bypass its gate or silently change model, effort, backend, or lane.
---

# DeepSeek V4 Pro executor

Use this skill only after an explicit decision to select the provisional
`builder` lane. The runner is pinned to `deepseek-v4-pro` through the official
OpenAI-compatible API with `reasoning_effort=max`; it has no provider, model, or
effort fallback.

Run `delegation-deepseek check --json` first. Then dispatch with:

```sh
delegation-deepseek run --lane builder --allow-provisional \
  --effort auto --backend auto --prompt-file "$brief" \
  --output "$result" --metrics "$metrics" --workdir "$repo"
```

The lane is text-only. It cannot inspect or edit the worktree and has no tools
or terminal, so the brief must contain every relevant file excerpt and require
a complete patch. For a unified diff, explicitly require `--- a/<path>` and
`+++ b/<path>` headers. The lead applies the patch, reviews it, and runs all
verification; successful provider output is never proof that the change works.

This route is provisional because one live deterministic patch smoke proved
only exact provider identity, `max` effort acceptance, structured output, and a
correct off-by-one fix. It was not a held-out repeated builder pack. The
provider's Terminal-Bench result uses another harness, and no DeepSWE row exists
for this exact route.

`clerk`, `scout`, `reviewer`, `senior`, and `policy-annotation` remain blocked
candidates; `judgement` is disabled. Never substitute one of them when builder
is refused. Exit 69 means the API key/runtime is unavailable, 70 means provider
or output validation failed, 75 means a temporary provider failure, and 78 is a
routing refusal. Raw provider data is retained only with an explicit private
`--debug-dir`.

The API key is read from `DEEPSEEK_API_KEY` or the mode-600 key file selected by
`DELEGATION_DEEPSEEK_KEY_FILE`. Do not copy credentials from another tool
silently.
