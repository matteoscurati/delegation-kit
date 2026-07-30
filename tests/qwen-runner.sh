#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/delegation-qwen-test.XXXXXX")"
trap 'rm -rf -- "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/work" "$TMP/results" "$TMP/runtime" "$TMP/debug"
printf 'Respond with PONG.\n' >"$TMP/prompt"

# Evaluation rejects a dirty runner checkout.  Exercise it in a throwaway,
# committed copy of the current tree, never by weakening that production check.
ROOT="$TMP/repo"
cp -R "$SOURCE_ROOT/." "$ROOT"
rm -rf -- "$ROOT/.git"
rm -f -- "$ROOT/.claude/settings.local.json"
mkdir -p "$ROOT/evaluation/test-fixtures"
printf '%s\n' 'policy annotation contract fixture' >"$ROOT/evaluation/test-fixtures/contract.txt"
printf '%s\n' '{"type":"object","required":["annotation"]}' >"$ROOT/evaluation/test-fixtures/output-schema.json"
git -C "$ROOT" init -q
git -C "$ROOT" config user.email test@example.invalid
git -C "$ROOT" config user.name delegation-runner-test
git -C "$ROOT" add -A
git -C "$ROOT" commit -qm 'evaluation fixture base'
BASE_COMMIT="$(git -C "$ROOT" rev-parse HEAD)"

cat >"$TMP/bin/curl" <<'EOF'
#!/usr/bin/env bash
output=""
request=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o) output="${2:-}"; shift 2 ;;
    --data-binary) request="${2#@}"; shift 2 ;;
    --config|-w|--connect-timeout|--max-time) shift 2 ;;
    -sS) shift ;;
    *) shift ;;
  esac
done
[ -n "$output" ] || exit 90
if [ -n "${FAKE_QWEN_REQUEST_CAPTURE:-}" ]; then
  cp "$request" "$FAKE_QWEN_REQUEST_CAPTURE" || exit 91
fi
case "${FAKE_QWEN_CASE:-success}" in
  success)
    printf '%s\n' '{"model":"qwen3.8-max-preview","choices":[{"message":{"content":"PONG"}}],"usage":{"prompt_tokens":7,"completion_tokens":3}}' >"$output"
    printf '200'
    ;;
  auth)
    printf '%s\n' '{"model":"qwen3.8-max-preview","error":{"message":"SECRET_PROVIDER_RESPONSE"}}' >"$output"
    printf '401'
    ;;
  rate)
    printf '%s\n' '{"model":"qwen3.8-max-preview","error":{"message":"SECRET_PROVIDER_RESPONSE"}}' >"$output"
    printf '429'
    ;;
  server)
    printf '%s\n' '{"model":"qwen3.8-max-preview","error":{"message":"SECRET_PROVIDER_RESPONSE"}}' >"$output"
    printf '503'
    ;;
  provider)
    printf '%s\n' '{"model":"qwen3.8-max-preview","error":{"message":"SECRET_PROVIDER_RESPONSE"}}' >"$output"
    printf '400'
    ;;
  malformed)
    printf '%s\n' '{not-json SECRET_PROVIDER_RESPONSE' >"$output"
    printf '200'
    ;;
  empty)
    printf '%s\n' '{"model":"qwen3.8-max-preview","choices":[{"message":{"content":""}}]}' >"$output"
    printf '200'
    ;;
  identity)
    printf '%s\n' '{"model":"qwen3.8-max-preview-fallback","choices":[{"message":{"content":"PONG"}}]}' >"$output"
    printf '200'
    ;;
  transport)
    printf 'SECRET_CURL_STDERR\n' >&2
    exit 7
    ;;
  *)
    exit 64
    ;;
esac
EOF
chmod +x "$TMP/bin/curl"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
json() { jq -e "$2" "$1" >/dev/null || fail "$1 did not satisfy $2"; }
sha256() { shasum -a 256 "$1" | awk '{print $1}'; }

