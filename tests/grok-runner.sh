#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/delegation-grok-tests.XXXXXX")"
trap 'rm -rf -- "$TMP"' EXIT
export DELEGATION_DATA_HOME="$TMP/runtime"
mkdir -p "$TMP/bin" "$TMP/work" "$TMP/results" "$TMP/debug" "$TMP/grok-home"
chmod 700 "$TMP/debug" "$TMP/grok-home"
jq -n '{"https://auth.x.ai::test":{key:"initial-access",refresh_token:"initial-refresh",expires_at:"2099-01-01T00:00:00Z"}}' \
  >"$TMP/grok-home/auth.json"
chmod 600 "$TMP/grok-home/auth.json"

fail() { printf 'grok runner test failed: %s\n' "$*" >&2; exit 1; }

cat >"$TMP/bin/grok" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
FAKE_GROK_HOME="${GROK_HOME:-$HOME/.grok}"
case "${1:-}" in
  --help)
    printf '%s\n' \
      '--prompt-file --model --reasoning-effort --output-format --permission-mode' \
      '--sandbox --no-memory --no-subagents --disable-web-search --tools' \
      '--allow --deny --max-turns' \
      '  inspect  Show configuration' \
      '  models   List models'
    exit 0
    ;;
  models)
    if [ "${2:-}" = --help ]; then
      printf 'List available models and exit\n'
      exit 0
    fi
    printf 'You are logged in with grok.com.\n\nAvailable models:\n  * grok-4.6 (default)\n'
    exit 0
    ;;
  inspect)
    if [ "${2:-}" = --help ]; then
      printf '%s\n' 'Show configuration' '--json'
      exit 0
    fi
    [ "${2:-}" = --json ] || exit 2
    # Project configuration is bound to the invocation directory: a workdir
    # carrying a Grok project config with hooks contaminates the inspection
    # even when the isolated home is clean.
    if [ -f "$PWD/.grok/project-config.toml" ]; then
      jq -n '{mcpServers:[],plugins:[],permissions:{sources:[]},hooks:["project-hook"]}'
    else
      jq -n '{mcpServers:[],plugins:[],permissions:{sources:[]},hooks:[]}'
    fi
    exit 0
    ;;
  --version)
    printf 'grok %s\n' "${GROK_FAKE_VERSION:-user-build-a}"
    exit 0
    ;;
esac
args=" $* "
sandbox_profile=""
previous=""
for argument in "$@"; do
  if [ "$previous" = --sandbox ]; then sandbox_profile="$argument"; break; fi
  previous="$argument"
done
for required in \
  '--model grok-4.6' '--reasoning-effort high' \
  '--permission-mode dontAsk' \
  '--output-format json' '--no-memory' '--no-subagents' '--disable-web-search' \
  '--no-auto-update' '--max-turns 40' \
  '--deny Edit(**/.grok/config.toml)' \
  '--deny Edit(**/.grok/sandbox.toml)' '--deny Edit(**/.grok/auth.json)'; do
  case "$args" in *" $required "*) ;; *) printf 'missing required argument: %s\n' "$required" >&2; exit 2 ;; esac
done
if [ "$sandbox_profile" = delegation-kit-read-only ]; then
  grep -q '^extends = "read-only"$' "$FAKE_GROK_HOME/sandbox.toml" \
    || { printf 'read-only sandbox profile is missing enforcement\n' >&2; exit 2; }
  ! grep -q '^read_only = true$' "$FAKE_GROK_HOME/sandbox.toml" \
    || { printf 'read-only sandbox profile uses unsupported boolean syntax\n' >&2; exit 2; }
  for required in '--tools grep,read_file,list_dir'; do
    case "$args" in *" $required "*) ;; *) printf 'missing read-only argument: %s\n' "$required" >&2; exit 2 ;; esac
  done
  case "$args" in *' --allow Edit(**) '*) printf 'read-only invocation exposed Edit\n' >&2; exit 2 ;; esac
else
  case "$sandbox_profile" in
    delegation-kit|delegation-kit-run-*) ;;
    *) printf 'unexpected builder sandbox profile: %s\n' "$sandbox_profile" >&2; exit 2 ;;
  esac
  for required in \
    '--tools grep,read_file,search_replace,list_dir,todo_write' \
    '--allow Edit(**)'; do
    case "$args" in *" $required "*) ;; *) printf 'missing builder argument: %s\n' "$required" >&2; exit 2 ;; esac
  done
  if [[ "$sandbox_profile" == delegation-kit-run-* ]]; then
    grep -q "^\[profiles\.$sandbox_profile\]\$" "$FAKE_GROK_HOME/sandbox.toml" \
      || { printf 'run-owned sandbox profile is missing\n' >&2; exit 2; }
    case "$args" in
      *' --deny Edit(**/sandbox-events.jsonl) '*) ;;
      *) printf 'sandbox event glob is not denied\n' >&2; exit 2 ;;
    esac
    for protected in config.toml sandbox.toml auth.json sandbox-events.jsonl; do
      case "$args" in
        *" --deny Edit($FAKE_GROK_HOME/$protected) "*) ;;
        *) printf 'shared Grok path is not denied: %s\n' "$protected" >&2; exit 2 ;;
      esac
    done
  fi
fi
case "$args" in *" --help "*) exit 0 ;; esac
[ -z "${GROK_FAKE_DISPATCH_LOG:-}" ] || printf 'dispatch\n' >>"$GROK_FAKE_DISPATCH_LOG"
prompt_path=""
previous=""
for argument in "$@"; do
  if [ "$previous" = --prompt-file ]; then prompt_path="$argument"; break; fi
  previous="$argument"
done
prompt_text=""
[ -z "$prompt_path" ] || prompt_text="$(<"$prompt_path")"
case "${GROK_FAKE_MODE:-success}" in
  auth) printf 'raw secret login required status 401\n' >&2; exit 1 ;;
  rate) printf 'raw secret rate limit status 429\n' >&2; exit 1 ;;
  timeout) sleep 3; exit 0 ;;
esac
mkdir -p "$FAKE_GROK_HOME"
case "$prompt_text" in
  ROTATE_OAUTH)
    jq -n '{"https://auth.x.ai::test":{key:"rotated-access",refresh_token:"rotated-refresh",expires_at:"2099-02-01T00:00:00Z"}}' \
      >"$FAKE_GROK_HOME/auth.json"
    ;;
  HOLD_LOCK_ROTATE)
    jq -n '{"https://auth.x.ai::test":{key:"deferred-access",refresh_token:"deferred-refresh",expires_at:"2099-04-01T00:00:00Z"}}' \
      >"$FAKE_GROK_HOME/auth.json"
    printf '%s\n' '1' >"${GROK_FAKE_KIT_LOCK:?kit lock path is required}"
    ;;
  REQUIRE_ROTATED_OAUTH)
    jq -e '.[].key == "rotated-access" and .[].refresh_token == "rotated-refresh"' \
      "$FAKE_GROK_HOME/auth.json" >/dev/null || exit 91
    ;;
  REQUIRE_EXTERNAL_OAUTH)
    jq -e '.[].key == "external-access" and .[].refresh_token == "external-refresh"' \
      "$FAKE_GROK_HOME/auth.json" >/dev/null || exit 91
    ;;
  REQUIRE_DEFERRED_OAUTH)
    jq -e '.[].key == "deferred-access" and .[].refresh_token == "deferred-refresh"' \
      "$FAKE_GROK_HOME/auth.json" >/dev/null || exit 91
    ;;
  CONCURRENT_LOGIN)
    jq -n '{"https://auth.x.ai::test":{key:"isolated-access",refresh_token:"isolated-refresh",expires_at:"2099-02-01T00:00:00Z"}}' \
      >"$FAKE_GROK_HOME/auth.json"
    jq -n '{"https://auth.x.ai::test":{key:"external-access",refresh_token:"external-refresh",expires_at:"2099-03-01T00:00:00Z"}}' \
      >"${GROK_FAKE_AMBIENT_AUTH:?ambient auth path is required}"
    ;;
  CORRUPT_OAUTH)
    printf '{}\n' >"$FAKE_GROK_HOME/auth.json"
    ;;
  WAIT_FOR_PEER_A|WAIT_FOR_PEER_B)
    sync_dir="${GROK_FAKE_SYNC_DIR:?sync directory is required}"
    mkdir -p "$sync_dir"
    if [ "$prompt_text" = WAIT_FOR_PEER_A ]; then own=peer-a; peer=peer-b; else own=peer-b; peer=peer-a; fi
    : >"$sync_dir/$own"
    for _ in $(seq 1 100); do [ -e "$sync_dir/$peer" ] && break; sleep 0.02; done
    [ -e "$sync_dir/$peer" ] || exit 92
    ;;
