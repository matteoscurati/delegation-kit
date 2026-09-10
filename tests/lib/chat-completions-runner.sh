#!/usr/bin/env bash
# Shared diagnostics for the OpenAI-compatible text-only runners.
# Provider wrappers set the exact model, backend, default effort, and key name.
set -euo pipefail

: "${PROVIDER_SLUG:?}"
: "${PROVIDER_LABEL:?}"
: "${MODEL:?}"
: "${BACKEND:?}"
: "${EFFORT:?}"
: "${RUNNER_NAME:?}"
: "${API_KEY_ENV:?}"
: "${API_KEY_VALUE:?}"
: "${EXPECT_THINKING:?}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/delegation-${PROVIDER_SLUG}-test.XXXXXX")"
trap 'rm -rf -- "$TMP" 2>/dev/null || true' EXIT
mkdir -p "$TMP/bin" "$TMP/work" "$TMP/results" "$TMP/runtime" "$TMP/debug"
printf 'Respond with PONG.\n' >"$TMP/prompt"

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
model="${FAKE_PROVIDER_MODEL:?}"
if [ -n "${FAKE_PROVIDER_REQUEST_CAPTURE:-}" ]; then
  cp "$request" "$FAKE_PROVIDER_REQUEST_CAPTURE" || exit 91
fi
case "${FAKE_PROVIDER_CASE:-success}" in
  success)
    printf '{"model":"%s","choices":[{"message":{"content":"PONG"}}],"usage":{"prompt_tokens":7,"completion_tokens":3}}\n' "$model" >"$output"
    printf '200'
    ;;
  auth)
    printf '{"model":"%s","error":{"message":"SECRET_PROVIDER_RESPONSE"}}\n' "$model" >"$output"
    printf '401'
    ;;
  rate)
    printf '{"model":"%s","error":{"message":"SECRET_PROVIDER_RESPONSE"}}\n' "$model" >"$output"
    printf '429'
    ;;
  server)
    printf '{"model":"%s","error":{"message":"SECRET_PROVIDER_RESPONSE"}}\n' "$model" >"$output"
    printf '503'
    ;;
  provider)
    printf '{"model":"%s","error":{"message":"SECRET_PROVIDER_RESPONSE"}}\n' "$model" >"$output"
    printf '400'
    ;;
  malformed)
    printf '%s\n' '{not-json SECRET_PROVIDER_RESPONSE' >"$output"
    printf '200'
    ;;
  empty)
    printf '{"model":"%s","choices":[{"message":{"content":""}}]}\n' "$model" >"$output"
    printf '200'
    ;;
  identity)
    printf '{"model":"%s-fallback","choices":[{"message":{"content":"PONG"}}]}\n' "$model" >"$output"
    printf '200'
    ;;
  transport)
    printf 'SECRET_CURL_STDERR\n' >&2
    exit 7
    ;;
  timeout)
    printf 'SECRET_CURL_STDERR\n' >&2
    exit 28
    ;;
  *)
    exit 64
    ;;
esac
EOF
chmod +x "$TMP/bin/curl"
chmod +x "$TMP/bin/curl"

RUNNER="$ROOT/bin/$RUNNER_NAME"
export "$API_KEY_ENV=$API_KEY_VALUE"
export FAKE_PROVIDER_MODEL="$MODEL"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
json() { jq -e "$2" "$1" >/dev/null || fail "$1 did not satisfy $2"; }

run_case() {
  local name="$1" expected="$2"
  shift 2
  local rc=0
  PATH="$TMP/bin:$PATH" TMPDIR="$TMP/runtime" \
    FAKE_PROVIDER_CASE="$name" \
    FAKE_PROVIDER_REQUEST_CAPTURE="$TMP/results/$name.request.json" \
    "$RUNNER" run --lane policy-annotation --effort auto \
    --backend "$BACKEND" --prompt-file "$TMP/prompt" \
    --output "$TMP/results/$name.out" --workdir "$TMP/work" "$@" \
    >"$TMP/results/$name.stdout" 2>"$TMP/results/$name.stderr" || rc=$?
  [ "$rc" = "$expected" ] || fail "$name returned $rc, expected $expected"
}

PATH="$TMP/bin:$PATH" \
  "$RUNNER" check --json >"$TMP/check.json"
jq -e --arg model "$MODEL" --arg backend "$BACKEND" --arg effort "$EFFORT" \
  '.model == $model and .adapter == $backend and
   .roles == ["builder","clerk","scout","reviewer","senior","judgement","policy-annotation"] and
   (.efforts | index($effort) != null) and .default_effort == $effort and
   .selected_backend == $backend and .backends[$backend].available == true' \
  "$TMP/check.json" >/dev/null || fail 'provider check did not expose the adapter contract'
