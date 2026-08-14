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

