# Dual judgement: Fable + Sol

Use `super-judgement` only after an explicit decision and only for a highly
complex, high-blast-radius, difficult-to-reverse question with at least two
documented complexity triggers. The lead remains the final authority.

## Phase 1 — independent verdicts

Send the same evidence, constraints, and output contract to `fable-judge` and
`astra-judge`. Neither sees the other's answer. Each returns:

1. decision;
2. evidence used;
3. rejected alternatives;
4. risks and failure modes;
5. unresolved evidence;
6. conditions that would change the verdict;
7. required verification.

Fable emphasizes architecture, trade-offs, and synthesis. Sol emphasizes
repository fit, technical feasibility, failure modes, and verifiability.

## Phase 2 — cross-review

Only after both independent verdicts exist, give each the other's verdict. Ask
for: approved claims, contested claims, missing evidence, the most serious
unaddressed risk, and whether the verdict changes. Do not ask merely whether the
models agree.

## Phase 3 — lead synthesis

The lead records agreement, unresolved disagreement, accepted risks, required
checks, rollback conditions, and a final decision. A model may draft the
synthesis, but it may not erase an unresolved objection. No automatic dispatch,
merge, deploy, or ship decision is permitted.

## User direction is required

This reference grants no standing permission to call another model. Every
dispatch it describes must be part of the user-approved finite plan, and
authorization does not silently carry to retries, reviewers, or advisors.