esac
case "${GROK_FAKE_MODE:-success}" in
  sandbox_missing) ;;
  sandbox_unenforced)
    jq -nc --arg profile "$sandbox_profile" \
      --arg workspace "$PWD" \
      '{event_type:"ProfileApplied",profile:$profile,enforced:false,workspace:$workspace}' \
      >>"$FAKE_GROK_HOME/sandbox-events.jsonl"
    ;;
  sandbox_no_workspace)
    jq -nc --arg profile "$sandbox_profile" \
      '{event_type:"ProfileApplied",profile:$profile,enforced:true}' \
      >>"$FAKE_GROK_HOME/sandbox-events.jsonl"
    ;;
  sandbox_malformed_then_unterminated)
    printf '{malformed\n' >>"$FAKE_GROK_HOME/sandbox-events.jsonl"
    jq -nc --arg profile "$sandbox_profile" --arg workspace "$PWD" \
      '{event_type:"ProfileApplied",profile:$profile,enforced:true,workspace:$workspace}' \
      | tr -d '\n' >>"$FAKE_GROK_HOME/sandbox-events.jsonl"
    ;;
  *)
    jq -nc --arg profile "$sandbox_profile" \
      --arg workspace "$PWD" \
      '{event_type:"ProfileApplied",profile:$profile,enforced:true,workspace:$workspace}' \
      >>"$FAKE_GROK_HOME/sandbox-events.jsonl"
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
usage_model=grok-4.6-build
[ "${GROK_FAKE_MODE:-success}" != model_mismatch ] || usage_model=grok-4.6-fallback-build
content_model=grok-4.6
[ "${GROK_FAKE_MODE:-success}" != content_model_missing ] || content_model=
[ "${GROK_FAKE_MODE:-success}" != content_model_mismatch ] || content_model=grok-4.6-fallback
multi_usage=false
[ "${GROK_FAKE_MODE:-success}" != multi_usage ] || multi_usage=true
jq -n --arg stop_reason "$stop_reason" --arg usage_model "$usage_model" \
  --arg content_model "$content_model" --argjson multi_usage "$multi_usage" '
  ({text:"PONG",thought:"SECRET_THOUGHT",stopReason:$stop_reason,num_turns:2,
   usage:{input_tokens:100,output_tokens:20,reasoning_tokens:7,
     cache_read_input_tokens:30,total_tokens:157},
   total_cost_usd:0.02,
   modelUsage:({($usage_model):{inputTokens:100,outputTokens:20,
     cacheReadInputTokens:30,modelCalls:1,costUSD:0.02}} +
     (if $multi_usage then {"safety-classifier":{inputTokens:5,outputTokens:2,
       cacheReadInputTokens:1,modelCalls:1,costUSD:0.001}} else {} end))} +
   (if $content_model == "" then {} else {model:$content_model} end))
'
EOF
chmod 755 "$TMP/bin/grok"
printf 'Reply with exactly PONG.\n' >"$TMP/prompt.txt"

# A stand-in for a compatible vendor update with a different version string.
mkdir -p "$TMP/bin-updated"
cat >"$TMP/bin-updated/grok" <<EOF
#!/usr/bin/env bash
set -euo pipefail
[ "\${1:-}" != --version ] || { printf 'grok user-build-b (deadbeef) [stable]\n'; exit 0; }
exec "$TMP/bin/grok" "\$@"
EOF
chmod 755 "$TMP/bin-updated/grok"

mkdir -p "$TMP/bin-incompatible"
cat >"$TMP/bin-incompatible/grok" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
args=" $* "
case "$args" in *" --allow "*) exit 2 ;; esac
case "${1:-}" in
  --version) printf 'grok user-build-incompatible\n' ;;
  --help)
    printf '%s\n' \
      '--prompt-file --model --reasoning-effort --output-format --permission-mode' \
      '--sandbox --no-memory --no-subagents --disable-web-search --tools' \
      '--deny --max-turns' \
      '  inspect  Show configuration' \
      '  models   List models'
    ;;
  models)
    [ "${2:-}" = --help ] && printf 'List models\n'
    ;;
  inspect)
    [ "${2:-}" = --help ] && printf '%s\n' 'Show configuration' '--json'
    ;;
esac
EOF
chmod 755 "$TMP/bin-incompatible/grok"

run_grok() {
  DELEGATION_GROK_HOME="$TMP/grok-home" DELEGATION_DATA_HOME="$TMP/runtime" \
    DELEGATION_GROK_BIN_STORE="$TMP/store" \
    PATH="$TMP/bin:$PATH" "$ROOT/bin/delegation-grok" "$@"
}

run_grok_updated() {
  DELEGATION_GROK_HOME="$TMP/grok-home" DELEGATION_DATA_HOME="$TMP/runtime" \
    DELEGATION_GROK_BIN_STORE="$TMP/store" \
    PATH="$TMP/bin-updated:$PATH" "$ROOT/bin/delegation-grok" "$@"
}

start_grok_background_named() {
  local name="$1"; shift
  run_grok "$@" >"$TMP/$name.stdout" 2>"$TMP/$name.stderr" &
  GROK_BACKGROUND_PID=$!
}

run_grok check --json >"$TMP/check.json"
jq -e '
  .model == "grok-4.6" and
  .runtime_cli_version == "user-build-a" and
  .runtime_cli_compatibility == "capability-probed" and
  .runtime_cli_source == "path" and
  .selected_backend == "grok-build" and
  .provisional_lanes == ["builder","frontend-builder"] and
  .qualified_lanes == [] and
  .backends["grok-build"].sandbox == "delegation-kit" and
  .backends["grok-build"].permission_mode == "dontAsk" and
  .backends["grok-build"].oauth_mode == "serialized" and
  .backends["grok-build"].oauth_modes == ["serialized","shared"] and
  .backends["grok-build"].runtime_home_isolated == true and
  .backends["grok-build"].grok_home_mode == "isolated-copy" and
  .backends["grok-build"].credential_state_shared == false and
  .backends["grok-build"].max_turns == 40 and
  .backends["grok-build"].timeout_seconds == 900 and
  .backends["grok-build"].isolated_home == true and
  .backends["grok-build"].plugins == false and
  .backends["grok-build"].mcp == false
' "$TMP/check.json" >/dev/null || fail "check contract mismatch"
! grep -q 'run_terminal_cmd' "$TMP/check.json" || fail "terminal tool leaked into check contract"

# Linux and minimal environments may not ship shlock. The portable atomic
# directory fallback must authenticate and release its lock cleanly.
DELEGATION_GROK_SHLOCK_BIN="$TMP/missing-shlock" run_grok check --json \
  >"$TMP/check-mkdir-lock.json"
jq -e '.selected_backend == "grok-build"' "$TMP/check-mkdir-lock.json" >/dev/null \
  || fail "mkdir OAuth lock fallback did not authenticate"
[ ! -e "$TMP/grok-home/.delegation-kit-oauth.lock.d" ] \
  || fail "mkdir OAuth lock fallback leaked its lock directory"
mkdir "$TMP/grok-home/.delegation-kit-oauth.lock.d"
touch -t 200001010000 "$TMP/grok-home/.delegation-kit-oauth.lock.d"
DELEGATION_GROK_SHLOCK_BIN="$TMP/missing-shlock" run_grok check --json \
  >"$TMP/check-ownerless-lock-recovery.json"
jq -e '.selected_backend == "grok-build"' \
  "$TMP/check-ownerless-lock-recovery.json" >/dev/null \
  || fail "ownerless mkdir OAuth lock did not recover"
