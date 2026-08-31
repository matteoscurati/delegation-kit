# User-directed delegation guard (installed by delegation-kit)

## No standing permission to delegate

DelegationKit exposes optional Claude and Codex lanes and profiles, but their
presence grants no standing permission to delegate. Do not call Agent,
Workflow, `codex exec`, `claude -p`, or any `delegation-* run` command unless
the current user request explicitly asks for delegation.

A user may name the exact profile/lane and task, or explicitly authorize the
lead to choose from the available lane choices. Task complexity, an installed
skill, route ordering, a previous authorization, a failed attempt, or a desire
for extra review is not authorization.

Authorization is per dispatch. It does not carry to retries, fallback, review,
judgement, additional workers, or a later user message unless the user named
that finite set of calls in the current request. If another agent call is
needed, stop and ask.

Read-only discovery is allowed without dispatch:

```sh
delegation-route lane <lane> --json
delegation-route resolve --lane <lane> [--producer-profile <profile>] --json
```

Present `.choices` to the user. After the user selects a profile, validate it
with `--selected-profile <profile>`; this validation never dispatches and grants
nothing. A delegated result still requires eligible cross-family review before
shipping, but that reviewer call must also be user-authorized. If it is not,
pause and ask rather than spawning it automatically.

The lead owns integration, verification, and the final response. Never silently
substitute a profile, widen a lane, merge, deploy, or claim that provider output
is verified.
