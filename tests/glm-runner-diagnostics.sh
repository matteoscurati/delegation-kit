#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/delegation-glm-test.XXXXXX")"
if [ "${DELEGATION_TEST_KEEP_TMP:-0}" = 1 ]; then
  trap 'printf "kept test directory: %s\n" "$TEST_TMP" >&2' EXIT
else
  trap 'rm -rf -- "$TEST_TMP"' EXIT
fi

mkdir -p "$TEST_TMP/bin" "$TEST_TMP/work" "$TEST_TMP/results" "$TEST_TMP/runtime"
printf 'Return the requested fixture result.\n' >"$TEST_TMP/prompt"

cat >"$TEST_TMP/bin/claude" <<'FAKE'
#!/bin/bash
set -euo pipefail

if [ "${1:-}" = "--help" ]; then
  printf '%s\n' 'usage: claude --effort <level>'
  exit 0
fi

case "${FAKE_CLAUDE_CASE:-success}" in
  success)
    printf '%s\n' \
      '{"type":"system","subtype":"init","model":"glm-5.3-flash"}' \
      '{"type":"result","subtype":"success","result":"PONG","usage":{"input_tokens":3,"output_tokens":1},"total_cost_usd":0.01}'
    ;;
  builder_success)
    ! printf '%s\n' 'forbidden git control write' >.git/delegation-canary
    printf '%s\n' 'fixed' >fixture.txt
    printf '%s\n' 'ignored but attested' >ignored-artifact.txt
    chmod 755 ignored-artifact.txt
    printf '%s\n' \
      '{"type":"system","subtype":"init","model":"glm-5.3-flash"}' \
      '{"type":"result","subtype":"success","result":"{\"status\":\"completed\"}","usage":{"input_tokens":4,"output_tokens":2},"total_cost_usd":0.02}'
    ;;
  read_isolation)
    ! IFS= read -r home_secret <"$FAKE_FORBIDDEN_HOME"
    ! IFS= read -r source_secret <"$FAKE_FORBIDDEN_SOURCE"
    ! IFS= read -r host_secret <"$FAKE_FORBIDDEN_HOST"
    IFS= read -r fixture_value <fixture.txt
    [ "$fixture_value" = original ]
    printf '%s\n' scratch >"$CLAUDE_CONFIG_DIR/read-canary"
    IFS= read -r scratch_value <"$CLAUDE_CONFIG_DIR/read-canary"
    [ "$scratch_value" = scratch ]
    ! /usr/bin/id
    ! /usr/bin/env
    printf '%s\n' \
      '{"type":"system","subtype":"init","model":"glm-5.3-flash"}' \
      '{"type":"result","subtype":"success","result":"","structured_output":{"status":"completed","answers":{"value":"ISOLATED"}},"usage":{"input_tokens":3,"output_tokens":4},"total_cost_usd":0.01}'
    ;;
  structured_success)
    printf '%s\n' \
      '{"type":"system","subtype":"init","model":"glm-5.3-flash"}' \
      '{"type":"result","subtype":"success","result":"","structured_output":{"status":"completed","answers":{"value":"PONG"}},"usage":{"input_tokens":3,"output_tokens":4},"total_cost_usd":0.01}'
    ;;
  process_exit)
    printf '%s\n' '{"type":"system","subtype":"init","model":"glm-5.3-flash"}'
    printf '%s\n' 'provider connection closed' >&2
    exit 42
    ;;
  malformed)
    printf '%s\n' '{"type":"system","subtype":"init","model":"glm-5.3-flash"}' '{broken'
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
      '{"type":"system","subtype":"init","model":"glm-5.3-flash"}' \
      '{"type":"system","subtype":"init","model":"SECRET_PAYLOAD"}' \
      '{"type":"result","subtype":"success","result":"PONG"}'
    ;;
  missing_result|missing_result_debug)
    printf '%s\n' \
      '{"type":"system","subtype":"init","model":"glm-5.3-flash"}' \
      '{"type":"SECRET_PAYLOAD","message":"SECRET_PAYLOAD"}'
    ;;
  empty_result)
    printf '%s\n' \
      '{"type":"system","subtype":"init","model":"glm-5.3-flash"}' \
      '{"type":"result","subtype":"success","result":""}'
    ;;
  terminal_empty_result)
    printf '%s\n' \
      '{"type":"system","subtype":"init","model":"glm-5.3-flash"}' \
      '{"type":"result","subtype":"success","result":"SECRET_PAYLOAD"}' \
      '{"type":"result","subtype":"success","result":""}'
    ;;
  result_error)
    printf '%s\n' \
      '{"type":"system","subtype":"init","model":"glm-5.3-flash"}' \
      '{"type":"result","subtype":"SECRET_PAYLOAD","is_error":true,"result":"SECRET_PAYLOAD"}'
    ;;
  unknown_result_subtype)
    printf '%s\n' \
      '{"type":"system","subtype":"init","model":"glm-5.3-flash"}' \
      '{"type":"result","subtype":"SECRET_PAYLOAD","result":"PONG"}'
    ;;
  numeric_result_subtype)
    printf '%s\n' \
      '{"type":"system","subtype":"init","model":"glm-5.3-flash"}' \
      '{"type":"result","subtype":123,"result":"PONG"}'
    ;;
  auth)
    printf '%s\n' \
      '{"type":"system","subtype":"init","model":"glm-5.3-flash"}' \
      '{"type":"system","subtype":"api_retry","error_status":401,"message":"SECRET_PAYLOAD"}' \
      '{"type":"result","subtype":"error_during_execution","is_error":true,"result":""}'
    exit 1
    ;;
  auth_mixed)
    printf '%s\n' \
      '{"type":"system","subtype":"init","model":"glm-5.3-flash"}' \
      '{"type":"system","subtype":"api_retry","error_status":401}' \
      '{"type":"system","subtype":"api_retry","error_status":429}' \
      '{"type":"result","subtype":"error_during_execution","is_error":true,"result":""}'
    printf '%s\n' 'rate limit SECRET_PAYLOAD' >&2
    exit 1
    ;;
  rate)
    printf '%s\n' \
      '{"type":"system","subtype":"init","model":"glm-5.3-flash"}' \
      '{"type":"system","subtype":"api_retry","error_status":429,"message":"SECRET_PAYLOAD"}' \
      '{"type":"result","subtype":"error_during_execution","is_error":true,"result":""}'
    exit 1
    ;;
  quota)
    printf '%s\n' \
      '{"type":"system","subtype":"init","model":"glm-5.3-flash"}' \
      '{"type":"system","subtype":"api_retry","error_status":429}' \
      '{"type":"rate_limit_event","resets_at":1754400000,"message":"SECRET_PAYLOAD"}' \
      '{"type":"result","subtype":"error_during_execution","is_error":true,"result":""}'
    printf '%s\n' 'SECRET_PAYLOAD' >&2
    exit 1
    ;;
  rate_stderr)
    printf '%s\n' \
      '{"type":"system","subtype":"init","model":"glm-5.3-flash"}' \
      '{"type":"result","subtype":"error_during_execution","is_error":true,"result":""}'
    printf '%s\n' 'Too Many Requests SECRET_PAYLOAD' >&2
    exit 1
    ;;
  extract_no_reclassify)
    printf '%s\n' \
      '{"type":"system","subtype":"init","model":"glm-5.3-flash"}' \
      '{"type":"system","subtype":"api_retry","error_status":429}' \
      '{"type":"result","subtype":"success","is_error":false,"result":""}'
    ;;
  *)
    printf 'unknown fake case: %s\n' "$FAKE_CLAUDE_CASE" >&2
    exit 64
    ;;
