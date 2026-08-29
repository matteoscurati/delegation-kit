#!/usr/bin/env bash
# Fail-closed regression suite for the common external-executor contract.
#
# The contract describes what the six external executor families already do and
# lets a validator detect drift. This suite proves three things:
#   1. the contract covers every external routing row and agrees with both the
#      central gate and each executable gate,
#   2. the permission classes stay exactly three, mutually exclusive, and
#      consistent with each lane's declared worktree access, and
#   3. every way of getting it wrong fails closed rather than passing quietly.
#
# It never dispatches a model, never touches a real home, and never writes into
# this checkout.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/delegation-contract-tests.XXXXXX")"
trap 'rm -rf -- "$TMP"' EXIT

command -v jq >/dev/null 2>&1 || { printf 'jq is required\n' >&2; exit 69; }
cd "$ROOT"

CMD="bin/delegation-executor-contract"
CONTRACT="config/external-executor-contract.json"

pass=0
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
expect_success() {
  "$@" >/dev/null 2>&1 || { printf 'expected success: ' >&2; printf '%q ' "$@" >&2; printf '\n' >&2; exit 1; }
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
# Run check against a mutated copy of the contract.
with_contract() { # $1=file, rest=args
  local file="$1"; shift
  env DELEGATION_EXECUTOR_CONTRACT_FILE="$file" "$CMD" "$@"
}

# ---------------------------------------------------------------------------
# The shipped contract validates, including both gate cross-checks.
# ---------------------------------------------------------------------------
expect_success "$CMD" check
expect_success "$CMD" check --json
"$CMD" check --json >"$TMP/check.json"
jq -e '
  .valid == true and .read_only == true and
  .grants_permissions == false and
  .enforcement_authority == "provider-runner" and
  .contract_version == "1.0.0" and .schema_version == 1 and
  .families == 6 and .lane_declarations == 35 and
  .permission_classes == ["read-only","text-patch","worktree-edit"] and
  .exit_codes == [64,69,70,75,78,130] and
  (.runners | sort) == ["delegation-deepseek","delegation-gemini","delegation-glm",
                        "delegation-grok","delegation-kimi","delegation-qwen"]
' "$TMP/check.json" >/dev/null || fail 'check --json did not report the expected contract summary'
pass=$((pass + 1))

# Every declared runner is a command this repository actually ships.
while IFS= read -r runner; do
  [ -f "bin/$runner" ] || fail "contract names a runner this repo does not ship: $runner"
done < <(jq -r '.families[].runner' "$CONTRACT")
pass=$((pass + 1))

# The six current external executor families are all covered.
jq -e '(.families | keys | sort) ==
  ["deepseek-v4-pro","gemini-3.7-flash","glm-5.3-flash","grok-4.6","kimi-k3","qwen3.8-max"]' \
  "$CONTRACT" >/dev/null || fail 'the six external executor families are not all declared'
jq -e '[.families[].provider_family] | sort ==
  ["alibaba","deepseek","google","moonshot","xai","zai"]' "$CONTRACT" >/dev/null \
  || fail 'declared provider families are wrong'
pass=$((pass + 1))

# ---------------------------------------------------------------------------
# Permission classes: exactly three, exhaustive, mutually exclusive, and used
# consistently by every lane. Recomputed here rather than trusting the command.
# ---------------------------------------------------------------------------
jq -e '
  (.vocabularies.permission_classes | keys) == ["read-only","text-patch","worktree-edit"] and
  ([.vocabularies.permission_classes[] | [.worktree_writes,.returns_patch]] |
    length == (unique | length)) and
  ([.families[].lanes[].permission_class] - (.vocabularies.permission_classes | keys) | length == 0) and
  ([.families[].lanes[] |
    select(.permission_class == "worktree-edit") |
    select(.worktree_access != "read-write" or .tool_policy.write_scope != "workdir")] | length == 0) and
  ([.families[].lanes[] |
    select(.permission_class != "worktree-edit") |
    select(.worktree_access == "read-write" or .tool_policy.write_scope != "none")] | length == 0)
' "$CONTRACT" >/dev/null || fail 'permission classes are not exhaustive, exclusive, or consistently applied'
pass=$((pass + 1))

# Each class is actually used, so none of the three is dead vocabulary.
jq -e '([.families[].lanes[].permission_class] | unique) ==
  ["read-only","text-patch","worktree-edit"]' "$CONTRACT" >/dev/null \
  || fail 'a declared permission class is never used by any lane'
pass=$((pass + 1))

# Every lane declares every security-relevant control, with no null and no gap,
# and every executable gate row mirrors all ten of them.
jq -e '
  ([.families[].lanes[].tool_policy |
    select((keys | sort) != ["allowed_tools","mcp","mode","network","permission_mode",
                             "plugins","subagents","terminal","write_scope"])] | length == 0) and
  ([.families[].lanes[].tool_policy | .terminal, .network, .mcp, .plugins, .subagents |
    select((. | type) != "string")] | length == 0) and
  ((.executable_gate_controls.required_fields | sort) ==
    ["mcp","network","permission_mode","plugins","subagents","terminal","tools",
     "worktree_access","worktree_edits","write_scope"])
' "$CONTRACT" >/dev/null || fail 'a lane leaves a security-relevant control unstated'
for gate in glm-5.3-flash-max-routing kimi-k3-routing grok-4.6-routing \
            qwen3.8-max-routing deepseek-v4-pro-routing gemini-3.7-flash-routing; do
  jq -e --slurpfile contract "$CONTRACT" '
    ($contract[0].executable_gate_controls.required_fields) as $required |
    [.lanes[].backends[] |
      select((($required - ((.runtime_controls // {}) | keys)) | length) != 0)] | length == 0
  ' "config/$gate.json" >/dev/null \
    || fail "config/$gate.json has a lane row without complete runtime_controls"
done
pass=$((pass + 1))

# Isolation metadata states what the runner actually does. An ordinary
# delegation-glm dispatch redirects CLAUDE_CONFIG_DIR per run and leaves HOME as
# the caller's — only the evaluation path pins a temporary HOME — so every GLM
# row declares isolated_home false and isolated_config_dir true, and the family
# declaration says the same thing.
jq -e '.families["glm-5.3-flash"].runtime_isolation ==
  {isolated_home:false,isolated_config_dir:true,sandbox:null}' "$CONTRACT" >/dev/null \
  || fail 'the GLM family no longer declares config-only isolation'
jq -e '
  [.lanes[].backends["claude-zai"].runtime_controls] as $rows |
  ($rows | length) == 5 and
  ($rows | all(.isolated_home == false and .isolated_config_dir == true))
' config/glm-5.3-flash-max-routing.json >/dev/null \
  || fail 'a GLM gate row claims an isolated HOME the runner does not create'
# Every isolation claim a gate row does state is one its family declares.
for gate in glm-5.3-flash-max-routing kimi-k3-routing grok-4.6-routing \
            qwen3.8-max-routing deepseek-v4-pro-routing gemini-3.7-flash-routing; do
  jq -e --slurpfile contract "$CONTRACT" --arg gate "$gate.json" '
    ($contract[0].families | to_entries[] | select(.value.executable_gate == $gate) |
      .value) as $family |
    ($contract[0].executable_gate_controls.isolation_cross_checked_against | keys) as $fields |
    [.lanes[].backends[] | (.runtime_controls // {}) | . as $rc |
      $fields[] | . as $field | select($rc | has($field)) |
      select($rc[$field] !=
             (if ($family.runtime_isolation | has($field))
              then $family.runtime_isolation[$field] else null end))] | length == 0
  ' "config/$gate.json" >/dev/null \
    || fail "config/$gate.json states an isolation claim its family does not declare"
done
pass=$((pass + 1))

# ---------------------------------------------------------------------------
# Coverage: every external row in the central gate has a declaration, and every
# declaration resolves to the same central decision.
# ---------------------------------------------------------------------------
jq -s '{contract:.[0],central:.[1]}' "$CONTRACT" config/routing-gates.json >"$TMP/merged.json"
jq -e '
  .contract as $c | .central as $g |
  [$c.families[] | {model:.model, harness:.harness}] as $external |
  [$c.families | to_entries[] as $f | $f.value.lanes | to_entries[] |
    {profile:.value.central_profile, lane:.key}] as $declared |
  [$g.profiles | to_entries[] |
    select(.value as $p | any($external[]; .model == $p.model and .harness == $p.harness)) as $p |
    $p.value.lanes | keys[] | {profile:$p.key, lane:.}] as $central |
  (($central - $declared) | length) == 0 and (($declared - $central) | length) == 0 and
  ($declared | length) == 35
' "$TMP/merged.json" >/dev/null || fail 'contract and central gate do not cover the same external rows'
pass=$((pass + 1))

# Active, provisional and candidate lanes are all declared; blocked judgement,
# reviewer and policy-annotation lanes stay non-dispatchable.
jq -e '
  ([.families[].lanes[] | select(.dispatchable) |
    select(.status != "qualified" and .status != "provisional" and .status != "manual-qualified")] | length == 0) and
  ([.families[].lanes[] | select(.dispatchable) | select(.selection == "blocked")] | length == 0) and
  ([.families[] | .lanes | to_entries[] | .key as $lane | .value as $l |
    select(["judgement","reviewer","policy-annotation"] | index($lane) != null) |
    select($l.dispatchable or $l.selection != "blocked")] | length == 0) and
  ([.families[].lanes[] | select(.status == "provisional" and .dispatchable) |
    select(.requires_allow_provisional != true)] | length == 0)
' "$CONTRACT" >/dev/null || fail 'lane dispatchability or blocked-lane discipline is wrong'
pass=$((pass + 1))

# ---------------------------------------------------------------------------
# Read-only inspection subcommands.
# ---------------------------------------------------------------------------
expect_success "$CMD" families --json
expect_success "$CMD" family kimi-k3 --json
expect_success "$CMD" classes --json
expect_success "$CMD" exit-codes --json
expect_success "$CMD" table
expect_success "$CMD" table --json
expect_failure 64 "$CMD" family not-a-family
expect_failure 64 "$CMD" not-a-command
"$CMD" table --json >"$TMP/table.json"
jq -e 'length == 35 and
  any(.[]; .family == "grok-4.6" and .lane == "builder" and
           .permission_class == "worktree-edit" and .dispatchable == true) and
  any(.[]; .family == "qwen3.8-max" and .lane == "builder" and
           .permission_class == "text-patch" and .worktree_access == "none") and
  any(.[]; .family == "glm-5.3-flash" and .lane == "scout" and
           .permission_class == "read-only")' "$TMP/table.json" >/dev/null \
  || fail 'the declaration table lost a lane or a permission class'
pass=$((pass + 1))

# ---------------------------------------------------------------------------
# Envelope validation: real artifact shapes pass, wrong ones fail closed.
# ---------------------------------------------------------------------------
cat >"$TMP/grok-result.json" <<'EOF'
{"model":"grok-4.6","requested_model":"grok-4.6","runtime_model":"grok-4.6",
 "effective_content_model":"grok-4.6","exact_model_identity_attested":true,
 "usage_participants":[{"model":"grok-4.6-build","input_tokens":10,"output_tokens":20,
   "cache_read_tokens":0,"model_calls":1,"cost_usd":0.01}],
 "target_usage_participant_present":true,
 "backend":"grok-build","effort":"high","lane":"builder",
 "started_at_epoch":1756400000,"finished_at_epoch":1756400012,"duration_seconds":12,
 "tokens":{"input":10,"output":20},"provider_cost_usd":0.01,
 "sandbox":"delegation-kit","permission_mode":"dontAsk"}
EOF
expect_success "$CMD" validate --envelope result --file "$TMP/grok-result.json"
expect_success "$CMD" validate --envelope result --file "$TMP/grok-result.json" --family grok-4.6
"$CMD" validate --envelope result --file "$TMP/grok-result.json" --family grok-4.6 --json \
  >"$TMP/grok-result-check.json"
jq -e '.valid == true and .read_only == true and .family == "grok-4.6" and
  (.extension_fields | sort) == ["permission_mode","sandbox"]' \
  "$TMP/grok-result-check.json" >/dev/null \
  || fail 'provider extension fields were not reported as extensions'
pass=$((pass + 1))

# The prompt-only transports report no usage; null counters stay legal.
cat >"$TMP/gemini-result.json" <<'EOF'
{"model":"gemini-3.7-flash","runtime_model":"gemini-3.7-flash-high","backend":"agy",
 "effort":"high","lane":"builder","started_at_epoch":1756400000,
 "finished_at_epoch":1756400009,"duration_seconds":9,
 "tokens":null,"provider_cost_usd":null,"context_mode":"prompt_only"}
EOF
expect_success "$CMD" validate --envelope result --file "$TMP/gemini-result.json" --family gemini-3.7-flash

# Kimi reports its runtime model name; the family declaration accepts it.
cat >"$TMP/kimi-result.json" <<'EOF'
{"model":"kimi-code/k3","backend":"native","effort":"max","lane":"scout",
 "started_at_epoch":1756400000,"finished_at_epoch":1756400030,
 "usage_reported":false,"tokens":{"input":0,"output":0},"provider_cost_usd":null}
EOF
expect_success "$CMD" validate --envelope result --file "$TMP/kimi-result.json" --family kimi-k3

# GLM reports first-party per-model usage: the participant carries the optional
# canonical_model and provider names, both declared and both type-checked, and
# the runner's own aggregate/identity accounting rides along as extensions.
cat >"$TMP/glm-result.json" <<'EOF'
{"model":"glm-5.3-flash","requested_model":"glm-5.3-flash",
 "effective_content_model":"glm-5.3-flash","exact_model_identity_attested":true,
 "usage_participants":[{"model":"glm-5.3-flash","canonical_model":"glm-5.3-flash",
   "provider":"firstParty","input_tokens":1200,"output_tokens":340,"reasoning_tokens":0,
   "cache_read_tokens":80,"cache_write_tokens":0,"model_calls":3,"cost_usd":0.004978}],
 "target_usage_participant_present":true,"usage_source":"model_usage",
 "backend":"claude-zai","effort":"max","lane":"scout",
 "started_at_epoch":1756400000,"finished_at_epoch":1756400029,
 "tokens":{"input":1200,"output":340,"reasoning":0,"cache_read":80,"cache_write":0},
 "provider_cost_usd":0.004978,"provider_total_cost_usd":0.004978,
 "target_usage_identity_attested":true,
 "provider_aggregate_tokens":{"input":1200,"output":340}}
EOF
expect_success "$CMD" validate --envelope result --file "$TMP/glm-result.json" --family glm-5.3-flash

# The two optional participant identity fields are declared nullable, so a
# transport that reports no canonical name or provider marker stays valid —
# nullable means null, not "any type".
jq '.usage_participants[0] |= (.canonical_model = null | .provider = null)' \
  "$TMP/grok-result.json" >"$TMP/result-null-participant-identity.json"
expect_success "$CMD" validate --envelope result \
  --file "$TMP/result-null-participant-identity.json" --family grok-4.6

cat >"$TMP/status.json" <<'EOF'
{"model":"kimi-k3","efforts":["max"],"selected_backend":"none",
 "qualified_lanes":[],"provisional_lanes":["builder","clerk","scout","frontend-builder"],
 "backends":{"native":{"available":false,"reason":"runtime not installed"}},
 "runtime_cli_version":null,"runtime_cli_compatibility":"capability-probed",
 "terminal":false,"web_tools":false}
EOF
expect_success "$CMD" validate --envelope status --file "$TMP/status.json" --family kimi-k3

# Kimi's diagnostic carries only the universal minimum; that is a recorded
# divergence, so it passes the common envelope and fails a family that promises
# identity fields it does not emit.
cat >"$TMP/kimi-diagnostic.json" <<'EOF'
{"schema":"delegation_kimi_error_v1","phase":"dispatch","reason":"runtime_unavailable",
 "exit_code":69,"vendor_exit_code":1,"duration_seconds":3}
EOF
expect_success "$CMD" validate --envelope diagnostic --file "$TMP/kimi-diagnostic.json"
expect_success "$CMD" validate --envelope diagnostic --file "$TMP/kimi-diagnostic.json" --family kimi-k3
expect_failure 65 "$CMD" validate --envelope diagnostic --file "$TMP/kimi-diagnostic.json" \
  --family glm-5.3-flash
jq -e 'any(.known_divergences[]; .family == "kimi-k3" and .envelope == "diagnostic")' \
  "$CONTRACT" >/dev/null || fail 'the Kimi diagnostic divergence is not recorded'
pass=$((pass + 1))

# Missing required field, wrong type, unknown lane value, and bad input paths.
jq 'del(.provider_cost_usd)' "$TMP/grok-result.json" >"$TMP/result-missing.json"
expect_failure 65 "$CMD" validate --envelope result --file "$TMP/result-missing.json"
jq '.started_at_epoch = "recently"' "$TMP/grok-result.json" >"$TMP/result-badtype.json"
expect_failure 65 "$CMD" validate --envelope result --file "$TMP/result-badtype.json"
jq '.lane = "architect"' "$TMP/grok-result.json" >"$TMP/result-badlane.json"
expect_failure 65 "$CMD" validate --envelope result --file "$TMP/result-badlane.json"
printf 'not json\n' >"$TMP/not-json.json"
expect_failure 65 "$CMD" validate --envelope result --file "$TMP/not-json.json"
expect_failure 64 "$CMD" validate --envelope result
expect_failure 64 "$CMD" validate --file "$TMP/grok-result.json"
expect_failure 64 "$CMD" validate --envelope receipt --file "$TMP/grok-result.json"
expect_failure 64 "$CMD" validate --envelope result --file "$TMP/grok-result.json" --family not-a-family
expect_failure 64 "$CMD" validate --envelope result --file "$TMP/grok-result.json" --unknown-flag
expect_failure 66 "$CMD" validate --envelope result --file "$TMP/absent.json"

# Identity-shape mismatch: an artifact whose model is not this family's.
jq '.model = "gpt-5.6-terra" | .requested_model = "gpt-5.6-terra" |
    .effective_content_model = "gpt-5.6-terra"' "$TMP/grok-result.json" >"$TMP/result-wrong-model.json"
expect_failure 65 "$CMD" validate --envelope result --file "$TMP/result-wrong-model.json" --family grok-4.6
jq '.backend = "codex"' "$TMP/grok-result.json" >"$TMP/result-wrong-backend.json"
expect_failure 65 "$CMD" validate --envelope result --file "$TMP/result-wrong-backend.json" --family grok-4.6
jq '.effort = "low"' "$TMP/grok-result.json" >"$TMP/result-wrong-effort.json"
expect_failure 65 "$CMD" validate --envelope result --file "$TMP/result-wrong-effort.json" --family grok-4.6
jq '.selected_backend = "kilo"' "$TMP/status.json" >"$TMP/status-wrong-backend.json"
expect_failure 65 "$CMD" validate --envelope status --file "$TMP/status-wrong-backend.json" --family kimi-k3

# ---------------------------------------------------------------------------
# Identity and accounting: an artifact can be well-formed and still lie about
# who ran, who was billed, and what it cost. Each field is mutated on its own.
# ---------------------------------------------------------------------------
# The reviewer's malicious Grok-shaped artifact: no participant at all, yet it
# asserts the target participated and that identity was attested. Every claim
# is well-typed; every claim is false.
cat >"$TMP/grok-false-accounting.json" <<'EOF'
{"model":"grok-4.6","requested_model":"grok-4.6","runtime_model":"grok-4.6",
 "effective_content_model":"grok-4.6","exact_model_identity_attested":true,
 "usage_participants":[],"target_usage_participant_present":true,
 "backend":"grok-build","effort":"high","lane":"builder",
 "started_at_epoch":1756400000,"finished_at_epoch":1756400012,"duration_seconds":12,
 "tokens":{"input":10,"output":20},"provider_cost_usd":0.01}
EOF
expect_failure 65 "$CMD" validate --envelope result --file "$TMP/grok-false-accounting.json" \
  --family grok-4.6

mutate_result_fails() { # $1=family, $2=source artifact, $3=jq mutation
  local family="$1" src="$2" filter="$3" out
  out="$TMP/mutated-$(printf '%s' "$filter" | cksum | tr -d ' /').json"
  jq "$filter" "$src" >"$out"
  expect_failure 65 "$CMD" validate --envelope result --file "$out" --family "$family"
}

# Participation is claimed without a participant, or by the wrong participant.
mutate_result_fails grok-4.6 "$TMP/grok-result.json" '.usage_participants = []'
mutate_result_fails grok-4.6 "$TMP/grok-result.json" '.usage_participants[0].model = "grok-4.6"'
mutate_result_fails grok-4.6 "$TMP/grok-result.json" '.target_usage_participant_present = false'
# The billing identity is reported as the model that wrote the content.
mutate_result_fails grok-4.6 "$TMP/grok-result.json" '.effective_content_model = "grok-4.6-build"'
# Identity is attested without the effective-content model that substantiates it.
mutate_result_fails grok-4.6 "$TMP/grok-result.json" 'del(.effective_content_model)'
mutate_result_fails grok-4.6 "$TMP/grok-result.json" '.effective_content_model = "gpt-5.6-terra"'
mutate_result_fails grok-4.6 "$TMP/grok-result.json" '.requested_model = "grok-4.7"'
mutate_result_fails grok-4.6 "$TMP/grok-result.json" '.runtime_model = "grok-4.7"'
# Participant objects are a closed shape: named, declared keys, nonnegative.
mutate_result_fails grok-4.6 "$TMP/grok-result.json" '.usage_participants[0].billing_note = "x"'
mutate_result_fails grok-4.6 "$TMP/grok-result.json" 'del(.usage_participants[0].model)'
mutate_result_fails grok-4.6 "$TMP/grok-result.json" '.usage_participants[0].input_tokens = -3'

# ...and closed by type, not only by key name. A declared type is enforced on
# every field a participant actually carries, so a counter cannot arrive as a
# string and be read as a zero, and a nullable identity field cannot arrive as
# a number or a list. Each field is mutated on its own, then all at once.
mutate_result_fails grok-4.6 "$TMP/grok-result.json" '.usage_participants[0].canonical_model = 5'
mutate_result_fails grok-4.6 "$TMP/grok-result.json" '.usage_participants[0].provider = []'
mutate_result_fails grok-4.6 "$TMP/grok-result.json" '.usage_participants[0].input_tokens = "ten"'
mutate_result_fails grok-4.6 "$TMP/grok-result.json" '.usage_participants[0].output_tokens = null'
mutate_result_fails grok-4.6 "$TMP/grok-result.json" '.usage_participants[0].cache_read_tokens = false'
mutate_result_fails grok-4.6 "$TMP/grok-result.json" '.usage_participants[0].model_calls = "1"'
mutate_result_fails grok-4.6 "$TMP/grok-result.json" '.usage_participants[0].cost_usd = "free"'
mutate_result_fails grok-4.6 "$TMP/grok-result.json" '.usage_participants[0].model = ""'
mutate_result_fails glm-5.3-flash "$TMP/glm-result.json" '.usage_participants[0].canonical_model = 5'
mutate_result_fails glm-5.3-flash "$TMP/glm-result.json" '.usage_participants[0].cost_usd = "free"'
# The reviewer probe: one participant, four wrongly typed fields, every other
# claim well-formed. It must fail on the types alone.
cat >"$TMP/result-wrong-participant-types.json" <<'EOF'
{"model":"grok-4.6","requested_model":"grok-4.6","runtime_model":"grok-4.6",
 "effective_content_model":"grok-4.6","exact_model_identity_attested":true,
 "usage_participants":[{"model":"grok-4.6-build","canonical_model":5,"provider":[],
   "input_tokens":"ten","output_tokens":20,"cache_read_tokens":0,"model_calls":1,
   "cost_usd":"free"}],
 "target_usage_participant_present":true,
 "backend":"grok-build","effort":"high","lane":"builder",
 "started_at_epoch":1756400000,"finished_at_epoch":1756400012,"duration_seconds":12,
 "tokens":{"input":10,"output":20},"provider_cost_usd":0.01}
EOF
expect_failure 65 "$CMD" validate --envelope result \
  --file "$TMP/result-wrong-participant-types.json" --family grok-4.6
expect_failure 65 "$CMD" validate --envelope result \
  --file "$TMP/result-wrong-participant-types.json"

# The token counter object is typed the same way: every counter it carries must
# be a nonnegative number of the declared counter type.
mutate_result_fails grok-4.6 "$TMP/grok-result.json" '.tokens.input = "ten"'
mutate_result_fails grok-4.6 "$TMP/grok-result.json" '.tokens.output = null'
mutate_result_fails grok-4.6 "$TMP/grok-result.json" '.tokens.cache_read = {}'
mutate_result_fails grok-4.6 "$TMP/grok-result.json" '.tokens.total = "0"'
mutate_result_fails glm-5.3-flash "$TMP/glm-result.json" '.tokens.cache_read = "80"'
mutate_result_fails kimi-k3 "$TMP/kimi-result.json" '.tokens.input = "0"'
# The same counter typing applies without a --family argument.
jq '.tokens.input = "ten"' "$TMP/grok-result.json" >"$TMP/result-string-token.json"
expect_failure 65 "$CMD" validate --envelope result --file "$TMP/result-string-token.json"

# Nonnegative counters, ordered timestamps, and an honest duration.
mutate_result_fails grok-4.6 "$TMP/grok-result.json" '.provider_cost_usd = -0.01'
mutate_result_fails grok-4.6 "$TMP/grok-result.json" '.tokens.input = -1'
mutate_result_fails grok-4.6 "$TMP/grok-result.json" '.duration_seconds = -1'
mutate_result_fails grok-4.6 "$TMP/grok-result.json" '.finished_at_epoch = 1756399000'
mutate_result_fails grok-4.6 "$TMP/grok-result.json" '.duration_seconds = 99999'
# usage_source must agree with whether participants exist.
mutate_result_fails grok-4.6 "$TMP/grok-result.json" '.usage_source = "provider_aggregate"'

# Kimi and Gemini report no usage at all; zeros there are absent measurement.
mutate_result_fails kimi-k3 "$TMP/kimi-result.json" '.tokens.input = 500'
mutate_result_fails kimi-k3 "$TMP/kimi-result.json" '.provider_cost_usd = 0.5'
mutate_result_fails kimi-k3 "$TMP/kimi-result.json" '.usage_participants = [{"model":"kimi-k3"}]'
mutate_result_fails kimi-k3 "$TMP/kimi-result.json" '.effective_content_model = "kimi-k3"'
mutate_result_fails gemini-3.7-flash "$TMP/gemini-result.json" '.runtime_model = "gemini-3.7-flash-low"'
mutate_result_fails gemini-3.7-flash "$TMP/gemini-result.json" '.effective_content_model = "gemini-3.7-flash"'
mutate_result_fails gemini-3.7-flash "$TMP/gemini-result.json" '.tokens = {"input":10,"output":10}'

# A status envelope cannot promote a lane by listing it, name a backend the
# family does not have, or claim a lane in two states at once.
jq '.qualified_lanes = ["builder"]' "$TMP/status.json" >"$TMP/status-false-qualified.json"
expect_failure 65 "$CMD" validate --envelope status --file "$TMP/status-false-qualified.json" --family kimi-k3
jq '.backends = {"kilo":{"available":true}}' "$TMP/status.json" >"$TMP/status-foreign-backend.json"
expect_failure 65 "$CMD" validate --envelope status --file "$TMP/status-foreign-backend.json" --family kimi-k3
jq '.candidate_lanes = ["scout"]' "$TMP/status.json" >"$TMP/status-overlapping-lanes.json"
expect_failure 65 "$CMD" validate --envelope status --file "$TMP/status-overlapping-lanes.json" --family kimi-k3

# A lane list is an inventory, not a sample: it must be exactly the lanes the
# contract puts in that state for the family. Dropping one hides a lane that is
# in fact dispatchable, so it fails the same way inventing one does.
jq '.provisional_lanes -= ["scout"]' "$TMP/status.json" >"$TMP/status-missing-lane.json"
expect_failure 65 "$CMD" validate --envelope status --file "$TMP/status-missing-lane.json" --family kimi-k3
jq '.provisional_lanes += ["scout"]' "$TMP/status.json" >"$TMP/status-duplicate-lane.json"
expect_failure 65 "$CMD" validate --envelope status --file "$TMP/status-duplicate-lane.json" --family kimi-k3
# An optional lane list is not required, but a runner that does emit one must
# emit all of it: Kimi's candidate lanes are exactly senior and policy-annotation.
jq '.candidate_lanes = ["senior","policy-annotation"]' "$TMP/status.json" \
  >"$TMP/status-complete-candidates.json"
expect_success "$CMD" validate --envelope status --file "$TMP/status-complete-candidates.json" \
  --family kimi-k3
jq '.candidate_lanes = ["senior"]' "$TMP/status.json" >"$TMP/status-partial-candidates.json"
expect_failure 65 "$CMD" validate --envelope status --file "$TMP/status-partial-candidates.json" \
  --family kimi-k3

# The inventory a runner reports is derived from the central gate, so the two
# must agree for every family without running a runner: each family's declared
# lane statuses are exactly the statuses of its own central profile rows.
jq -e --slurpfile contract "$CONTRACT" '
  . as $g |
  $contract[0].families | to_entries | all(.[];
    .value as $f |
    ([$f.lanes[].central_profile] | unique) as $profiles |
    [$g.profiles | to_entries[] | select(.key as $k | $profiles | index($k)) |
      .value.lanes | to_entries[]] as $rows |
    ["qualified","manual-qualified","provisional","candidate","disabled"] | all(.[];
      . as $status |
      ([$rows[] | select(.value.status == $status) | .key] | unique | sort) ==
      ([$f.lanes | to_entries[] | select(.value.status == $status) | .key] | sort)))
' config/routing-gates.json >/dev/null \
  || fail 'a family lane inventory disagrees with the lane lists its runner derives centrally'
pass=$((pass + 1))

# Diagnostic phase and reason are stable machine vocabulary, not free text.
jq '.phase = "thinking"' "$TMP/kimi-diagnostic.json" >"$TMP/diagnostic-bad-phase.json"
expect_failure 65 "$CMD" validate --envelope diagnostic --file "$TMP/diagnostic-bad-phase.json"
jq '.reason = "failed while reading /Users/someone/private.key"' "$TMP/kimi-diagnostic.json" \
  >"$TMP/diagnostic-freetext-reason.json"
expect_failure 65 "$CMD" validate --envelope diagnostic --file "$TMP/diagnostic-freetext-reason.json"
jq '.cli_exit_code = -7' "$TMP/kimi-diagnostic.json" >"$TMP/diagnostic-bad-exit.json"
expect_failure 65 "$CMD" validate --envelope diagnostic --file "$TMP/diagnostic-bad-exit.json"
jq '.elapsed_seconds = -3' "$TMP/kimi-diagnostic.json" >"$TMP/diagnostic-negative-elapsed.json"
expect_failure 65 "$CMD" validate --envelope diagnostic --file "$TMP/diagnostic-negative-elapsed.json"
pass=$((pass + 1))

# ---------------------------------------------------------------------------
# Extension policy: real provider attestations pass; credentials and raw
# provider content do not, at any depth.
# ---------------------------------------------------------------------------
jq '. + {"oauth_mode":"serialized","credential_state_shared":false,"stop_reason":"end_turn",
         "search_runtime":{"identity":"ripgrep","sha256":"ab","copied_per_run":true},
         "process_exec":{"mode":"allowlist","allowed":["rg"],"attested":true},
         "prompt_sha256":"cd","runtime_cli_compatibility":"capability-probed"}' \
  "$TMP/grok-result.json" >"$TMP/result-benign-extensions.json"
expect_success "$CMD" validate --envelope result --file "$TMP/result-benign-extensions.json" \
  --family grok-4.6

secret_extension_fails() { # $1=jq mutation
  local filter="$1" out
  out="$TMP/secret-$(printf '%s' "$filter" | cksum | tr -d ' /').json"
  jq "$filter" "$TMP/grok-result.json" >"$out"
  expect_failure 65 "$CMD" validate --envelope result --file "$out" --family grok-4.6
}
secret_extension_fails '. + {"api_key":"redacted-anyway"}'
secret_extension_fails '. + {"authorization":"Bearer abc"}'
secret_extension_fails '. + {"credential":"x"}'
secret_extension_fails '. + {"secret":"x"}'
secret_extension_fails '. + {"prompt":"the full task prompt"}'
secret_extension_fails '. + {"messages":[{"role":"user"}]}'
secret_extension_fails '. + {"response_body":{"choices":[]}}'
secret_extension_fails '. + {"provider_response":{"a":1}}'
secret_extension_fails '. + {"stderr":"boom"}'
# Nested, inside an otherwise benign provider extension object.
secret_extension_fails '. + {"provider_debug":{"upstream":{"access_token":"x"}}}'
secret_extension_fails '. + {"attestation":{"oauth":{"refresh_token":"x"}}}'
# A credential-shaped value under an innocuous key name.
secret_extension_fails '. + {"note":"sk-abcdefghijklmnopqrstuvwxyz0123"}'
secret_extension_fails '. + {"receipt":"-----BEGIN RSA PRIVATE KEY-----"}'
# The same filter applies to diagnostics, which are sanitized metadata.
jq '. + {"raw_response":{"error":{}}}' "$TMP/kimi-diagnostic.json" >"$TMP/diagnostic-raw.json"
expect_failure 65 "$CMD" validate --envelope diagnostic --file "$TMP/diagnostic-raw.json"
pass=$((pass + 1))

# ---------------------------------------------------------------------------
# Negative: contract mutations must fail closed.
# ---------------------------------------------------------------------------
# A lane pointing at a profile the central gate does not define.
jq '.families["kimi-k3"].lanes.builder.central_profile = "kimi-k4"' "$CONTRACT" \
  >"$TMP/missing-profile.json"
expect_failure 65 with_contract "$TMP/missing-profile.json" check

# A declared external row that the contract stops covering.
jq 'del(.families["qwen3.8-max"].lanes.scout)' "$CONTRACT" >"$TMP/uncovered-lane.json"
expect_failure 65 with_contract "$TMP/uncovered-lane.json" check

# A lane that claims a class its own capabilities contradict.
jq '.families["glm-5.3-flash"].lanes.builder.permission_class = "read-only"' "$CONTRACT" \
  >"$TMP/permission-mismatch.json"
expect_failure 65 with_contract "$TMP/permission-mismatch.json" check
jq '.families["kimi-k3"].lanes.scout.tool_policy.write_scope = "workdir"' "$CONTRACT" \
  >"$TMP/write-scope-mismatch.json"
expect_failure 65 with_contract "$TMP/write-scope-mismatch.json" check

# A text-only transport silently promoted to worktree editing contradicts its
# own executable gate, which declares worktree_edits false.
jq '.families["qwen3.8-max"].lanes.builder.permission_class = "worktree-edit" |
    .families["qwen3.8-max"].lanes.builder.worktree_access = "read-write" |
    .families["qwen3.8-max"].lanes.builder.tool_policy.write_scope = "workdir"' \
  "$CONTRACT" >"$TMP/text-only-promoted.json"
expect_failure 65 with_contract "$TMP/text-only-promoted.json" check

# ---------------------------------------------------------------------------
# Permission drift is fail-closed. Each mutation below is internally consistent
# — it would pass every self-check the contract makes about itself — and is
# caught only because the executable gate declares the real control. One
# mutation per family, per control, so no single check masks another.
# ---------------------------------------------------------------------------
drift_fails() { # $1=label, $2=jq mutation of the contract
  local label="$1" filter="$2" out
  out="$TMP/drift-$label.json"
  jq "$filter" "$CONTRACT" >"$out"
  expect_failure 65 with_contract "$out" check
}

# GLM: the builder is silently demoted to a read-only plan-mode lane. The gate
# still says acceptEdits and workdir, so the two no longer agree.
drift_fails glm-builder-readonly '
  .families["glm-5.3-flash"].lanes.builder |=
    (.permission_class = "read-only" | .worktree_access = "read" |
     .tool_policy.write_scope = "none" | .tool_policy.permission_mode = "plan")'
drift_fails glm-builder-permission-mode '
  .families["glm-5.3-flash"].lanes.builder.tool_policy.permission_mode = "dontAsk"'
drift_fails glm-scout-mcp '
  .families["glm-5.3-flash"].lanes.scout.tool_policy.mcp = "permission-mode-gated"'
drift_fails glm-scout-plugins '
  .families["glm-5.3-flash"].lanes.scout.tool_policy.plugins = "permission-mode-gated"'
drift_fails glm-clerk-tools '
  .families["glm-5.3-flash"].lanes.clerk.tool_policy |=
    (.mode = "allowlist" | .allowed_tools = ["Read","Bash"])'
# GLM isolates the Claude config dir, not HOME. Restoring the old overstatement
# on either side of the comparison fails, and so does dropping the narrower
# claim the gate does evidence.
drift_fails glm-isolated-home-overstated '
  .families["glm-5.3-flash"].runtime_isolation.isolated_home = true'
drift_fails glm-isolated-config-unstated '
  .families["glm-5.3-flash"].runtime_isolation |= del(.isolated_config_dir)'
drift_fails glm-isolated-config-denied '
  .families["glm-5.3-flash"].runtime_isolation.isolated_config_dir = false'
drift_fails kimi-isolated-home-understated '
  .families["kimi-k3"].runtime_isolation.isolated_home = false'

# Kimi: the scout is granted Bash and a terminal.
drift_fails kimi-scout-bash '
  .families["kimi-k3"].lanes.scout.tool_policy.allowed_tools += ["Bash"]'
drift_fails kimi-scout-terminal '
  .families["kimi-k3"].lanes.scout.tool_policy.terminal = "permission-mode-gated"'
drift_fails kimi-scout-network '
  .families["kimi-k3"].lanes.scout.tool_policy.network = "permission-mode-gated"'
drift_fails kimi-scout-subagents '
  .families["kimi-k3"].lanes.scout.tool_policy.subagents = "permission-mode-gated"'
drift_fails kimi-clerk-permission-mode '
  .families["kimi-k3"].lanes.clerk.tool_policy.permission_mode = "acceptEdits"'
drift_fails kimi-builder-tools '
  .families["kimi-k3"].lanes.builder.tool_policy.allowed_tools = ["Read","Write","Edit","Bash"]'

# Grok: the sandboxed builder is widened, and the read-only policy lane gains
# the edit tool.
drift_fails grok-builder-mcp '
  .families["grok-4.6"].lanes.builder.tool_policy.mcp = "permission-mode-gated"'
drift_fails grok-builder-terminal '
  .families["grok-4.6"].lanes.builder.tool_policy.terminal = "permission-mode-gated"'
drift_fails grok-policy-tools '
  .families["grok-4.6"].lanes["policy-annotation"].tool_policy.allowed_tools += ["search_replace"]'
drift_fails grok-frontend-permission-mode '
  .families["grok-4.6"].lanes["frontend-builder"].tool_policy.permission_mode = "acceptEdits"'

# Qwen and DeepSeek are text-only: they have no tool surface to widen, so a
# contract that gives them one contradicts its own gate.
drift_fails qwen-builder-tools '
  .families["qwen3.8-max"].lanes.builder.tool_policy |=
    (.mode = "allowlist" | .allowed_tools = ["Bash"])'
drift_fails qwen-scout-worktree '
  .families["qwen3.8-max"].lanes.scout.worktree_access = "read"'
drift_fails deepseek-builder-tools '
  .families["deepseek-v4-pro"].lanes.builder.tool_policy |=
    (.mode = "allowlist" | .allowed_tools = ["Read","Write"])'
drift_fails deepseek-clerk-worktree '
  .families["deepseek-v4-pro"].lanes.clerk.worktree_access = "read"'

# Gemini is blocked on every lane; a blocked lane may not drift either.
drift_fails gemini-builder-permission-mode '
  .families["gemini-3.7-flash"].lanes.builder.tool_policy.permission_mode = "acceptEdits"'
drift_fails gemini-scout-worktree '
  .families["gemini-3.7-flash"].lanes.scout.worktree_access = "read"'
drift_fails gemini-reviewer-permission-mode '
  .families["gemini-3.7-flash"].lanes.reviewer.tool_policy.permission_mode = "dontAsk"'
pass=$((pass + 1))

# A security-relevant control may not be null, absent, or unknown.
jq '.families["kimi-k3"].lanes.scout.tool_policy.terminal = null' "$CONTRACT" \
  >"$TMP/null-capability.json"
expect_failure 65 with_contract "$TMP/null-capability.json" check
jq 'del(.families["kimi-k3"].lanes.scout.tool_policy.terminal)' "$CONTRACT" \
  >"$TMP/missing-capability.json"
expect_failure 65 with_contract "$TMP/missing-capability.json" check
jq '.families["kimi-k3"].lanes.scout.tool_policy.terminal = "sometimes"' "$CONTRACT" \
  >"$TMP/unknown-capability.json"
expect_failure 65 with_contract "$TMP/unknown-capability.json" check
jq '.vocabularies.capability_values.granted = "invented"' "$CONTRACT" \
  >"$TMP/extra-capability-value.json"
expect_failure 65 with_contract "$TMP/extra-capability-value.json" check
# `permission-mode-gated` is only meaningful where a mode is actually pinned.
jq '.families["qwen3.8-max"].lanes.builder.tool_policy.terminal = "permission-mode-gated"' \
  "$CONTRACT" >"$TMP/gated-without-mode.json"
expect_failure 65 with_contract "$TMP/gated-without-mode.json" check
pass=$((pass + 1))

# Every normative map is closed, including the usage participant fields and the
# per-family identity contract.
jq '.usage_accounting.participant_fields.session_token = "string"' "$CONTRACT" \
  >"$TMP/open-participant-fields.json"
expect_failure 65 with_contract "$TMP/open-participant-fields.json" check
jq 'del(.usage_accounting.participant_fields.canonical_model)' "$CONTRACT" \
  >"$TMP/narrow-participant-fields.json"
expect_failure 65 with_contract "$TMP/narrow-participant-fields.json" check
jq '.vocabularies.identity_kinds.vibes = "invented"' "$CONTRACT" >"$TMP/open-identity-kinds.json"
expect_failure 65 with_contract "$TMP/open-identity-kinds.json" check
# Participant and counter types are enforced on artifacts, so the declared type
# strings are themselves a closed vocabulary, and the counter type may not be
# quietly dropped to disable the check.
jq '.usage_accounting.participant_fields.cost_usd = "money"' "$CONTRACT" \
  >"$TMP/unknown-participant-type.json"
expect_failure 65 with_contract "$TMP/unknown-participant-type.json" check
jq 'del(.envelopes.result.token_counter_value_type)' "$CONTRACT" >"$TMP/no-counter-type.json"
expect_failure 65 with_contract "$TMP/no-counter-type.json" check
jq '.envelopes.result.token_counter_value_type = "money"' "$CONTRACT" \
  >"$TMP/unknown-counter-type.json"
expect_failure 65 with_contract "$TMP/unknown-counter-type.json" check
# The cross-checked isolation fields must stay inside the descriptive set.
jq '.executable_gate_controls.isolation_cross_checked_against.isolated_keychain =
      "family.runtime_isolation.isolated_keychain"' "$CONTRACT" \
  >"$TMP/undeclared-isolation-field.json"
expect_failure 65 with_contract "$TMP/undeclared-isolation-field.json" check
jq '.families["glm-5.3-flash"].runtime_isolation.isolated_keychain = true' "$CONTRACT" \
  >"$TMP/unknown-isolation-key.json"
expect_failure 65 with_contract "$TMP/unknown-isolation-key.json" check
jq '.vocabularies.usage_participation_values["trust-me"] = "invented"' "$CONTRACT" \
  >"$TMP/open-usage-participation.json"
expect_failure 65 with_contract "$TMP/open-usage-participation.json" check
jq '.extension_policy.rejected_key_names = []' "$CONTRACT" >"$TMP/empty-secret-list.json"
expect_failure 65 with_contract "$TMP/empty-secret-list.json" check
jq '.extension_policy.provider_extensions_permitted = false' "$CONTRACT" \
  >"$TMP/extensions-claimed-forbidden.json"
expect_failure 65 with_contract "$TMP/extensions-claimed-forbidden.json" check
# A family cannot claim first-party usage accounting without a participant
# identity, or claim an effective-content identity it never emits.
jq '.families["glm-5.3-flash"].identity.usage_participant_provider = null' "$CONTRACT" \
  >"$TMP/identity-no-provider.json"
expect_failure 65 with_contract "$TMP/identity-no-provider.json" check
jq '.families["kimi-k3"].identity.usage_participant_model = "kimi-k3"' "$CONTRACT" \
  >"$TMP/identity-invented-participant.json"
expect_failure 65 with_contract "$TMP/identity-invented-participant.json" check
jq '.families["kimi-k3"].identity.effective_content_identity = "must-equal-requested"' "$CONTRACT" \
  >"$TMP/identity-unemitted-effective.json"
expect_failure 65 with_contract "$TMP/identity-unemitted-effective.json" check
pass=$((pass + 1))

# An unknown permission class, and a fourth class in the vocabulary.
jq '.families["grok-4.6"].lanes.builder.permission_class = "worktree-write"' "$CONTRACT" \
  >"$TMP/unknown-class.json"
expect_failure 65 with_contract "$TMP/unknown-class.json" check
jq '.vocabularies.permission_classes["worktree-append"] =
      {worktree_writes:true,returns_patch:true,summary:"invented"}' "$CONTRACT" \
  >"$TMP/extra-class.json"
expect_failure 65 with_contract "$TMP/extra-class.json" check
jq 'del(.vocabularies.permission_classes["text-patch"])' "$CONTRACT" >"$TMP/missing-class.json"
expect_failure 65 with_contract "$TMP/missing-class.json" check
# Two classes with the same capability shape are no longer mutually exclusive.
jq '.vocabularies.permission_classes["text-patch"].returns_patch = false' "$CONTRACT" \
  >"$TMP/ambiguous-class.json"
expect_failure 65 with_contract "$TMP/ambiguous-class.json" check

# Identity-shape mismatch inside the contract itself.
jq '.families["deepseek-v4-pro"].identity.requested_model = "deepseek-v4"' "$CONTRACT" \
  >"$TMP/identity-mismatch.json"
expect_failure 65 with_contract "$TMP/identity-mismatch.json" check
jq '.families["glm-5.3-flash"].identity.usage_participation = "trust-me"' "$CONTRACT" \
  >"$TMP/identity-unknown-usage.json"
expect_failure 65 with_contract "$TMP/identity-unknown-usage.json" check
jq '.families["grok-4.6"].envelope_fields.result -= ["model"]' "$CONTRACT" \
  >"$TMP/identity-envelope-gap.json"
expect_failure 65 with_contract "$TMP/identity-envelope-gap.json" check

# Exit codes are a closed set: no invented code, no missing universal code.
jq '.exit_codes["71"] = {name:"protocol",universal:false,retryable:false,meaning:"invented"}' \
  "$CONTRACT" >"$TMP/extra-exit-code.json"
expect_failure 65 with_contract "$TMP/extra-exit-code.json" check
jq 'del(.exit_codes["130"])' "$CONTRACT" >"$TMP/missing-exit-code.json"
expect_failure 65 with_contract "$TMP/missing-exit-code.json" check
jq '.families["glm-5.3-flash"].exit_codes_emitted += [99]' "$CONTRACT" \
  >"$TMP/family-bad-exit-code.json"
expect_failure 65 with_contract "$TMP/family-bad-exit-code.json" check
jq '.families["glm-5.3-flash"].exit_codes_emitted -= [78]' "$CONTRACT" \
  >"$TMP/family-missing-exit-code.json"
expect_failure 65 with_contract "$TMP/family-missing-exit-code.json" check
jq '.exit_codes["75"].retryable = false' "$CONTRACT" >"$TMP/exit-code-semantics.json"
expect_failure 65 with_contract "$TMP/exit-code-semantics.json" check

# The contract is normative over itself: an unknown key fails closed.
jq '.families["kimi-k3"].lanes.builder.sandbox_bypass = true' "$CONTRACT" \
  >"$TMP/unknown-key.json"
expect_failure 65 with_contract "$TMP/unknown-key.json" check
jq '.new_top_level_section = {}' "$CONTRACT" >"$TMP/unknown-top-key.json"
expect_failure 65 with_contract "$TMP/unknown-top-key.json" check
jq '.authority.grants_permissions = true' "$CONTRACT" >"$TMP/grants-permissions.json"
expect_failure 65 with_contract "$TMP/grants-permissions.json" check
# Benign provider extension fields are accepted, so a contract may not claim
# extensions are forbidden outright — that would advertise a check the command
# does not perform. What it does perform is the narrower extension_policy
# filter, exercised above.
jq '.envelopes.result.extensions_permitted = false' "$CONTRACT" >"$TMP/extensions-forbidden.json"
expect_failure 65 with_contract "$TMP/extensions-forbidden.json" check
jq '.known_divergences += [{family:"kilo",envelope:"result",detail:"no such family"}]' \
  "$CONTRACT" >"$TMP/unknown-divergence.json"
expect_failure 65 with_contract "$TMP/unknown-divergence.json" check
printf 'not json\n' >"$TMP/broken-contract.json"
expect_failure 65 with_contract "$TMP/broken-contract.json" check
expect_failure 66 env DELEGATION_EXECUTOR_CONTRACT_FILE="$TMP/absent-contract.json" "$CMD" check

# ---------------------------------------------------------------------------
# Negative: disagreement with the central gate and with an executable gate.
# ---------------------------------------------------------------------------
jq '.profiles["grok-build"].lanes.builder.selection = "explicit-only"' config/routing-gates.json \
  >"$TMP/central-drift.json"
expect_failure 65 env DELEGATION_ROUTING_GATES_FILE="$TMP/central-drift.json" "$CMD" check
jq '.profiles["kimi-k3"].effort = "high"' config/routing-gates.json >"$TMP/central-effort-drift.json"
expect_failure 65 env DELEGATION_ROUTING_GATES_FILE="$TMP/central-effort-drift.json" "$CMD" check

mkdir -p "$TMP/gates"
cp config/*.json "$TMP/gates/"
expect_success env DELEGATION_EXECUTOR_GATE_DIR="$TMP/gates" "$CMD" check
jq '.lanes.builder.backends["grok-build"].status = "qualified" | .qualified_lanes = ["builder"]' \
  config/grok-4.6-routing.json >"$TMP/gates/grok-4.6-routing.json"
expect_failure 65 env DELEGATION_EXECUTOR_GATE_DIR="$TMP/gates" "$CMD" check
cp config/grok-4.6-routing.json "$TMP/gates/grok-4.6-routing.json"
jq '.lanes.scout.backends.native.effort = "high"' config/kimi-k3-routing.json \
  >"$TMP/gates/kimi-k3-routing.json"
expect_failure 65 env DELEGATION_EXECUTOR_GATE_DIR="$TMP/gates" "$CMD" check
cp config/kimi-k3-routing.json "$TMP/gates/kimi-k3-routing.json"
jq '.lanes.builder.backends["deepseek-api"].runtime_controls.worktree_edits = true' \
  config/deepseek-v4-pro-routing.json >"$TMP/gates/deepseek-v4-pro-routing.json"
expect_failure 65 env DELEGATION_EXECUTOR_GATE_DIR="$TMP/gates" "$CMD" check
cp config/deepseek-v4-pro-routing.json "$TMP/gates/deepseek-v4-pro-routing.json"
jq 'del(.lanes.senior)' config/qwen3.8-max-routing.json >"$TMP/gates/qwen3.8-max-routing.json"
expect_failure 65 env DELEGATION_EXECUTOR_GATE_DIR="$TMP/gates" "$CMD" check
cp config/qwen3.8-max-routing.json "$TMP/gates/qwen3.8-max-routing.json"

# Runtime controls are mandatory on the gate side too. Omitting the object, or
# one field of it, must fail rather than silently skip the comparison — that
# omission is exactly what let permission drift through before.
gate_fails() { # $1=gate basename, $2=jq mutation
  local gate="$1" filter="$2"
  jq "$filter" "config/$gate" >"$TMP/gates/$gate"
  expect_failure 65 env DELEGATION_EXECUTOR_GATE_DIR="$TMP/gates" "$CMD" check
  cp "config/$gate" "$TMP/gates/$gate"
}
gate_fails glm-5.3-flash-max-routing.json \
  'del(.lanes.builder.backends["claude-zai"].runtime_controls)'
# An isolation claim a gate row states must be the one the family declares, and
# a declared isolation must be evidenced somewhere in the family's own gate.
gate_fails glm-5.3-flash-max-routing.json \
  '.lanes.builder.backends["claude-zai"].runtime_controls.isolated_home = true'
gate_fails glm-5.3-flash-max-routing.json \
  '.lanes.scout.backends["claude-zai"].runtime_controls.isolated_config_dir = false'
gate_fails glm-5.3-flash-max-routing.json \
  '.lanes |= with_entries(.value.backends |=
     with_entries(.value.runtime_controls |= del(.isolated_config_dir)))'
gate_fails kimi-k3-routing.json \
  '.lanes.scout.backends.native.runtime_controls.isolated_home = false'
gate_fails glm-5.3-flash-max-routing.json \
  'del(.lanes.builder.backends["claude-zai"].runtime_controls.permission_mode)'
gate_fails glm-5.3-flash-max-routing.json \
  '.lanes.builder.backends["claude-zai"].runtime_controls.permission_mode = "plan"'
gate_fails glm-5.3-flash-max-routing.json \
  '.lanes.scout.backends["claude-zai"].runtime_controls.sandbox_bypass = true'
gate_fails kimi-k3-routing.json \
  'del(.lanes.scout.backends.native.runtime_controls.terminal)'
gate_fails kimi-k3-routing.json \
  '.lanes.scout.backends.native.runtime_controls.tools += ["Bash"]'
gate_fails kimi-k3-routing.json \
  '.lanes.builder.backends.native.runtime_controls.worktree_access = "read"'
gate_fails grok-4.6-routing.json \
  '.lanes.builder.backends["grok-build"].runtime_controls.network = "permission-mode-gated"'
gate_fails grok-4.6-routing.json \
  'del(.lanes["policy-annotation"].backends["grok-build"].runtime_controls.subagents)'
gate_fails qwen3.8-max-routing.json \
  'del(.lanes.clerk.backends["token-plan-openai"].runtime_controls)'
gate_fails deepseek-v4-pro-routing.json \
  '.lanes.builder.backends["deepseek-api"].runtime_controls.write_scope = "workdir"'
gate_fails gemini-3.7-flash-routing.json \
  'del(.lanes.scout.backends.agy.runtime_controls)'
gate_fails gemini-3.7-flash-routing.json \
  '.lanes.builder.backends.agy.runtime_controls.mcp = "permission-mode-gated"'
pass=$((pass + 1))

rm -f "$TMP/gates/gemini-3.7-flash-routing.json"
expect_failure 66 env DELEGATION_EXECUTOR_GATE_DIR="$TMP/gates" "$CMD" check
cp config/gemini-3.7-flash-routing.json "$TMP/gates/gemini-3.7-flash-routing.json"
expect_success env DELEGATION_EXECUTOR_GATE_DIR="$TMP/gates" "$CMD" check

# ---------------------------------------------------------------------------
# No routing decision and no runner behaviour moves with this contract.
# ---------------------------------------------------------------------------
expect_success bin/delegation-route check --json
for runner in glm kimi grok qwen deepseek gemini; do
  ! grep -q 'external-executor-contract' "bin/delegation-$runner" \
    || fail "bin/delegation-$runner reads the common contract; enforcement must stay runner-local"
done
pass=$((pass + 1))
! grep -q 'delegation-executor-contract' bin/delegation-route \
  || fail 'the router depends on the contract command; the contract must stay advisory'
pass=$((pass + 1))

# The installer installs both surfaces and the uninstaller removes the command.
grep -q 'bin/delegation-executor-contract' install.sh \
  || fail 'install.sh does not install the contract command'
grep -q 'config/external-executor-contract.json' install.sh \
  || fail 'install.sh does not install the contract file'
grep -q 'delegation-executor-contract' uninstall.sh \
  || fail 'uninstall.sh does not remove the installed contract command'
grep -q 'delegation-executor-contract' doctor.sh \
  || fail 'doctor.sh does not verify the installed contract command'
pass=$((pass + 1))

# The command is read-only: a full run leaves the checkout untouched.
before="$(git -C "$ROOT" status --porcelain)"
"$CMD" check --json >/dev/null
"$CMD" table >/dev/null
[ "$before" = "$(git -C "$ROOT" status --porcelain)" ] \
  || fail 'running the contract command changed the checkout'
pass=$((pass + 1))

printf 'external executor contract tests: %s passed\n' "$pass"
