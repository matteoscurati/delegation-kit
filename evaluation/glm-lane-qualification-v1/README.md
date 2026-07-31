# GLM-5.2 lane qualification contract

This directory defines the public, reusable protocol for qualifying the exact
`glm-5.2` / `claude-zai` / `high` tuple. It does not contain prompts, fixture
repositories, raw provider output, or results. Those artifacts may contain
downstream source material and remain under the ignored private `eval/` tree.

Every provider attempt is bound by a private manifest using
`delegation_glm_lane_evaluation_v1`. The manifest hashes the prompt, this
contract, the per-attempt output schema, the runner, the committed runner source, and the
committed fixture worktree. Its hash must appear in both a private copy of the
central gate and a private copy of the GLM executable gate. The public routing
files are changed only after the frozen aggregate has been checked against the
preregistered decision rule.

The three `output-schema-<lane>.json` files are the portable schemas used by
real comparisons. `output-schema.json` is the minimal common shape used by the
runner's transport test. All provider outputs are checked again by the scorer.

The comparison uses three independent attempts for GLM and both incumbents in
each lane. Clerk compares with Codex `luna-clerk`/`low` and Claude
`sonnet`/`low`; scout with `terra-scout`/`low` and `sonnet`/`low`; builder with
`terra-builder`/`medium` and `sonnet`/`medium`. A timeout, non-zero process exit,
missing required structured output, identity mismatch, permission violation, or
checker failure makes that attempt `VOID`. Observed attempts are never retried.

The bounded packs test extraction for clerk, repository tracing for scout, and
fixture edits plus deterministic checks for builder. Passing this protocol can
qualify only the named lane at the exact tuple. It is not evidence for reviewer,
judgement, policy annotation, another provider wrapper, or a broad claim about
the model family.