esac
FAKE
chmod +x "$TEST_TMP/bin/claude"

cat >"$TEST_TMP/bin/claude-override" <<'FAKE_OVERRIDE'
#!/bin/bash
set -euo pipefail
if [ "${1:-}" = "--help" ]; then
  printf '%s\n' 'usage: claude --effort <level>'
  exit 0
fi
printf '%s\n' \
  '{"type":"system","subtype":"init","model":"glm-5.3-flash"}' \
  '{"type":"result","subtype":"success","result":"OVERRIDE","usage":{"input_tokens":3,"output_tokens":1},"total_cost_usd":0.01}'
FAKE_OVERRIDE
chmod +x "$TEST_TMP/bin/claude-override"

cat >"$TEST_TMP/bin/claude-slow" <<'FAKE_SLOW'
#!/bin/bash
set -euo pipefail
if [ "${1:-}" = "--help" ]; then
  sleep 5
  printf '%s\n' 'usage: claude --effort <level>'
  exit 0
fi
exit 91
FAKE_SLOW
chmod +x "$TEST_TMP/bin/claude-slow"

# Ordinary runner diagnostics use a minimal synthetic qualified scout gate so
# transport and extraction cases do not depend on unrelated operational lanes.
jq '.profiles["glm53-flash-max-scout"].lanes.scout.status = "qualified" |
    .profiles["glm53-flash-max-scout"].lanes.scout.selection = "explicit-only" |
    del(.profiles["glm53-flash-max-scout"].lanes.scout.evaluation_manifest_sha256)' \
  "$ROOT/config/routing-gates.json" >"$TEST_TMP/operational-central.json"
jq '.lanes.scout.backends["claude-zai"].qualified = true |
    .lanes.scout.backends["claude-zai"].status = "qualified" |
    .lanes.scout.backends["claude-zai"].selection = "explicit-only" |
    .lanes.scout.backends["claude-zai"].evaluation_manifest_sha256 = [] |
    .qualified_lanes = ["scout"] |
    .provisional_lanes = []' \
  "$ROOT/config/glm-5.3-flash-max-routing.json" >"$TEST_TMP/operational-executable.json"
export DELEGATION_ROUTING_GATES_FILE="$TEST_TMP/operational-central.json"
export DELEGATION_GLM_ROUTING_FILE="$TEST_TMP/operational-executable.json"

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
  '.model == "glm-5.3-flash" and .tokens.input == 3 and .tokens.output == 1'
[ ! -e "$TEST_TMP/results/success.out.error.json" ] || fail "success wrote an error diagnostic"

PATH="$TEST_TMP/bin:$PATH" TMPDIR="$TEST_TMP/runtime" \
  ZAI_API_KEY="fixture-key" FAKE_CLAUDE_CASE=success \
  "$ROOT/bin/delegation-glm" run \
    --lane scout --effort auto --backend auto \
    --prompt-file "$TEST_TMP/prompt" \
    --output "$TEST_TMP/results/qualified.out" --workdir "$TEST_TMP/work"
[ "$(cat "$TEST_TMP/results/qualified.out")" = PONG ] \
  || fail "qualified dispatch without provisional flag failed"

rc=0
PATH="$TEST_TMP/bin:$PATH" ZAI_API_KEY="fixture-key" FAKE_CLAUDE_CASE=success \
  "$ROOT/bin/delegation-glm" run \
    --lane scout --effort high --backend claude-zai \
    --prompt-file "$TEST_TMP/prompt" --output "$TEST_TMP/results/high-effort.out" \
    --workdir "$TEST_TMP/work" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 64 ] || fail "removed high effort returned $rc, expected 64"

# An explicit binary override is the binary capability-probed and dispatched;
# the neighboring PATH fake returns PONG, so OVERRIDE proves there was no
# post-probe re-resolution through PATH.
PATH="$TEST_TMP/bin:$PATH" TMPDIR="$TEST_TMP/runtime" \
  ZAI_API_KEY="fixture-key" FAKE_CLAUDE_CASE=success \
  DELEGATION_GLM_CLAUDE_BIN="$TEST_TMP/bin/claude-override" \
  "$ROOT/bin/delegation-glm" run \
    --lane scout --effort auto --backend auto \
    --prompt-file "$TEST_TMP/prompt" \
    --output "$TEST_TMP/results/override.out" --workdir "$TEST_TMP/work"
[ "$(cat "$TEST_TMP/results/override.out")" = OVERRIDE ] \
  || fail "explicit Claude binary override was not used for dispatch"