write_manifest() {
  jq -n \
    --arg prompt_sha256 "$(sha256 "$TMP/prompt")" \
    --arg runner_sha256 "$(sha256 "$ROOT/bin/delegation-qwen")" \
    --arg contract_sha256 "$(sha256 "$ROOT/evaluation/test-fixtures/contract.txt")" \
    --arg output_schema_sha256 "$(sha256 "$ROOT/evaluation/test-fixtures/output-schema.json")" \
    --arg source_commit "$BASE_COMMIT" \
    '{schema:"delegation_policy_annotation_evaluation_v1",profile:"qwen3.8-max-preview",lane:"policy-annotation",model:"qwen3.8-max-preview",backend:"token-plan-openai",effort:"xhigh",prompt_sha256:$prompt_sha256,runner_source_commit:$source_commit,runner_sha256:$runner_sha256,contract_path:"evaluation/test-fixtures/contract.txt",contract_sha256:$contract_sha256,output_schema_path:"evaluation/test-fixtures/output-schema.json",output_schema_sha256:$output_schema_sha256,timeout_seconds:60,max_output_chars:1024}' \
    >"$TMP/manifest.json"
}
write_manifest
MANIFEST_SHA="$(sha256 "$TMP/manifest.json")"
jq --arg hash "$MANIFEST_SHA" '
  .profiles["qwen3.8-max-preview"].lanes["policy-annotation"].evaluation_manifest_sha256 = [$hash]
' "$ROOT/config/routing-gates.json" >"$TMP/gates.json"
mv "$TMP/gates.json" "$ROOT/config/routing-gates.json"
jq --arg hash "$MANIFEST_SHA" '
  .lanes["policy-annotation"].backends["token-plan-openai"].evaluation_manifest_sha256 = [$hash]
' "$ROOT/config/qwen3.8-max-preview-routing.json" >"$TMP/qwen-routing.json"
mv "$TMP/qwen-routing.json" "$ROOT/config/qwen3.8-max-preview-routing.json"
git -C "$ROOT" add config/routing-gates.json config/qwen3.8-max-preview-routing.json
git -C "$ROOT" commit -qm 'allowlist evaluation fixture'

run_case() {
  local name="$1" expected="$2"
  shift 2
  local rc=0
  PATH="$TMP/bin:$PATH" TMPDIR="$TMP/runtime" \
    QWEN_TOKEN_PLAN_API_KEY=sk-sp-test FAKE_QWEN_CASE="$name" \
    FAKE_QWEN_REQUEST_CAPTURE="$TMP/results/$name.request.json" \
    "$ROOT/bin/delegation-qwen" run --lane policy-annotation --effort auto \
    --backend token-plan-openai --evaluation --prompt-file "$TMP/prompt" \
    --evaluation-manifest "$TMP/manifest.json" \
    --output "$TMP/results/$name.out" --workdir "$TMP/work" "$@" \
    >"$TMP/results/$name.stdout" 2>"$TMP/results/$name.stderr" || rc=$?
  [ "$rc" = "$expected" ] || fail "$name returned $rc, expected $expected"
}

PATH="$TMP/bin:$PATH" QWEN_TOKEN_PLAN_API_KEY=sk-sp-test \
  "$ROOT/bin/delegation-qwen" check --json >"$TMP/check.json"
json "$TMP/check.json" \
  '.model == "qwen3.8-max-preview" and .backends["token-plan-openai"].available == true'

# Disabled lanes remain blocked even for controlled evaluations and must fail
# before runtime/authentication inspection.
rc=0
PATH="/usr/bin:/bin" QWEN_TOKEN_PLAN_API_KEY='' \
  "$ROOT/bin/delegation-qwen" run --lane judgement --evaluation \
  --evaluation-manifest "$TMP/missing-manifest.json" --prompt-file "$TMP/prompt" --output "$TMP/results/judgement.out" \
  --workdir "$TMP/work" >/dev/null 2>&1 || rc=$?
[ "$rc" = 78 ] || fail "disabled judgement evaluation returned $rc"

