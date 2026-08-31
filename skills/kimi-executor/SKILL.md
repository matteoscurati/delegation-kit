---
name: kimi-executor
description: Use only when the current user explicitly selects a Kimi lane or authorizes the lead to choose it from displayed choices. Never dispatch Kimi as an automatic fallback.
---

# Kimi K3 executor bridge

## User direction is required

This skill grants no standing permission to call another model. The current user
must select the exact lane/profile, or explicitly authorize the lead to choose
from `delegation-route resolve` choices. Authorization is per dispatch and does
not silently carry to retries, reviewers, advisors, or additional workers.


Kimi K3 is an optional external executor available through native Kimi Code
(`kimi-code/k3`, effort `max`).

Before every dispatch, run `delegation-kimi check --json`. Require the native
backend and the requested lane in `provisional_lanes`, then pass
`--allow-provisional`. The gate permits `clerk`, `scout`, `builder`, and
`frontend-builder`; senior is blocked, while reviewer and judgement are disabled.
`policy-annotation` is candidate/blocked only for a manifest-bound evaluation
at the exact Kimi K3/max tuple; it never creates an operational route or
qualifies broad architecture/trade-off judgement.
Provider quota exhaustion is exit 69 and never
triggers a silent substitution.

The gate points to exact rows in the dated external snapshot. Inspect them with
`delegation-evidence lane <lane>`; they support the owner decision but never
replace the local runtime, scope, and permission checks enforced below.

Write a self-contained worker brief to a file, then run:

```sh
delegation-kimi run \
  --lane <clerk|scout|builder|frontend-builder> --allow-provisional \
  --backend auto --effort auto --prompt-file "$brief" \
  --output "$result" --metrics "$metrics" --workdir "$repo"
```

Create the output and metrics parent directories before dispatch. For every
read-only lane, keep them outside the worktree; the runner rejects in-worktree
paths, symlinks, canonical path collisions, and unqualified effort overrides.
Omit `--debug-dir` unless detailed vendor evidence is needed; when supplied, it
must already exist, be private, and stay outside the worktree. Credential-like
fields are redacted, but prompts and repository content remain sensitive. The public
`<output>.stderr` is only a sanitized one-line receipt, while
`<output>.error.json` is the canonical failure diagnostic.
There is no public evaluation bypass. `auto` and `native` both resolve to the
native Kimi Code backend; there is no fallback to select.

Every lane runs with an ephemeral `--agent-file`, a minimal isolated
`KIMI_CODE_HOME`/TMP, and a duplicated `[tools]` deny policy. `clerk` and `scout`
receive only `Read`, `Glob`, `Grep`, and `TodoList`; builders add `Write` and
`Edit`, and `frontend-builder` also receives `ReadMediaFile`. Web, MCP, skills,
subagents, cron, background tasks, Plan, and Bash stay disabled.
`delegation-kimi pin-rg` archives one verified ripgrep binary and its non-system
dependency digests. Each run copies those exact bytes into a separate
runner-owned, sandbox-unwritable exec directory, and the OS
sandbox permits process execution only for Kimi, `/usr/bin/true`, and that
precise `rg`. Shells, Git, and arbitrary executables remain blocked.
The child environment is an allowlist, ambient HOME file contents are
unreadable, and project `AGENTS.md` instructions remain part of the base prompt.
Because Kimi rotates the OAuth refresh token on every refresh, the default
mode serializes dispatches: the kit lock spans the whole run, and a concurrent
invocation fails fast with exit 75. For parallel workers, pass
`--oauth shared` (or set DELEGATION_KIMI_OAUTH_MODE=shared): OAuth state then
lives in a runner-owned generation under
`$DELEGATION_DATA_HOME/kimi-shared-oauth`, concurrent children coordinate
refreshes through the vendor CLI's own cross-process oauth lock — the
vendor-supported layout, account cap ~30 concurrent, one shared quota pool —
and the kit lock is held only briefly to seed the generation and publish it
back. In either mode the parent validates and atomically persists a changed
`credentials/kimi-code.json` and never exposes the ambient file to the model
process. Do not run `kimi login` concurrently with dispatch, and avoid driving
the ambient `kimi` CLI during shared-mode bursts: an external credential
replacement wins — the run returns exit 75 without publishing, and the next
shared dispatch reseeds from the ambient state. A shared-mode publish that
finds the kit lock busy is deferred to the next run, which is a success, not a
failure. Evaluation runs are always serialized.
CLI compatibility is determined from capabilities: the runtime must
expose `--agent-file`, `stream-json`, the exact `kimi-code/k3` model, OAuth
credentials, a valid isolated configuration, and `max` as both supported and
effective default effort. The observed CLI version is recorded only as
provenance. Upgrade the vendor CLI explicitly with `kimi update`; the
delegation-kit installer never updates it. Re-run `delegation-kimi pin-rg`
after deliberately changing the search runtime, adding `--force` only to
replace different archived bytes.

`clerk` and `scout` are filesystem-read-only: macOS `sandbox-exec` permits writes
only in runner-owned scratch. `builder` and `frontend-builder` may write only in
the canonical worktree plus scratch. All lanes fail closed without the OS guard,
and workdir cannot be `/` or the user's HOME. This is a filesystem and process
boundary, not a claim that model output is trusted; inspect every result and diff.

Operational runs time out after 900 seconds and emit sanitized heartbeats every
30 seconds with duration, event count, and last tool only. Evaluation runs keep
the timeout bound by their immutable manifest, up to 1200 seconds. `INT`/`TERM`
stop the child, perform the final OAuth sync, release the lock, and return 130.

Exit 69 means runtime, login, entitlement, or quota is unavailable; exit 70
means sandbox, output, or unclassified dispatch failure; exit 75 means overload,
5xx, timeout, or a temporary OAuth conflict (including a busy or superseded
shared OAuth session); exit 78 means the lane is not
authorized; and exit 130 is caller cancellation. Route deliberately to a
documented incumbent after any failure. Treat K3 output as unverified and
exercise the deliverable before accepting it.
