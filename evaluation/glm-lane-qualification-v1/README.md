# GLM-5.2 lane qualification contract

This directory defines the public, reusable protocol for qualifying the exact
`glm-5.2` / `claude-zai` / `high` tuple. It does not contain prompts, fixture
repositories, raw provider output, or per-attempt results. Those artifacts may
contain downstream source material and remain under the ignored private `eval/`
tree; only the minimal non-sensitive aggregate is published here.

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

## 2026-07-31 result

[`result-2026-07-31.json`](./result-2026-07-31.json) records the minimal public
aggregate for the final frozen v6 runner. GLM completed all three valid repeats
in every lane with mean score 1.0. It matched the best incumbent in each pack: clerk and
scout therefore move from provisional to qualified, retaining explicit-only
selection; builder moves only from candidate to provisional after its first
exact repeated pack. GLM scout latency was 151–254 seconds, materially slower
than both incumbents, so the result does not make it a default route.

Two transport preflights were invalidated before the first comparison: one
schema used an unsupported Draft 2020-12 identifier; the other was too generic
for Codex structured output. Neither reached its provider. Final review then
invalidated every v3 GLM attempt because the evaluation sandbox did not yet
isolate host reads or fully attest builder writes. V4 and v5 were pre-provider
runtime probes for the hardened sandbox and were also invalidated. V6 reran only
GLM after the material runner change, with prompts, fixtures, schemas, scorers,
and thresholds unchanged; the frozen v3 Codex and Claude incumbent attempts
were reused byte-for-byte. No v6 attempt was retried. Raw streams, prompts,
fixture repositories, and private allowlist copies remain ignored under `eval/`.

The Claude builder comparator completed one valid repeat. Its private wrapper
failed to enter the fixture for repeats 2 and 3 and wrote outside the disposable
worktree; both attempts are `VOID`, the artifact was quarantined, and neither
was retried. Builder's threshold comparison therefore uses the fully valid
Terra incumbent, which scored 1.0 across all three repeats.
