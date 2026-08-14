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
aggregate. `max` completed all nine attempts with score 1.0 in every lane and
all builder checkers passing. `high` completed clerk and scout, but one builder
attempt claimed the intended path without changing the fixture; that observed
attempt is `VOID`, so `high` is not eligible.

The preregistered rule therefore selects `max`. Against the historical
GLM-5.2/high pack, GLM-5.3/max preserves the 1.0 lane scores while reducing
total elapsed time from 976 to 487 seconds and provider-reported cost from
$1.159437 to $0.622429. Clerk and scout qualify explicit-only; builder remains
provisional explicit-only after the bounded synthetic pack.