run_case success 0
[ "$(cat "$TMP/results/success.out")" = PONG ] || fail 'success output mismatch'
json "$TMP/results/success.out.metrics.json" \
  '.model == "qwen3.8-max-preview" and .effort == "xhigh" and
   .tokens.input == 7 and .tokens.output == 3'
[ ! -e "$TMP/results/success.out.error.json" ] || fail 'success left diagnostic'

# A successful policy-annotation evaluation publishes the runner-emitted receipt
# with exactly the bound fields, recomputed here from independent sources.
json "$TMP/results/success.request.json" '.max_tokens == 16384'
jq -e --arg manifest_sha "$MANIFEST_SHA" \
  --arg prompt_sha "$(sha256 "$TMP/prompt")" \
  --arg source_commit "$(git -C "$ROOT" rev-parse HEAD)" \
  --arg runner_sha "$(sha256 "$ROOT/bin/delegation-qwen")" \
  --arg output_sha "$(sha256 "$TMP/results/success.out")" \
  '(.evaluation_receipt | keys | sort) ==
     ["evaluation_manifest_sha256","post_observation_retries","prompt_sha256",
      "provider_attempts","raw_output_sha256","runner_sha256",
      "runner_source_commit","schema_version"] and
   .evaluation_receipt.schema_version == "delegation_policy_annotation_attempt_receipt_v1" and
   .evaluation_receipt.evaluation_manifest_sha256 == $manifest_sha and
   .evaluation_receipt.prompt_sha256 == $prompt_sha and
   .evaluation_receipt.runner_source_commit == $source_commit and
   .evaluation_receipt.runner_sha256 == $runner_sha and
   .evaluation_receipt.raw_output_sha256 == $output_sha and
   .evaluation_receipt.provider_attempts == 1 and
   .evaluation_receipt.post_observation_retries == 0' \
  "$TMP/results/success.out.metrics.json" >/dev/null \
  || fail 'evaluation receipt mismatch'
jq -e --arg output_sha "$(sha256 "$TMP/results/success.out")" \
  --arg metrics_sha "$(sha256 "$TMP/results/success.out.metrics.json")" \
  --arg manifest_sha "$MANIFEST_SHA" \
  '(keys | sort) == ["evaluation_manifest_sha256","metrics_sha256",
    "raw_output_sha256","schema_version"] and
   .schema_version == "delegation_policy_annotation_publication_commit_v1" and
   .raw_output_sha256 == $output_sha and .metrics_sha256 == $metrics_sha and
   .evaluation_manifest_sha256 == $manifest_sha' \
  "$TMP/results/success.out.commit.json" >/dev/null \
  || fail 'evaluation publication commit mismatch'

# Handled publication failures clean every member; the marker is always last.
mkdir -p "$TMP/mv-fail"
cat >"$TMP/mv-fail/mv" <<'EOF'
#!/usr/bin/env bash
target="${@: -1}"
if [ "$target" = "${FAIL_MV_TARGET:-}" ]; then
  printf 'partial\n' >"$target"
  exit 1
fi
exec /bin/mv "$@"
EOF
chmod 755 "$TMP/mv-fail/mv"
for phase in output metrics commit; do
  out="$TMP/results/publish-$phase.out"
  case "$phase" in
    output) target="$out" ;;
    metrics) target="$out.metrics.json" ;;
    commit) target="$out.commit.json" ;;
  esac
  target="$(cd "$(dirname "$target")" && pwd -P)/$(basename "$target")"
  rc=0
  FAIL_MV_TARGET="$target" PATH="$TMP/mv-fail:$TMP/bin:$PATH" \
    TMPDIR="$TMP/runtime" QWEN_TOKEN_PLAN_API_KEY=sk-sp-test FAKE_QWEN_CASE=success \
    "$ROOT/bin/delegation-qwen" run --lane policy-annotation --effort auto \
    --backend token-plan-openai --evaluation --prompt-file "$TMP/prompt" \
    --evaluation-manifest "$TMP/manifest.json" --output "$out" --workdir "$TMP/work" \
    >/dev/null 2>&1 || rc=$?
  [ "$rc" = 70 ] || fail "$phase publication failure returned $rc"
  [ ! -e "$out" ] && [ ! -e "$out.metrics.json" ] && [ ! -e "$out.commit.json" ] \
    || fail "$phase publication failure left a published member"
