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
