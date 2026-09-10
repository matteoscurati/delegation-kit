---
name: kimi-executor
description: Use only when the current user explicitly selects a Kimi lane or authorizes the lead to choose it from displayed choices. Never dispatch Kimi as an automatic fallback.
---

# kimi-executor

## User direction and selection

This skill grants no permission to dispatch. The current user must select the
profile and task, or explicitly authorize the lead to choose from displayed
choices. Authorization is per dispatch; retries, fallbacks, review and further
workers require their own explicit authorization. No automatic substitution.

Use `delegation-route resolve --lane LANE --json` to inspect `.choices`, then
`--selected-profile PROFILE` to validate the user's selection without dispatch.
Profiles come from `${XDG_CONFIG_HOME:-$HOME/.config}/delegation-kit/config.json`
or `DELEGATION_CONFIG_FILE`, never automatically from the project repository.
No benchmark or kit qualification is required to choose a profile.

Dispatch the chosen profile once using `delegation-run --profile PROFILE
--lane LANE --prompt-file FILE --output FILE --workdir DIR`. Output and receipt
paths must be new and outside the worktree. `--allow-provisional` is deprecated
and unnecessary. A provider's `check --json` reports the adapter's roles,
efforts, and runtime availability; its technical restrictions still apply.

Review follows the configuration: `optional` by default, `required` for any
compatible reviewer, `cross-family` for a different declared family. Required
review never grants permission for a second call. Keep the result pending if
authorization or a compatible reviewer is absent. The lead owns integration,
verification, and the final response. Never claim a requested-only model as
provider-reported, or provider-reported identity as independent certification.

## Native execution boundary

Retain the runner's isolated home, credential handling, enforced sandbox,
allowed tools, worktree restrictions and patch checks. A new model does not
change these permissions. Runtime unavailability is a stop, never permission
for another backend. Inspect the selected provider command's help for native
runtime prerequisites and diagnostic/evaluation options. Kimi implements only
clerk, scout, builder, frontend-builder and policy-annotation tool profiles.