printf 'not executable\n' >"$TEST_TMP/bin/claude-nonexec"
for bad_override in "$TEST_TMP/bin/claude-missing" "$TEST_TMP/bin/claude-nonexec"; do
  PATH="$TEST_TMP/bin:$PATH" ZAI_API_KEY="fixture-key" \
    DELEGATION_GLM_CLAUDE_BIN="$bad_override" \
    "$ROOT/bin/delegation-glm" check --json >"$TEST_TMP/results/bad-override.json"
  assert_json "$TEST_TMP/results/bad-override.json" \
    '.selected_backend == "none" and .backends["claude-zai"].available == false'
done

PATH="$TEST_TMP/bin:$PATH" ZAI_API_KEY="fixture-key" \
  DELEGATION_GLM_CLAUDE_BIN="$TEST_TMP/bin/claude-slow" \
  DELEGATION_GLM_CAPABILITY_TIMEOUT_SECONDS=1 \
  "$ROOT/bin/delegation-glm" check --json >"$TEST_TMP/results/probe-timeout.json"
assert_json "$TEST_TMP/results/probe-timeout.json" \
  '.selected_backend == "none" and .backends["claude-zai"].reason == "Claude Code capability probe timed out"'

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

run_case quota 75
assert_failed_case quota quota_exhausted dispatch 1
assert_json "$TEST_TMP/results/quota.out.error.json" \
  '.next_flush_time == 1754400000 and .schema_version == 2'
run_case rate_stderr 75
assert_failed_case rate_stderr rate_limited dispatch 1
run_case extract_no_reclassify 70
assert_failed_case extract_no_reclassify empty_result extract null

# Evaluation deliberately refuses script launchers: permitting a general-purpose
# shebang interpreter would let a model-launched subprocess inherit the provider
# credential. Replace the broad shell fake with a small native fixture before
# exercising the OS sandbox.
cat >"$TEST_TMP/fake-claude.c" <<'NATIVE_FAKE'
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

static int emit_success(void) {
  puts("{\"type\":\"system\",\"subtype\":\"init\",\"model\":\"glm-5.3-flash\"}");
  puts("{\"type\":\"assistant\",\"message\":{\"model\":\"glm-5.3-flash\"}}");
  puts("{\"type\":\"result\",\"subtype\":\"success\",\"modelUsage\":{\"glm-5.3-flash\":{\"canonicalModel\":\"glm-5.3-flash\",\"provider\":\"firstParty\",\"inputTokens\":3,\"outputTokens\":1}},\"result\":\"PONG\",\"usage\":{\"input_tokens\":3,\"output_tokens\":1},\"total_cost_usd\":0.01}");
  return 0;
}

static int emit_structured(const char *value) {
  puts("{\"type\":\"system\",\"subtype\":\"init\",\"model\":\"glm-5.3-flash\"}");
  puts("{\"type\":\"assistant\",\"message\":{\"model\":\"glm-5.3-flash\"}}");
  printf("{\"type\":\"result\",\"subtype\":\"success\",\"modelUsage\":{\"glm-5.3-flash\":{\"canonicalModel\":\"glm-5.3-flash\",\"provider\":\"firstParty\",\"inputTokens\":3,\"outputTokens\":4}},\"result\":\"\",\"structured_output\":{\"status\":\"completed\",\"answers\":{\"value\":\"%s\"}},\"usage\":{\"input_tokens\":3,\"output_tokens\":4},\"total_cost_usd\":0.01}\n", value);
  return 0;
}

static int emit_structured_without_identity(const char *value) {
  puts("{\"type\":\"system\",\"subtype\":\"init\",\"model\":\"glm-5.3-flash\"}");
  printf("{\"type\":\"result\",\"subtype\":\"success\",\"result\":\"\",\"structured_output\":{\"status\":\"completed\",\"answers\":{\"value\":\"%s\"}},\"usage\":{\"input_tokens\":3,\"output_tokens\":4},\"total_cost_usd\":0.01}\n", value);
  return 0;
}

static int emit_structured_partial_identity(const char *value) {
  puts("{\"type\":\"system\",\"subtype\":\"init\",\"model\":\"glm-5.3-flash\"}");
  puts("{\"type\":\"assistant\",\"message\":{\"model\":\"glm-5.3-flash\"}}");
  puts("{\"type\":\"assistant\",\"message\":{}}");
  printf("{\"type\":\"result\",\"subtype\":\"success\",\"modelUsage\":{\"glm-5.3-flash\":{\"canonicalModel\":\"glm-5.3-flash\",\"provider\":\"firstParty\",\"inputTokens\":3,\"outputTokens\":4}},\"result\":\"\",\"structured_output\":{\"status\":\"completed\",\"answers\":{\"value\":\"%s\"}},\"usage\":{\"input_tokens\":3,\"output_tokens\":4},\"total_cost_usd\":0.01}\n", value);
  return 0;
}

static int emit_structured_multi_usage(const char *value) {
  puts("{\"type\":\"system\",\"subtype\":\"init\",\"model\":\"glm-5.3-flash\"}");
  puts("{\"type\":\"assistant\",\"message\":{\"model\":\"glm-5.3-flash\"}}");
  printf("{\"type\":\"result\",\"subtype\":\"success\",\"modelUsage\":{\"glm-5.3-flash\":{\"canonicalModel\":\"glm-5.3-flash\",\"provider\":\"firstParty\",\"inputTokens\":3,\"outputTokens\":4,\"cacheReadInputTokens\":2,\"cacheCreationInputTokens\":1,\"costUSD\":0.01},\"safety-classifier\":{\"canonicalModel\":\"safety-classifier\",\"provider\":\"firstParty\",\"inputTokens\":5,\"outputTokens\":2,\"cacheReadInputTokens\":1,\"cacheCreationInputTokens\":0,\"costUSD\":0.001}},\"result\":\"\",\"structured_output\":{\"status\":\"completed\",\"answers\":{\"value\":\"%s\"}},\"usage\":{\"input_tokens\":3,\"output_tokens\":4,\"cache_read_input_tokens\":2,\"cache_creation_input_tokens\":1},\"total_cost_usd\":0.01}\n", value);
  return 0;
}

static int readable(const char *path) {
  FILE *file = fopen(path, "r");
  if (!file) return 0;
  fclose(file);
  return 1;
}