[ ! -e "$TMP/grok-home/.delegation-kit-oauth.lock.d" ] \
  || fail "ownerless mkdir OAuth lock recovery leaked state"

# Shared-mode health checks keep the JSON contract on unavailable credentials
# and lock contention instead of exiting from inside generation seeding.
cp "$TMP/grok-home/auth.json" "$TMP/auth-before-logged-out.json"
printf '{}\n' >"$TMP/grok-home/auth.json"
DELEGATION_GROK_OAUTH_MODE=shared run_grok check --json \
  >"$TMP/check-shared-logged-out.json"
jq -e '
  .selected_backend == "none" and .backends["grok-build"].available == false and
  (.backends["grok-build"].reason | test("unavailable|credentials|logged out"; "i"))
' "$TMP/check-shared-logged-out.json" >/dev/null \
  || fail "shared logged-out check did not return unavailable JSON"
cp "$TMP/auth-before-logged-out.json" "$TMP/grok-home/auth.json"
printf '%s\n' "$$" >"$TMP/grok-home/.delegation-kit-oauth.lock"
DELEGATION_GROK_OAUTH_MODE=shared DELEGATION_GROK_OAUTH_WAIT_SECONDS=0 \
  run_grok check --json >"$TMP/check-shared-busy.json"
jq -e '
  .selected_backend == "none" and .backends["grok-build"].available == false and
  (.backends["grok-build"].reason | test("another Grok invocation"))
' "$TMP/check-shared-busy.json" >/dev/null \
  || fail "shared busy-lock check did not return unavailable JSON"
rm -f -- "$TMP/grok-home/.delegation-kit-oauth.lock"

rc=0
run_grok run --lane builder --prompt-file "$TMP/prompt.txt" \
  --output "$TMP/results/refused.txt" --workdir "$TMP/work" >/dev/null 2>&1 || rc=$?
[ "$rc" = 78 ] || fail "provisional run without explicit flag returned $rc"

run_grok run --lane builder --allow-provisional --prompt-file "$TMP/prompt.txt" \
  --output "$TMP/results/builder.txt" --workdir "$TMP/work"
[ "$(cat "$TMP/results/builder.txt")" = PONG ] || fail "text extraction mismatch"
! grep -q SECRET_THOUGHT "$TMP/results/builder.txt" || fail "thought leaked into output"
jq -e '
  .model == "grok-4.6" and .runtime_model == "grok-4.6" and
  .requested_model == "grok-4.6" and
  .effective_content_model == "grok-4.6" and
  .exact_model_identity_attested == true and
  .runtime_cli_version == "user-build-a" and
  .runtime_cli_compatibility == "capability-probed" and
  .usage_model == "grok-4.6-build" and
  .target_usage_participant_present == true and
  (.usage_participants | length) == 1 and
  .usage_participants[0].model == "grok-4.6-build" and .effort == "high" and
  .lane == "builder" and .tokens.reasoning == 7 and
  .provider_cost_usd == 0.02 and .sandbox == "delegation-kit" and
  .permission_mode == "dontAsk" and .max_turns == 40 and
  .timeout_seconds == 900 and .isolated_home == true
' "$TMP/results/builder.txt.metrics.json" >/dev/null || fail "metrics mismatch"
# Ordinary (non-evaluation) runs never claim the evaluation receipt.
jq -e 'has("evaluation_receipt") | not' "$TMP/results/builder.txt.metrics.json" >/dev/null \
  || fail "non-evaluation run claimed an evaluation receipt"
[ ! -e "$TMP/results/builder.txt.commit.json" ] \
  || fail "non-evaluation run wrote an evaluation commit marker"
jq -e '.oauth_mode == "serialized" and .oauth_sync == "ok"' \
  "$TMP/results/builder.txt.metrics.json" >/dev/null \
  || fail "serialized OAuth metrics mismatch"
[ ! -e "$TMP/grok-home/.delegation-kit-oauth.lock" ] \
  || fail "serialized OAuth run leaked its shlock file"

# Serialized mode holds the kit lock for the full dispatch and atomically
# publishes a rotated credential back to the ambient Grok home.
printf '%s\n' 'ROTATE_OAUTH' >"$TMP/rotate-oauth-prompt.txt"
printf '%s\n' 'REQUIRE_ROTATED_OAUTH' >"$TMP/require-rotated-oauth-prompt.txt"
run_grok run --lane builder --allow-provisional \
  --prompt-file "$TMP/rotate-oauth-prompt.txt" \
  --output "$TMP/results/serialized-rotate.txt" --workdir "$TMP/work"
jq -e '.[].key == "rotated-access" and .[].refresh_token == "rotated-refresh"' \
  "$TMP/grok-home/auth.json" >/dev/null \
  || fail "serialized OAuth rotation was not published"
run_grok run --lane builder --allow-provisional \
  --prompt-file "$TMP/require-rotated-oauth-prompt.txt" \
  --output "$TMP/results/serialized-require-rotated.txt" --workdir "$TMP/work"
[ "$(cat "$TMP/results/serialized-require-rotated.txt")" = PONG ] \
  || fail "next serialized run did not receive rotated OAuth"

# Shared OAuth mode keeps one durable generation. Two children dispatch in
# parallel while the vendor's shared auth lock is available in one GROK_HOME.
jq -n '{"https://auth.x.ai::test":{key:"shared-initial",refresh_token:"shared-initial-refresh",expires_at:"2099-01-01T00:00:00Z"}}' \
  >"$TMP/grok-home/auth.json"
printf '%s\n' 'WAIT_FOR_PEER_A' >"$TMP/peer-a-prompt.txt"
printf '%s\n' 'WAIT_FOR_PEER_B' >"$TMP/peer-b-prompt.txt"
mkdir -p "$TMP/peer-sync"
GROK_FAKE_SYNC_DIR="$TMP/peer-sync" start_grok_background_named shared-peer-a \
  run --lane builder --allow-provisional --oauth shared \
  --prompt-file "$TMP/peer-a-prompt.txt" \
  --output "$TMP/results/shared-peer-a.txt" --workdir "$TMP/work"
peer_a_pid="$GROK_BACKGROUND_PID"
GROK_FAKE_SYNC_DIR="$TMP/peer-sync" start_grok_background_named shared-peer-b \
  run --lane builder --allow-provisional --oauth shared \
  --prompt-file "$TMP/peer-b-prompt.txt" \
  --output "$TMP/results/shared-peer-b.txt" --workdir "$TMP/work"
peer_b_pid="$GROK_BACKGROUND_PID"
rc=0; wait "$peer_a_pid" || rc=$?
[ "$rc" = 0 ] || fail "concurrent shared Grok run A failed with $rc"
rc=0; wait "$peer_b_pid" || rc=$?
[ "$rc" = 0 ] || fail "concurrent shared Grok run B failed with $rc"
[ "$(cat "$TMP/results/shared-peer-a.txt")" = PONG ] &&
  [ "$(cat "$TMP/results/shared-peer-b.txt")" = PONG ] \
  || fail "concurrent shared Grok runs did not both answer"
jq -e '.oauth_mode == "shared" and .oauth_sync == "ok"' \
  "$TMP/results/shared-peer-a.txt.metrics.json" >/dev/null \
  || fail "shared OAuth metrics mismatch"
jq -e '
  .runtime_home_isolated == true and .grok_home_mode == "shared-generation" and
  .credential_state_shared == true
' "$TMP/results/shared-peer-a.txt.metrics.json" >/dev/null \
  || fail "shared Grok HOME metrics mismatch"
SHARED_GROK_ROOT="$TMP/runtime/grok-shared-oauth"

# One worker's event must never attest a peer, even in the same workdir. Run A
# emits no event while B emits an enforced event under its own unique profile.
mkdir -p "$TMP/peer-negative"
GROK_FAKE_MODE=sandbox_missing GROK_FAKE_SYNC_DIR="$TMP/peer-negative" \
  start_grok_background_named shared-negative-a \
  run --lane builder --allow-provisional --oauth shared \
  --prompt-file "$TMP/peer-a-prompt.txt" \
  --output "$TMP/results/shared-negative-a.txt" --workdir "$TMP/work"
