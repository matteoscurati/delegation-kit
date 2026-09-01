#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/delegation-routing-tests.XXXXXX")"
trap 'rm -rf -- "$TMP"' EXIT

pass=0
expect_success() {
  "$@" >/dev/null 2>&1 || { printf 'expected success: %q ' "$@" >&2; printf '\n' >&2; exit 1; }
  pass=$((pass + 1))
}
expect_failure() {
  local expected="$1"; shift
  set +e
  "$@" >/dev/null 2>&1
  local actual=$?
  set -e
  [ "$actual" -eq "$expected" ] || {
    printf 'expected exit %s, got %s: ' "$expected" "$actual" >&2
    printf '%q ' "$@" >&2; printf '\n' >&2; exit 1
  }
  pass=$((pass + 1))
}

cd "$ROOT"
expect_success bin/delegation-route check --json
bin/delegation-glm check --json >"$TMP/glm-check.json"
jq -e '
  .model == "glm-5.3-flash" and
  .qualified_lanes == ["clerk","scout"] and
  .provisional_lanes == ["builder"] and
  .efforts == ["max"]
' "$TMP/glm-check.json" >/dev/null
pass=$((pass + 1))

# GLM-5.3-Flash/max is the sole executable gate and profile family.
env DELEGATION_GLM_ROUTING_FILE="$ROOT/config/glm-5.3-flash-max-routing.json" \
  DELEGATION_GLM_CLAUDE_BIN=/usr/bin/true \
  bin/delegation-glm check --json >"$TMP/glm53-flash-max-check.json"
jq -e '
  .model == "glm-5.3-flash" and .qualified_lanes == ["clerk","scout"] and
  .provisional_lanes == ["builder"] and .efforts == ["max"]
' "$TMP/glm53-flash-max-check.json" >/dev/null
pass=$((pass + 1))
[ ! -e config/glm-5.2-routing.json ] && [ ! -e config/glm-5.3-high-routing.json ] &&
  [ ! -e config/glm-5.3-max-routing.json ]
pass=$((pass + 1))
bin/delegation-route lane builder --json >"$TMP/builder-candidates.json"
jq -e '
  any(.[]; .profile == "glm53-flash-max-builder" and .status == "provisional" and .selection == "explicit-only") and
  all(.[]; (.model == "glm-5.2" or .model == "glm-5.3") | not)
' "$TMP/builder-candidates.json" >/dev/null
pass=$((pass + 1))

# Delegation is user-directed: there are no automatic/default/fallback routes,
# and a dispatch decision never carries to another dispatch implicitly.
jq -e '
  (.activation_policy.mode == "user-directed" and
   .activation_policy.scope == "per-dispatch" and
   .activation_policy.assistant_may_list_choices == true and
   .activation_policy.assistant_may_select_profile_only_when_user_authorizes_selection == true and
   .activation_policy.authorization_carries_to_retries == false and
   .activation_policy.authorization_carries_to_review == false and
   .activation_policy.automatic_dispatch == false and
   (.activation_policy.basis | type == "string" and length > 0)) and
  .selection_values == ["explicit-only", "blocked"] and
  all(.profiles[].lanes[];
      (.selection == "explicit-only" or .selection == "blocked") and
      (has("fallback") | not))
' config/routing-gates.json >/dev/null
pass=$((pass + 1))

for gate in \
  config/glm-5.3-flash-max-routing.json \
  config/kimi-k3-routing.json \
  config/gemini-3.7-flash-routing.json \
  config/grok-4.6-routing.json \
  config/qwen3.8-max-routing.json \
  config/deepseek-v4-pro-routing.json
do
  jq -e 'all(.lanes[].backends[];
    .selection == "explicit-only" or .selection == "blocked")' "$gate" >/dev/null
done
pass=$((pass + 1))

# The repository owns reusable qualification assets only. Downstream-project
# packs stay in their owning repository, and every central allowlist hash must
# resolve to a committed delegation-kit qualification manifest.
[ -z "$(find evaluation -maxdepth 1 -type d -name 'dipylon-ai-jury-*' -print -quit)" ]
git check-ignore -q --no-index evaluation/dipylon-ai-jury-v99/manifest.json
qualification_hashes="$TMP/qualification-manifest-hashes"
find evaluation/policy-annotation-qualification-v2 evaluation/policy-annotation-qualification-v3 \
  -type f -name 'manifest-*.json' -print0 |
  while IFS= read -r -d '' manifest; do
    shasum -a 256 "$manifest"
  done | awk '{print $1}' | sort -u >"$qualification_hashes"