static int exec_is_denied(const char *path) {
  pid_t pid = fork();
  int status = 0;
  if (pid < 0) return 0;
  if (pid == 0) {
    execl(path, path, (char *)NULL);
    _exit(errno == EPERM ? 77 : 78);
  }
  if (waitpid(pid, &status, 0) < 0) return 0;
  return WIFEXITED(status) && WEXITSTATUS(status) == 77;
}

int main(int argc, char **argv) {
  const char *mode = getenv("FAKE_CLAUDE_CASE");
  int i;
  if (argc > 1 && strcmp(argv[1], "--help") == 0) {
    puts("usage: claude --effort <level>");
    return 0;
  }
  for (i = 1; i + 1 < argc; i++) {
    if (strcmp(argv[i], "--json-schema") == 0 && strstr(argv[i + 1], "\"$schema\"") != NULL) {
      return 88;
    }
  }
  if (!mode || !*mode || strcmp(mode, "success") == 0) return emit_success();
  if (strcmp(mode, "structured_success") == 0) return emit_structured("PONG");
  if (strcmp(mode, "structured_identity_missing") == 0) return emit_structured_without_identity("PONG");
  if (strcmp(mode, "structured_partial_identity") == 0) return emit_structured_partial_identity("PONG");
  if (strcmp(mode, "structured_multi_usage") == 0) return emit_structured_multi_usage("PONG");
  if (strcmp(mode, "builder_success") == 0) {
    FILE *file = fopen(".git/delegation-canary", "w");
    if (file) { fclose(file); return 91; }
    file = fopen("fixture.txt", "w");
    if (!file) return 92;
    fputs("fixed\n", file); fclose(file);
    file = fopen("ignored-artifact.txt", "w");
    if (!file) return 93;
    fputs("ignored but attested\n", file); fclose(file);
    if (chmod("ignored-artifact.txt", 0755) != 0) return 94;
    puts("{\"type\":\"system\",\"subtype\":\"init\",\"model\":\"glm-5.3-flash\"}");
    puts("{\"type\":\"assistant\",\"message\":{\"model\":\"glm-5.3-flash\"}}");
    puts("{\"type\":\"result\",\"subtype\":\"success\",\"modelUsage\":{\"glm-5.3-flash\":{\"canonicalModel\":\"glm-5.3-flash\",\"provider\":\"firstParty\",\"inputTokens\":4,\"outputTokens\":2}},\"result\":\"{\\\"status\\\":\\\"completed\\\"}\",\"usage\":{\"input_tokens\":4,\"output_tokens\":2},\"total_cost_usd\":0.02}");
    return 0;
  }
  if (strcmp(mode, "read_isolation") == 0) {
    const char *home = getenv("FAKE_FORBIDDEN_HOME");
    const char *source = getenv("FAKE_FORBIDDEN_SOURCE");
    const char *host = getenv("FAKE_FORBIDDEN_HOST");
    const char *config = getenv("CLAUDE_CONFIG_DIR");
    const char *tmpdir = getenv("TMPDIR");
    const char *bun_tmpdir = getenv("BUN_TMPDIR");
    const char *claude_tmpdir = getenv("CLAUDE_TMPDIR");
    const char *claude_code_tmpdir = getenv("CLAUDE_CODE_TMPDIR");
    const char *user = getenv("USER");
    char scratch[4096];
    char value[32];
    FILE *file;
    if (!home || !source || !host || !config || !tmpdir || !bun_tmpdir ||
        !claude_tmpdir || !claude_code_tmpdir || !user || !*user) return 95;
    if (strcmp(tmpdir, bun_tmpdir) != 0 || strcmp(tmpdir, claude_tmpdir) != 0 ||
        strcmp(tmpdir, claude_code_tmpdir) != 0) return 102;
    if (readable(home) || readable(source) || readable(host)) return 96;
    file = fopen("fixture.txt", "r");
    if (!file || !fgets(value, sizeof(value), file)) return 97;
    fclose(file);
    if (strncmp(value, "original", 8) != 0) return 98;
    snprintf(scratch, sizeof(scratch), "%s/read-canary", config);
    file = fopen(scratch, "w");
    if (!file) return 99;
    fputs("scratch\n", file); fclose(file);
    if (!readable(scratch)) return 100;
    if (!exec_is_denied("/usr/bin/env") || !exec_is_denied("/usr/bin/id")) return 101;
    return emit_structured("ISOLATED");
  }
  return 64;
}
NATIVE_FAKE
/usr/bin/cc -O2 -Wall -Wextra -o "$TEST_TMP/bin/claude-native" "$TEST_TMP/fake-claude.c"
mv "$TEST_TMP/bin/claude" "$TEST_TMP/bin/claude-shell"
mv "$TEST_TMP/bin/claude-native" "$TEST_TMP/bin/claude"

# Exercise the real manifest gate from a clean committed copy. Production
# evaluation intentionally rejects this test's dirty source checkout.
EVAL_ROOT="$TEST_TMP/eval-repo"
cp -R "$ROOT/." "$EVAL_ROOT"
rm -rf -- "$EVAL_ROOT/.git"
rm -f -- "$EVAL_ROOT/.claude/settings.local.json"
mkdir -p "$EVAL_ROOT/evaluation/test-fixtures"
printf '%s\n' 'policy annotation contract fixture' \
  >"$EVAL_ROOT/evaluation/test-fixtures/contract.txt"
printf '%s\n' '{"type":"object","required":["annotation"]}' \
  >"$EVAL_ROOT/evaluation/test-fixtures/output-schema.json"