negative_a_pid="$GROK_BACKGROUND_PID"
GROK_FAKE_SYNC_DIR="$TMP/peer-negative" start_grok_background_named shared-negative-b \
  run --lane builder --allow-provisional --oauth shared \
  --prompt-file "$TMP/peer-b-prompt.txt" \
  --output "$TMP/results/shared-negative-b.txt" --workdir "$TMP/work"
negative_b_pid="$GROK_BACKGROUND_PID"
rc_a=0; wait "$negative_a_pid" || rc_a=$?
rc_b=0; wait "$negative_b_pid" || rc_b=$?
[ "$rc_a" = 70 ] || fail "peer event cross-satisfied un-attested run A: $rc_a"
[ "$rc_b" = 0 ] || fail "attested peer B failed with $rc_b"
jq -e '.reason == "sandbox_not_enforced"' \
  "$TMP/results/shared-negative-a.txt.error.json" >/dev/null \
  || fail "un-attested peer did not report sandbox failure"

rc=0
GROK_FAKE_MODE=sandbox_no_workspace run_grok run --lane builder \
  --allow-provisional --oauth shared --prompt-file "$TMP/prompt.txt" \
  --output "$TMP/results/shared-no-workspace.txt" --workdir "$TMP/work" \
  >/dev/null 2>&1 || rc=$?
[ "$rc" = 70 ] || fail "workspace-less sandbox event returned $rc"
GROK_FAKE_MODE=sandbox_malformed_then_unterminated run_grok run \
  --lane builder --allow-provisional --oauth shared \
  --prompt-file "$TMP/prompt.txt" \
  --output "$TMP/results/shared-malformed-events.txt" --workdir "$TMP/work"
[ "$(cat "$TMP/results/shared-malformed-events.txt")" = PONG ] \
  || fail "line-by-line sandbox event parser rejected valid unterminated event"
printf '\n' >>"$SHARED_GROK_ROOT/$(jq -r '.generation' "$SHARED_GROK_ROOT/sync-marker.json")/sandbox-events.jsonl"
[ -f "$SHARED_GROK_ROOT/sync-marker.json" ] \
  || fail "shared Grok OAuth marker was not written"
shared_generation="$(jq -r '.generation' "$SHARED_GROK_ROOT/sync-marker.json")"
[ -f "$SHARED_GROK_ROOT/$shared_generation/auth.json" ] \
  || fail "shared Grok OAuth generation is missing"

# A runner policy upgrade starts a new generation instead of mutating policy
# under active peers. Superseded credential generations stay bounded to two.
printf '%s\n' 'hooks = ["stale-hook"]' \
  >"$SHARED_GROK_ROOT/$shared_generation/config.toml"
jq '.policy_version = "obsolete-policy"' "$SHARED_GROK_ROOT/sync-marker.json" \
  >"$TMP/obsolete-marker.json"
mv "$TMP/obsolete-marker.json" "$SHARED_GROK_ROOT/sync-marker.json"
run_grok run --lane builder --allow-provisional --oauth shared \
  --prompt-file "$TMP/prompt.txt" \
  --output "$TMP/results/shared-config-reconcile.txt" --workdir "$TMP/work"
shared_generation_2="$(jq -r '.generation' "$SHARED_GROK_ROOT/sync-marker.json")"
[ "$shared_generation_2" != "$shared_generation" ] \
  || fail "shared Grok policy change reused the stale generation"
! grep -q 'stale-hook' "$SHARED_GROK_ROOT/$shared_generation_2/config.toml" \
  || fail "new shared Grok generation inherited stale policy"
jq '.policy_version = "obsolete-again"' "$SHARED_GROK_ROOT/sync-marker.json" \
  >"$TMP/obsolete-marker-again.json"
mv "$TMP/obsolete-marker-again.json" "$SHARED_GROK_ROOT/sync-marker.json"
run_grok run --lane builder --allow-provisional --oauth shared \
  --prompt-file "$TMP/prompt.txt" \
  --output "$TMP/results/shared-generation-prune.txt" --workdir "$TMP/work"
[ "$(find "$SHARED_GROK_ROOT" -mindepth 1 -maxdepth 1 -type d -name 'gen-*' | wc -l | tr -d ' ')" -le 2 ] \
  || fail "superseded Grok OAuth generations accumulated"

# Refresh inside the shared generation is published atomically and consumed by
# the following run rather than being deleted with a per-run HOME.
run_grok run --lane builder --allow-provisional --oauth shared \
  --prompt-file "$TMP/rotate-oauth-prompt.txt" \
  --output "$TMP/results/shared-rotate.txt" --workdir "$TMP/work"
jq -e '.[].key == "rotated-access" and .[].refresh_token == "rotated-refresh"' \
  "$TMP/grok-home/auth.json" >/dev/null \
  || fail "shared OAuth rotation was not published"
run_grok run --lane builder --allow-provisional --oauth shared \
  --prompt-file "$TMP/require-rotated-oauth-prompt.txt" \
  --output "$TMP/results/shared-require-rotated.txt" --workdir "$TMP/work"

# A manual login during a run always wins. The stale generation is rejected,
# its output is not published, and the next run adopts a fresh generation.
printf '%s\n' 'CONCURRENT_LOGIN' >"$TMP/concurrent-login-prompt.txt"
rc=0
GROK_FAKE_AMBIENT_AUTH="$TMP/grok-home/auth.json" run_grok run \
  --lane builder --allow-provisional --oauth shared \
  --prompt-file "$TMP/concurrent-login-prompt.txt" \
  --output "$TMP/results/shared-concurrent-login.txt" --workdir "$TMP/work" \
  >/dev/null 2>&1 || rc=$?
[ "$rc" = 75 ] || fail "shared external login conflict returned $rc"
[ ! -e "$TMP/results/shared-concurrent-login.txt" ] \
  || fail "shared external login conflict published output"
jq -e '.phase == "oauth-sync" and .reason == "oauth_conflict"' \
  "$TMP/results/shared-concurrent-login.txt.error.json" >/dev/null \
  || fail "shared external login conflict diagnostic mismatch"
jq -e '.[].key == "external-access" and .[].refresh_token == "external-refresh"' \
  "$TMP/grok-home/auth.json" >/dev/null \
  || fail "shared publish overwrote external login"
printf '%s\n' 'REQUIRE_EXTERNAL_OAUTH' >"$TMP/require-external-oauth-prompt.txt"
run_grok run --lane builder --allow-provisional --oauth shared \
  --prompt-file "$TMP/require-external-oauth-prompt.txt" \
  --output "$TMP/results/shared-after-conflict.txt" --workdir "$TMP/work"

# Malformed refreshed state never replaces the ambient login; the next shared
# seed abandons the corrupt generation and heals from ambient state.
printf '%s\n' 'CORRUPT_OAUTH' >"$TMP/corrupt-oauth-prompt.txt"
cp "$TMP/grok-home/auth.json" "$TMP/oauth-before-corruption.json"
rc=0
run_grok run --lane builder --allow-provisional --oauth shared \
  --prompt-file "$TMP/corrupt-oauth-prompt.txt" \
  --output "$TMP/results/shared-corrupt.txt" --workdir "$TMP/work" \
  >/dev/null 2>&1 || rc=$?
[ "$rc" = 70 ] || fail "shared malformed OAuth returned $rc"
[ ! -e "$TMP/results/shared-corrupt.txt" ] \
  || fail "shared malformed OAuth published output"
cmp -s "$TMP/oauth-before-corruption.json" "$TMP/grok-home/auth.json" \
  || fail "shared malformed OAuth replaced ambient login"
run_grok run --lane builder --allow-provisional --oauth shared \
  --prompt-file "$TMP/require-external-oauth-prompt.txt" \
  --output "$TMP/results/shared-heal.txt" --workdir "$TMP/work"
[ "$(cat "$TMP/results/shared-heal.txt")" = PONG ] \
  || fail "shared OAuth mode did not heal corrupt generation"

