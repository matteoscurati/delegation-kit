#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/delegation-qwen-test.XXXXXX")"
trap 'rm -rf -- "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/work" "$TMP/results" "$TMP/runtime" "$TMP/debug"
printf 'Respond with PONG.\n' >"$TMP/prompt"

cat >"$TMP/bin/curl" <<'EOF'
#!/usr/bin/env bash
output=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o) output="${2:-}"; shift 2 ;;
    --config|-w|--connect-timeout|--max-time|--data-binary) shift 2 ;;
    -sS) shift ;;
    *) shift ;;
  esac
done
[ -n "$output" ] || exit 90
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

run_case() {
  local name="$1" expected="$2"
  shift 2
  local rc=0
  PATH="$TMP/bin:$PATH" TMPDIR="$TMP/runtime" \
    QWEN_TOKEN_PLAN_API_KEY=sk-sp-test FAKE_QWEN_CASE="$name" \
    "$ROOT/bin/delegation-qwen" run --lane clerk --effort auto \
    --backend token-plan-openai --evaluation --prompt-file "$TMP/prompt" \
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
  --prompt-file "$TMP/prompt" --output "$TMP/results/judgement.out" \
  --workdir "$TMP/work" >/dev/null 2>&1 || rc=$?
[ "$rc" = 78 ] || fail "disabled judgement evaluation returned $rc"

run_case success 0
[ "$(cat "$TMP/results/success.out")" = PONG ] || fail 'success output mismatch'
json "$TMP/results/success.out.metrics.json" \
  '.model == "qwen3.8-max-preview" and .effort == "xhigh" and
   .tokens.input == 7 and .tokens.output == 3'
[ ! -e "$TMP/results/success.out.error.json" ] || fail 'success left diagnostic'

for spec in \
  'auth 69 authentication_failed dispatch 401' \
  'rate 75 rate_limited dispatch 429' \
  'server 75 provider_temporary_failure dispatch 503' \
  'provider 70 provider_error dispatch 400' \
  'malformed 70 invalid_or_empty_response extract 200' \
  'empty 70 invalid_or_empty_response extract 200' \
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
  "$ROOT/bin/delegation-qwen" run --lane clerk --evaluation \
  --prompt-file "$TMP/prompt" --output "$TMP/results/existing.out" \
  --workdir "$TMP/work" >/dev/null 2>&1 || rc=$?
[ "$rc" = 64 ] || fail 'existing output accepted'
[ "$(cat "$TMP/results/existing.out")" = existing ] || fail 'existing output changed'

ln -s "$TMP/results/existing.out" "$TMP/results/symlink.out.error.json"
rc=0
PATH="$TMP/bin:$PATH" QWEN_TOKEN_PLAN_API_KEY=sk-sp-test \
  "$ROOT/bin/delegation-qwen" run --lane clerk --evaluation \
  --prompt-file "$TMP/prompt" --output "$TMP/results/symlink.out" \
  --workdir "$TMP/work" >/dev/null 2>&1 || rc=$?
[ "$rc" = 64 ] || fail 'symlink diagnostic accepted'
[ "$(cat "$TMP/results/existing.out")" = existing ] || fail 'symlink target changed'

mkdir "$TMP/work/debug"
rc=0
PATH="$TMP/bin:$PATH" QWEN_TOKEN_PLAN_API_KEY=sk-sp-test \
  "$ROOT/bin/delegation-qwen" run --lane clerk --evaluation \
  --prompt-file "$TMP/prompt" --output "$TMP/results/worktree-debug.out" \
  --workdir "$TMP/work" --debug-dir "$TMP/work/debug" >/dev/null 2>&1 || rc=$?
[ "$rc" = 64 ] || fail 'debug directory inside read-only workdir accepted'

[ -z "$(find "$TMP/runtime" -mindepth 1 -maxdepth 1 -name 'delegation-qwen.*' -print)" ] \
  || fail 'temporary directories not cleaned'
printf 'Qwen runner diagnostics tests passed.\n'
