#!/usr/bin/env bash
# delegation-muse against a fake Muse Code binary, sandbox-exec and shlock:
# the isolated environment, the per-role flags, contributor mode, identity,
# failure classes, the subscription-only sign-in and the OAuth sync. No
# network and no real CLI.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/delegation-muse-test.XXXXXX")"
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf -- "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/work" "$TMP/results" "$TMP/runtime" \
  "$TMP/muse-config" "$TMP/keychains" "$TMP/ambient-home"
printf '%s\n' 'Respond with PONG.' >"$TMP/prompt"
printf '%s\n' 'before' >"$TMP/work/value.txt"

fail() { printf 'Muse runner test failed: %s\n' "$*" >&2; exit 1; }

sign_in() { # $1=mechanism $2=subs_active
  jq -n --arg mechanism "$1" --argjson subs "$2" \
    '{schema_version:2,providers:{meta:{mechanism:$mechanism,storage:"keychain",subs_active:$subs}}}' \
    >"$TMP/muse-config/auth.json"
  chmod 600 "$TMP/muse-config/auth.json"
}
sign_in oauth true

cat >"$TMP/bin/sandbox-exec" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
profile=""
: >"$root/sandbox-defines.txt"
while [ "$#" -gt 0 ]; do
  case "$1" in
    -D) printf '%s\n' "${2:-}" >>"$root/sandbox-defines.txt"; shift 2 ;;
    -p) profile="${2:-}"; shift 2; break ;;
    *) exit 64 ;;
  esac
done
printf '%s\n' "$profile" >"$root/sandbox.profile"
grep -q 'deny process-exec (require-not (literal (param "MUSE_BIN"))))' "$root/sandbox.profile"
grep -q 'deny file-read-data' "$root/sandbox.profile"
grep -q 'deny file-write' "$root/sandbox.profile"
for name in SCRATCH WORKDIR REAL_HOME KEYCHAINS MUSE_BIN; do
  grep -q "^$name=" "$root/sandbox-defines.txt"
done
exec "$@"
EOF

cat >"$TMP/bin/shlock" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
while [ "$#" -gt 0 ]; do
  case "$1" in -f) lock_file="$2"; shift 2 ;; -p) owner_pid="$2"; shift 2 ;; *) exit 64 ;; esac
done
if [ -e "$lock_file" ]; then
  kill -0 "$(<"$lock_file")" 2>/dev/null && exit 1
  rm -f -- "$lock_file"
fi
printf '%s\n' "$owner_pid" >"$lock_file"
EOF

# The fake CLI records its argv and environment, then answers by scenario
# (MUSE_FAKE_SCENARIO is read from a file: the runner passes no such variable).
cat >"$TMP/bin/muse-bin-fake" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
if [ "${1:-}" = --version ]; then printf 'Muse Code 9.9.9 (9.9.9-R1)\n'; exit 0; fi
if [ "${1:-}" = exec ] && [ "${2:-}" = --help ]; then
  printf '%s\n' --json --prompt-file --model --reasoning-effort --contributor-mode \
    --no-session-log --no-foreign-personal-context --disable-web-tools \
    --disable-reminders --disable-request-user-input --disable-shell \
    --disable-write --approval-mode --approval-judge --max-model-steps --workspace
  exit 0
fi
printf '%s\n' "$@" >"$root/argv.txt"
env >"$root/env.txt"
scenario="$(cat "$root/scenario" 2>/dev/null || printf ok)"
model=""; prev=""
for arg in "$@"; do [ "$prev" = --model ] && model="$arg"; prev="$arg"; done
reported="$model"
[ "$scenario" != wrong-model ] || reported="muse-spark-1.2"
usage() {
  jq -cn --arg m "$1" '{record_type:"status",payload_type:"run.usage",payload:{kind:"run_usage",
    models:[{model:$m,input_tokens:100,cached_tokens:10,output_tokens:5,reasoning_tokens:2,calls:1}],
    allowance:{tier:null,source:"stream"}}}'
}
case "$scenario" in
  entitlement)
    jq -cn '{payload_type:"run.terminal.failed",payload:{kind:"run_terminal",terminal:"failed",text:"",
      reason:"model `muse-wonder-full-1.0` does not exist or you lack access"}}'
    exit 1
    ;;
  failed-exit-zero)
    jq -cn '{payload_type:"run.terminal.failed",payload:{kind:"run_terminal",terminal:"failed",text:"",reason:"gateway timeout"}}'
    exit 0
    ;;
  refresh)
    printf '%s\n' '{"schema_version":2,"providers":{"meta":{"mechanism":"oauth","subs_active":true,"refreshed":true}}}' \
      >"$XDG_CONFIG_HOME/muse/auth.json"
    ;;