# A rotated credential whose ambient publication is blocked remains durable in
# the shared generation, but the completed result is not reported as success.
printf '%s\n' 'HOLD_LOCK_ROTATE' >"$TMP/hold-lock-rotate-prompt.txt"
rc=0
GROK_FAKE_KIT_LOCK="$TMP/grok-home/.delegation-kit-oauth.lock" \
  DELEGATION_GROK_OAUTH_WAIT_SECONDS=0 run_grok run \
  --lane builder --allow-provisional --oauth shared \
  --prompt-file "$TMP/hold-lock-rotate-prompt.txt" \
  --output "$TMP/results/shared-deferred.txt" --workdir "$TMP/work" \
  >/dev/null 2>&1 || rc=$?
[ "$rc" = 75 ] || fail "deferred shared OAuth publication returned $rc"
jq -e '.phase == "oauth-sync" and .reason == "oauth_publish_deferred"' \
  "$TMP/results/shared-deferred.txt.error.json" >/dev/null \
  || fail "deferred shared OAuth diagnostic mismatch"
[ ! -e "$TMP/results/shared-deferred.txt" ] \
  || fail "deferred shared OAuth published a successful output"
rm -f -- "$TMP/grok-home/.delegation-kit-oauth.lock"
printf '%s\n' 'REQUIRE_DEFERRED_OAUTH' >"$TMP/require-deferred-oauth-prompt.txt"
run_grok run --lane builder --allow-provisional --oauth shared \
  --prompt-file "$TMP/require-deferred-oauth-prompt.txt" \
  --output "$TMP/results/shared-deferred-catchup.txt" --workdir "$TMP/work"
jq -e '.[].key == "deferred-access" and .[].refresh_token == "deferred-refresh"' \
  "$TMP/grok-home/auth.json" >/dev/null \
  || fail "next shared run did not publish deferred OAuth rotation"

rc=0
run_grok run --lane builder --allow-provisional --oauth bogus \
  --prompt-file "$TMP/prompt.txt" --output "$TMP/results/oauth-bogus.txt" \
  --workdir "$TMP/work" >/dev/null 2>&1 || rc=$?
[ "$rc" = 64 ] || fail "invalid OAuth mode returned $rc"

GROK_FAKE_MODE=multi_usage run_grok run --lane builder --allow-provisional \
  --prompt-file "$TMP/prompt.txt" --output "$TMP/results/multi-usage.txt" \
  --workdir "$TMP/work"
jq -e '
  (.usage_participants | map(.model) | sort) == ["grok-4.6-build","safety-classifier"] and
  .tokens.input == 105 and .tokens.output == 22 and
  .tokens.cache_read == 31 and .tokens.reasoning == 7 and .tokens.total == 165 and
  .provider_cost_usd == 0.021
' "$TMP/results/multi-usage.txt.metrics.json" >/dev/null \
  || fail "multi-participant usage was not preserved and summed"

GROK_FAKE_MODE=content_model_missing run_grok run --lane builder --allow-provisional \
  --prompt-file "$TMP/prompt.txt" --output "$TMP/results/no-content-model.txt" \
  --workdir "$TMP/work"
jq -e '
  .effective_content_model == null and .exact_model_identity_attested == false and
  .target_usage_participant_present == true
' "$TMP/results/no-content-model.txt.metrics.json" >/dev/null \
  || fail "operational run conflated usage participation with content identity"

rc=0
GROK_FAKE_MODE=content_model_mismatch run_grok run --lane builder --allow-provisional \
  --prompt-file "$TMP/prompt.txt" --output "$TMP/results/operational-mismatch.txt" \
  --workdir "$TMP/work" >/dev/null 2>&1 || rc=$?
[ "$rc" = 70 ] || fail "operational content identity mismatch returned $rc"
[ ! -e "$TMP/results/operational-mismatch.txt" ] \
  || fail "operational content identity mismatch published output"
jq -e '.phase == "identity" and .reason == "provider_identity_mismatch"' \
  "$TMP/results/operational-mismatch.txt.error.json" >/dev/null \
  || fail "operational content identity mismatch diagnostic"

run_grok run --lane frontend-builder --allow-provisional --prompt-file "$TMP/prompt.txt" \
  --output "$TMP/results/frontend.txt" --workdir "$TMP/work"
[ "$(cat "$TMP/results/frontend.txt")" = PONG ] || fail "frontend lane failed"

# Exercise the manifest gate, read-only tool surface, sandbox attestation, and
# separately surfaced effective content identity from a clean committed runner checkout.
EVAL_ROOT="$TMP/eval-repo"
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
  --arg prompt_sha256 "$(sha256 "$TMP/prompt.txt")" \
  --arg runner_sha256 "$(sha256 "$EVAL_ROOT/bin/delegation-grok")" \
  --arg contract_sha256 "$(sha256 "$EVAL_ROOT/evaluation/test-fixtures/contract.txt")" \
  --arg output_schema_sha256 "$(sha256 "$EVAL_ROOT/evaluation/test-fixtures/output-schema.json")" \
  --arg source_commit "$EVAL_BASE_COMMIT" \
  '{schema:"delegation_policy_annotation_evaluation_v1",profile:"grok-build",lane:"policy-annotation",model:"grok-4.6",backend:"grok-build",effort:"high",prompt_sha256:$prompt_sha256,runner_source_commit:$source_commit,runner_sha256:$runner_sha256,contract_path:"evaluation/test-fixtures/contract.txt",contract_sha256:$contract_sha256,output_schema_path:"evaluation/test-fixtures/output-schema.json",output_schema_sha256:$output_schema_sha256,timeout_seconds:60,max_output_chars:1024}' \
  >"$TMP/grok-evaluation-manifest.json"
GROK_MANIFEST_SHA="$(sha256 "$TMP/grok-evaluation-manifest.json")"
jq --arg hash "$GROK_MANIFEST_SHA" '
  .profiles["grok-build"].lanes["policy-annotation"].evaluation_manifest_sha256 = [$hash]
' "$EVAL_ROOT/config/routing-gates.json" >"$TMP/grok-central.json"
mv "$TMP/grok-central.json" "$EVAL_ROOT/config/routing-gates.json"
jq --arg hash "$GROK_MANIFEST_SHA" '
  .lanes["policy-annotation"].backends["grok-build"].evaluation_manifest_sha256 = [$hash]
' "$EVAL_ROOT/config/grok-4.6-routing.json" >"$TMP/grok-routing.json"
mv "$TMP/grok-routing.json" "$EVAL_ROOT/config/grok-4.6-routing.json"
git -C "$EVAL_ROOT" add config/routing-gates.json config/grok-4.6-routing.json
git -C "$EVAL_ROOT" commit -qm 'allowlist Grok evaluation fixture'
EVAL_HEAD="$(git -C "$EVAL_ROOT" rev-parse HEAD)"

DELEGATION_GROK_HOME="$TMP/grok-home" \
DELEGATION_GROK_BIN_STORE="$TMP/eval-store" \
DELEGATION_GROK_BIN="$TMP/bin/grok" \
PATH="$TMP/bin:$PATH" "$EVAL_ROOT/bin/delegation-grok" run \
  --lane policy-annotation --effort high --backend grok-build --evaluation \
  --evaluation-manifest "$TMP/grok-evaluation-manifest.json" \
  --prompt-file "$TMP/prompt.txt" --output "$TMP/results/policy-annotation.txt" \
  --workdir "$TMP/work"
[ "$(cat "$TMP/results/policy-annotation.txt")" = PONG ] \
  || fail "policy-annotation output mismatch"
jq -e '
  .lane == "policy-annotation" and .model == "grok-4.6" and
  .effort == "high" and .sandbox == "delegation-kit-read-only"
' "$TMP/results/policy-annotation.txt.metrics.json" >/dev/null \
  || fail "policy-annotation metrics mismatch"

# A successful policy-annotation evaluation publishes the runner-emitted
# receipt with exactly the bound fields, recomputed here independently.
jq -e --arg manifest_sha "$GROK_MANIFEST_SHA" \
  --arg prompt_sha "$(sha256 "$TMP/prompt.txt")" \
  --arg source_commit "$EVAL_HEAD" \
  --arg runner_sha "$(sha256 "$EVAL_ROOT/bin/delegation-grok")" \
  --arg output_sha "$(sha256 "$TMP/results/policy-annotation.txt")" \
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
  "$TMP/results/policy-annotation.txt.metrics.json" >/dev/null \
  || fail "evaluation receipt mismatch"
