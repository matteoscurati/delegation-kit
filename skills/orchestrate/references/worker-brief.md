# Worker brief format

Every worker dispatch is one bounded call — a Sonnet/Luna non-builder profile,
an Opus/Terra max-effort builder, or a gate-approved external runner such as
`delegation-grok` — carrying this brief.
The worker has no memory of the conversation and no follow-ups; it sees this
text and the working tree, nothing else.

**Inputs discipline.** Unlike a stateless API worker, our executors *share the
repo's working tree*, so reference in-tree files **by path** (`src/foo.ts:42`),
don't paste them. Anything the worker can't get from the tree — a decision made
in chat, an external constraint, the acceptance bar — must be **inline and
complete**. For code subtasks paste the entrypoint, file layout, and exact run
command, or the worker invents its own.

```
You are an executor completing ONE subtask of a larger project. This brief plus
the working tree is everything you get. No follow-ups are possible.

SUBTASK: <one-line goal>
INPUTS: <in-tree material by path; everything else inline and complete>
ACCEPTANCE CRITERIA (output fails if any fail):
1. <criterion — checkable, exercises the deliverable>
2. <criterion>
3. <criterion>
OUTPUT FORMAT: <exact structure, length, style; or "changed paths + checks run">

Rules: do only the subtask, no scope expansion, no editorializing. If an input is
missing or contradictory, write INPUT GAP plus one line naming it at the top, then
proceed with what you have. Return distilled evidence — changed paths, checks run,
unresolved risks — not raw logs or an essay.
```

Record the worker's exact producer profile in the orchestration state. The next
review dispatch must resolve a review lane with that profile; a self-review or a
sibling model from the same family is invalid.

**Redispatch rule (FIX).** When a result comes back FIX, send a **fresh** brief
that quotes the failed criterion and names the specific failure. Never continue
the old call — every dispatch is stateless. Two FIX rounds on the same subtask is
a commitment boundary: escalate the lane (small worker → builder → review/judgement), don't retry a third
time on the same worker.

**Lane mechanics.** Prefer the Workflow tool for real fan-out (deterministic
parallelism, schema returns, worktree isolation) and the Agent tool for a couple
of workers. Drop to raw `codex exec`/`claude -p` only to reach a different model
family — and when you do, harden the dispatch (brief on a temp file passed as a
quoted expansion, non-zero exit or empty output = failed dispatch, one output file
per parallel worker) per the bridge section of `CLAUDE.delegation.md`. For
external runners, resolve the lane first, obey the executor skill, and pass
`--allow-provisional` only after an explicit routing decision.
