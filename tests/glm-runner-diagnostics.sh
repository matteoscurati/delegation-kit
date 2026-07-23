#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/delegation-glm-test.XXXXXX")"
trap 'rm -rf -- "$TEST_TMP"' EXIT

mkdir -p "$TEST_TMP/bin" "$TEST_TMP/work" "$TEST_TMP/results" "$TEST_TMP/runtime"
printf 'Return the requested fixture result.\n' >"$TEST_TMP/prompt"

cat >"$TEST_TMP/bin/claude" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail

if [ "${1:-}" = "--help" ]; then
  printf '%s\n' 'usage: claude --effort <level>'
  exit 0
fi

case "${FAKE_CLAUDE_CASE:-success}" in
  success)
    printf '%s\n' \
      '{"type":"system","subtype":"init","model":"glm-5.2"}' \
      '{"type":"result","subtype":"success","result":"PONG","usage":{"input_tokens":3,"output_tokens":1},"total_cost_usd":0.01}'
    ;;
  process_exit)
    printf '%s\n' '{"type":"system","subtype":"init","model":"glm-5.2"}'
    printf '%s\n' 'provider connection closed' >&2
    exit 42
    ;;
  malformed)
    printf '%s\n' '{"type":"system","subtype":"init","model":"glm-5.2"}' '{broken'
    ;;
  primitive)
    printf '%s\n' '"SECRET_PAYLOAD"'
    ;;
  missing_init)
    printf '%s\n' '{"type":"result","subtype":"success","result":"PONG"}'
    ;;
  model_mismatch)
    printf '%s\n' \
      '{"type":"system","subtype":"init","model":"SECRET_PAYLOAD"}' \
      '{"type":"result","subtype":"success","result":"PONG"}'
    ;;
  mixed_init)
    printf '%s\n' \
      '{"type":"system","subtype":"init","model":"glm-5.2"}' \
      '{"type":"system","subtype":"init","model":"SECRET_PAYLOAD"}' \
      '{"type":"result","subtype":"success","result":"PONG"}'
    ;;
  missing_result|missing_result_debug)
    printf '%s\n' \
      '{"type":"system","subtype":"init","model":"glm-5.2"}' \
      '{"type":"SECRET_PAYLOAD","message":"SECRET_PAYLOAD"}'
    ;;
  empty_result)
    printf '%s\n' \
      '{"type":"system","subtype":"init","model":"glm-5.2"}' \
      '{"type":"result","subtype":"success","result":""}'
    ;;
  terminal_empty_result)
    printf '%s\n' \
      '{"type":"system","subtype":"init","model":"glm-5.2"}' \
      '{"type":"result","subtype":"success","result":"SECRET_PAYLOAD"}' \
      '{"type":"result","subtype":"success","result":""}'
    ;;
  result_error)
    printf '%s\n' \
      '{"type":"system","subtype":"init","model":"glm-5.2"}' \
      '{"type":"result","subtype":"SECRET_PAYLOAD","is_error":true,"result":"SECRET_PAYLOAD"}'
    ;;
  unknown_result_subtype)
    printf '%s\n' \
      '{"type":"system","subtype":"init","model":"glm-5.2"}' \
      '{"type":"result","subtype":"SECRET_PAYLOAD","result":"PONG"}'
    ;;
  numeric_result_subtype)
    printf '%s\n' \
      '{"type":"system","subtype":"init","model":"glm-5.2"}' \
      '{"type":"result","subtype":123,"result":"PONG"}'
    ;;
  auth)
    printf '%s\n' \
      '{"type":"system","subtype":"init","model":"glm-5.2"}' \
      '{"type":"system","subtype":"api_retry","error_status":401,"message":"SECRET_PAYLOAD"}' \
      '{"type":"result","subtype":"error_during_execution","is_error":true,"result":""}'
    exit 1
    ;;
  auth_mixed)
    printf '%s\n' \
      '{"type":"system","subtype":"init","model":"glm-5.2"}' \
      '{"type":"system","subtype":"api_retry","error_status":401}' \
      '{"type":"system","subtype":"api_retry","error_status":429}' \
      '{"type":"result","subtype":"error_during_execution","is_error":true,"result":""}'
    printf '%s\n' 'rate limit SECRET_PAYLOAD' >&2
    exit 1
    ;;
  rate)
    printf '%s\n' \
      '{"type":"system","subtype":"init","model":"glm-5.2"}' \
      '{"type":"system","subtype":"api_retry","error_status":429,"message":"SECRET_PAYLOAD"}' \
      '{"type":"result","subtype":"error_during_execution","is_error":true,"result":""}'
    exit 1
    ;;
  *)
    printf 'unknown fake case: %s\n' "$FAKE_CLAUDE_CASE" >&2
    exit 64
    ;;