jq -e --arg output_sha "$(sha256 "$TMP/results/policy-annotation.txt")" \
  --arg metrics_sha "$(sha256 "$TMP/results/policy-annotation.txt.metrics.json")" \
  --arg manifest_sha "$GROK_MANIFEST_SHA" \
  '(keys | sort) == ["evaluation_manifest_sha256","metrics_sha256",
    "raw_output_sha256","schema_version"] and
   .schema_version == "delegation_policy_annotation_publication_commit_v1" and
   .raw_output_sha256 == $output_sha and .metrics_sha256 == $metrics_sha and
   .evaluation_manifest_sha256 == $manifest_sha' \
  "$TMP/results/policy-annotation.txt.commit.json" >/dev/null \
  || fail "evaluation publication commit mismatch"

# ---- evaluation preflight: full validation, no provider dispatch, no artifacts ----
# GROK_FAKE_MODE=auth makes any real dispatch fail with 69; a zero exit here is
# only possible if the provider task never began.
rc=0
DELEGATION_GROK_HOME="$TMP/grok-home" \
DELEGATION_GROK_BIN_STORE="$TMP/eval-store" \
DELEGATION_GROK_BIN="$TMP/bin/grok" \
GROK_FAKE_MODE=auth PATH="$TMP/bin:$PATH" "$EVAL_ROOT/bin/delegation-grok" run \
  --lane policy-annotation --effort high --backend grok-build --evaluation \
  --evaluation-manifest "$TMP/grok-evaluation-manifest.json" --preflight-only \
  --prompt-file "$TMP/prompt.txt" --output "$TMP/results/policy-preflight.txt" \
  --workdir "$TMP/work" >"$TMP/results/policy-preflight.stdout" \
  2>"$TMP/results/policy-preflight.stderr" || rc=$?
[ "$rc" = 0 ] || fail "preflight returned $rc"
[ ! -s "$TMP/results/policy-preflight.stderr" ] || fail "preflight wrote to stderr"
jq -e --arg manifest_sha "$GROK_MANIFEST_SHA" \
  --arg prompt_sha "$(sha256 "$TMP/prompt.txt")" \
  --arg source_commit "$(git -C "$EVAL_ROOT" rev-parse HEAD)" \
  --arg runner_sha "$(sha256 "$EVAL_ROOT/bin/delegation-grok")" \
  --arg contract_sha "$(sha256 "$EVAL_ROOT/evaluation/test-fixtures/contract.txt")" \
  --arg output_schema_sha "$(sha256 "$EVAL_ROOT/evaluation/test-fixtures/output-schema.json")" \
  '(keys | sort) ==
     ["backend","contract_sha256","effort","evaluation_manifest_sha256","lane",
      "model","output_schema_sha256","post_observation_retries","profile",
      "prompt_sha256","provider_attempts","provider_dispatch_started",
      "runner_sha256","runner_source_commit","schema_version","status"] and
   .schema_version == "delegation_policy_annotation_preflight_receipt_v1" and
   .status == "READY_NO_PROVIDER_CALL" and
   .profile == "grok-build" and .model == "grok-4.6" and
   .backend == "grok-build" and .effort == "high" and
   .lane == "policy-annotation" and
   .evaluation_manifest_sha256 == $manifest_sha and
   .prompt_sha256 == $prompt_sha and
   .runner_source_commit == $source_commit and
   .runner_sha256 == $runner_sha and
   .contract_sha256 == $contract_sha and
   .output_schema_sha256 == $output_schema_sha and
   .provider_dispatch_started == false and
   .provider_attempts == 0 and .post_observation_retries == 0' \
  "$TMP/results/policy-preflight.stdout" >/dev/null || fail "preflight receipt mismatch"
[ ! -e "$TMP/results/policy-preflight.txt" ] &&
  [ ! -e "$TMP/results/policy-preflight.txt.metrics.json" ] &&
  [ ! -e "$TMP/results/policy-preflight.txt.error.json" ] &&
  [ ! -e "$TMP/results/policy-preflight.txt.commit.json" ] \
  || fail "preflight created a caller-visible artifact"

# ---- regression: preflight rejects a workdir-bound forbidden Grok config ----
# The project configuration under the workdir enables hooks. runtime_status
# inspects from the runner's own directory and stays clean; only the
# workdir-bound inspection the real run performs can see the contamination,
# so preflight must traverse it too and refuse the receipt. The dispatch log
# proves no provider work began; GROK_FAKE_MODE=auth would turn any real
# dispatch into an authentication failure rather than a receipt.
mkdir -p "$TMP/work-contaminated/.grok"
printf '%s\n' 'hooks = ["project-hook"]' \
  >"$TMP/work-contaminated/.grok/project-config.toml"
rc=0
DELEGATION_GROK_HOME="$TMP/grok-home" \
DELEGATION_GROK_BIN_STORE="$TMP/eval-store" \
DELEGATION_GROK_BIN="$TMP/bin/grok" \
GROK_FAKE_MODE=auth GROK_FAKE_DISPATCH_LOG="$TMP/contaminated-dispatch.log" \
PATH="$TMP/bin:$PATH" "$EVAL_ROOT/bin/delegation-grok" run \
  --lane policy-annotation --effort high --backend grok-build --evaluation \
  --evaluation-manifest "$TMP/grok-evaluation-manifest.json" --preflight-only \
  --prompt-file "$TMP/prompt.txt" \
  --output "$TMP/results/policy-preflight-contaminated.txt" \
  --workdir "$TMP/work-contaminated" \
  >"$TMP/results/policy-preflight-contaminated.stdout" \
  2>"$TMP/results/policy-preflight-contaminated.stderr" || rc=$?
[ "$rc" = 69 ] || fail "preflight with contaminated workdir returned $rc"
grep -q 'isolation is contaminated' "$TMP/results/policy-preflight-contaminated.stderr" \
  || fail "preflight with contaminated workdir did not name the isolation failure"
[ ! -s "$TMP/results/policy-preflight-contaminated.stdout" ] \
  || fail "preflight emitted a receipt for a contaminated workdir"
[ ! -e "$TMP/contaminated-dispatch.log" ] \
  || fail "preflight with contaminated workdir dispatched to the provider"
[ ! -e "$TMP/results/policy-preflight-contaminated.txt" ] &&
  [ ! -e "$TMP/results/policy-preflight-contaminated.txt.metrics.json" ] &&
  [ ! -e "$TMP/results/policy-preflight-contaminated.txt.error.json" ] &&
  [ ! -e "$TMP/results/policy-preflight-contaminated.txt.commit.json" ] \
  || fail "contaminated preflight created a caller-visible artifact"

# The identical real run rejects the same workdir at the same isolation check.
rc=0
DELEGATION_GROK_HOME="$TMP/grok-home" \
DELEGATION_GROK_BIN_STORE="$TMP/eval-store" \
DELEGATION_GROK_BIN="$TMP/bin/grok" \
GROK_FAKE_DISPATCH_LOG="$TMP/contaminated-run-dispatch.log" \
PATH="$TMP/bin:$PATH" "$EVAL_ROOT/bin/delegation-grok" run \
  --lane policy-annotation --effort high --backend grok-build --evaluation \
  --evaluation-manifest "$TMP/grok-evaluation-manifest.json" \
  --prompt-file "$TMP/prompt.txt" \
  --output "$TMP/results/policy-run-contaminated.txt" \
  --workdir "$TMP/work-contaminated" >/dev/null 2>&1 || rc=$?
[ "$rc" = 69 ] || fail "real run with contaminated workdir returned $rc"
[ ! -e "$TMP/contaminated-run-dispatch.log" ] \
  || fail "contaminated workdir reached provider dispatch"
[ ! -e "$TMP/results/policy-run-contaminated.txt" ] &&
  [ ! -e "$TMP/results/policy-run-contaminated.txt.metrics.json" ] &&
  [ ! -e "$TMP/results/policy-run-contaminated.txt.error.json" ] &&
  [ ! -e "$TMP/results/policy-run-contaminated.txt.commit.json" ] \
  || fail "contaminated real run created a caller-visible artifact"