while IFS= read -r manifest_hash; do
  grep -Fxq "$manifest_hash" "$qualification_hashes"
done < <(jq -r '.. | objects | .evaluation_manifest_sha256? // empty | .[]' config/routing-gates.json)
pass=$((pass + 1))

# Opus and Terra are high-level builders at max and also have separate read-only
# reviewer profiles at max. Sonnet and Luna remain non-builder lanes.
bin/delegation-route profile opus-builder --json >"$TMP/opus-builder.json"
jq -e '
  .model == "claude-opus-5" and .harness == "claude-code" and
  .effort == "max" and
  (.lanes | keys) == ["builder"] and
  .lanes.builder.status == "provisional" and
  .lanes.builder.selection == "explicit-only" and
  .lanes.builder.exact_evidence_ids == ["aa-claude-opus-5-max"] and
  .lanes.builder.local_evaluation.run_id == "2026-08-17-opus-builder-named-profile-smoke" and
  .lanes.builder.local_evaluation.all_checker_runs_pass == true
' "$TMP/opus-builder.json" >/dev/null
grep -Fxq 'model: claude-opus-5' agents/opus-builder.md
grep -Fxq 'effort: max' agents/opus-builder.md
[ ! -e agents/sonnet-builder.md ]
[ -e agents/opus-reviewer.md ]
grep -Fxq 'model: claude-opus-5' agents/opus-reviewer.md
grep -Fxq 'effort: max' agents/opus-reviewer.md
grep -Fxq 'tools: Read, Grep, Glob' agents/opus-reviewer.md
grep -Fq 'outside the Anthropic family' agents/opus-reviewer.md
[ ! -e codex/agents/terra-scout.toml ] && [ ! -e codex/profiles/terra-scout.config.toml ]
grep -Fxq 'model = "gpt-5.6-terra"' codex/agents/terra-builder.toml
grep -Fxq 'model_reasoning_effort = "max"' codex/agents/terra-builder.toml
grep -Fxq 'model_reasoning_effort = "max"' codex/profiles/terra-builder.config.toml
grep -Fxq 'model = "gpt-5.6-terra"' codex/agents/terra-reviewer.toml
grep -Fxq 'model_reasoning_effort = "max"' codex/agents/terra-reviewer.toml
grep -Fxq 'sandbox_mode = "read-only"' codex/agents/terra-reviewer.toml
grep -Fq 'outside the OpenAI model family' codex/agents/terra-reviewer.toml
grep -Fxq 'model_reasoning_effort = "max"' codex/profiles/terra-reviewer.config.toml
grep -Fxq 'sandbox_mode = "read-only"' codex/profiles/terra-reviewer.config.toml
pass=$((pass + 1))

# Builder routing is user-directed: no defaults, no fallbacks, only choices.
bin/delegation-route resolve --lane builder --json >"$TMP/builder-routing.json"
jq -e '
  .requires_user_direction == true and
  .automatic_dispatch == false and
  .selection_validated == false and
  .selected == null and
  ([.choices[].profile] | sort) ==
    ["deepseek-v4-pro","glm53-flash-max-builder","grok-build","kimi-k3",
     "opus-builder","qwen3.8-max","terra-builder"] and
  all(.choices[]; .selection == "explicit-only")
' "$TMP/builder-routing.json" >/dev/null
pass=$((pass + 1))

bin/delegation-route resolve --lane builder \
  --selected-profile terra-builder --json >"$TMP/selected-builder.json"
jq -e '
  .requires_user_direction == true and
  .automatic_dispatch == false and
  .selection_validated == true and
  .selected.profile == "terra-builder" and
  .selected.lane == "builder"
' "$TMP/selected-builder.json" >/dev/null
pass=$((pass + 1))

expect_failure 78 bin/delegation-route resolve --lane builder \
  --selected-profile sonnet-scout --json

# Scout presents the read-only scouts as choices, and Terra has no non-builder
# profile; Kimi remains selectable only through an explicit user decision.
bin/delegation-route resolve --lane scout --json >"$TMP/scout-routing.json"
jq -e '
  .requires_user_direction == true and
  ([.choices[].profile] | sort) ==
    ["glm53-flash-max-scout","kimi-k3","sonnet-scout"] and
  ([.choices[],.blocked[]] | all(.profile != "terra-scout"))