git -C "$EVAL_ROOT" init -q
git -C "$EVAL_ROOT" config user.email test@example.invalid
git -C "$EVAL_ROOT" config user.name delegation-runner-test
git -C "$EVAL_ROOT" add -A
git -C "$EVAL_ROOT" commit -qm 'evaluation fixture base'
EVAL_BASE_COMMIT="$(git -C "$EVAL_ROOT" rev-parse HEAD)"
sha256() { shasum -a 256 "$1" | awk '{print $1}'; }
jq -n \
  --arg prompt_sha256 "$(sha256 "$TEST_TMP/prompt")" \
  --arg runner_sha256 "$(sha256 "$EVAL_ROOT/bin/delegation-glm")" \
  --arg contract_sha256 "$(sha256 "$EVAL_ROOT/evaluation/test-fixtures/contract.txt")" \
  --arg output_schema_sha256 "$(sha256 "$EVAL_ROOT/evaluation/test-fixtures/output-schema.json")" \
  --arg source_commit "$EVAL_BASE_COMMIT" \
  '{schema:"delegation_policy_annotation_evaluation_v1",profile:"glm53-flash-max-policy-annotation",lane:"policy-annotation",model:"glm-5.3-flash",backend:"claude-zai",effort:"max",prompt_sha256:$prompt_sha256,runner_source_commit:$source_commit,runner_sha256:$runner_sha256,contract_path:"evaluation/test-fixtures/contract.txt",contract_sha256:$contract_sha256,output_schema_path:"evaluation/test-fixtures/output-schema.json",output_schema_sha256:$output_schema_sha256,timeout_seconds:60,max_output_chars:1024}' \
  >"$TEST_TMP/glm-evaluation-manifest.json"
GLM_MANIFEST_SHA="$(sha256 "$TEST_TMP/glm-evaluation-manifest.json")"
jq --arg hash "$GLM_MANIFEST_SHA" '
  .profiles["glm53-flash-max-policy-annotation"].lanes["policy-annotation"].evaluation_manifest_sha256 = [$hash]
' "$EVAL_ROOT/config/routing-gates.json" >"$TEST_TMP/glm-central.json"
mv "$TEST_TMP/glm-central.json" "$EVAL_ROOT/config/routing-gates.json"
jq --arg hash "$GLM_MANIFEST_SHA" '
  .lanes["policy-annotation"].backends["claude-zai"].evaluation_manifest_sha256 = [$hash]
' "$EVAL_ROOT/config/glm-5.3-flash-max-routing.json" >"$TEST_TMP/glm-routing.json"
mv "$TEST_TMP/glm-routing.json" "$EVAL_ROOT/config/glm-5.3-flash-max-routing.json"
git -C "$EVAL_ROOT" add config/routing-gates.json config/glm-5.3-flash-max-routing.json
git -C "$EVAL_ROOT" commit -qm 'allowlist GLM evaluation fixture'

PATH="$TEST_TMP/bin:$PATH" TMPDIR="$TEST_TMP/runtime" ZAI_API_KEY=fixture-key \
  FAKE_CLAUDE_CASE=success \
  DELEGATION_ROUTING_GATES_FILE="$EVAL_ROOT/config/routing-gates.json" \
  DELEGATION_GLM_ROUTING_FILE="$EVAL_ROOT/config/glm-5.3-flash-max-routing.json" \
  "$EVAL_ROOT/bin/delegation-glm" run \
  --lane policy-annotation --effort max --backend claude-zai --evaluation \
  --evaluation-manifest "$TEST_TMP/glm-evaluation-manifest.json" \
  --prompt-file "$TEST_TMP/prompt" --output "$TEST_TMP/results/policy-annotation.out" \
  --workdir "$TEST_TMP/work"
[ "$(cat "$TEST_TMP/results/policy-annotation.out")" = PONG ] \
  || fail "policy-annotation output mismatch"
assert_json "$TEST_TMP/results/policy-annotation.out.metrics.json" \
  '.lane == "policy-annotation" and .model == "glm-5.3-flash" and .effort == "max"'

jq '.max_output_chars = 2' "$TEST_TMP/glm-evaluation-manifest.json" \
  >"$TEST_TMP/glm-small-output-manifest.json"
GLM_SMALL_SHA="$(sha256 "$TEST_TMP/glm-small-output-manifest.json")"
jq --arg first "$GLM_MANIFEST_SHA" --arg second "$GLM_SMALL_SHA" '
  .profiles["glm53-flash-max-policy-annotation"].lanes["policy-annotation"].evaluation_manifest_sha256 = [$first, $second]
' "$EVAL_ROOT/config/routing-gates.json" >"$TEST_TMP/glm-central-small.json"
mv "$TEST_TMP/glm-central-small.json" "$EVAL_ROOT/config/routing-gates.json"
jq --arg first "$GLM_MANIFEST_SHA" --arg second "$GLM_SMALL_SHA" '
  .lanes["policy-annotation"].backends["claude-zai"].evaluation_manifest_sha256 = [$first, $second]
' "$EVAL_ROOT/config/glm-5.3-flash-max-routing.json" >"$TEST_TMP/glm-routing-small.json"
mv "$TEST_TMP/glm-routing-small.json" "$EVAL_ROOT/config/glm-5.3-flash-max-routing.json"
git -C "$EVAL_ROOT" add config/routing-gates.json config/glm-5.3-flash-max-routing.json
git -C "$EVAL_ROOT" commit -qm 'allowlist GLM output-limit fixture'
rc=0
PATH="$TEST_TMP/bin:$PATH" TMPDIR="$TEST_TMP/runtime" ZAI_API_KEY=fixture-key \
  FAKE_CLAUDE_CASE=success \
  DELEGATION_ROUTING_GATES_FILE="$EVAL_ROOT/config/routing-gates.json" \
  DELEGATION_GLM_ROUTING_FILE="$EVAL_ROOT/config/glm-5.3-flash-max-routing.json" \
  "$EVAL_ROOT/bin/delegation-glm" run \
  --lane policy-annotation --effort max --backend claude-zai --evaluation \
  --evaluation-manifest "$TEST_TMP/glm-small-output-manifest.json" \
  --prompt-file "$TEST_TMP/prompt" --output "$TEST_TMP/results/policy-too-large.out" \
  --workdir "$TEST_TMP/work" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 70 ] || fail "policy-annotation output limit returned $rc"
[ ! -e "$TEST_TMP/results/policy-too-large.out" ] \
  && [ ! -e "$TEST_TMP/results/policy-too-large.out.metrics.json" ] \
  || fail "policy-annotation output limit published partial artifacts"
assert_json "$TEST_TMP/results/policy-too-large.out.error.json" \
  '.reason == "max_output_chars" and .phase == "extract"'