# --preflight-only is rejected for ordinary (non-evaluation) runs.
rc=0
run_grok run --lane builder --allow-provisional --preflight-only \
  --prompt-file "$TMP/prompt.txt" --output "$TMP/results/preflight-ordinary.txt" \
  --workdir "$TMP/work" >/dev/null 2>&1 || rc=$?
[ "$rc" = 64 ] || fail "--preflight-only without --evaluation returned $rc"
[ ! -e "$TMP/results/preflight-ordinary.txt" ] || fail "rejected preflight created output"

# Manifest validation failures stay failures before provider use.
rc=0
DELEGATION_GROK_HOME="$TMP/grok-home" \
DELEGATION_GROK_BIN_STORE="$TMP/eval-store" \
DELEGATION_GROK_BIN="$TMP/bin/grok" \
GROK_FAKE_MODE=auth PATH="$TMP/bin:$PATH" "$EVAL_ROOT/bin/delegation-grok" run \
  --lane policy-annotation --effort high --backend grok-build --evaluation \
  --evaluation-manifest "$TMP/missing-manifest.json" --preflight-only \
  --prompt-file "$TMP/prompt.txt" --output "$TMP/results/preflight-missing.txt" \
  --workdir "$TMP/work" >/dev/null 2>&1 || rc=$?
[ "$rc" = 78 ] || fail "preflight with missing manifest returned $rc"
[ ! -e "$TMP/results/preflight-missing.txt" ] &&
  [ ! -e "$TMP/results/preflight-missing.txt.error.json" ] \
  || fail "manifest failure created artifacts"

rc=0
DELEGATION_GROK_HOME="$TMP/grok-home" \
DELEGATION_GROK_BIN_STORE="$TMP/eval-store" DELEGATION_GROK_BIN="$TMP/bin/grok" \
PATH="$TMP/bin:$PATH" "$EVAL_ROOT/bin/delegation-grok" run \
  --lane policy-annotation --effort high --backend grok-build --evaluation \
  --evaluation-manifest "$TMP/grok-evaluation-manifest.json" \
  --prompt-file "$TMP/prompt.txt" --output "$TMP/results/grok-collision.txt" \
  --metrics "$TMP/results/grok-collision.txt.commit.json" --workdir "$TMP/work" \
  >/dev/null 2>&1 || rc=$?
[ "$rc" = 64 ] || fail "metrics/commit collision returned $rc"
[ ! -e "$TMP/results/grok-collision.txt" ] \
  && [ ! -e "$TMP/results/grok-collision.txt.commit.json" ] \
  || fail "metrics/commit collision published artifacts"

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
  out="$TMP/results/grok-publish-$phase.txt"
  case "$phase" in
    output) target="$out" ;;
    metrics) target="$out.metrics.json" ;;
    commit) target="$out.commit.json" ;;
  esac
  target="$(cd "$(dirname "$target")" && pwd -P)/$(basename "$target")"
  rc=0
  FAIL_MV_TARGET="$target" DELEGATION_GROK_HOME="$TMP/grok-home" \
  DELEGATION_GROK_BIN_STORE="$TMP/eval-store" DELEGATION_GROK_BIN="$TMP/bin/grok" \
  PATH="$TMP/mv-fail:$TMP/bin:$PATH" "$EVAL_ROOT/bin/delegation-grok" run \
    --lane policy-annotation --effort high --backend grok-build --evaluation \
    --evaluation-manifest "$TMP/grok-evaluation-manifest.json" \
    --prompt-file "$TMP/prompt.txt" --output "$out" --workdir "$TMP/work" \
    >/dev/null 2>&1 || rc=$?
  [ "$rc" = 70 ] || fail "$phase publication failure returned $rc"
  [ ! -e "$out" ] && [ ! -e "$out.metrics.json" ] && [ ! -e "$out.commit.json" ] \
    || fail "$phase publication failure left a published member"
done

rc=0
DELEGATION_GROK_HOME="$TMP/grok-home" \
DELEGATION_GROK_BIN_STORE="$TMP/eval-store" \
DELEGATION_GROK_BIN="$TMP/bin/grok" \
GROK_FAKE_MODE=content_model_missing PATH="$TMP/bin:$PATH" \
  "$EVAL_ROOT/bin/delegation-grok" run \
  --lane policy-annotation --effort high --backend grok-build --evaluation \
  --evaluation-manifest "$TMP/grok-evaluation-manifest.json" \
  --prompt-file "$TMP/prompt.txt" --output "$TMP/results/policy-identity.txt" \
  --workdir "$TMP/work" >/dev/null 2>&1 || rc=$?
[ "$rc" = 70 ] || fail "policy-annotation missing content identity returned $rc"
jq -e '.phase == "identity" and .reason == "strict_identity_evaluation_void"' \
  "$TMP/results/policy-identity.txt.error.json" >/dev/null \
  || fail "policy-annotation missing identity was not VOID"

rc=0
DELEGATION_GROK_HOME="$TMP/grok-home" \
DELEGATION_GROK_BIN_STORE="$TMP/eval-store" \
DELEGATION_GROK_BIN="$TMP/bin/grok" \
GROK_FAKE_MODE=content_model_mismatch PATH="$TMP/bin:$PATH" \
  "$EVAL_ROOT/bin/delegation-grok" run \
  --lane policy-annotation --effort high --backend grok-build --evaluation \
  --evaluation-manifest "$TMP/grok-evaluation-manifest.json" \
  --prompt-file "$TMP/prompt.txt" --output "$TMP/results/policy-mismatch.txt" \
  --workdir "$TMP/work" >/dev/null 2>&1 || rc=$?
[ "$rc" = 70 ] || fail "policy-annotation content identity mismatch returned $rc"
jq -e '.phase == "identity" and .reason == "provider_identity_mismatch"' \
  "$TMP/results/policy-mismatch.txt.error.json" >/dev/null \
  || fail "policy-annotation content identity mismatch diagnostic"

# A receipt that cannot be merged fails closed: exit 70, no output, no metrics.
# The shim refuses only the runner's receipt-merge jq invocation and delegates
# every other jq call to the real binary.
mkdir -p "$TMP/bin-receipt-fail"
cat >"$TMP/bin-receipt-fail/jq" <<EOF
#!/usr/bin/env bash
case " \$* " in *evaluation_receipt*) exit 1 ;; esac
exec "$(command -v jq)" "\$@"
EOF
chmod 755 "$TMP/bin-receipt-fail/jq"
rc=0
DELEGATION_GROK_HOME="$TMP/grok-home" \
DELEGATION_GROK_BIN_STORE="$TMP/eval-store" \
DELEGATION_GROK_BIN="$TMP/bin/grok" \
PATH="$TMP/bin-receipt-fail:$TMP/bin:$PATH" \
  "$EVAL_ROOT/bin/delegation-grok" run \
  --lane policy-annotation --effort high --backend grok-build --evaluation \
  --evaluation-manifest "$TMP/grok-evaluation-manifest.json" \
  --prompt-file "$TMP/prompt.txt" --output "$TMP/results/policy-receipt-fail.txt" \
  --workdir "$TMP/work" >/dev/null 2>&1 || rc=$?
[ "$rc" = 70 ] || fail "receipt merge failure returned $rc"
[ ! -e "$TMP/results/policy-receipt-fail.txt" ] || fail "receipt failure published output"
[ ! -e "$TMP/results/policy-receipt-fail.txt.metrics.json" ] \
  || fail "receipt failure published metrics"
jq -e '.phase == "extract" and .reason == "receipt_merge_failed"' \
  "$TMP/results/policy-receipt-fail.txt.error.json" >/dev/null \
  || fail "receipt failure diagnostic mismatch"

rc=0
run_grok run --lane builder --allow-provisional --effort max --prompt-file "$TMP/prompt.txt" \
  --output "$TMP/results/effort.txt" --workdir "$TMP/work" >/dev/null 2>&1 || rc=$?
[ "$rc" = 64 ] || fail "invalid effort returned $rc"

GROK_FAKE_VERSION=user-build-b run_grok run \
  --lane builder --allow-provisional --prompt-file "$TMP/prompt.txt" \
  --output "$TMP/results/alternate-version.txt" --workdir "$TMP/work"