PATH="$TMP/bin:$PATH" "$RUNNER" check >"$TMP/check.txt"
grep -q "selected=$BACKEND roles=builder,clerk,scout,reviewer,senior,judgement,policy-annotation" "$TMP/check.txt" \
  || fail 'text check did not report the adapter roles'

# The builder role dispatches at the adapter default effort with the 4096 ceiling.
rc=0
PATH="$TMP/bin:$PATH" TMPDIR="$TMP/runtime" \
  FAKE_PROVIDER_CASE=success \
  FAKE_PROVIDER_REQUEST_CAPTURE="$TMP/results/builder.request.json" \
  "$RUNNER" run --lane builder \
  --prompt-file "$TMP/prompt" --output "$TMP/results/builder.out" \
  --workdir "$TMP/work" >/dev/null 2>&1 || rc=$?
[ "$rc" = 0 ] || fail "builder returned $rc"
[ "$(cat "$TMP/results/builder.out")" = PONG ] || fail 'builder output mismatch'
jq -e --arg model "$MODEL" --arg effort "$EFFORT" --arg backend "$BACKEND" \
  '.schema_version == 2 and .model == $model and .requested_model == $model and
   .provider_reported_model == $model and .model_identity_source == "provider-reported" and
   .backend == $backend and .lane == "builder" and .effort == $effort' \
  "$TMP/results/builder.out.metrics.json" >/dev/null || fail 'builder metrics mismatch'
json "$TMP/results/builder.out.metrics.json" 'has("evaluation_receipt") | not'
jq -e --arg effort "$EFFORT" '.max_tokens == 4096 and .reasoning_effort == $effort' \
  "$TMP/results/builder.request.json" >/dev/null || fail 'builder request mismatch'
if [ "$EXPECT_THINKING" = true ]; then
  json "$TMP/results/builder.request.json" '.thinking.type == "enabled"'
fi
[ ! -e "$TMP/results/builder.out.commit.json" ] || fail 'builder run wrote commit marker'

# --allow-provisional is a deprecated no-op that only warns.
rc=0
PATH="$TMP/bin:$PATH" TMPDIR="$TMP/runtime" FAKE_PROVIDER_CASE=success \
  "$RUNNER" run --lane builder --allow-provisional \
  --prompt-file "$TMP/prompt" --output "$TMP/results/builder-deprecated.out" \
  --workdir "$TMP/work" >/dev/null 2>"$TMP/results/builder-deprecated.stderr" || rc=$?
[ "$rc" = 0 ] || fail "deprecated flag returned $rc"
grep -q 'deprecated' "$TMP/results/builder-deprecated.stderr" || fail 'deprecated flag did not warn'

# The caller chooses the effort; any tier the provider exposes is accepted.
rc=0
PATH="$TMP/bin:$PATH" TMPDIR="$TMP/runtime" FAKE_PROVIDER_CASE=success \
  FAKE_PROVIDER_REQUEST_CAPTURE="$TMP/results/builder-effort.request.json" \
  "$RUNNER" run --lane builder --effort high \
  --prompt-file "$TMP/prompt" --output "$TMP/results/builder-effort.out" \
  --workdir "$TMP/work" >/dev/null 2>&1 || rc=$?
[ "$rc" = 0 ] || fail "explicit effort returned $rc"
json "$TMP/results/builder-effort.request.json" '.reasoning_effort == "high"'

# Removed qualification flags are unknown arguments, never silent no-ops.
for removed in --evaluation --preflight-only; do
  rc=0
  PATH="$TMP/bin:$PATH" "$RUNNER" run --lane builder "$removed" \
    --prompt-file "$TMP/prompt" --output "$TMP/results/removed-flag.out" \
    --workdir "$TMP/work" >/dev/null 2>&1 || rc=$?
  [ "$rc" = 64 ] || fail "removed flag $removed returned $rc"
  [ ! -e "$TMP/results/removed-flag.out" ] || fail "removed flag $removed created output"
done
rc=0
PATH="$TMP/bin:$PATH" "$RUNNER" run --lane builder \
  --evaluation-manifest "$TMP/missing-manifest.json" \
  --prompt-file "$TMP/prompt" --output "$TMP/results/removed-flag.out" \
  --workdir "$TMP/work" >/dev/null 2>&1 || rc=$?
[ "$rc" = 64 ] || fail "removed flag --evaluation-manifest returned $rc"

# A role the text-only adapter does not support fails closed before any
# runtime or credential inspection.
rc=0
env PATH="/usr/bin:/bin" "$API_KEY_ENV=" \
  "$RUNNER" run --lane frontend-builder --prompt-file "$TMP/prompt" \
  --output "$TMP/results/unsupported-role.out" \
  --workdir "$TMP/work" >/dev/null 2>&1 || rc=$?