done

for spec in \
  'auth 69 authentication_failed dispatch 401' \
  'rate 75 rate_limited dispatch 429' \
  'server 75 provider_temporary_failure dispatch 503' \
  'provider 70 provider_error dispatch 400' \
  'malformed 70 provider_identity_mismatch extract 200' \
  'empty 70 invalid_or_empty_response extract 200' \
  'identity 70 provider_identity_mismatch extract 200' \
  'transport 75 transport_failure dispatch 000'
do
  read -r name expected reason phase http_code <<EOF
$spec
EOF
  run_case "$name" "$expected"
  diagnostic="$TMP/results/$name.out.error.json"
  [ -f "$diagnostic" ] || fail "$name diagnostic missing"
  json "$diagnostic" \
    ".reason == \"$reason\" and .phase == \"$phase\" and
     .http_code == \"$http_code\" and .debug_dir == null"
  ! grep -Eq 'SECRET_PROVIDER_RESPONSE|SECRET_CURL_STDERR' "$diagnostic" \
    || fail "$name diagnostic leaked raw provider data"
  [ ! -e "$TMP/results/$name.out" ] || fail "$name left partial output"
  [ ! -e "$TMP/results/$name.out.metrics.json" ] || fail "$name left partial metrics"
  [ ! -e "$TMP/results/$name.out.stderr" ] || fail "$name left legacy raw stderr"
done

rm -f "$TMP/results/provider.out.error.json"
run_case provider 70 --debug-dir "$TMP/debug"
debug_run="$(find "$TMP/debug" -maxdepth 1 -type d -name 'delegation-qwen.*' | head -1)"
[ -n "$debug_run" ] || fail 'debug artifacts missing'
grep -q SECRET_PROVIDER_RESPONSE "$debug_run/response.json" \
  || fail 'raw provider response was not preserved'
[ -f "$debug_run/stderr.txt" ] && [ -f "$debug_run/diagnostic.json" ] \
  || fail 'debug files missing'