# Exercise the generic lane-qualification schema with private gate copies. The
# source checkout stays clean and at the exact commit bound by both manifests;
# allowlisting the private hashes therefore cannot create a commit/hash cycle.
LANE_EVAL_ROOT="$TEST_TMP/lane-eval-repo"
cp -R "$ROOT/." "$LANE_EVAL_ROOT"
rm -rf -- "$LANE_EVAL_ROOT/.git"
rm -f -- "$LANE_EVAL_ROOT/.claude/settings.local.json"
jq '. + {"$schema":"https://json-schema.org/draft/2020-12/schema"}' \
  "$LANE_EVAL_ROOT/evaluation/glm-lane-qualification-v1/output-schema.json" \
  >"$TEST_TMP/lane-schema-with-dialect.json"
mv "$TEST_TMP/lane-schema-with-dialect.json" \
  "$LANE_EVAL_ROOT/evaluation/glm-lane-qualification-v1/output-schema.json"
git -C "$LANE_EVAL_ROOT" init -q
git -C "$LANE_EVAL_ROOT" config user.email test@example.invalid
git -C "$LANE_EVAL_ROOT" config user.name delegation-runner-test
git -C "$LANE_EVAL_ROOT" add -A
git -C "$LANE_EVAL_ROOT" commit -qm 'generic lane evaluation fixture'
LANE_SOURCE_COMMIT="$(git -C "$LANE_EVAL_ROOT" rev-parse HEAD)"
LANE_RUNNER_SHA="$(sha256 "$LANE_EVAL_ROOT/bin/delegation-glm")"
LANE_CONTRACT_PATH="evaluation/glm-lane-qualification-v1/contract.json"
LANE_SCHEMA_PATH="evaluation/glm-lane-qualification-v1/output-schema.json"
LANE_CONTRACT_SHA="$(sha256 "$LANE_EVAL_ROOT/$LANE_CONTRACT_PATH")"
LANE_SCHEMA_SHA="$(sha256 "$LANE_EVAL_ROOT/$LANE_SCHEMA_PATH")"

LANE_SCOUT_WORK="$TEST_TMP/lane-scout-work"
LANE_BUILDER_WORK="$TEST_TMP/lane-builder-work"
for fixture in "$LANE_SCOUT_WORK" "$LANE_BUILDER_WORK"; do
  mkdir "$fixture"
  printf '%s\n' 'original' >"$fixture/fixture.txt"
  git -C "$fixture" init -q
  git -C "$fixture" config user.email test@example.invalid
  git -C "$fixture" config user.name delegation-runner-test
  git -C "$fixture" add fixture.txt
  git -C "$fixture" commit -qm 'fixture base'
done
printf '%s\n' 'ignored-artifact.txt' >"$LANE_BUILDER_WORK/.gitignore"
git -C "$LANE_BUILDER_WORK" add .gitignore
git -C "$LANE_BUILDER_WORK" commit -qm 'ignore generated fixture artifact'

make_lane_manifest() {
  local lane="$1" permission="$2" workdir_mode="$3" workdir="$4" destination="$5"
  jq -n \
    --arg lane "$lane" --arg permission "$permission" \
    --arg workdir_mode "$workdir_mode" \
    --arg prompt_sha256 "$(sha256 "$TEST_TMP/prompt")" \
    --arg runner_sha256 "$LANE_RUNNER_SHA" \
    --arg runner_source_commit "$LANE_SOURCE_COMMIT" \
    --arg workdir_commit "$(git -C "$workdir" rev-parse HEAD)" \
    --arg contract_path "$LANE_CONTRACT_PATH" \
    --arg contract_sha256 "$LANE_CONTRACT_SHA" \
    --arg output_schema_path "$LANE_SCHEMA_PATH" \
    --arg output_schema_sha256 "$LANE_SCHEMA_SHA" \
    '{schema:"delegation_glm_lane_evaluation_v1",profile:("glm53-flash-max-" + $lane),lane:$lane,model:"glm-5.3-flash",backend:"claude-zai",effort:"max",permission_mode:$permission,workdir_mode:$workdir_mode,prompt_sha256:$prompt_sha256,runner_source_commit:$runner_source_commit,runner_sha256:$runner_sha256,workdir_commit:$workdir_commit,contract_path:$contract_path,contract_sha256:$contract_sha256,output_schema_path:$output_schema_path,output_schema_sha256:$output_schema_sha256,task_count:3,timeout_seconds:60,max_output_chars:1024,max_cost_usd:2}' \
    >"$destination"
}

LANE_SCOUT_MANIFEST="$TEST_TMP/glm-scout-manifest.json"
LANE_BUILDER_MANIFEST="$TEST_TMP/glm-builder-manifest.json"
make_lane_manifest scout plan read-only "$LANE_SCOUT_WORK" "$LANE_SCOUT_MANIFEST"
make_lane_manifest builder acceptEdits writable-fixture "$LANE_BUILDER_WORK" "$LANE_BUILDER_MANIFEST"
LANE_SCOUT_MANIFEST_SHA="$(sha256 "$LANE_SCOUT_MANIFEST")"
LANE_BUILDER_MANIFEST_SHA="$(sha256 "$LANE_BUILDER_MANIFEST")"

LANE_CENTRAL_GATE="$TEST_TMP/lane-central.json"
LANE_EXECUTABLE_GATE="$TEST_TMP/lane-executable.json"
jq --arg scout "$LANE_SCOUT_MANIFEST_SHA" --arg builder "$LANE_BUILDER_MANIFEST_SHA" '
  .profiles["glm53-flash-max-scout"].lanes.scout.status = "provisional" |
  .profiles["glm53-flash-max-scout"].lanes.scout.selection = "explicit-only" |
  .profiles["glm53-flash-max-builder"].lanes.builder.status = "candidate" |
  .profiles["glm53-flash-max-builder"].lanes.builder.selection = "blocked" |
  .profiles["glm53-flash-max-scout"].lanes.scout.evaluation_manifest_sha256 = [$scout] |
  .profiles["glm53-flash-max-builder"].lanes.builder.evaluation_manifest_sha256 = [$builder]
