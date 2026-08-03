---
name: qwen-executor
description: Dispatch the explicitly promoted Qwen3.8-Max builder lane through the isolated Token Plan runner, or inspect the still-blocked lanes. Never bypass its gate or silently change model, effort, or lane.
---

# Qwen3.8-Max executor

Pinned to `qwen3.8-max` through the Qwen Cloud Token Plan OpenAI-compatible
endpoint at `xhigh`. There is no provider, model, or effort fallback.

Run `delegation-qwen check --json` before dispatch.

## The builder lane

`builder` is **provisional and explicit-only**. It was promoted on an owner
routing decision after Qwen3.8-Max left preview and a local probe confirmed the
endpoint serves `qwen3.8-max` at `xhigh` — **not** on measured builder
capability. No DeepSWE or Terminal-Bench v2 row exists for this model on any
harness, so both builder required metrics are unmet. Dispatch needs an explicit
decision and `--allow-provisional`:

```sh
delegation-qwen run --lane builder --allow-provisional \
  --effort auto --backend auto --prompt-file "$brief" \
  --output "$result" --metrics "$metrics" --workdir "$repo"
```

Two constraints shape how you use it:

- **It cannot edit a worktree.** The transport is chat-completions only, with no
  tools and no terminal. Ask for a patch or complete file contents; the lead
  applies them and runs verification. Treat it as a strong text generator, not
  an autonomous editing agent like Grok Build or Kimi Code.
- **It is prompt-only.** Nothing about the repository reaches the model unless
  you put it in the brief. Embed the relevant file excerpts; paths alone are
  useless to it.

Output is unverified until the lead checks it — read the patch and exercise the
deliverable before it ships.

## Everything else stays blocked

`clerk`, `scout`, `reviewer`, `senior`, and `policy-annotation` are candidates;
`judgement` is disabled. Runtime availability, a Token Plan subscription, and a
successful smoke test do not qualify a lane. Never widen a lane silently, and
never substitute a neighbouring lane because builder was refused.

`--evaluation` is reserved for a manifest-bound `policy-annotation` evaluation
at the exact Qwen/`xhigh` tuple. It cannot be combined with
`--allow-provisional`, changes neither gate, adds no operational route, and does
not qualify broad architecture/trade-off judgement. The previously allowlisted
manifest was bound to the old `qwen3.8-max-preview` tuple and is void after the
rename; regenerate it before any evaluation run.
