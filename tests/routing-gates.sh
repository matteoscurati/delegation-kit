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

# The senior/taste/security profile is pinned to the exact current Opus model.
bin/delegation-route profile opus-reviewer --json >"$TMP/opus-reviewer.json"
jq -e '
  .model == "claude-opus-5" and .harness == "claude-code" and
  .effort == "high" and
  .lanes.senior.status == "manual-qualified" and
  (.lanes.senior.context_evidence_ids | index("anthropic-claude-opus-5-launch") != null) and
  .lanes.security.status == "manual-qualified" and
  .lanes.security.local_evaluation.run_id == "2026-07-25-claude-opus-5-security-smoke" and
  .lanes.security.provider_fallback.possible == true and
  .lanes.security.provider_fallback.target_model == "claude-opus-4.8" and
  .lanes.security.provider_fallback.exact_variant_guaranteed == false
' "$TMP/opus-reviewer.json" >/dev/null
grep -Fxq 'model: claude-opus-5' agents/opus-reviewer.md
grep -Fxq 'effort: high' agents/opus-reviewer.md
pass=$((pass + 1))

# Provider-controlled model fallback must remain visible to route consumers.
bin/delegation-route resolve --lane security --json >"$TMP/security.json"
jq -e '
  .explicit | length == 1 and
  .[0].model == "claude-opus-5" and
  .[0].provider_fallback.possible == true and
  .[0].provider_fallback.target_model == "claude-opus-4.8" and
  .[0].provider_fallback.exact_variant_guaranteed == false
' "$TMP/security.json" >/dev/null
pass=$((pass + 1))

# Provider fallback declarations must be complete and evidence-backed.
jq '.profiles["opus-reviewer"].lanes.security.provider_fallback.exact_variant_guaranteed = true' \
  config/routing-gates.json >"$TMP/bad-provider-fallback.json"
expect_failure 65 env DELEGATION_ROUTING_GATES_FILE="$TMP/bad-provider-fallback.json" \
  bin/delegation-route check --json

# Illegal status/selection pairs must fail schema validation.
jq '.profiles["kimi-k3"].lanes.judgement.selection = "explicit-only"' \
  config/routing-gates.json >"$TMP/bad-pair.json"
expect_failure 65 env DELEGATION_ROUTING_GATES_FILE="$TMP/bad-pair.json" \
  bin/delegation-route check --json

# Evaluation manifest allowlists belong only to policy-annotation, contain
# unique lowercase SHA-256 values, and remain central/executable-identical.
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
jq '.profiles["kimi-k3"].lanes["policy-annotation"].evaluation_manifest_sha256 =
      ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]' \
  config/routing-gates.json >"$TMP/central-only-manifest.json"
expect_failure 65 env DELEGATION_ROUTING_GATES_FILE="$TMP/central-only-manifest.json" \
  bin/delegation-route check --json

# An evidence row cannot be called exact when model+harness+effort differ.
jq '.profiles["fable-judge"].lanes.judgement.exact_evidence_ids = ["aa-claude-fable-5-max"] |
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

# Fallbacks must resolve to installed profile names.
jq '.profiles["luna-clerk"].lanes.clerk.fallback = "missing-profile"' \
  config/routing-gates.json >"$TMP/bad-fallback.json"
expect_failure 65 env DELEGATION_ROUTING_GATES_FILE="$TMP/bad-fallback.json" \
  bin/delegation-route check --json

# Executable gates are checked bidirectionally, including extra lanes and arrays.
jq '.lanes.reviewer.backends["claude-zai"] |=
      (.status = "qualified" | .selection = "explicit-only" | .qualified = true) |
    .qualified_lanes = ["reviewer"]' config/glm-5.2-routing.json >"$TMP/bad-glm.json"
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
  bin/delegation-gemini check --json
expect_failure 78 env DELEGATION_ROUTING_GATES_FILE="$TMP/bad-pair.json" \
  bin/delegation-grok check --json

# Qwen is installed as a blocked candidate and cannot dispatch normal work.
expect_failure 78 bin/delegation-qwen run --lane clerk --effort auto --backend auto \
  --prompt-file README.md --output "$TMP/qwen.txt" --workdir "$ROOT"