esac
if ! grep -qx -- --disable-write "$root/argv.txt"; then
  printf '%s\n' 'after' >value.txt
fi
usage "$reported"
jq -cn '{record_type:"event",payload_type:"run.terminal.completed",payload:{kind:"run_terminal",terminal:"completed",text:"PONG",reason:null}}'
EOF
chmod 755 "$TMP/bin/"*

run_muse() {
  env HOME="$TMP/ambient-home" TMPDIR="$TMP/runtime" META_API_KEY=sk-must-not-pass \
    DELEGATION_CONFIG_FILE="$TMP/no-config/config.json" \
    DELEGATION_MUSE_BIN="$TMP/bin/muse-bin-fake" \
    DELEGATION_MUSE_CONFIG_DIR="$TMP/muse-config" \
    DELEGATION_MUSE_KEYCHAINS_DIR="$TMP/keychains" \
    DELEGATION_MUSE_PLATFORM=Darwin \
    DELEGATION_MUSE_SANDBOX_BIN="$TMP/bin/sandbox-exec" \
    DELEGATION_MUSE_SHLOCK_BIN="$TMP/bin/shlock" \
    DELEGATION_MUSE_OAUTH_WAIT_SECONDS=0 \
    "$ROOT/bin/delegation-muse" "$@"
}
dispatch() { # $1=lane $2=name, then NAME=value settings for the runner
  local lane="$1" name="$2" setting; shift 2
  (
    for setting in "$@"; do export "${setting?}"; done
    run_muse run --lane "$lane" \
      --prompt-file "$TMP/prompt" --output "$TMP/results/$name" --workdir "$TMP/work"
  )
}

# check: ready on a browser sign-in with a subscription
run_muse check --json >"$TMP/check.json"
jq -e '
  .adapter == "muse-code-cli" and .selected_backend == "native" and
  .model == "muse-spark-1.3" and .billing == "subscription" and
  .contributor_mode == "off" and .runtime_cli_version == "Muse Code 9.9.9 (9.9.9-R1)" and
  .backends.native.api_key_passed == false and .backends.native.auto_update == false and
  .backends.native.terminal == false and .backends.native.web_tools == false
' "$TMP/check.json" >/dev/null || fail "check contract mismatch"

# an API-key sign-in, no subscription, or another model: not this lane
sign_in api_key true
run_muse check --json | jq -e '.selected_backend == "none" and (.backends.native.reason | test("subscription only"))' >/dev/null \
  || fail "an API-key sign-in was accepted"
sign_in oauth false
run_muse check --json | jq -e '.selected_backend == "none" and (.backends.native.reason | test("no active Muse Code subscription"))' >/dev/null \
  || fail "a sign-in without a subscription was accepted"
sign_in oauth true
DELEGATION_REQUESTED_MODEL=muse-glimmer run_muse check --json \
  | jq -e '.selected_backend == "none" and (.backends.native.reason | test("not a supported Muse Code model"))' >/dev/null \
  || fail "an unsupported model was accepted"
DELEGATION_CONTRIBUTOR_MODE=maybe run_muse check --json | jq -e '.selected_backend == "none"' >/dev/null \
  || fail "an invalid contributor mode was accepted"