mode="$(stat -f '%Lp' "$debug_run" 2>/dev/null || stat -c '%a' "$debug_run")"
[ "$mode" = 700 ] || fail "debug directory mode $mode"
for file in "$debug_run"/*; do
  mode="$(stat -f '%Lp' "$file" 2>/dev/null || stat -c '%a' "$file")"
  [ "$mode" = 600 ] || fail "debug file mode $mode"
done

# Existing and symlinked destinations are rejected instead of being truncated.
printf 'existing\n' >"$TMP/results/existing.out"
rc=0
PATH="$TMP/bin:$PATH" QWEN_TOKEN_PLAN_API_KEY=sk-sp-test \
  "$ROOT/bin/delegation-qwen" run --lane policy-annotation --evaluation \
  --evaluation-manifest "$TMP/manifest.json" \
  --prompt-file "$TMP/prompt" --output "$TMP/results/existing.out" \
  --workdir "$TMP/work" >/dev/null 2>&1 || rc=$?
[ "$rc" = 64 ] || fail 'existing output accepted'
[ "$(cat "$TMP/results/existing.out")" = existing ] || fail 'existing output changed'

ln -s "$TMP/results/existing.out" "$TMP/results/symlink.out.error.json"
rc=0
PATH="$TMP/bin:$PATH" QWEN_TOKEN_PLAN_API_KEY=sk-sp-test \
  "$ROOT/bin/delegation-qwen" run --lane policy-annotation --evaluation \
  --evaluation-manifest "$TMP/manifest.json" \
  --prompt-file "$TMP/prompt" --output "$TMP/results/symlink.out" \
  --workdir "$TMP/work" >/dev/null 2>&1 || rc=$?
[ "$rc" = 64 ] || fail 'symlink diagnostic accepted'
[ "$(cat "$TMP/results/existing.out")" = existing ] || fail 'symlink target changed'

mkdir "$TMP/work/debug"
rc=0
PATH="$TMP/bin:$PATH" QWEN_TOKEN_PLAN_API_KEY=sk-sp-test \
  "$ROOT/bin/delegation-qwen" run --lane policy-annotation --evaluation \
  --evaluation-manifest "$TMP/manifest.json" \
  --prompt-file "$TMP/prompt" --output "$TMP/results/worktree-debug.out" \
  --workdir "$TMP/work" --debug-dir "$TMP/work/debug" >/dev/null 2>&1 || rc=$?
[ "$rc" = 64 ] || fail 'debug directory inside read-only workdir accepted'

# Flip the throwaway lane to qualified in BOTH gates so ordinary (non-evaluation)
# dispatch can be exercised; the production gates stay candidate and untouched.
jq '.profiles["qwen3.8-max-preview"].lanes["policy-annotation"].status = "qualified" |
    .profiles["qwen3.8-max-preview"].lanes["policy-annotation"].selection = "explicit-only" |
    .profiles["qwen3.8-max-preview"].lanes["policy-annotation"].evaluation_manifest_sha256 = []' \
  "$ROOT/config/routing-gates.json" >"$TMP/gates.json"
mv "$TMP/gates.json" "$ROOT/config/routing-gates.json"
jq '.qualified_lanes = ["policy-annotation"] |
    .lanes["policy-annotation"].backends["token-plan-openai"].status = "qualified" |
    .lanes["policy-annotation"].backends["token-plan-openai"].selection = "explicit-only" |
    .lanes["policy-annotation"].backends["token-plan-openai"].qualified = true |
    del(.lanes["policy-annotation"].backends["token-plan-openai"].evaluation_manifest_sha256)' \
  "$ROOT/config/qwen3.8-max-preview-routing.json" >"$TMP/qwen-routing.json"
mv "$TMP/qwen-routing.json" "$ROOT/config/qwen3.8-max-preview-routing.json"
git -C "$ROOT" add config/routing-gates.json config/qwen3.8-max-preview-routing.json
git -C "$ROOT" commit -qm 'qualify policy-annotation for ordinary dispatch test'

rc=0
PATH="$TMP/bin:$PATH" TMPDIR="$TMP/runtime" \
  QWEN_TOKEN_PLAN_API_KEY=sk-sp-test FAKE_QWEN_CASE=success \
  FAKE_QWEN_REQUEST_CAPTURE="$TMP/results/ordinary.request.json" \
  "$ROOT/bin/delegation-qwen" run --lane policy-annotation --effort auto \
  --backend token-plan-openai --prompt-file "$TMP/prompt" \
  --output "$TMP/results/ordinary.out" --workdir "$TMP/work" \
  >"$TMP/results/ordinary.stdout" 2>"$TMP/results/ordinary.stderr" || rc=$?
[ "$rc" = 0 ] || fail "ordinary qualified run returned $rc"
[ "$(cat "$TMP/results/ordinary.out")" = PONG ] || fail 'ordinary output mismatch'
json "$TMP/results/ordinary.out.metrics.json" \
  '.model == "qwen3.8-max-preview" and .tokens.input == 7 and .tokens.output == 3'
# Ordinary runs never claim the evaluation receipt and keep the 4096 ceiling.
json "$TMP/results/ordinary.out.metrics.json" 'has("evaluation_receipt") | not'
json "$TMP/results/ordinary.request.json" '.max_tokens == 4096'
[ ! -e "$TMP/results/ordinary.out.commit.json" ] || fail 'ordinary run wrote commit marker'
[ ! -e "$TMP/results/ordinary.out.error.json" ] || fail 'ordinary run left diagnostic'

[ -z "$(find "$TMP/runtime" -mindepth 1 -maxdepth 1 -name 'delegation-qwen.*' -print)" ] \
  || fail 'temporary directories not cleaned'
printf 'Qwen runner diagnostics tests passed.\n'