[ "$rc" = 78 ] || fail "unsupported role returned $rc"
[ ! -e "$TMP/results/unsupported-role.out" ] || fail 'unsupported role created output'

run_case success 0
[ "$(cat "$TMP/results/success.out")" = PONG ] || fail 'success output mismatch'
jq -e --arg model "$MODEL" --arg effort "$EFFORT" \
  '.model == $model and .effort == $effort and .lane == "policy-annotation" and
   .tokens.input == 7 and .tokens.output == 3' \
  "$TMP/results/success.out.metrics.json" >/dev/null || fail 'success metrics mismatch'
[ ! -e "$TMP/results/success.out.error.json" ] || fail 'success left diagnostic'
[ ! -e "$TMP/results/success.out.commit.json" ] || fail 'success wrote commit marker'
json "$TMP/results/success.request.json" '.max_tokens == 4096'

# Handled publication failures clean every member.
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
for phase in output metrics; do
  out="$TMP/results/publish-$phase.out"
  case "$phase" in
    output) target="$out" ;;
    metrics) target="$out.metrics.json" ;;
  esac
  target="$(cd "$(dirname "$target")" && pwd -P)/$(basename "$target")"
  rc=0
  FAIL_MV_TARGET="$target" PATH="$TMP/mv-fail:$TMP/bin:$PATH" \
    TMPDIR="$TMP/runtime" FAKE_PROVIDER_CASE=success \
    "$RUNNER" run --lane policy-annotation --effort auto \
    --backend "$BACKEND" --prompt-file "$TMP/prompt" \
    --output "$out" --workdir "$TMP/work" \
    >/dev/null 2>&1 || rc=$?
  [ "$rc" = 70 ] || fail "$phase publication failure returned $rc"
  [ ! -e "$out" ] && [ ! -e "$out.metrics.json" ] \
    || fail "$phase publication failure left a published member"
done

for spec in \
  'auth 69 authentication_failed dispatch 401' \
  'rate 75 rate_limited dispatch 429' \
  'server 75 provider_temporary_failure dispatch 503' \
  'provider 70 provider_error dispatch 400' \
  'malformed 70 invalid_or_empty_response extract 200' \
  'empty 70 invalid_or_empty_response extract 200' \
  'identity 70 provider_identity_mismatch extract 200' \
  'transport 75 transport_failure dispatch 000' \
  'timeout 75 deadline_exceeded dispatch 000'
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
debug_run="$(find "$TMP/debug" -maxdepth 1 -type d -name "delegation-${PROVIDER_SLUG}.*" | head -1)"
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
PATH="$TMP/bin:$PATH" \
  "$RUNNER" run --lane policy-annotation \
  --prompt-file "$TMP/prompt" --output "$TMP/results/existing.out" \
  --workdir "$TMP/work" >/dev/null 2>&1 || rc=$?
[ "$rc" = 64 ] || fail 'existing output accepted'
[ "$(cat "$TMP/results/existing.out")" = existing ] || fail 'existing output changed'

ln -s "$TMP/results/existing.out" "$TMP/results/symlink.out.error.json"
rc=0
PATH="$TMP/bin:$PATH" \
  "$RUNNER" run --lane policy-annotation \
  --prompt-file "$TMP/prompt" --output "$TMP/results/symlink.out" \
  --workdir "$TMP/work" >/dev/null 2>&1 || rc=$?
[ "$rc" = 64 ] || fail 'symlink diagnostic accepted'
[ "$(cat "$TMP/results/existing.out")" = existing ] || fail 'symlink target changed'

mkdir "$TMP/work/debug"
rc=0
PATH="$TMP/bin:$PATH" \
  "$RUNNER" run --lane policy-annotation \
  --prompt-file "$TMP/prompt" --output "$TMP/results/worktree-debug.out" \
  --workdir "$TMP/work" --debug-dir "$TMP/work/debug" >/dev/null 2>&1 || rc=$?
[ "$rc" = 64 ] || fail 'debug directory inside read-only workdir accepted'

rc=0
PATH="$TMP/bin:$PATH" \
  "$RUNNER" run --lane policy-annotation \
  --prompt-file "$TMP/prompt" --output "$TMP/work/inside.out" \
  --workdir "$TMP/work" >/dev/null 2>&1 || rc=$?
[ "$rc" = 64 ] || fail 'output inside the workdir accepted'

[ -z "$(find "$TMP/runtime" -mindepth 1 -maxdepth 1 -name "delegation-${PROVIDER_SLUG}.*" -print)" ] \
  || fail 'temporary directories not cleaned'
printf '%s runner diagnostics tests passed.\n' "$PROVIDER_LABEL"
