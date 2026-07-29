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
    printf 'You are logged in with grok.com.\n\nAvailable models:\n  * grok-4.5 (default)\n'
    exit 0
    ;;
  inspect)
    if [ "${2:-}" = --help ]; then
      printf '%s\n' 'Show configuration' '--json'
      exit 0
    fi
    [ "${2:-}" = --json ] || exit 2
    jq -n --arg target "$HOME/.grok/hooks/delegation-policy.sh" '
      {mcpServers:[],plugins:[],permissions:{sources:[]},hooks:[]}
    '
    exit 0
    ;;
  --version)
    printf 'grok %s\n' "${GROK_FAKE_VERSION:-user-build-a}"
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
case "$args" in *" --help "*) exit 0 ;; esac
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
  DELEGATION_GROK_HOME="$TMP/grok-home" DELEGATION_GROK_BIN_STORE="$TMP/store" \
    PATH="$TMP/bin:$PATH" "$ROOT/bin/delegation-grok" "$@"
}

run_grok_updated() {
  DELEGATION_GROK_HOME="$TMP/grok-home" DELEGATION_GROK_BIN_STORE="$TMP/store" \
    PATH="$TMP/bin-updated:$PATH" "$ROOT/bin/delegation-grok" "$@"
}

run_grok check --json >"$TMP/check.json"
jq -e '
  .model == "grok-4.5" and
  .runtime_cli_version == "user-build-a" and
  .runtime_cli_compatibility == "capability-probed" and
  .runtime_cli_source == "path" and
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
  .runtime_cli_version == "user-build-a" and
  .runtime_cli_compatibility == "capability-probed" and
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
