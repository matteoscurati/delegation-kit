# GLM-5.3 high/max lane comparison

This protocol compares the exact `glm-5.3` / `claude-zai` tuples at `high`
and `max` without changing or relabelling the historical GLM-5.2 result. The
same frozen clerk, scout, and builder packs used for GLM-5.2 are reused so the
new attempts can be compared directly with the published 2026-07-31 baseline.

Every tuple receives three no-retry attempts per lane. Manifests bind the
model, effort, prompt, contract, schema, runner commit and bytes, fixture
commit, permission mode, timeout, and cost ceiling. A timeout, non-zero exit,
missing structured output, identity mismatch, permission violation, or failed
builder checker makes the observed attempt `VOID`.

Prompts, fixture repositories, raw streams, and per-attempt outputs remain in
the ignored private `eval/` tree. Only the contract and the final minimal,
non-sensitive aggregate are suitable for publication.

The comparison may choose an effort and qualify only the exact chosen tuple.
Clerk and scout may become qualified explicit-only if their thresholds pass;
builder can move only to provisional after this bounded synthetic pack.
Reviewer, judgement, security, and policy annotation are outside scope.

## 2026-08-14 result

[`result-2026-08-14.json`](./result-2026-08-14.json) records the minimal public
aggregate. Both `high` and `max` completed all nine attempts with score 1.0 in
every lane and all builder checkers passing on the same frozen runner. The
public result also records SHA-256 digests for the private comparison,
per-effort aggregates, scores, provenance, and manifests.

The preregistered rule selected `high`: it matched max's quality while
using 372 rather than 505 seconds and $0.334234 rather than $0.719138 of
provider-reported cost. Against the historical GLM-5.2/high pack, selected
GLM-5.3/high preserves the 1.0 lane scores while reducing total elapsed time
from 976 to 372 seconds and provider-reported cost from $1.159437 to $0.334234.
Clerk and scout qualify explicit-only; builder remains provisional explicit-only
after the bounded synthetic pack.

The owner later made a separate operational decision to ship only `max`, despite
high remaining the comparison's efficiency winner. GLM-5.2 and GLM-5.3/high
therefore have no executable gate or selectable profile. The exact final
max-only runner was requalified separately: all nine attempts again scored 1.0,
all builder checkers passed, and the public result binds that run's aggregate,
scores, provenance, and manifests by SHA-256. This establishes exact-runner
validity for max; it does not relabel max as the preregistered efficiency winner.