esac
FAKE
chmod +x "$TEST_TMP/bin/claude"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_json() {
  local file="$1" expression="$2"
  jq -e "$expression" "$file" >/dev/null || fail "$file does not satisfy: $expression"
}

run_case() {
  local name="$1" expected_rc="$2"
  shift 2
  local output="$TEST_TMP/results/$name.out" rc=0
  PATH="$TEST_TMP/bin:$PATH" \
    TMPDIR="$TEST_TMP/runtime" \
    ZAI_API_KEY="fixture-key" \
    FAKE_CLAUDE_CASE="$name" \
    "$ROOT/bin/delegation-glm" run \
      --lane scout --effort auto --backend auto --allow-provisional \
      --prompt-file "$TEST_TMP/prompt" --output "$output" \
      --workdir "$TEST_TMP/work" "$@" \
      >"$TEST_TMP/results/$name.stdout" 2>"$TEST_TMP/results/$name.stderr" || rc=$?
  [ "$rc" -eq "$expected_rc" ] || fail "$name returned $rc, expected $expected_rc"
}

assert_failed_case() {
  local name="$1" expected_reason="$2" expected_phase="$3" expected_cli="$4"
  local output="$TEST_TMP/results/$name.out"
  [ ! -e "$output" ] || fail "$name left a partial output"
  [ ! -e "$output.metrics.json" ] || fail "$name left partial metrics"
  [ ! -e "$output.stderr" ] || fail "$name preserved raw stderr without opt-in"
  [ -f "$output.error.json" ] || fail "$name did not write a diagnostic"
  assert_json "$output.error.json" \
    ".reason == \"$expected_reason\" and .phase == \"$expected_phase\" and .cli_exit_code == $expected_cli"
  ! grep -q 'SECRET_PAYLOAD' "$output.error.json" \
    || fail "$name leaked event content into its diagnostic"
}

printf 'stale diagnostic\n' >"$TEST_TMP/results/success.out.error.json"
run_case success 0
[ "$(cat "$TEST_TMP/results/success.out")" = PONG ] || fail "success output mismatch"
assert_json "$TEST_TMP/results/success.out.metrics.json" \
  '.model == "glm-5.2" and .tokens.input == 3 and .tokens.output == 1'
[ ! -e "$TEST_TMP/results/success.out.error.json" ] || fail "success wrote an error diagnostic"

run_case process_exit 70
assert_failed_case process_exit process_exit dispatch 42

for fixture in malformed primitive missing_init model_mismatch mixed_init \
  missing_result empty_result terminal_empty_result result_error \
  unknown_result_subtype numeric_result_subtype; do
  run_case "$fixture" 70
done
assert_failed_case malformed invalid_stream extract null
assert_failed_case primitive invalid_stream extract null
assert_failed_case missing_init missing_init extract null
assert_failed_case model_mismatch model_mismatch extract null
assert_json "$TEST_TMP/results/model_mismatch.out.error.json" \
  '.observed_models == ["<unexpected>"]'
assert_failed_case mixed_init model_mismatch extract null
assert_failed_case missing_result missing_result extract null
assert_failed_case empty_result empty_result extract null
assert_failed_case terminal_empty_result empty_result extract null
assert_failed_case result_error result_error extract null
assert_failed_case unknown_result_subtype invalid_stream extract null
assert_failed_case numeric_result_subtype invalid_stream extract null

run_case auth 69
assert_failed_case auth authentication_failed dispatch 1
run_case auth_mixed 69
assert_failed_case auth_mixed authentication_failed dispatch 1
run_case rate 75
assert_failed_case rate rate_limited dispatch 1

