#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/delegation-grok-tests.XXXXXX")"
trap 'rm -rf -- "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/work" "$TMP/results" "$TMP/debug" "$TMP/grok-home"
chmod 700 "$TMP/debug" "$TMP/grok-home"
printf '%s\n' '{"test":"credential"}' >"$TMP/grok-home/auth.json"

fail() { printf 'grok runner test failed: %s\n' "$*" >&2; exit 1; }

cat >"$TMP/bin/grok" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  --help)
    printf '%s\n' '--prompt-file --model --reasoning-effort --output-format --permission-mode --sandbox --no-memory --no-subagents --tools --max-turns'
    exit 0
    ;;
  models)
    printf 'You are logged in with grok.com.\n\nAvailable models:\n  * grok-4.5 (default)\n'
    exit 0
    ;;
  inspect)
    [ "${2:-}" = --json ] || exit 2
    jq -n --arg target "$HOME/.grok/hooks/delegation-policy.sh" '
      {mcpServers:[],plugins:[],permissions:{sources:[]},hooks:[]}
    '
    exit 0
    ;;
  --version)
    printf 'grok %s\n' "${GROK_FAKE_VERSION:-0.2.111}"
    exit 0
    ;;
esac
args=" $* "
for required in \
  '--model grok-4.5' '--reasoning-effort high' \
  '--permission-mode dontAsk' '--sandbox delegation-kit' \
  '--output-format json' '--no-memory' '--no-subagents' '--disable-web-search' \
  '--no-auto-update' '--max-turns 40' \
  '--tools grep,read_file,search_replace,list_dir,todo_write' \
  '--allow Edit(**)' \
  '--deny Edit(**/.grok/config.toml)' \
  '--deny Edit(**/.grok/sandbox.toml)' '--deny Edit(**/.grok/auth.json)'; do
  case "$args" in *" $required "*) ;; *) printf 'missing required argument: %s\n' "$required" >&2; exit 2 ;; esac
done
case "${GROK_FAKE_MODE:-success}" in
  auth) printf 'raw secret login required status 401\n' >&2; exit 1 ;;
  rate) printf 'raw secret rate limit status 429\n' >&2; exit 1 ;;
  timeout) sleep 3; exit 0 ;;
esac
mkdir -p "$HOME/.grok"
case "${GROK_FAKE_MODE:-success}" in
  sandbox_missing) ;;
  sandbox_unenforced)
    printf '%s\n' '{"event_type":"ProfileApplied","profile":"delegation-kit","enforced":false}' \
      >"$HOME/.grok/sandbox-events.jsonl"
    ;;
  *)
    printf '%s\n' '{"event_type":"ProfileApplied","profile":"delegation-kit","enforced":true}' \
      >"$HOME/.grok/sandbox-events.jsonl"
    ;;
esac
if [ "${GROK_FAKE_MODE:-success}" = malformed ]; then
  printf '{"text":"PONG"}\n'
  exit 0
fi
stop_reason=EndTurn
[ "${GROK_FAKE_MODE:-success}" != max_turns ] || stop_reason=MaxTurns
[ "${GROK_FAKE_MODE:-success}" != cancelled ] || stop_reason=Cancelled
[ "${GROK_FAKE_MODE:-success}" != unexpected_stop ] || stop_reason=Unknown
jq -n --arg stop_reason "$stop_reason" '
  {text:"PONG",thought:"SECRET_THOUGHT",stopReason:$stop_reason,num_turns:2,
   usage:{input_tokens:100,output_tokens:20,reasoning_tokens:7,
     cache_read_input_tokens:30,total_tokens:157},
   total_cost_usd:0.02,
   modelUsage:{"grok-4.5-build":{inputTokens:100,outputTokens:20,
     cacheReadInputTokens:30,modelCalls:1,costUSD:0.02}}}
'
EOF
chmod 755 "$TMP/bin/grok"
printf 'Reply with exactly PONG.\n' >"$TMP/prompt.txt"

run_grok() {
  DELEGATION_GROK_HOME="$TMP/grok-home" PATH="$TMP/bin:$PATH" \
    "$ROOT/bin/delegation-grok" "$@"
}

run_grok check --json >"$TMP/check.json"
jq -e '
  .model == "grok-4.5" and
  .runtime_cli_version == "0.2.111" and
  .selected_backend == "grok-build" and
  .provisional_lanes == ["builder","frontend-builder"] and
  .qualified_lanes == [] and
  .backends["grok-build"].sandbox == "delegation-kit" and
  .backends["grok-build"].permission_mode == "dontAsk" and
  .backends["grok-build"].max_turns == 40 and
  .backends["grok-build"].timeout_seconds == 900 and
  .backends["grok-build"].isolated_home == true and
  .backends["grok-build"].plugins == false and
  .backends["grok-build"].mcp == false
' "$TMP/check.json" >/dev/null || fail "check contract mismatch"
! grep -q 'run_terminal_cmd' "$TMP/check.json" || fail "terminal tool leaked into check contract"

rc=0
run_grok run --lane builder --prompt-file "$TMP/prompt.txt" \
  --output "$TMP/results/refused.txt" --workdir "$TMP/work" >/dev/null 2>&1 || rc=$?