' "$LANE_EVAL_ROOT/config/routing-gates.json" >"$LANE_CENTRAL_GATE"
jq --arg scout "$LANE_SCOUT_MANIFEST_SHA" --arg builder "$LANE_BUILDER_MANIFEST_SHA" '
  .status = "provisional" |
  .qualified_lanes = [] |
  .provisional_lanes = ["scout"] |
  .lanes.scout.backends["claude-zai"].qualified = false |
  .lanes.scout.backends["claude-zai"].status = "provisional" |
  .lanes.scout.backends["claude-zai"].selection = "explicit-only" |
  .lanes.builder.backends["claude-zai"].qualified = false |
  .lanes.builder.backends["claude-zai"].status = "candidate" |
  .lanes.builder.backends["claude-zai"].selection = "blocked" |
  .lanes.scout.backends["claude-zai"].evaluation_manifest_sha256 = [$scout] |
  .lanes.builder.backends["claude-zai"].evaluation_manifest_sha256 = [$builder]
' "$LANE_EVAL_ROOT/config/glm-5.3-flash-max-routing.json" >"$LANE_EXECUTABLE_GATE"

PATH="$TEST_TMP/bin:$PATH" TMPDIR="$TEST_TMP/runtime" ZAI_API_KEY=fixture-key \
  FAKE_CLAUDE_CASE=structured_success DELEGATION_ROUTING_GATES_FILE="$LANE_CENTRAL_GATE" \
  DELEGATION_GLM_ROUTING_FILE="$LANE_EXECUTABLE_GATE" \
  "$LANE_EVAL_ROOT/bin/delegation-glm" run \
  --lane scout --effort max --backend claude-zai --evaluation \
  --evaluation-manifest "$LANE_SCOUT_MANIFEST" \
  --prompt-file "$TEST_TMP/prompt" --output "$TEST_TMP/results/lane-scout.out" \
  --workdir "$LANE_SCOUT_WORK"
assert_json "$TEST_TMP/results/lane-scout.out" \
  '.status == "completed" and .answers.value == "PONG"'
assert_json "$TEST_TMP/results/lane-scout.out.metrics.json" '
  .lane == "scout" and
  .evaluation_receipt.schema_version == "delegation_glm_lane_evaluation_attempt_receipt_v2" and
  .evaluation_receipt.task_count == 3 and
  .evaluation_receipt.provider_attempts == 1 and
  .evaluation_receipt.post_observation_retries == 0 and
  .evaluation_receipt.changed_paths == [] and
  .evaluation_receipt.ignored_paths == [] and
  .evaluation_receipt.workdir_tree_before_sha256 == .evaluation_receipt.workdir_tree_after_sha256 and
  .evaluation_receipt.git_control_before_sha256 == .evaluation_receipt.git_control_after_sha256
'
[ -z "$(git -C "$LANE_SCOUT_WORK" status --porcelain=v1)" ] \
  || fail "generic scout evaluation modified its read-only fixture"

PATH="$TEST_TMP/bin:$PATH" TMPDIR="$TEST_TMP/runtime" ZAI_API_KEY=fixture-key \
  FAKE_CLAUDE_CASE=structured_multi_usage \
  DELEGATION_ROUTING_GATES_FILE="$LANE_CENTRAL_GATE" \
  DELEGATION_GLM_ROUTING_FILE="$LANE_EXECUTABLE_GATE" \
  "$LANE_EVAL_ROOT/bin/delegation-glm" run \
  --lane scout --effort max --backend claude-zai --evaluation \
  --evaluation-manifest "$LANE_SCOUT_MANIFEST" \
  --prompt-file "$TEST_TMP/prompt" \
  --output "$TEST_TMP/results/lane-multi-usage.out" \
  --workdir "$LANE_SCOUT_WORK"
assert_json "$TEST_TMP/results/lane-multi-usage.out.metrics.json" '
  .usage_source == "model_usage" and
  .observed_assistant_models == ["glm-5.3-flash"] and
  .assistant_event_count == 1 and .assistant_model_attributed_count == 1 and
  .assistant_model_missing_or_malformed_count == 0 and .assistant_model_mismatch_count == 0 and
  .effective_content_model == "glm-5.3-flash" and
  .effective_content_model_source == "assistant_events" and
  .exact_model_identity_attested == true and
  .target_usage_identity_attested == true and
  .tokens == {input:8,output:6,reasoning:0,cache_read:3,cache_write:1} and
  .provider_aggregate_tokens == {input:3,output:4,reasoning:0,cache_read:2,cache_write:1} and
  .provider_cost_usd == 0.011 and .provider_total_cost_usd == 0.01 and
  .target_usage_participant_present == true and
  [.usage_participants[].model] == ["glm-5.3-flash","safety-classifier"] and
  .usage_participants[0].canonical_model == "glm-5.3-flash" and
  .usage_participants[0].provider == "firstParty"
'

rc=0
PATH="$TEST_TMP/bin:$PATH" TMPDIR="$TEST_TMP/runtime" ZAI_API_KEY=fixture-key \
  FAKE_CLAUDE_CASE=structured_identity_missing \
  DELEGATION_ROUTING_GATES_FILE="$LANE_CENTRAL_GATE" \
  DELEGATION_GLM_ROUTING_FILE="$LANE_EXECUTABLE_GATE" \
  "$LANE_EVAL_ROOT/bin/delegation-glm" run \
  --lane scout --effort max --backend claude-zai --evaluation \
  --evaluation-manifest "$LANE_SCOUT_MANIFEST" \
  --prompt-file "$TEST_TMP/prompt" \
  --output "$TEST_TMP/results/lane-identity-missing.out" \
  --workdir "$LANE_SCOUT_WORK" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 70 ] || fail "missing strict identity returned $rc, expected 70"
[ ! -e "$TEST_TMP/results/lane-identity-missing.out" ] &&
  [ ! -e "$TEST_TMP/results/lane-identity-missing.out.metrics.json" ] \
  || fail "missing strict identity published output or metrics"
assert_json "$TEST_TMP/results/lane-identity-missing.out.error.json" \
  '.phase == "extract" and .reason == "strict_identity_evaluation_void"'