' "$TMP/scout-routing.json" >/dev/null
pass=$((pass + 1))

# Review resolution fails closed without producer identity.
expect_failure 64 bin/delegation-route resolve --lane material-review --json
expect_failure 64 bin/delegation-route resolve --lane security --json

# Terra/OpenAI output can be reviewed by Opus/Anthropic, never by Terra or Sol.
bin/delegation-route resolve --lane security --producer-profile terra-builder --json >"$TMP/security-routing.json"
jq -e '
  .requires_user_direction == true and
  ([.choices[].profile] | sort) == ["opus-reviewer"] and
  .choices[0].provider_fallback.possible == true and
  .choices[0].provider_fallback.target_model == "claude-opus-4.8" and
  .choices[0].provider_fallback.exact_variant_guaranteed == false and
  ([.excluded_same_family[].profile] | sort) == ["sol-reviewer","terra-reviewer"] and
  .review_policy.producer_family == "openai" and
  .review_policy.require_cross_family == true
' "$TMP/security-routing.json" >/dev/null
pass=$((pass + 1))

# No row-local fallback hints exist anywhere in the user-directed gates.
bin/delegation-route resolve --lane routine-review --producer-profile terra-builder --json >"$TMP/routine-routing.json"
jq -e '
  ([.choices[].profile] | sort) == ["opus-reviewer","sonnet-reviewer"] and
  all(.choices[]; .fallback == null) and
  ([.excluded_same_family[].profile] | sort) == ["sol-reviewer","terra-reviewer"]
' "$TMP/routine-routing.json" >/dev/null
pass=$((pass + 1))

# Provider-controlled model fallback must remain complete, explicit, and
# visible to route consumers even after the cross-family filter is applied.
jq '.profiles["opus-reviewer"].lanes.security.provider_fallback.exact_variant_guaranteed = true' \
  config/routing-gates.json >"$TMP/bad-provider-fallback.json"
expect_failure 65 env DELEGATION_ROUTING_GATES_FILE="$TMP/bad-provider-fallback.json" \
  bin/delegation-route check --json

# A review row that re-acquires a row-local fallback hint is refused: the
# property itself is forbidden under user-directed activation.
jq '.profiles["sonnet-reviewer"].lanes["routine-review"].fallback = "sol-reviewer"' \
  config/routing-gates.json >"$TMP/bad-review-fallback.json"
expect_failure 65 env DELEGATION_ROUTING_GATES_FILE="$TMP/bad-review-fallback.json" \
  bin/delegation-route check --json

# Opus/Anthropic output can be reviewed by Sol or Terra, never by Opus itself.
bin/delegation-route resolve --lane material-review --producer-profile opus-builder --json >"$TMP/opus-produced-review.json"
jq -e '
  ([.choices[].profile] | sort) == ["sol-reviewer","terra-reviewer"] and
  ([.excluded_same_family[].profile] == ["opus-reviewer"]) and
  .review_policy.producer_family == "anthropic"
' "$TMP/opus-produced-review.json" >/dev/null
pass=$((pass + 1))

# A third-family producer keeps every sufficiently advanced cross-family
# reviewer available as a choice, with no ranking attached.
bin/delegation-route resolve --lane material-review --producer-profile kimi-k3 --json >"$TMP/kimi-produced-review.json"
jq -e '
  ([.choices[].profile] | sort) == ["opus-reviewer","sol-reviewer","terra-reviewer"] and
  (.excluded_same_family | length) == 0 and
  .review_policy.producer_family == "moonshot" and
  .review_policy.availability_must_be_verified == true
' "$TMP/kimi-produced-review.json" >/dev/null
pass=$((pass + 1))

expect_failure 64 bin/delegation-route resolve --lane material-review --producer-profile not-a-profile --json
expect_failure 64 bin/delegation-route resolve --lane material-review --producer-family not-a-family --json
expect_failure 64 bin/delegation-route resolve --lane builder --producer-profile opus-builder --json

# Every profile model must have an explicit family, and every operational
# review profile must stay on the reviewer allowlist.
jq 'del(.model_families["claude-opus-5"])' config/routing-gates.json >"$TMP/missing-family.json"
expect_failure 65 env DELEGATION_ROUTING_GATES_FILE="$TMP/missing-family.json" bin/delegation-route check --json
jq '.review_policy.eligible_reviewer_profiles -= ["opus-reviewer"]' \
  config/routing-gates.json >"$TMP/missing-reviewer-allowlist.json"