# Qwen bridge drift is checked in both directions.
jq '.lanes.clerk.backends["token-plan-openai"].status = "provisional" |
    .lanes.clerk.backends["token-plan-openai"].selection = "explicit-only" |
    .provisional_lanes = ["clerk"]' config/qwen3.8-max-preview-routing.json >"$TMP/bad-qwen.json"
expect_failure 65 env DELEGATION_QWEN_ROUTING_FILE="$TMP/bad-qwen.json" \
  bin/delegation-route check --json
jq '.lanes["policy-annotation"].backends["token-plan-openai"].evaluation_manifest_sha256 =
      ["bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"]' \
  config/qwen3.8-max-preview-routing.json >"$TMP/bad-qwen-manifest.json"
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
  config/gemini-3.6-flash-routing.json >"$TMP/bad-gemini.json"
expect_failure 65 env DELEGATION_GEMINI_ROUTING_FILE="$TMP/bad-gemini.json" \
  bin/delegation-route check --json

# Grok bridge drift is checked in both directions.
jq '.lanes.builder.backends["grok-build"].effort = "max"' \
  config/grok-4.5-routing.json >"$TMP/bad-grok.json"
expect_failure 65 env DELEGATION_GROK_ROUTING_FILE="$TMP/bad-grok.json" \
  bin/delegation-route check --json
jq '.lanes["policy-annotation"].backends["grok-build"].evaluation_manifest_sha256 =
      ["dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"]' \
  config/grok-4.5-routing.json >"$TMP/bad-grok-manifest.json"
expect_failure 65 env DELEGATION_GROK_ROUTING_FILE="$TMP/bad-grok-manifest.json" \
  bin/delegation-route check --json

# GLM evaluation allowlist drift is checked independently from status drift.
jq '.lanes["policy-annotation"].backends["claude-zai"].evaluation_manifest_sha256 =
      ["eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"]' \
  config/glm-5.2-routing.json >"$TMP/bad-glm-manifest.json"
expect_failure 65 env DELEGATION_GLM_ROUTING_FILE="$TMP/bad-glm-manifest.json" \
  bin/delegation-route check --json

# Grok CLI compatibility policy is mirrored centrally without naming a version.
jq '.runtime_cli_compatibility = "version-pinned"' \
  config/grok-4.5-routing.json >"$TMP/bad-grok-compatibility.json"
expect_failure 65 env DELEGATION_GROK_ROUTING_FILE="$TMP/bad-grok-compatibility.json" \
  bin/delegation-route check --json

# Disabled/candidate profiles never leak into explicit/fallback candidates.
bin/delegation-route resolve --lane judgement --json >"$TMP/judgement.json"
jq -e '([.explicit[].profile] | sort) == ["fable-judge","sol-judge"] and
       ([.blocked[].profile] | index("kimi-k3") != null) and
       ([.blocked[].profile] | index("qwen3.8-max-preview") != null)' "$TMP/judgement.json" >/dev/null
pass=$((pass + 1))

# Policy annotation is candidate/blocked only, including separate exact-variant
# Opus and Sol-max profiles; it must never leak into an operational group.
bin/delegation-route resolve --lane policy-annotation --json >"$TMP/policy-annotation.json"
jq -e '
  (.defaults | length) == 0 and (.fallbacks | length) == 0 and (.explicit | length) == 0 and
  ([.blocked[].profile] | sort) ==
    ["fable-policy-annotator","glm-policy-annotation","grok-build","kimi-k3",
     "opus-policy-annotator","qwen3.8-max-preview","sol-max-policy-annotator"]
' "$TMP/policy-annotation.json" >/dev/null
jq -e '
  .profiles["kimi-k3"].lanes.reviewer.status == "disabled" and
  .profiles["kimi-k3"].lanes.judgement.status == "disabled" and
  .profiles["qwen3.8-max-preview"].lanes.judgement.status == "disabled"
' config/routing-gates.json >/dev/null
pass=$((pass + 1))

# The generated table exposes exact and contextual evidence separately.
bin/delegation-route table --json >"$TMP/table.json"
jq -e '.profiles[] | select(.profile == "fable-judge" and .lane == "judgement") |
       (.exact_evidence_ids | length) == 0 and (.context_evidence_ids | length) == 2' \
  "$TMP/table.json" >/dev/null
pass=$((pass + 1))

printf 'routing gate tests: %s passed\n' "$pass"
