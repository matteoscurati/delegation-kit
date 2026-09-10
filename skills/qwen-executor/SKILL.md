---
name: qwen-executor
description: Use only when the current user explicitly selects the Qwen text-patch builder or asks to inspect Qwen choices. Never dispatch Qwen automatically.
---

# qwen-executor

## User direction and selection

This skill grants no permission to dispatch. The current user must select the
profile and task, or explicitly authorize the lead to choose from displayed
choices. Authorization is per dispatch; retries, fallbacks, review and further
workers require their own explicit authorization. No automatic substitution.

Use `delegation-route resolve --lane LANE --json` to inspect `.choices`, then
`--selected-profile PROFILE` to validate the user's selection without dispatch.
Profiles come from `${XDG_CONFIG_HOME:-$HOME/.config}/delegation-kit/config.json`
or `DELEGATION_CONFIG_FILE`, never automatically from the project repository.
Evidence is advisory; missing or unfavorable benchmarks do not veto a choice.

Dispatch the chosen profile once using `delegation-run --profile PROFILE
--lane LANE --prompt-file FILE --output FILE --workdir DIR`. Output and receipt
paths must be new and outside the worktree. `--allow-provisional` is deprecated
and unnecessary. Use provider-specific commands for their diagnostic and
controlled evaluation options; their technical restrictions still apply.

Review follows the configuration: `optional` by default, `required` for any
compatible reviewer, `cross-family` for a different declared family. Required
review never grants permission for a second call. Keep the result pending if
authorization or a compatible reviewer is absent. The lead owns integration,
verification, and the final response. Never claim a requested-only model as
provider-reported, or provider-reported identity as independent certification.

## Text output boundary

The adapter cannot write directly to the worktree. Supply all context in the
prompt. For a builder task request a unified text patch, then inspect and apply
it with the existing `delegation-executor-contract` and
`delegation-patch-verify` workflow. A role does not confer filesystem access.