expect_failure 65 env DELEGATION_ROUTING_GATES_FILE="$TMP/missing-reviewer-allowlist.json" bin/delegation-route check --json

# Illegal status/selection pairs must fail schema validation. Judgement is
# manual-qualified and may only pair with explicit-only; "default" is now
# outside the vocabulary entirely and must fail too.
jq '.profiles["kimi-k3"].lanes.judgement.selection = "default"' \
  config/routing-gates.json >"$TMP/bad-pair.json"
expect_failure 65 env DELEGATION_ROUTING_GATES_FILE="$TMP/bad-pair.json" \
  bin/delegation-route check --json

# Evaluation manifest allowlists normally belong only to policy-annotation.
# GLM qualification also permits private, central/executable-identical hashes
# for clerk/scout/builder while those routes remain provisional or candidate.
jq '.profiles["kimi-k3"].lanes["policy-annotation"].evaluation_manifest_sha256 = ["NOT-A-SHA"]' \
  config/routing-gates.json >"$TMP/bad-manifest-shape.json"
expect_failure 65 env DELEGATION_ROUTING_GATES_FILE="$TMP/bad-manifest-shape.json" \
  bin/delegation-route check --json
jq '.profiles["kimi-k3"].lanes["policy-annotation"].evaluation_manifest_sha256 =
      ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
       "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]' \
  config/routing-gates.json >"$TMP/duplicate-manifest.json"
expect_failure 65 env DELEGATION_ROUTING_GATES_FILE="$TMP/duplicate-manifest.json" \
  bin/delegation-route check --json
jq '.profiles["kimi-k3"].lanes.scout.evaluation_manifest_sha256 =
      ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]' \
  config/routing-gates.json >"$TMP/misplaced-manifest.json"
expect_failure 65 env DELEGATION_ROUTING_GATES_FILE="$TMP/misplaced-manifest.json" \
  bin/delegation-route check --json
jq '.profiles["glm53-flash-max-scout"].lanes.scout.evaluation_manifest_sha256 =
      ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"] |
    .profiles["glm53-flash-max-scout"].lanes.scout.status = "provisional" |
    .profiles["glm53-flash-max-scout"].lanes.scout.selection = "explicit-only"' \
  config/routing-gates.json >"$TMP/glm-lane-central.json"
jq '.lanes.scout.backends["claude-zai"].evaluation_manifest_sha256 =
      ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"] |
    .lanes.scout.backends["claude-zai"].status = "provisional" |
    .lanes.scout.backends["claude-zai"].qualified = false |
    .lanes.scout.backends["claude-zai"].selection = "explicit-only" |
    .qualified_lanes = ["clerk"] |
    .provisional_lanes = ["builder","scout"]' \
  config/glm-5.3-flash-max-routing.json >"$TMP/glm-lane-executable.json"
env DELEGATION_ROUTING_GATES_FILE="$TMP/glm-lane-central.json" \
  DELEGATION_GLM_ROUTING_FILE="$TMP/glm-lane-executable.json" \
  bin/delegation-route check --json >/dev/null
jq '.profiles["kimi-k3"].lanes["policy-annotation"].evaluation_manifest_sha256 =
      ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]' \
  config/routing-gates.json >"$TMP/central-only-manifest.json"
expect_failure 65 env DELEGATION_ROUTING_GATES_FILE="$TMP/central-only-manifest.json" \
  bin/delegation-route check --json

# An evidence row cannot be called exact when model+harness+effort differ.
jq '.profiles["fable-judge"].lanes.judgement.exact_evidence_ids = ["frontiercode-fable-5-xhigh"] |
    .profiles["fable-judge"].lanes.judgement.context_evidence_ids = []' \
  config/routing-gates.json >"$TMP/bad-exact.json"
expect_failure 65 env DELEGATION_ROUTING_GATES_FILE="$TMP/bad-exact.json" \
  bin/delegation-route check --json

# Exact variant identity is insufficient when the row lacks lane-required metrics.
jq '.profiles["sol-reviewer"].lanes["material-review"].exact_evidence_ids = ["aa-codex-gpt-5.6-sol-high"] |
    .profiles["sol-reviewer"].lanes["material-review"].context_evidence_ids = []' \
  config/routing-gates.json >"$TMP/bad-domain.json"