jq -e '
  .runtime_cli_version == "user-build-b" and
  .runtime_cli_compatibility == "capability-probed"
' "$TMP/results/alternate-version.txt.metrics.json" >/dev/null \
  || fail "compatible alternate CLI version was not accepted"

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

# ---- private CLI archive: version is provenance, bytes retain a digest ----
run_grok pin --from "$TMP/bin/grok" >"$TMP/pin.txt"
grep -q 'user-build-a' "$TMP/pin.txt" || fail "pin did not report observed provenance"
[ -x "$TMP/store/current/grok" ] || fail "pin did not archive the binary"
[ -r "$TMP/store/current/grok.sha256" ] || fail "pin did not record a digest"
[ "$(stat -f '%Lp' "$TMP/store/current/grok")" = 500 ] || fail "pinned binary is writable"

run_grok pin --from "$TMP/bin/grok" >"$TMP/pin-again.txt"
grep -q 'already archived' "$TMP/pin-again.txt" || fail "second pin was not idempotent"

rc=0
run_grok pin --from "$TMP/bin-updated/grok" >/dev/null 2>&1 || rc=$?
[ "$rc" = 64 ] || fail "replacing an archived compatible build without --force returned $rc"

# A compatible ambient update does not replace the explicitly archived bytes.
run_grok_updated check --json >"$TMP/check-pinned.json"
jq -e '
  .runtime_cli_version == "user-build-a" and
  .runtime_cli_compatibility == "capability-probed" and
  .runtime_cli_source == "pinned" and
  .selected_backend == "grok-build" and
  .provisional_lanes == ["builder","frontend-builder"]
' "$TMP/check-pinned.json" >/dev/null || fail "private archive did not survive an ambient CLI update"
[ "$(jq -r '.runtime_cli_path' "$TMP/check-pinned.json")" = "$TMP/store/current/grok" ] \
  || fail "check did not report the pinned binary path"

run_grok_updated run --lane builder --allow-provisional --prompt-file "$TMP/prompt.txt" \
  --output "$TMP/results/pinned.txt" --workdir "$TMP/work"
[ "$(cat "$TMP/results/pinned.txt")" = PONG ] || fail "pinned dispatch failed"
jq -e '.runtime_cli_version == "user-build-a" and .runtime_cli_source == "pinned"' \
  "$TMP/results/pinned.txt.metrics.json" >/dev/null || fail "metrics lost pinned provenance"

# A tampered store must fail closed rather than run unattested bytes.
chmod 600 "$TMP/store/current/grok.sha256"
printf '%s  grok\n' deadbeef >"$TMP/store/current/grok.sha256"
rc=0
run_grok_updated run --lane builder --allow-provisional --prompt-file "$TMP/prompt.txt" \
  --output "$TMP/results/tampered.txt" --workdir "$TMP/work" >/dev/null 2>&1 || rc=$?
[ "$rc" = 69 ] || fail "digest mismatch returned $rc"
[ ! -e "$TMP/results/tampered.txt" ] || fail "digest mismatch published output"
run_grok_updated check --json >"$TMP/check-tampered.json"
jq -e '
  .selected_backend == "none" and
  .runtime_cli_source == "none" and
  (.backends["grok-build"].reason | test("digest mismatch"))
' "$TMP/check-tampered.json" >/dev/null || fail "digest mismatch was not reported"
run_grok pin --from "$TMP/bin/grok" --force >/dev/null

# An explicit compatible override outranks the store regardless of version.
DELEGATION_GROK_BIN="$TMP/bin-updated/grok" run_grok run --lane builder --allow-provisional \
  --prompt-file "$TMP/prompt.txt" --output "$TMP/results/override.txt" \
  --workdir "$TMP/work"
jq -e '.runtime_cli_version == "user-build-b" and .runtime_cli_source == "override"' \
  "$TMP/results/override.txt.metrics.json" >/dev/null \
  || fail "compatible alternate override was not accepted"
DELEGATION_GROK_BIN="$TMP/bin/grok" run_grok check --json >"$TMP/check-override.json"
jq -e '.runtime_cli_source == "override" and .selected_backend == "grok-build"' \
  "$TMP/check-override.json" >/dev/null || fail "override was not honored"

rc=0
run_grok pin --from "$TMP/bin-incompatible/grok" --force >/dev/null 2>&1 || rc=$?
[ "$rc" = 69 ] || fail "pinning a capability-incompatible build returned $rc"

DELEGATION_GROK_BIN="$TMP/bin-incompatible/grok" \
  run_grok check --json >"$TMP/check-incompatible.json"
jq -e '
  .selected_backend == "none" and
  .runtime_cli_source == "none" and
  (.backends["grok-build"].reason | test("lacks the required interface"))
' "$TMP/check-incompatible.json" >/dev/null \
  || fail "incomplete dispatch interface was reported as ready"

# A pre-migration, version-directory archive remains usable without PATH and is
# migrated into the stable current/ slot by `pin`.
mkdir -p "$TMP/nogrok"
for tool in jq shasum sha256sum timeout gtimeout; do
  tool_path="$(command -v "$tool" 2>/dev/null || true)"
  [ -z "$tool_path" ] || ln -sf "$tool_path" "$TMP/nogrok/$tool"
done
rm -rf "$TMP/store"
mkdir -p "$TMP/store/legacy-user-build"
cp "$TMP/bin/grok" "$TMP/store/legacy-user-build/grok"
chmod 500 "$TMP/store/legacy-user-build/grok"
if command -v shasum >/dev/null 2>&1; then
  legacy_digest="$(shasum -a 256 "$TMP/store/legacy-user-build/grok" | awk '{print $1}')"
else
  legacy_digest="$(sha256sum "$TMP/store/legacy-user-build/grok" | awk '{print $1}')"
fi
printf '%s  grok\n' "$legacy_digest" >"$TMP/store/legacy-user-build/grok.sha256"
chmod 400 "$TMP/store/legacy-user-build/grok.sha256"
DELEGATION_GROK_HOME="$TMP/grok-home" DELEGATION_GROK_BIN_STORE="$TMP/store" \
  PATH="$TMP/nogrok:/usr/bin:/bin" "$ROOT/bin/delegation-grok" check --json \
  >"$TMP/check-legacy.json"
jq -e '
  .selected_backend == "grok-build" and
  .runtime_cli_source == "legacy" and
  (.runtime_cli_path | endswith("/legacy-user-build/grok"))
' "$TMP/check-legacy.json" >/dev/null || fail "legacy archive fallback failed"
DELEGATION_GROK_HOME="$TMP/grok-home" DELEGATION_GROK_BIN_STORE="$TMP/store" \
  PATH="$TMP/nogrok:/usr/bin:/bin" "$ROOT/bin/delegation-grok" pin \
  >"$TMP/pin-legacy.txt"
[ -x "$TMP/store/current/grok" ] || fail "legacy archive was not migrated"
DELEGATION_GROK_HOME="$TMP/grok-home" DELEGATION_GROK_BIN_STORE="$TMP/store" \
  PATH="$TMP/nogrok:/usr/bin:/bin" "$ROOT/bin/delegation-grok" check --json \
  >"$TMP/check-migrated.json"
jq -e '.selected_backend == "grok-build" and .runtime_cli_source == "pinned"' \
  "$TMP/check-migrated.json" >/dev/null || fail "migrated archive was not selected"

# With no store and no ambient CLI the lane refuses, and says how to fix it.
rm -rf "$TMP/store"
rc=0
DELEGATION_GROK_HOME="$TMP/grok-home" DELEGATION_GROK_BIN_STORE="$TMP/store" \
  PATH="$TMP/nogrok:/usr/bin:/bin" "$ROOT/bin/delegation-grok" run --lane builder \
  --allow-provisional --prompt-file "$TMP/prompt.txt" \
  --output "$TMP/results/missing.txt" --workdir "$TMP/work" \
  >/dev/null 2>"$TMP/missing.err" || rc=$?
[ "$rc" = 69 ] || fail "missing CLI returned $rc"
grep -q 'delegation-grok pin' "$TMP/missing.err" || fail "missing CLI did not name the remedy"

printf 'Grok runner tests passed.\n'
