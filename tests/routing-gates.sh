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

# The v3 Dipylon pack is immutable input to the four blocked evaluation-only
# lanes.  Its six files, canonical contract/schema pins, installer staging,
# and central/executable allowlists must move together.
[ "$(find evaluation/dipylon-ai-jury-v3 -maxdepth 1 -type f -name '*.json' | wc -l | tr -d ' ')" = 6 ]
[ "$(shasum -a 256 evaluation/dipylon-ai-jury-v3/contract.json | awk '{print $1}')" = "c14a4f90268c7c06331c4e6c959dabb9b6eb61e15ba79eedbde71a7a57d25024" ]
[ "$(shasum -a 256 evaluation/dipylon-ai-jury-v3/output-schema.json | awk '{print $1}')" = "def58aa8e751d4c51f530a25ec073c2cf3ec303c51f5170f7db83fbf65c31802" ]
qwen_v3="0ff9a95fd8178916e1938b19aebaf8f2b96a2232131ebfdb12d893917bd6dca9"
grok_v3="9e4d859533801db008dfdaed9d6203ac8da2623d9cb973179e972b9bb4e1aae0"
kimi_v3="2d971308304df41f48bedfce95673548c0d0ca603d92662c143cc4fe200ae410"
sol_v3="8755602701bd8324bfeb2351a65bdf2df4813057efae104ba17089aca5297a5d"
for manifest in evaluation/dipylon-ai-jury-v3/manifest-*.json; do
  jq -e '.lane == "policy-annotation" and .timeout_seconds == 600 and .max_output_chars == 65536 and .contract_sha256 == "c14a4f90268c7c06331c4e6c959dabb9b6eb61e15ba79eedbde71a7a57d25024" and .output_schema_sha256 == "def58aa8e751d4c51f530a25ec073c2cf3ec303c51f5170f7db83fbf65c31802"' "$manifest" >/dev/null
done
jq -e --arg q "$qwen_v3" --arg g "$grok_v3" --arg k "$kimi_v3" --arg s "$sol_v3" '
  (.profiles["qwen3.8-max-preview"].lanes["policy-annotation"].evaluation_manifest_sha256 | index($q)) and
  (.profiles["grok-build"].lanes["policy-annotation"].evaluation_manifest_sha256 | index($g)) and
  (.profiles["kimi-k3"].lanes["policy-annotation"].evaluation_manifest_sha256 | index($k)) and
  (.profiles["sol-max-policy-annotator"].lanes["policy-annotation"].evaluation_manifest_sha256 | index($s))
' config/routing-gates.json >/dev/null
jq -e --arg q "$qwen_v3" '(.lanes["policy-annotation"].backends["token-plan-openai"].evaluation_manifest_sha256 | index($q))' config/qwen3.8-max-preview-routing.json >/dev/null
jq -e --arg g "$grok_v3" '(.lanes["policy-annotation"].backends["grok-build"].evaluation_manifest_sha256 | index($g))' config/grok-4.5-routing.json >/dev/null
jq -e --arg k "$kimi_v3" '(.lanes["policy-annotation"].backends.native.evaluation_manifest_sha256 | index($k))' config/kimi-k3-routing.json >/dev/null
grep -Fq "EVAL_V3_PACK_SRC=\"\$KIT/evaluation/dipylon-ai-jury-v3\"" install.sh
grep -Fq "expected exactly 6 regular JSON files in \$EVAL_V3_PACK_SRC" install.sh
pass=$((pass + 1))

# The v4 pack is a separate frozen, evaluation-only successor to v3. Its raw
# canonical assets and four manifest hashes must remain bound to blocked lanes.
[ "$(find evaluation/dipylon-ai-jury-v4 -maxdepth 1 -type f -name '*.json' | wc -l | tr -d ' ')" = 6 ]
for pack_file in evaluation/dipylon-ai-jury-v4/{contract.json,output-schema.json,manifest-qwen3.8-max-preview.json,manifest-sol-max.json,manifest-grok-4.5.json,manifest-kimi-k3.json}; do
  [ -f "$pack_file" ] && [ ! -L "$pack_file" ]