mkdir "$TEST_TMP/output-dir" "$TEST_TMP/metrics-dir"
rc=0
PATH="$TEST_TMP/bin:$PATH" ZAI_API_KEY="fixture-key" FAKE_CLAUDE_CASE=success \
  "$ROOT/bin/delegation-glm" run \
    --lane scout --effort auto --backend auto --allow-provisional \
    --prompt-file "$TEST_TMP/prompt" --output "$TEST_TMP/output-dir" \
    --workdir "$TEST_TMP/work" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 64 ] || fail "directory output returned $rc, expected 64"
rc=0
PATH="$TEST_TMP/bin:$PATH" ZAI_API_KEY="fixture-key" FAKE_CLAUDE_CASE=success \
  "$ROOT/bin/delegation-glm" run \
    --lane scout --effort auto --backend auto --allow-provisional \
    --prompt-file "$TEST_TMP/prompt" --output "$TEST_TMP/results/metrics-target.out" \
    --metrics "$TEST_TMP/metrics-dir" --workdir "$TEST_TMP/work" \
    >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 64 ] || fail "directory metrics returned $rc, expected 64"

collision_output="$TEST_TMP/results/collision.out"
rc=0
PATH="$TEST_TMP/bin:$PATH" ZAI_API_KEY="fixture-key" FAKE_CLAUDE_CASE=success \
  "$ROOT/bin/delegation-glm" run \
    --lane scout --effort auto --backend auto --allow-provisional \
    --prompt-file "$TEST_TMP/prompt" --output "$collision_output" \
    --metrics "$collision_output" --workdir "$TEST_TMP/work" \
    >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 64 ] || fail "output/metrics collision returned $rc, expected 64"

diagnostic_collision_output="$TEST_TMP/results/diagnostic-collision.out"
rc=0
PATH="$TEST_TMP/bin:$PATH" ZAI_API_KEY="fixture-key" FAKE_CLAUDE_CASE=success \
  "$ROOT/bin/delegation-glm" run \
    --lane scout --effort auto --backend auto --allow-provisional \
    --prompt-file "$TEST_TMP/prompt" --output "$diagnostic_collision_output" \
    --metrics "$diagnostic_collision_output.error.json" \
    --workdir "$TEST_TMP/work" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 64 ] || fail "metrics/diagnostic collision returned $rc, expected 64"

diagnostic_dir_output="$TEST_TMP/results/diagnostic-dir.out"
mkdir "$diagnostic_dir_output.error.json"
rc=0
PATH="$TEST_TMP/bin:$PATH" ZAI_API_KEY="fixture-key" FAKE_CLAUDE_CASE=success \
  "$ROOT/bin/delegation-glm" run \
    --lane scout --effort auto --backend auto --allow-provisional \
    --prompt-file "$TEST_TMP/prompt" --output "$diagnostic_dir_output" \
    --workdir "$TEST_TMP/work" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 64 ] || fail "diagnostic directory returned $rc, expected 64"

mkdir "$TEST_TMP/debug"
run_case missing_result_debug 70 --debug-dir "$TEST_TMP/debug"
debug_run="$(find "$TEST_TMP/debug" -mindepth 1 -maxdepth 1 -type d -name 'delegation-glm.*' -print)"
[ -n "$debug_run" ] || fail "debug opt-in did not preserve a run directory"
[ "$(find "$TEST_TMP/debug" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')" -eq 1 ] \
  || fail "debug opt-in preserved an unexpected number of directories"
grep -q 'SECRET_PAYLOAD' "$debug_run/events.jsonl" \
  || fail "debug event stream is missing the raw fixture content"
[ -f "$debug_run/stderr.txt" ] || fail "debug stderr is missing"
[ -f "$debug_run/diagnostic.json" ] || fail "debug diagnostic is missing"
mode="$(stat -f '%Lp' "$debug_run" 2>/dev/null || stat -c '%a' "$debug_run")"
[ "$mode" = 700 ] || fail "debug directory mode is $mode, expected 700"
for artifact in "$debug_run/events.jsonl" "$debug_run/stderr.txt" "$debug_run/diagnostic.json"; do
  mode="$(stat -f '%Lp' "$artifact" 2>/dev/null || stat -c '%a' "$artifact")"
  [ "$mode" = 600 ] || fail "$artifact mode is $mode, expected 600"
done

[ -z "$(find "$TEST_TMP/runtime" -mindepth 1 -maxdepth 1 -name 'delegation-glm.*' -print)" ] \
  || fail "runner temporary directories were not cleaned up"

printf 'GLM runner diagnostics tests passed.\n'