expect_failure 65 env DELEGATION_ROUTING_GATES_FILE="$TMP/bad-domain.json" \
  bin/delegation-route check --json

# The user-directed vocabulary rejects anything but explicit-only/blocked.
jq '.profiles["luna-clerk"].lanes.clerk.selection = "fallback"' \
  config/routing-gates.json >"$TMP/bad-selection.json"
expect_failure 65 env DELEGATION_ROUTING_GATES_FILE="$TMP/bad-selection.json" \
  bin/delegation-route check --json

# Executable gates are checked bidirectionally, including extra lanes and arrays.
jq '.lanes.reviewer.backends["claude-zai"] |=
      (.status = "qualified" | .selection = "explicit-only" | .qualified = true) |
    .qualified_lanes = ["reviewer"]' config/glm-5.3-flash-max-routing.json >"$TMP/bad-glm.json"
expect_failure 65 env DELEGATION_GLM_ROUTING_FILE="$TMP/bad-glm.json" \
  bin/delegation-route check --json

# Runners must refuse an invalid central gate before inspecting runtime/auth.
expect_failure 78 env DELEGATION_ROUTING_GATES_FILE="$TMP/bad-pair.json" \
  bin/delegation-glm check --json
expect_failure 78 env DELEGATION_ROUTING_GATES_FILE="$TMP/bad-pair.json" \
  bin/delegation-kimi check --json
expect_failure 78 env DELEGATION_ROUTING_GATES_FILE="$TMP/bad-pair.json" \
  bin/delegation-qwen check --json
expect_failure 78 env DELEGATION_ROUTING_GATES_FILE="$TMP/bad-pair.json" \
  bin/delegation-deepseek check --json
expect_failure 78 env DELEGATION_ROUTING_GATES_FILE="$TMP/bad-pair.json" \
  bin/delegation-gemini check --json
expect_failure 78 env DELEGATION_ROUTING_GATES_FILE="$TMP/bad-pair.json" \
  bin/delegation-grok check --json

# Every Qwen lane except builder is still a blocked candidate.
expect_failure 78 bin/delegation-qwen run --lane clerk --effort auto --backend auto \
  --prompt-file README.md --output "$TMP/qwen.txt" --workdir "$ROOT"
expect_failure 78 bin/delegation-qwen run --lane judgement --effort auto --backend auto \
  --allow-provisional --prompt-file README.md --output "$TMP/qwen-judge.txt" --workdir "$ROOT"

# Builder is provisional: explicit-only, and never dispatchable by default.
expect_failure 78 bin/delegation-qwen run --lane builder --effort auto --backend auto \
  --prompt-file README.md --output "$TMP/qwen-builder.txt" --workdir "$ROOT"
# With the explicit decision the gate allows it through and the run stops only
# at the runtime check (69), proving the refusal above was the gate and not a
# missing key.
expect_failure 69 env -u QWEN_TOKEN_PLAN_API_KEY \
  DELEGATION_QWEN_KEY_FILE="$TMP/absent-qwen-key.env" \
  bin/delegation-qwen run --lane builder --effort auto --backend auto \
  --allow-provisional --prompt-file README.md \
  --output "$TMP/qwen-builder-ok.txt" --workdir "$ROOT"
# --evaluation is a separate path and never rides on the provisional decision.
expect_failure 64 bin/delegation-qwen run --lane policy-annotation --effort auto \
  --backend auto --allow-provisional --evaluation \
  --evaluation-manifest "$TMP/absent-manifest.json" --prompt-file README.md \
  --output "$TMP/qwen-eval.txt" --workdir "$ROOT"

# DeepSeek V4 Pro/max mirrors the same text-only promotion discipline: only
# builder is provisional and an explicit decision reaches runtime/auth.
expect_failure 78 bin/delegation-deepseek run --lane scout --effort auto --backend auto \
  --prompt-file README.md --output "$TMP/deepseek-scout.txt" --workdir "$ROOT"
expect_failure 78 bin/delegation-deepseek run --lane builder --effort auto --backend auto \
  --prompt-file README.md --output "$TMP/deepseek-builder.txt" --workdir "$ROOT"