done
[ "$(shasum -a 256 evaluation/dipylon-ai-jury-v4/contract.json | awk '{print $1}')" = "3f08a7d417f0e76c55a68b138808d47ad438e4c917ecdc62877dd7fd91dcf64b" ]
[ "$(shasum -a 256 evaluation/dipylon-ai-jury-v4/output-schema.json | awk '{print $1}')" = "12aec803f1949dd39b91712843ad20949bf60ec1d4bb1d68c8e3d2f02b05877a" ]
qwen_v4="4c28aa4fbf488d77cf80aeb2dd00652a356439bf9f9008b98490bd37d97674da"
sol_v4="7f274ac025066d40d6f2aac3dfbdc24fc4508c76067c72fe9f276530f58fa407"
grok_v4="fe7a2ab7575fe2a88f12d1e118e5bde26f6e85807d8baf39da18897055d60836"
kimi_v4="03eecda56793c82f8f1b2f86be9cf55010c594bb342fbe26e798f6ea2b5378b8"
[ "$(shasum -a 256 evaluation/dipylon-ai-jury-v4/manifest-qwen3.8-max-preview.json | awk '{print $1}')" = "$qwen_v4" ]
[ "$(shasum -a 256 evaluation/dipylon-ai-jury-v4/manifest-sol-max.json | awk '{print $1}')" = "$sol_v4" ]
[ "$(shasum -a 256 evaluation/dipylon-ai-jury-v4/manifest-grok-4.5.json | awk '{print $1}')" = "$grok_v4" ]
[ "$(shasum -a 256 evaluation/dipylon-ai-jury-v4/manifest-kimi-k3.json | awk '{print $1}')" = "$kimi_v4" ]
for manifest in evaluation/dipylon-ai-jury-v4/manifest-*.json; do
  jq -e '.lane == "policy-annotation" and .timeout_seconds == 600 and .max_output_chars == 65536 and .contract_path == "evaluation/dipylon-ai-jury-v4/contract.json" and .contract_sha256 == "3f08a7d417f0e76c55a68b138808d47ad438e4c917ecdc62877dd7fd91dcf64b" and .output_schema_path == "evaluation/dipylon-ai-jury-v4/output-schema.json" and .output_schema_sha256 == "12aec803f1949dd39b91712843ad20949bf60ec1d4bb1d68c8e3d2f02b05877a"' "$manifest" >/dev/null
done
jq -e --arg q "$qwen_v4" --arg g "$grok_v4" --arg k "$kimi_v4" --arg s "$sol_v4" '
  (.profiles["qwen3.8-max-preview"].lanes["policy-annotation"] | .status == "candidate" and .selection == "blocked" and (.evaluation_manifest_sha256 | index($q))) and
  (.profiles["grok-build"].lanes["policy-annotation"] | .status == "candidate" and .selection == "blocked" and (.evaluation_manifest_sha256 | index($g))) and
  (.profiles["kimi-k3"].lanes["policy-annotation"] | .status == "candidate" and .selection == "blocked" and (.evaluation_manifest_sha256 | index($k))) and
  (.profiles["sol-max-policy-annotator"].lanes["policy-annotation"] | .status == "candidate" and .selection == "blocked" and (.evaluation_manifest_sha256 | index($s)))
' config/routing-gates.json >/dev/null
jq -e --argjson central "$(jq -c '.profiles["qwen3.8-max-preview"].lanes["policy-annotation"].evaluation_manifest_sha256' config/routing-gates.json)" '.lanes["policy-annotation"].backends["token-plan-openai"].evaluation_manifest_sha256 == $central' config/qwen3.8-max-preview-routing.json >/dev/null
jq -e --argjson central "$(jq -c '.profiles["grok-build"].lanes["policy-annotation"].evaluation_manifest_sha256' config/routing-gates.json)" '.lanes["policy-annotation"].backends["grok-build"].evaluation_manifest_sha256 == $central' config/grok-4.5-routing.json >/dev/null
jq -e --argjson central "$(jq -c '.profiles["kimi-k3"].lanes["policy-annotation"].evaluation_manifest_sha256' config/routing-gates.json)" '.lanes["policy-annotation"].backends.native.evaluation_manifest_sha256 == $central' config/kimi-k3-routing.json >/dev/null
grep -Fq "EVAL_V4_PACK_SRC=\"\$KIT/evaluation/dipylon-ai-jury-v4\"" install.sh
grep -Fq "expected exactly 6 regular JSON files in \$EVAL_V4_PACK_SRC" install.sh
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