rc=0
PATH="$TEST_TMP/bin:$PATH" TMPDIR="$TEST_TMP/runtime" ZAI_API_KEY=fixture-key \
  FAKE_CLAUDE_CASE=structured_partial_identity \
  DELEGATION_ROUTING_GATES_FILE="$LANE_CENTRAL_GATE" \
  DELEGATION_GLM_ROUTING_FILE="$LANE_EXECUTABLE_GATE" \
  "$LANE_EVAL_ROOT/bin/delegation-glm" run \
  --lane scout --effort max --backend claude-zai --evaluation \
  --evaluation-manifest "$LANE_SCOUT_MANIFEST" \
  --prompt-file "$TEST_TMP/prompt" \
  --output "$TEST_TMP/results/lane-partial-identity.out" \
  --workdir "$LANE_SCOUT_WORK" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 70 ] || fail "partial strict identity returned $rc, expected 70"
[ ! -e "$TEST_TMP/results/lane-partial-identity.out" ] &&
  [ ! -e "$TEST_TMP/results/lane-partial-identity.out.metrics.json" ] \
  || fail "partial strict identity published output or metrics"
assert_json "$TEST_TMP/results/lane-partial-identity.out.error.json" \
  '.phase == "extract" and .reason == "strict_identity_evaluation_void"'

READ_CANARY_HOME="$(mktemp -d "$HOME/.delegation-glm-read-test.XXXXXX")"
if [ "${DELEGATION_TEST_KEEP_TMP:-0}" = 1 ]; then
  trap 'rm -rf -- "$READ_CANARY_HOME"; printf "kept test directory: %s\n" "$TEST_TMP" >&2' EXIT
else
  trap 'rm -rf -- "$READ_CANARY_HOME" "$TEST_TMP"' EXIT
fi
printf '%s\n' 'ambient secret' >"$READ_CANARY_HOME/secret"
printf '%s\n' '/private-read-canary' >>"$LANE_EVAL_ROOT/.git/info/exclude"
printf '%s\n' 'source secret' >"$LANE_EVAL_ROOT/private-read-canary"
printf '%s\n' 'host secret' >"$TEST_TMP/host-private-canary"
PATH="$TEST_TMP/bin:$PATH" TMPDIR="$TEST_TMP/runtime" ZAI_API_KEY=fixture-key \
  FAKE_CLAUDE_CASE=read_isolation FAKE_FORBIDDEN_HOME="$READ_CANARY_HOME/secret" \
  FAKE_FORBIDDEN_SOURCE="$LANE_EVAL_ROOT/private-read-canary" \
  FAKE_FORBIDDEN_HOST="$TEST_TMP/host-private-canary" \
  DELEGATION_ROUTING_GATES_FILE="$LANE_CENTRAL_GATE" \
  DELEGATION_GLM_ROUTING_FILE="$LANE_EXECUTABLE_GATE" \
  "$LANE_EVAL_ROOT/bin/delegation-glm" run \
  --lane scout --effort max --backend claude-zai --evaluation \
  --evaluation-manifest "$LANE_SCOUT_MANIFEST" \
  --prompt-file "$TEST_TMP/prompt" --output "$TEST_TMP/results/lane-read-isolation.out" \
  --workdir "$LANE_SCOUT_WORK"
assert_json "$TEST_TMP/results/lane-read-isolation.out" \
  '.status == "completed" and .answers.value == "ISOLATED"'

PATH="$TEST_TMP/bin:$PATH" TMPDIR="$TEST_TMP/runtime" ZAI_API_KEY=fixture-key \
  FAKE_CLAUDE_CASE=builder_success DELEGATION_ROUTING_GATES_FILE="$LANE_CENTRAL_GATE" \
  DELEGATION_GLM_ROUTING_FILE="$LANE_EXECUTABLE_GATE" \
  "$LANE_EVAL_ROOT/bin/delegation-glm" run \
  --lane builder --effort max --backend claude-zai --evaluation \
  --evaluation-manifest "$LANE_BUILDER_MANIFEST" \
  --prompt-file "$TEST_TMP/prompt" --output "$TEST_TMP/results/lane-builder.out" \
  --workdir "$LANE_BUILDER_WORK"
[ "$(cat "$LANE_BUILDER_WORK/fixture.txt")" = fixed ] \
  || fail "generic builder evaluation did not edit its fixture"
[ ! -e "$LANE_BUILDER_WORK/.git/delegation-canary" ] \
  || fail "generic builder evaluation wrote git control state"
assert_json "$TEST_TMP/results/lane-builder.out.metrics.json" '
  .lane == "builder" and
  .evaluation_receipt.schema_version == "delegation_glm_lane_evaluation_attempt_receipt_v2" and
  .evaluation_receipt.workdir_commit != null and
  .evaluation_receipt.workdir_diff_sha256 != null and
  .evaluation_receipt.workdir_tree_before_sha256 != .evaluation_receipt.workdir_tree_after_sha256 and
  .evaluation_receipt.git_control_before_sha256 == .evaluation_receipt.git_control_after_sha256 and
  .evaluation_receipt.changed_paths == ["fixture.txt", "ignored-artifact.txt"] and
  .evaluation_receipt.ignored_paths == ["ignored-artifact.txt"] and
  (.evaluation_receipt.changed_path_modes | map(select(.path == "ignored-artifact.txt" and .mode == "0755")) | length) == 1
'

rc=0
PATH="$TEST_TMP/bin:$PATH" ZAI_API_KEY=fixture-key FAKE_CLAUDE_CASE=success \
  "$ROOT/bin/delegation-glm" run \
    --lane scout --effort max --backend claude-zai --evaluation \
    --allow-provisional --evaluation-manifest "$LANE_SCOUT_MANIFEST" \
    --prompt-file "$TEST_TMP/prompt" --output "$TEST_TMP/results/eval-provisional.out" \
    --workdir "$LANE_SCOUT_WORK" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 64 ] || fail "evaluation plus provisional returned $rc, expected 64"

mv "$TEST_TMP/bin/claude" "$TEST_TMP/bin/claude-native"
mv "$TEST_TMP/bin/claude-shell" "$TEST_TMP/bin/claude"

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