expect_failure 69 env -u DEEPSEEK_API_KEY \
  DELEGATION_DEEPSEEK_KEY_FILE="$TMP/absent-deepseek-key.env" \
  bin/delegation-deepseek run --lane builder --effort auto --backend auto \
  --allow-provisional --prompt-file README.md \
  --output "$TMP/deepseek-builder-ok.txt" --workdir "$ROOT"

# DeepSeek executable-gate drift is checked bidirectionally.
jq '.lanes.clerk.backends["deepseek-api"].status = "provisional" |
    .lanes.clerk.backends["deepseek-api"].selection = "explicit-only" |
    .provisional_lanes = ["clerk"]' config/deepseek-v4-pro-routing.json >"$TMP/bad-deepseek.json"
expect_failure 65 env DELEGATION_DEEPSEEK_ROUTING_FILE="$TMP/bad-deepseek.json" \
  bin/delegation-route check --json

# Qwen bridge drift is checked in both directions.
jq '.lanes.clerk.backends["token-plan-openai"].status = "provisional" |
    .lanes.clerk.backends["token-plan-openai"].selection = "explicit-only" |
    .provisional_lanes = ["clerk"]' config/qwen3.8-max-routing.json >"$TMP/bad-qwen.json"
expect_failure 65 env DELEGATION_QWEN_ROUTING_FILE="$TMP/bad-qwen.json" \
  bin/delegation-route check --json
jq '.lanes["policy-annotation"].backends["token-plan-openai"].evaluation_manifest_sha256 =
      ["bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"]' \
  config/qwen3.8-max-routing.json >"$TMP/bad-qwen-manifest.json"
expect_failure 65 env DELEGATION_QWEN_ROUTING_FILE="$TMP/bad-qwen-manifest.json" \
  bin/delegation-route check --json

# Kimi lane/effort drift is checked in both directions; CLI version is
# deliberately runtime provenance, not a routing decision.
jq '.lanes.scout.backends.native.effort = "high"' \
  config/kimi-k3-routing.json >"$TMP/bad-kimi.json"
expect_failure 65 env DELEGATION_KIMI_ROUTING_FILE="$TMP/bad-kimi.json" \
  bin/delegation-route check --json
jq '.lanes["policy-annotation"].backends.native.evaluation_manifest_sha256 =
      ["cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"]' \
  config/kimi-k3-routing.json >"$TMP/bad-kimi-manifest.json"
expect_failure 65 env DELEGATION_KIMI_ROUTING_FILE="$TMP/bad-kimi-manifest.json" \
  bin/delegation-route check --json

# Gemini bridge drift is checked in both directions.
jq '.lanes.scout.backends.agy.effort = "high"' \
  config/gemini-3.7-flash-routing.json >"$TMP/bad-gemini.json"
expect_failure 65 env DELEGATION_GEMINI_ROUTING_FILE="$TMP/bad-gemini.json" \
  bin/delegation-route check --json

# Grok bridge drift is checked in both directions.
jq '.lanes.builder.backends["grok-build"].effort = "max"' \
  config/grok-4.6-routing.json >"$TMP/bad-grok.json"
expect_failure 65 env DELEGATION_GROK_ROUTING_FILE="$TMP/bad-grok.json" \
  bin/delegation-route check --json
jq '.lanes["policy-annotation"].backends["grok-build"].evaluation_manifest_sha256 =
      ["dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"]' \
  config/grok-4.6-routing.json >"$TMP/bad-grok-manifest.json"
expect_failure 65 env DELEGATION_GROK_ROUTING_FILE="$TMP/bad-grok-manifest.json" \
  bin/delegation-route check --json

# GLM evaluation allowlist drift is checked independently from status drift.
jq '.lanes["policy-annotation"].backends["claude-zai"].evaluation_manifest_sha256 =
      ["eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"]' \
  config/glm-5.3-flash-max-routing.json >"$TMP/bad-glm-manifest.json"
expect_failure 65 env DELEGATION_GLM_ROUTING_FILE="$TMP/bad-glm-manifest.json" \
  bin/delegation-route check --json

# Grok CLI compatibility policy is mirrored centrally without naming a version.
jq '.runtime_cli_compatibility = "version-pinned"' \
  config/grok-4.6-routing.json >"$TMP/bad-grok-compatibility.json"
expect_failure 65 env DELEGATION_GROK_ROUTING_FILE="$TMP/bad-grok-compatibility.json" \
  bin/delegation-route check --json

