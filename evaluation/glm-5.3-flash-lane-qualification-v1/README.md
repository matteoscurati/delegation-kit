# GLM-5.3-Flash max lane qualification

This protocol evaluates the exact `glm-5.3-flash` / `claude-zai` / `max`
tuple before it may replace the shipped GLM-5.3 route. The frozen clerk,
scout, and builder packs used for the previous GLM qualifications are reused
so the replacement can be compared on the same deterministic tasks.

Each lane receives three no-retry attempts. Manifests bind the model, effort,
prompt, contract, schema, runner commit and bytes, fixture commit, permission
mode, timeout, and cost ceiling. A timeout, non-zero exit, missing structured
output, identity mismatch, permission violation, or failed builder checker
makes the observed attempt `VOID`.

Official launch evidence and the earlier `ox-alpha` diagnostic are contextual
only: the latter used a different OpenRouter transport. Only this exact local
pack can qualify the Claude-to-Z.AI route. Clerk and scout may become qualified
explicit-only if all thresholds pass; builder may become provisional
explicit-only. Reviewer, judgement, security, and policy annotation remain out
of scope.

Prompts, fixture repositories, raw streams, and per-attempt outputs stay in the
ignored private `eval/` tree. Only a minimal non-sensitive aggregate may be
published after every attempt has been scored.

## 2026-08-28 result

[`result-2026-08-28.json`](./result-2026-08-28.json) records the corrected v2
aggregate. All nine no-retry task attempts passed at score 1.0, every builder
checker passed, and provider-reported cost totaled $0.774166. Strict identity
is nevertheless `VOID`: retained evidence did not record separately surfaced
effective content identity or complete `modelUsage`, so no lane is promoted.
This does not establish what the provider originally exposed. The
earlier v1 attempt failed in the sandbox before any provider event and remains
a separate terminal `VOID`.

## 2026-08-29 identity probe

[`result-2026-08-29-v3.json`](./result-2026-08-29-v3.json) records one fresh
manifest-bound clerk attempt. It reached Z.AI and completed the task, but the
runner published no result because it expected a top-level result model. The
private stream showed the real identity shape instead: every assistant event
reported `message.model = glm-5.3-flash`, and the sole `modelUsage` participant
reported `canonicalModel = glm-5.3-flash` with `provider = firstParty`. No
classifier participant appeared. V3 remains terminal `VOID`; the corrected
parser requires a fresh v4 pack.

## 2026-08-29 qualification

[`result-2026-08-29-v4.json`](./result-2026-08-29-v4.json) records the final
exact pack. All nine no-retry attempts passed at score 1.0; all 204 assistant
events had complete Flash attribution; every terminal `modelUsage` contained
the sole canonical `glm-5.3-flash` participant with `provider=firstParty`; and
all builder checkers passed. Clerk and scout qualify explicit-only, while
builder becomes provisional explicit-only. V1-v3 remain terminal and are not
relabelled.
