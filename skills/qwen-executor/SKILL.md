---
name: qwen-executor
description: Inspect and, only after qualification, dispatch Qwen3.8 Max Preview through the isolated Token Plan runner. Never bypass its candidate gate.
---

# Qwen3.8 Max Preview executor

Qwen3.8 Max Preview is installed as a blocked candidate. Runtime availability,
a Token Plan subscription, and a successful smoke test do not qualify a lane.

Run `delegation-qwen check --json` before considering it. Normal dispatch is
allowed only after both `routing-gates.json` and the executable Qwen gate promote
the exact lane at the pinned effort. Never use `--evaluation` for ordinary work;
that flag exists only for manifest-bound `policy-annotation` evaluation at the
exact Qwen/xhigh tuple. It does not change either gate, add an operational
route, or qualify broad architecture/trade-off judgement.

The backend is pinned to `qwen3.8-max-preview` through the Token Plan
OpenAI-compatible endpoint. There is no provider, model, or effort fallback.
Every supported lane is read-only: the direct API returns an answer but cannot
edit a worktree. Treat output as unverified until the lead checks it.