# runtime_controls is descriptive metadata for the external-executor contract.
# The router must not read it: stripping it from every external gate changes no
# route decision, and the router still accepts the gate. (The contract command
# is the thing that refuses the stripped gate; that is asserted in
# tests/external-executor-contract.sh.)
bin/delegation-route table --json >"$TMP/route-table-before.json"
for gate in glm-5.3-flash-max-routing kimi-k3-routing grok-4.6-routing \
            qwen3.8-max-routing deepseek-v4-pro-routing gemini-3.7-flash-routing; do
  jq 'if has("lanes") then .lanes |= with_entries(
        .value.backends |= with_entries(.value |= del(.runtime_controls))) else . end' \
    "config/$gate.json" >"$TMP/stripped-$gate.json"
done
env DELEGATION_GLM_ROUTING_FILE="$TMP/stripped-glm-5.3-flash-max-routing.json" \
  DELEGATION_KIMI_ROUTING_FILE="$TMP/stripped-kimi-k3-routing.json" \
  DELEGATION_GROK_ROUTING_FILE="$TMP/stripped-grok-4.6-routing.json" \
  DELEGATION_QWEN_ROUTING_FILE="$TMP/stripped-qwen3.8-max-routing.json" \
  DELEGATION_DEEPSEEK_ROUTING_FILE="$TMP/stripped-deepseek-v4-pro-routing.json" \
  DELEGATION_GEMINI_ROUTING_FILE="$TMP/stripped-gemini-3.7-flash-routing.json" \
  bin/delegation-route check --json >/dev/null
env DELEGATION_GLM_ROUTING_FILE="$TMP/stripped-glm-5.3-flash-max-routing.json" \
  DELEGATION_KIMI_ROUTING_FILE="$TMP/stripped-kimi-k3-routing.json" \
  DELEGATION_GROK_ROUTING_FILE="$TMP/stripped-grok-4.6-routing.json" \
  DELEGATION_QWEN_ROUTING_FILE="$TMP/stripped-qwen3.8-max-routing.json" \
  DELEGATION_DEEPSEEK_ROUTING_FILE="$TMP/stripped-deepseek-v4-pro-routing.json" \
  DELEGATION_GEMINI_ROUTING_FILE="$TMP/stripped-gemini-3.7-flash-routing.json" \
  bin/delegation-route table --json >"$TMP/route-table-after.json"
cmp -s "$TMP/route-table-before.json" "$TMP/route-table-after.json" \
  || { printf 'runtime_controls metadata changed a route decision\n' >&2; exit 1; }
pass=$((pass + 1))

# Descriptive though it is, the isolation metadata must describe what the runner
# actually does. An ordinary delegation-glm dispatch redirects CLAUDE_CONFIG_DIR
# and leaves HOME as the caller's; only the evaluation path pins a temporary
# HOME. Every GLM row therefore states config-only isolation.
jq -e '
  [.lanes[].backends["claude-zai"].runtime_controls] as $rows |
  ($rows | length) == 5 and
  ($rows | all(.isolated_home == false and .isolated_config_dir == true))
' config/glm-5.3-flash-max-routing.json >/dev/null \
  || { printf 'a GLM gate row claims an isolated HOME the runner does not create\n' >&2; exit 1; }
[ "$(grep -c 'HOME="\$tmp/home"' bin/delegation-glm)" = 1 ] \
  || { printf 'delegation-glm HOME handling moved; recheck the isolation metadata\n' >&2; exit 1; }
pass=$((pass + 1))

# For a non-OpenAI/non-Anthropic producer, all three advanced reviewers stay
# selectable with no ranking, and Sol keeps its measured effort metadata.
bin/delegation-route resolve --lane material-review --producer-family deepseek --json >"$TMP/material-review.json"
jq -e '
  .requires_user_direction == true and
  ([.choices[].profile] | sort) == ["opus-reviewer","sol-reviewer","terra-reviewer"] and
  (first(.choices[] | select(.profile == "sol-reviewer")).model == "gpt-5.6-sol") and
  (first(.choices[] | select(.profile == "sol-reviewer")).effort == "high") and
  (first(.choices[] | select(.profile == "sol-reviewer")).status == "provisional") and
  (.review_policy.producer_family == "deepseek")
' "$TMP/material-review.json" >/dev/null
pass=$((pass + 1))