[ "$rc" = 78 ] || fail "provisional run without explicit flag returned $rc"

run_grok run --lane builder --allow-provisional --prompt-file "$TMP/prompt.txt" \
  --output "$TMP/results/builder.txt" --workdir "$TMP/work"
[ "$(cat "$TMP/results/builder.txt")" = PONG ] || fail "text extraction mismatch"
! grep -q SECRET_THOUGHT "$TMP/results/builder.txt" || fail "thought leaked into output"
jq -e '
  .model == "grok-4.5" and .runtime_model == "grok-4.5" and
  .runtime_cli_version == "0.2.111" and
  .usage_model == "grok-4.5-build" and .effort == "high" and
  .lane == "builder" and .tokens.reasoning == 7 and
  .provider_cost_usd == 0.02 and .sandbox == "delegation-kit" and
  .permission_mode == "dontAsk" and .max_turns == 40 and
  .timeout_seconds == 900 and .isolated_home == true
' "$TMP/results/builder.txt.metrics.json" >/dev/null || fail "metrics mismatch"

run_grok run --lane frontend-builder --allow-provisional --prompt-file "$TMP/prompt.txt" \
  --output "$TMP/results/frontend.txt" --workdir "$TMP/work"
[ "$(cat "$TMP/results/frontend.txt")" = PONG ] || fail "frontend lane failed"

rc=0
run_grok run --lane builder --allow-provisional --effort max --prompt-file "$TMP/prompt.txt" \
  --output "$TMP/results/effort.txt" --workdir "$TMP/work" >/dev/null 2>&1 || rc=$?
[ "$rc" = 64 ] || fail "invalid effort returned $rc"

rc=0
GROK_FAKE_VERSION=0.2.112 run_grok run \
  --lane builder --allow-provisional --prompt-file "$TMP/prompt.txt" \
  --output "$TMP/results/version.txt" --workdir "$TMP/work" >/dev/null 2>&1 || rc=$?
[ "$rc" = 69 ] || fail "version mismatch returned $rc"

for mode in sandbox_missing sandbox_unenforced max_turns cancelled unexpected_stop malformed; do
  rc=0
  GROK_FAKE_MODE="$mode" run_grok run \
    --lane builder --allow-provisional --prompt-file "$TMP/prompt.txt" \
    --output "$TMP/results/$mode.txt" --workdir "$TMP/work" >/dev/null 2>&1 || rc=$?
  [ "$rc" = 70 ] || fail "$mode returned $rc"
  [ ! -e "$TMP/results/$mode.txt" ] || fail "$mode published output"
  jq -e '.reason | type == "string"' "$TMP/results/$mode.txt.error.json" >/dev/null \
    || fail "$mode did not write a sanitized diagnostic"
done

rc=0
GROK_FAKE_MODE=auth run_grok run \
  --lane builder --allow-provisional --prompt-file "$TMP/prompt.txt" \
  --output "$TMP/results/auth.txt" --workdir "$TMP/work" >/dev/null 2>&1 || rc=$?
[ "$rc" = 69 ] || fail "auth failure returned $rc"
! grep -q 'raw secret' "$TMP/results/auth.txt.error.json" || fail "raw auth stderr leaked"
[ ! -e "$TMP/results/auth.txt.stderr" ] || fail "legacy raw stderr artifact created"

rc=0
GROK_FAKE_MODE=rate run_grok run \
  --lane builder --allow-provisional --prompt-file "$TMP/prompt.txt" \
  --output "$TMP/results/rate.txt" --workdir "$TMP/work" >/dev/null 2>&1 || rc=$?
[ "$rc" = 75 ] || fail "rate failure returned $rc"

rc=0
DELEGATION_GROK_TIMEOUT_SECONDS=1 GROK_FAKE_MODE=timeout run_grok run \
  --lane builder --allow-provisional --prompt-file "$TMP/prompt.txt" \
  --output "$TMP/results/timeout.txt" --workdir "$TMP/work" >/dev/null 2>&1 || rc=$?
[ "$rc" = 75 ] || fail "timeout returned $rc"
jq -e '.reason == "timeout"' "$TMP/results/timeout.txt.error.json" >/dev/null \
  || fail "timeout diagnostic mismatch"

rc=0
GROK_FAKE_MODE=auth run_grok run \
  --lane builder --allow-provisional --prompt-file "$TMP/prompt.txt" \
  --output "$TMP/results/debug.txt" --workdir "$TMP/work" \
  --debug-dir "$TMP/debug" >/dev/null 2>&1 || rc=$?
[ "$rc" = 69 ] || fail "debug auth failure returned $rc"
debug_path="$(jq -r '.debug_path' "$TMP/results/debug.txt.error.json")"
[ -d "$debug_path" ] || fail "debug path was not preserved"
[ "$(stat -f '%Lp' "$debug_path")" = 700 ] || fail "debug directory permissions are not 700"
grep -q 'raw secret' "$debug_path/stderr.txt" || fail "opt-in debug stderr missing"

printf 'Grok runner tests passed.\n'