# a read-only lane: scrubbed environment, write disabled, contributor off
dispatch scout scout DELEGATION_REQUESTED_MODEL=muse-wonder-1.0 DELEGATION_PROFILE_EFFORT=max
[ "$(cat "$TMP/results/scout")" = PONG ] || fail "scout answer missing"
grep -qx before "$TMP/work/value.txt" || fail "a read-only lane wrote to the workdir"
! grep -q 'META_API_KEY' "$TMP/env.txt" || fail "META_API_KEY reached the CLI"
grep -q "^HOME=$TMP/runtime/" "$TMP/env.txt" || fail "the CLI saw the ambient home"
for flag in --disable-write --disable-shell --disable-web-tools --no-foreign-personal-context \
    --no-session-log --disable-request-user-input; do
  grep -qx -- "$flag" "$TMP/argv.txt" || fail "scout lacks $flag"
done
grep -A1 -x -- --contributor-mode "$TMP/argv.txt" | grep -qx off || fail "contributor mode not off"
grep -A1 -x -- --reasoning-effort "$TMP/argv.txt" | grep -qx max || fail "effort not passed"
jq -e '
  .provider_reported_model == "muse-wonder-1.0" and .model_identity_source == "provider-reported" and
  .billing == "subscription" and .subscription_allowance_reported == true and
  .contributor_mode == "off" and .write_scope == "scratch" and .api_key_passed == false and
  .tokens == {input:100,output:5,reasoning:2,cache_read:10,cache_write:0}
' "$TMP/results/scout.metrics.json" >/dev/null || fail "scout metrics mismatch"

# a builder writes inside the workdir; contributor on is passed and recorded
dispatch builder builder DELEGATION_CONTRIBUTOR_MODE=on
grep -qx after "$TMP/work/value.txt" || fail "builder did not edit the workdir"
! grep -qx -- --disable-write "$TMP/argv.txt" || fail "builder was denied writes"
grep -qx -- --disable-shell "$TMP/argv.txt" || fail "builder has a shell"
grep -A1 -x -- --contributor-mode "$TMP/argv.txt" | grep -qx on || fail "contributor on not passed"
jq -e '.contributor_mode == "on" and .write_scope == "workdir"' "$TMP/results/builder.metrics.json" >/dev/null \
  || fail "builder metrics mismatch"
printf '%s\n' before >"$TMP/work/value.txt"

# another model in the usage record is an identity failure, with no answer
printf wrong-model >"$TMP/scenario"
rc=0; dispatch clerk wrong >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 70 ] && [ ! -e "$TMP/results/wrong" ] || fail "identity mismatch not refused (rc=$rc)"

# failure classes, including a failed run that exits 0
printf entitlement >"$TMP/scenario"
rc=0; dispatch clerk entitlement >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 69 ] && jq -e '.reason == "entitlement_unavailable"' "$TMP/results/entitlement.error.json" >/dev/null \
  || fail "entitlement not classified (rc=$rc)"
printf failed-exit-zero >"$TMP/scenario"
rc=0; dispatch clerk timeout >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 75 ] && [ ! -e "$TMP/results/timeout" ] || fail "a failed terminal record was accepted (rc=$rc)"

# a sign-in the CLI refreshed goes back to the ambient file
printf refresh >"$TMP/scenario"
dispatch clerk refresh
jq -e '.providers.meta.refreshed == true' "$TMP/muse-config/auth.json" >/dev/null || fail "refreshed sign-in not synced back"
rm -f "$TMP/scenario"
sign_in oauth true

# a busy kit lock is temporary; unknown roles and efforts are refused
sleep 30 & holder=$!
printf '%s\n' "$holder" >"$TMP/muse-config/.delegation-kit-oauth.lock"
rc=0; dispatch clerk busy >/dev/null 2>&1 || rc=$?
kill "$holder" 2>/dev/null || true
[ "$rc" -eq 75 ] || fail "busy OAuth lock not reported as temporary (rc=$rc)"
rc=0; dispatch senior senior >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 78 ] || fail "unsupported lane not refused (rc=$rc)"
rc=0; run_muse run --lane clerk --effort ultra --prompt-file "$TMP/prompt" --output "$TMP/results/ultra" --workdir "$TMP/work" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 64 ] || fail "invalid effort not refused (rc=$rc)"

printf '%s\n' "Muse runner tests passed."