# Technical judgement stays a manual, explicit choice alongside Fable, and
# disabled/candidate profiles never leak into the choice set.
bin/delegation-route resolve --lane judgement --json >"$TMP/judgement.json"
jq -e '.requires_user_direction == true and
       ([.choices[].profile] | sort) == ["fable-judge","sol-judge"] and
       (first(.choices[] | select(.profile == "fable-judge")).model == "claude-fable-5-1") and
       (first(.choices[] | select(.profile == "fable-judge")).effort == "max") and
       (first(.choices[] | select(.profile == "sol-judge")).effort == "max") and
       (first(.choices[] | select(.profile == "sol-judge")).context_evidence_ids | index("aa-codex-gpt-5.6-sol-max") != null) and
       ([.blocked[].profile] | index("kimi-k3") != null) and
       ([.blocked[].profile] | index("qwen3.8-max") != null)' "$TMP/judgement.json" >/dev/null
grep -Fxq 'model_reasoning_effort = "max"' codex/agents/sol-judge.toml
grep -Fxq 'model_reasoning_effort = "max"' codex/profiles/sol-judge.config.toml
grep -Fxq 'effort: max' agents/fable-judge.md
grep -Fxq 'tools: Read, Grep, Glob' agents/fable-judge.md
grep -Fxq 'model: sonnet' agents/sonnet-reviewer.md
grep -Fxq 'effort: medium' agents/sonnet-reviewer.md
grep -Fxq 'tools: Read, Grep, Glob' agents/sonnet-reviewer.md
grep -Fq 'outside the Anthropic' agents/sonnet-reviewer.md
grep -Fxq 'model = "gpt-5.6-sol"' codex/agents/sol-reviewer.toml
grep -Fxq 'model = "gpt-5.6-sol"' codex/profiles/sol-reviewer.config.toml
grep -Fxq 'model_reasoning_effort = "high"' codex/agents/sol-reviewer.toml
grep -Fxq 'model_reasoning_effort = "high"' codex/profiles/sol-reviewer.config.toml
grep -Fxq 'sandbox_mode = "read-only"' codex/agents/sol-reviewer.toml
grep -Fxq 'sandbox_mode = "read-only"' codex/profiles/sol-reviewer.config.toml
grep -Fq 'outside the OpenAI model family' codex/agents/sol-reviewer.toml
grep -Fxq 'model = "gpt-5.6-sol"' codex/agents/sol-judge.toml
grep -Fxq 'model = "gpt-5.6-sol"' codex/profiles/sol-judge.config.toml
grep -Fxq 'sandbox_mode = "read-only"' codex/agents/sol-judge.toml
grep -Fxq 'sandbox_mode = "read-only"' codex/profiles/sol-judge.config.toml
pass=$((pass + 1))

# Policy annotation is candidate/blocked only, including separate exact-variant
# Opus and Sol-max profiles; it must never leak into an operational group.
bin/delegation-route resolve --lane policy-annotation --json >"$TMP/policy-annotation.json"
jq -e '
  (.choices | length) == 0 and
  ([.blocked[].profile] | sort) ==
    ["deepseek-v4-pro","fable-policy-annotator","glm53-flash-max-policy-annotation","grok-build","kimi-k3",
     "opus-policy-annotator","qwen3.8-max","sol-max-policy-annotator"]
' "$TMP/policy-annotation.json" >/dev/null
jq -e '
  .profiles["kimi-k3"].lanes.reviewer.status == "disabled" and
  .profiles["kimi-k3"].lanes.judgement.status == "disabled" and
  .profiles["qwen3.8-max"].lanes.judgement.status == "disabled"
  and .profiles["deepseek-v4-pro"].lanes.judgement.status == "disabled"
' config/routing-gates.json >/dev/null
pass=$((pass + 1))

# The generated table exposes exact and contextual evidence separately.
bin/delegation-route table --json >"$TMP/table.json"
jq -e '.profiles[] | select(.profile == "fable-judge" and .lane == "judgement") |
       (.exact_evidence_ids | length) == 1 and (.context_evidence_ids | length) == 3' \
  "$TMP/table.json" >/dev/null
jq -e '
  .review_policy.require_cross_family == true and
  .model_families["claude-opus-5"] == "anthropic" and
  .model_families["gpt-5.6-terra"] == "openai" and
  any(.profiles[]; .profile == "terra-reviewer" and .family == "openai")
' "$TMP/table.json" >/dev/null
pass=$((pass + 1))

printf 'routing gate tests: %s passed\n' "$pass"
