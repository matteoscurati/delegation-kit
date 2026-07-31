#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/delegation-kimi-test.XXXXXX")"
TMP="$(cd "$TMP" && pwd -P)"
cleanup() {
  if [ "${KEEP_KIMI_TEST_TMP:-0}" = 1 ]; then
    printf 'Kimi test artifacts: %s\n' "$TMP" >&2
  else
    rm -rf -- "$TMP"
  fi
}
trap cleanup EXIT
mkdir -p \
  "$TMP/bin" "$TMP/work" "$TMP/results" "$TMP/runtime" \
  "$TMP/kimi-home/credentials" "$TMP/ambient-home" "$TMP/debug"
chmod 700 "$TMP/debug"
printf '%s\n' '{"access_token":"test-token","refresh_token":""}' \
  >"$TMP/kimi-home/credentials/kimi-code.json"
chmod 600 "$TMP/kimi-home/credentials/kimi-code.json"
printf '%s\n' 'ambient secret' >"$TMP/ambient-home/secret.txt"
printf '%s\n' 'Respond with PONG.' >"$TMP/prompt"
printf '%s\n' 'before' >"$TMP/work/value.txt"

# The production runner must reject a dirty evaluation checkout.  Build a
# separate committed repository fixture so positive evaluation coverage never
# relaxes that protection in the real worktree.
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

fail() { printf 'Kimi runner test failed: %s\n' "$*" >&2; exit 1; }

cat >"$TMP/bin/uname" <<'EOF'
#!/usr/bin/env bash
printf 'Darwin\n'
EOF

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
grep -q 'deny process-exec' "$root/sandbox.profile"
grep -q 'literal "/usr/bin/true"' "$root/sandbox.profile"
grep -q 'param "RG_BIN"' "$root/sandbox.profile"
grep -q 'deny file-read-data' "$root/sandbox.profile"
grep -q 'deny file-write' "$root/sandbox.profile"
grep -q '^SCRATCH=' "$root/sandbox-defines.txt"
grep -q '^WORKDIR=' "$root/sandbox-defines.txt"
grep -q '^REAL_HOME=' "$root/sandbox-defines.txt"
grep -q '^KIMI_BIN=' "$root/sandbox-defines.txt"
grep -q '^RG_BIN=' "$root/sandbox-defines.txt"
grep -q '^RG_DIR=' "$root/sandbox-defines.txt"
exec "$@"
EOF

cat >"$TMP/bin/shlock" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
lock_file=""
owner_pid=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -f) lock_file="${2:-}"; shift 2 ;;
    -p) owner_pid="${2:-}"; shift 2 ;;
    *) exit 64 ;;
  esac
done
[ -n "$lock_file" ] && [ -n "$owner_pid" ] || exit 64
[ ! -L "$lock_file" ] || exit 1
if [ -e "$lock_file" ]; then
  current="$(<"$lock_file")"
  case "$current" in
    ""|*[!0-9]*) exit 1 ;;
  esac
  kill -0 "$current" 2>/dev/null && exit 1
  rm -f -- "$lock_file"
fi
candidate="$lock_file.$$.candidate"
trap 'rm -f -- "$candidate"' EXIT
printf '%s\n' "$owner_pid" >"$candidate"
ln "$candidate" "$lock_file" 2>/dev/null
EOF

cat >"$TMP/bin/gtimeout" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = -k ]; then shift 2; fi
seconds="${1:-}"; shift
case "$*" in *TIMEOUT_EVALUATION*) exit 124 ;; esac
case "$*" in *TIMEOUT_OPERATIONAL*) exit 124 ;; esac
exec "$@"
EOF

cat >"$TMP/bin/rg" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  --version) printf '%s\n' 'ripgrep 99.0.0-test'; exit 0 ;;
esac
printf '%s\n' "$*" >"$HOME/rg-used"
printf '%s\n' 'needle:fixture'
EOF

cat >"$TMP/bin/kimi" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
case "${1:-}" in
  --version)
    printf '%s\n' "${KIMI_FAKE_VERSION:-user-build-a}"
    exit 0
    ;;
  --help)
    if [ "${KIMI_FAKE_NO_AGENT_FILE:-0}" = 1 ]; then
      printf '%s\n' '--prompt --model --output-format stream-json --skills-dir'
    elif [ "${KIMI_FAKE_NO_STREAM_JSON:-0}" = 1 ]; then
      printf '%s\n' '--prompt --model --output-format text --agent-file --skills-dir'
    elif [ "${KIMI_FAKE_NO_SKILLS_DIR:-0}" = 1 ]; then
      printf '%s\n' '--prompt --model --output-format stream-json --agent-file'
    else
      printf '%s\n' '--prompt --model --output-format stream-json --agent-file --skills-dir'
    fi
    exit 0
    ;;
  provider)
    [ "${2:-}" = list ] || exit 64
    if [ "${3:-}" = --json ]; then
      effort="${KIMI_FAKE_DEFAULT_EFFORT:-max}"
      if [ "${KIMI_FAKE_IGNORE_ISOLATED_EFFORT:-0}" != 1 ] &&
          grep -Fq 'default_effort = "max"' "$HOME/.kimi-code/config.toml" 2>/dev/null; then
        effort=max
      fi
      jq -n --arg effort "$effort" '
        {models:{"kimi-code/k3":{
          provider:"managed:kimi-code",model:"k3",
          supportEfforts:["low","high","max"],defaultEffort:$effort}}}
      '
    else
      printf '%s\n' 'managed:kimi-code source=oauth'
    fi
    exit 0
    ;;
  doctor)
    if [ "${2:-}" = --help ]; then
      printf '%s\n' 'doctor config <path>'
      exit 0
    fi
    [ "${2:-}" = config ] || exit 64
    [ -f "${3:-}" ] || exit 64
    exit 0
    ;;
esac

[ -z "${LEAK_ME:-}" ] || { printf 'environment leak\n' >&2; exit 91; }
[ -z "${ZAI_API_KEY:-}" ] || { printf 'credential leak\n' >&2; exit 92; }
[ "$SHELL" = /usr/bin/true ] || { printf 'unsafe shell\n' >&2; exit 93; }
[ "$KIMI_CODE_HOME" = "$HOME/.kimi-code" ] || { printf 'KIMI_CODE_HOME mismatch\n' >&2; exit 93; }
[ "${KIMI_DISABLE_TELEMETRY:-}" = 1 ] || { printf 'telemetry enabled\n' >&2; exit 93; }
[ "${KIMI_CODE_NO_AUTO_UPDATE:-}" = 1 ] || { printf 'updates enabled\n' >&2; exit 93; }
[ "${KIMI_DISABLE_CRON:-}" = 1 ] || { printf 'cron enabled\n' >&2; exit 93; }
config="$HOME/.kimi-code/config.toml"
grep -Fq 'default_model = "kimi-code/k3"' "$config" \
  || { printf 'model not pinned\n' >&2; exit 94; }
grep -Fq 'effort = "max"' "$config" \
  || { printf 'effort not pinned\n' >&2; exit 95; }
! grep -Eq '^\[\[hooks\]\]|^\[services\.' "$config" \
  || { printf 'ambient config leaked\n' >&2; exit 96; }
grep -Fq 'max_retries_per_step = 3' "$config" || { printf 'retry count mismatch\n' >&2; exit 96; }
grep -Fq 'print_background_mode = "exit"' "$config" || { printf 'background mode mismatch\n' >&2; exit 96; }
grep -Fq 'telemetry = false' "$config" || { printf 'telemetry config mismatch\n' >&2; exit 96; }
grep -Fq 'auto_install = false' "$HOME/.kimi-code/tui.toml" \
  || { printf 'auto update config mismatch\n' >&2; exit 96; }

prompt=""
agent_file=""
args=" $* "
[[ "$args" == *" --model kimi-code/k3 "* ]] \
  || { printf 'model argument missing\n' >&2; exit 97; }
[[ "$args" == *" --output-format stream-json "* ]] \
  || { printf 'output format missing\n' >&2; exit 98; }
[[ "$args" == *" --agent-file "* ]] \
  || { printf 'agent file missing\n' >&2; exit 98; }
[[ "$args" == *" --skills-dir "* ]] \
  || { printf 'skills isolation missing\n' >&2; exit 98; }
while [ "$#" -gt 0 ]; do
  case "$1" in
    --prompt) prompt="${2:-}"; shift 2 ;;
    --agent-file) agent_file="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done
[ -f "$agent_file" ] || { printf 'agent file unreadable\n' >&2; exit 98; }
grep -Fq '${base_prompt}' "$agent_file" || { printf 'base prompt missing\n' >&2; exit 98; }
allowed_tools="$(awk '/^tools:/{inside=1; next} /^disallowedTools:/{inside=0} inside {print}' "$agent_file")"
! grep -Eq '^  - (Bash|WebSearch|FetchURL|Agent|AgentSwarm|Skill|TaskList|CronCreate|EnterPlanMode)$' <<<"$allowed_tools" \
  || { printf 'forbidden tool exposed\n' >&2; exit 98; }
case "$(awk '/^name:/{print $2; exit}' "$agent_file")" in
  delegation-kimi-clerk)
    grep -Fq 'max_steps_per_turn = 30' "$config" || exit 98
    ;;
  delegation-kimi-scout)
    grep -Fq 'max_steps_per_turn = 40' "$config" || exit 98
    grep -Fq '  - Grep' <<<"$allowed_tools" || exit 98
    ! grep -Fq '  - Edit' <<<"$allowed_tools" || exit 98
    ;;
  delegation-kimi-builder)
    grep -Fq 'max_steps_per_turn = 60' "$config" || exit 98
    grep -Fq '  - Edit' <<<"$allowed_tools" || exit 98
    ! grep -Fq '  - ReadMediaFile' <<<"$allowed_tools" || exit 98
    ;;
  delegation-kimi-frontend-builder)
    grep -Fq 'max_steps_per_turn = 60' "$config" || exit 98
    grep -Fq '  - ReadMediaFile' <<<"$allowed_tools" || exit 98
    ;;
  delegation-kimi-policy-annotation)
    grep -Fq 'max_steps_per_turn = 30' "$config" || exit 98
    grep -Fxq 'tools: []' "$agent_file" || exit 98
    ;;
  *) printf 'unexpected agent name\n' >&2; exit 98 ;;
esac
case "$prompt" in
  *WRITE_BUILDER*) printf 'after\n' >"$PWD/value.txt" ;;
  *USE_GREP*) rg needle . >/dev/null ;;
  *HEARTBEAT_WAIT*)
    jq -nc '{role:"assistant",tool_calls:[{function:{name:"Grep",arguments:"hidden-content"}}]}'
    /bin/sleep 2
    ;;
  ROTATE_OAUTH)
    jq -n '{access_token:"rotated-access",refresh_token:"rotated-refresh",expires_at:4102444800}' \
      >"$HOME/.kimi-code/credentials/kimi-code.json"
    ;;
  *REQUIRE_ROTATED_OAUTH*)
    jq -e '
      .access_token == "rotated-access" and .refresh_token == "rotated-refresh"
    ' "$HOME/.kimi-code/credentials/kimi-code.json" >/dev/null \
      || { printf 'rotated OAuth credential missing\n' >&2; exit 99; }
    ;;
  *REQUIRE_INTERRUPT_OAUTH*)
    jq -e '
      .access_token == "interrupt-access" and .refresh_token == "interrupt-refresh"
    ' "$HOME/.kimi-code/credentials/kimi-code.json" >/dev/null \
      || { printf 'interrupt OAuth credential missing\n' >&2; exit 99; }
    ;;
  *CONCURRENT_LOGIN*)
    jq -n '{access_token:"external-access",refresh_token:"external-refresh",expires_at:4102444800}' \
      >"$root/kimi-home/credentials/kimi-code.json"
    jq -n '{access_token:"isolated-access",refresh_token:"isolated-refresh",expires_at:4102444800}' \
      >"$HOME/.kimi-code/credentials/kimi-code.json"
    ;;
  *CORRUPT_OAUTH*)
    printf '%s\n' '{}' >"$HOME/.kimi-code/credentials/kimi-code.json"
    ;;
  *ACCESS_ONLY_OAUTH*)
    jq -n '{access_token:"short-lived-access",refresh_token:"",expires_at:4102444800}' \
      >"$HOME/.kimi-code/credentials/kimi-code.json"
    ;;
  *INTERRUPT_ROTATE_OAUTH*)
    jq -n '{access_token:"interrupt-access",refresh_token:"interrupt-refresh",expires_at:4102444800}' \
      >"$HOME/.kimi-code/credentials/kimi-code.json"
    : >"$root/interrupt-ready"
    trap 'exit 143' INT TERM
    while :; do /bin/sleep 1; done
    ;;
  *INTERRUPT_STUBBORN*)
    trap '' TERM
    : >"$root/stubborn-ready"
    while :; do /bin/sleep 1; done
    ;;
  *EVENT_TEXT_FAILURE*)
    jq -nc '{role:"assistant",content:"usage limit for this billing cycle sandbox permission denied"}'
    printf '%s\n' 'unclassified provider failure' >&2
    exit 1
    ;;
  *AUTH_AND_BROKEN_OAUTH*)
    printf '%s\n' '{}' >"$HOME/.kimi-code/credentials/kimi-code.json"
    printf '%s\n' 'Invalid Authentication' >&2
    exit 1
    ;;
  *AUTH_FAILURE*)
    printf '%s\n' 'Invalid Authentication VENDOR_SECRET Authorization: Bearer DEBUG_BEARER_SECRET' >&2
    exit 1
    ;;
  *ENTITLEMENT_FAILURE*) printf '%s\n' 'Your current subscription does not have access to k3 VENDOR_SECRET' >&2; exit 1 ;;
  *QUOTA_FAILURE*) printf '%s\n' "You've reached your usage limit for this billing cycle VENDOR_SECRET" >&2; exit 1 ;;
  *OVERLOAD_FAILURE*) printf '%s\n' 'The engine is currently overloaded VENDOR_SECRET' >&2; exit 1 ;;
  *SERVER_FAILURE*) printf '%s\n' '503 Service Unavailable VENDOR_SECRET' >&2; exit 1 ;;
  *SANDBOX_FAILURE*) printf '%s\n' 'sandbox deny(process-exec) VENDOR_SECRET' >&2; exit 1 ;;
esac
jq -nc '{role:"assistant",content:"PONG"}'
EOF
chmod 755 \
  "$TMP/bin/uname" "$TMP/bin/sandbox-exec" "$TMP/bin/shlock" \
  "$TMP/bin/gtimeout" "$TMP/bin/rg" "$TMP/bin/kimi"

sha256() { shasum -a 256 "$1" | awk '{print $1}'; }
file_mode() {
  stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1"
}
write_manifest() {
  jq -n \
    --arg prompt_sha256 "$(sha256 "$TMP/prompt")" \
    --arg runner_sha256 "$(sha256 "$ROOT/bin/delegation-kimi")" \
    --arg contract_sha256 "$(sha256 "$ROOT/evaluation/test-fixtures/contract.txt")" \
    --arg output_schema_sha256 "$(sha256 "$ROOT/evaluation/test-fixtures/output-schema.json")" \
    --arg source_commit "$BASE_COMMIT" \
    '{schema:"delegation_policy_annotation_evaluation_v1",profile:"kimi-k3",lane:"policy-annotation",model:"kimi-code/k3",backend:"native",effort:"max",prompt_sha256:$prompt_sha256,runner_source_commit:$source_commit,runner_sha256:$runner_sha256,contract_path:"evaluation/test-fixtures/contract.txt",contract_sha256:$contract_sha256,output_schema_path:"evaluation/test-fixtures/output-schema.json",output_schema_sha256:$output_schema_sha256,timeout_seconds:60,max_output_chars:1024}' \
    >"$TMP/manifest.json"
}
write_manifest
MANIFEST_SHA="$(sha256 "$TMP/manifest.json")"
jq --arg hash "$MANIFEST_SHA" '
  .profiles["kimi-k3"].lanes["policy-annotation"].evaluation_manifest_sha256 = [$hash]
' "$ROOT/config/routing-gates.json" >"$TMP/gates.json"
mv "$TMP/gates.json" "$ROOT/config/routing-gates.json"
jq --arg hash "$MANIFEST_SHA" '
  .lanes["policy-annotation"].backends.native.evaluation_manifest_sha256 = [$hash]
' "$ROOT/config/kimi-k3-routing.json" >"$TMP/kimi-routing.json"
mv "$TMP/kimi-routing.json" "$ROOT/config/kimi-k3-routing.json"
git -C "$ROOT" add config/routing-gates.json config/kimi-k3-routing.json
git -C "$ROOT" commit -qm 'allowlist evaluation fixture'

run_kimi() {
  HOME="$TMP/ambient-home" KIMI_CODE_HOME="$TMP/kimi-home" \
    TMPDIR="$TMP/runtime" DELEGATION_DATA_HOME="$TMP/runtime" PATH="$TMP/bin:$PATH" \
    DELEGATION_KIMI_PLATFORM="${DELEGATION_KIMI_PLATFORM:-Darwin}" \
    DELEGATION_KIMI_SANDBOX_BIN="${DELEGATION_KIMI_SANDBOX_BIN:-$TMP/bin/sandbox-exec}" \
    DELEGATION_KIMI_SHLOCK_BIN="${DELEGATION_KIMI_SHLOCK_BIN:-$TMP/bin/shlock}" \
    DELEGATION_KIMI_CANCEL_GRACE_SECONDS="${DELEGATION_KIMI_CANCEL_GRACE_SECONDS:-1}" \
    LEAK_ME=secret ZAI_API_KEY=secret \
    "$ROOT/bin/delegation-kimi" "$@"
}

start_kimi_background() {
  HOME="$TMP/ambient-home" KIMI_CODE_HOME="$TMP/kimi-home" \
    TMPDIR="$TMP/runtime" DELEGATION_DATA_HOME="$TMP/runtime" PATH="$TMP/bin:$PATH" \
    DELEGATION_KIMI_PLATFORM=Darwin \
    DELEGATION_KIMI_SANDBOX_BIN="$TMP/bin/sandbox-exec" \
    DELEGATION_KIMI_SHLOCK_BIN="$TMP/bin/shlock" \
    DELEGATION_KIMI_CANCEL_GRACE_SECONDS="${DELEGATION_KIMI_CANCEL_GRACE_SECONDS:-1}" \
    LEAK_ME=secret ZAI_API_KEY=secret \
    "$ROOT/bin/delegation-kimi" "$@" \
    >"$TMP/background.stdout" 2>"$TMP/background.stderr" &
  KIMI_BACKGROUND_PID=$!
}

run_kimi pin-rg --from "$TMP/bin/rg" >"$TMP/pin-rg.out"
[ -x "$TMP/runtime/kimi-rg/current/rg" ] \
  || fail "pin-rg did not archive the search runtime"
[ -s "$TMP/runtime/kimi-rg/current/rg.sha256" ] &&
  [ -s "$TMP/runtime/kimi-rg/current/rg.version" ] &&
  [ -s "$TMP/runtime/kimi-rg/current/dependencies.json" ] &&
  [ -s "$TMP/runtime/kimi-rg/current/dependencies.sha256" ] \
  || fail "pin-rg attestation is incomplete"

run_kimi check --json >"$TMP/check.json"
jq -e '
  .runtime_cli_version == "user-build-a" and
  .runtime_cli_compatibility == "capability-probed" and
  .selected_backend == "native" and
  .process_exec == {mode:"allowlist",allowed:["rg"],attested:true} and
  .search_runtime.identity == "ripgrep" and
  (.search_runtime.sha256 | test("^[0-9a-f]{64}$")) and
  (.search_runtime.dependencies_sha256 | test("^[0-9a-f]{64}$")) and
  .terminal == false and .web_tools == false and
  .subagents == false and .skills == false and
  .backends.native.available == true and
  .backends.native.isolated_home == true and
  .backends.native.environment_mode == "allowlist" and
  .backends.native.ambient_home_read == false and
  .backends.native.process_exec == {mode:"allowlist",allowed:["rg"],attested:true} and
  .backends.native.terminal == false and
  .backends.native.web_tools == false and
  .backends.native.subagents == false and
  .backends.native.skills == false and
  .backends.native.hooks == false and
  .backends.native.services == false and
  .backends.native.oauth_refresh_persistence == "serialized-atomic-sync" and
  .backends.native.builder_write_scope == "workdir" and
  .backends.native.read_only_write_scope == "scratch"
' "$TMP/check.json" >/dev/null || fail "check contract mismatch"

KIMI_FAKE_NO_AGENT_FILE=1 run_kimi check --json >"$TMP/check-no-agent-file.json"
jq -e '
  .selected_backend == "none" and .backends.native.available == false and
  (.backends.native.reason | test("lacks --agent-file"))
' "$TMP/check-no-agent-file.json" >/dev/null \
  || fail "missing --agent-file capability was accepted"

KIMI_FAKE_NO_STREAM_JSON=1 run_kimi check --json >"$TMP/check-no-stream-json.json"
jq -e '
  .selected_backend == "none" and .backends.native.available == false and
  (.backends.native.reason | test("lacks stream-json"))
' "$TMP/check-no-stream-json.json" >/dev/null \
  || fail "missing stream-json capability was accepted"

KIMI_FAKE_NO_SKILLS_DIR=1 run_kimi check --json >"$TMP/check-no-skills-dir.json"
jq -e '
  .selected_backend == "none" and .backends.native.available == false and
  (.backends.native.reason | test("lacks --skills-dir"))
' "$TMP/check-no-skills-dir.json" >/dev/null \
  || fail "missing --skills-dir capability was accepted"

# Existing verified bytes are immutable unless the caller explicitly forces a
# replacement. Both binary and dependency tamper must fail closed.
PINNED_RG="$TMP/runtime/kimi-rg/current/rg"
PINNED_RG_SHA="$(sha256 "$PINNED_RG")"
cat >"$TMP/alternate-rg" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' 'alternate rg'
EOF
chmod 755 "$TMP/alternate-rg"
rc=0
run_kimi pin-rg --from "$TMP/alternate-rg" >/dev/null 2>&1 || rc=$?
[ "$rc" = 64 ] || fail "different pin without --force returned $rc"
[ "$(sha256 "$PINNED_RG")" = "$PINNED_RG_SHA" ] \
  || fail "different pin replaced verified bytes without --force"

chmod 700 "$PINNED_RG"
printf '%s\n' '# tamper' >>"$PINNED_RG"
chmod 500 "$PINNED_RG"
run_kimi check --json >"$TMP/check-rg-tamper.json"
jq -e '
  .selected_backend == "none" and
  (.backends.native.reason | test("ripgrep digest mismatch"))
' "$TMP/check-rg-tamper.json" >/dev/null || fail "tampered rg was accepted"
run_kimi pin-rg --from "$TMP/bin/rg" --force >/dev/null

chmod 600 "$TMP/runtime/kimi-rg/current/dependencies.json"
printf '%s\n' '[{"path":"/tmp/not-real","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}]' \
  >"$TMP/runtime/kimi-rg/current/dependencies.json"
chmod 400 "$TMP/runtime/kimi-rg/current/dependencies.json"
run_kimi check --json >"$TMP/check-rg-dependencies-tamper.json"
jq -e '
  .selected_backend == "none" and
  (.backends.native.reason | test("dependency digest mismatch"))
' "$TMP/check-rg-dependencies-tamper.json" >/dev/null \
  || fail "tampered rg dependency manifest was accepted"
run_kimi pin-rg --from "$TMP/bin/rg" --force >/dev/null

DELEGATION_KIMI_PLATFORM=Linux run_kimi check --json >"$TMP/check-no-sandbox.json"
jq -e '
  .selected_backend == "none" and
  .backends.native.available == false and
  (.backends.native.reason | test("require macOS sandbox-exec"))
' "$TMP/check-no-sandbox.json" >/dev/null \
  || fail "unsupported platform was reported as available"

DELEGATION_KIMI_SANDBOX_BIN="$TMP/bin/missing-sandbox-exec" \
  run_kimi check --json >"$TMP/check-missing-sandbox.json"
jq -e '
  .selected_backend == "none" and
  .backends.native.available == false and
  (.backends.native.reason | test("require executable sandbox-exec"))
' "$TMP/check-missing-sandbox.json" >/dev/null \
  || fail "missing sandbox executable was reported as available"

DELEGATION_KIMI_SHLOCK_BIN="$TMP/bin/missing-shlock" \
  run_kimi check --json >"$TMP/check-missing-shlock.json"
jq -e '
  .selected_backend == "none" and
  .backends.native.available == false and
  (.backends.native.reason | test("require executable shlock"))
' "$TMP/check-missing-shlock.json" >/dev/null \
  || fail "missing shlock was reported as available"

rc=0
run_kimi run --lane scout --prompt-file "$TMP/prompt" \
  --output "$TMP/results/refused.txt" --workdir "$TMP/work" \
  >/dev/null 2>&1 || rc=$?
[ "$rc" = 78 ] || fail "provisional run without explicit flag returned $rc"

mkdir -p "$TMP/debug-public"
chmod 755 "$TMP/debug-public"
rc=0
run_kimi run --lane scout --allow-provisional --prompt-file "$TMP/prompt" \
  --output "$TMP/results/debug-public.txt" --workdir "$TMP/work" \
  --debug-dir "$TMP/debug-public" >/dev/null 2>&1 || rc=$?
[ "$rc" = 64 ] || fail "non-private debug directory returned $rc"

mkdir -p "$TMP/work/debug-private"
chmod 700 "$TMP/work/debug-private"
rc=0
run_kimi run --lane builder --allow-provisional --prompt-file "$TMP/prompt" \
  --output "$TMP/results/debug-in-worktree.txt" --workdir "$TMP/work" \
  --debug-dir "$TMP/work/debug-private" >/dev/null 2>&1 || rc=$?
[ "$rc" = 64 ] || fail "builder accepted debug directory inside worktree"

# Evaluation is a manifest-bound candidate-only harness, never an alternate
# spelling of a provisional production dispatch.
rc=0
run_kimi run --lane scout --allow-provisional --evaluation \
  --evaluation-manifest "$TMP/missing-manifest.json" --prompt-file "$TMP/prompt" \
  --output "$TMP/results/mutually-exclusive.txt" --workdir "$TMP/work" \
  >/dev/null 2>&1 || rc=$?
[ "$rc" = 64 ] || fail "evaluation plus allow-provisional returned $rc"

# Disabled lanes fail before manifest or runtime inspection.
rc=0
PATH="/usr/bin:/bin" KIMI_CODE_HOME="$TMP/missing-kimi-home" \
  "$ROOT/bin/delegation-kimi" run --lane judgement --evaluation \
  --evaluation-manifest "$TMP/missing-manifest.json" --prompt-file "$TMP/prompt" \
  --output "$TMP/results/judgement.txt" --workdir "$TMP/work" \
  >/dev/null 2>&1 || rc=$?
[ "$rc" = 78 ] || fail "disabled judgement evaluation returned $rc"

EVAL_HEAD="$(git -C "$ROOT" rev-parse HEAD)"
run_kimi run --lane policy-annotation --evaluation \
  --evaluation-manifest "$TMP/manifest.json" --prompt-file "$TMP/prompt" \
  --output "$TMP/results/evaluation.txt" --workdir "$TMP/work"
[ "$(cat "$TMP/results/evaluation.txt")" = PONG ] || fail "evaluation output mismatch"
jq -e '.lane == "policy-annotation" and .effort == "max"' \
  "$TMP/results/evaluation.txt.metrics.json" >/dev/null || fail "evaluation metrics mismatch"

# A successful policy-annotation evaluation publishes the runner-emitted
# receipt with exactly the bound fields, recomputed here independently.
jq -e --arg manifest_sha "$MANIFEST_SHA" \
  --arg prompt_sha "$(sha256 "$TMP/prompt")" \
  --arg source_commit "$EVAL_HEAD" \
  --arg runner_sha "$(sha256 "$ROOT/bin/delegation-kimi")" \
  --arg output_sha "$(sha256 "$TMP/results/evaluation.txt")" \
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
  "$TMP/results/evaluation.txt.metrics.json" >/dev/null \
  || fail "evaluation receipt mismatch"
jq -e --arg output_sha "$(sha256 "$TMP/results/evaluation.txt")" \
  --arg metrics_sha "$(sha256 "$TMP/results/evaluation.txt.metrics.json")" \
  --arg manifest_sha "$MANIFEST_SHA" \
  '(keys | sort) == ["evaluation_manifest_sha256","metrics_sha256",
    "raw_output_sha256","schema_version"] and
   .schema_version == "delegation_policy_annotation_publication_commit_v1" and
   .raw_output_sha256 == $output_sha and .metrics_sha256 == $metrics_sha and
   .evaluation_manifest_sha256 == $manifest_sha' \
  "$TMP/results/evaluation.txt.commit.json" >/dev/null \
  || fail "evaluation publication commit mismatch"

# ---- evaluation preflight: full validation, no provider dispatch, no artifacts ----
rc=0
run_kimi run --lane policy-annotation --evaluation \
  --evaluation-manifest "$TMP/manifest.json" --preflight-only \
  --prompt-file "$TMP/prompt" --output "$TMP/results/preflight.txt" \
  --workdir "$TMP/work" >"$TMP/results/preflight.stdout" \
  2>"$TMP/results/preflight.stderr" || rc=$?
[ "$rc" = 0 ] || fail "preflight returned $rc"
[ ! -s "$TMP/results/preflight.stderr" ] || fail "preflight wrote to stderr"
jq -e --arg manifest_sha "$MANIFEST_SHA" \
  --arg prompt_sha "$(sha256 "$TMP/prompt")" \
  --arg source_commit "$(git -C "$ROOT" rev-parse HEAD)" \
  --arg runner_sha "$(sha256 "$ROOT/bin/delegation-kimi")" \
  --arg contract_sha "$(sha256 "$ROOT/evaluation/test-fixtures/contract.txt")" \
  --arg output_schema_sha "$(sha256 "$ROOT/evaluation/test-fixtures/output-schema.json")" \
  '(keys | sort) ==
     ["backend","contract_sha256","effort","evaluation_manifest_sha256","lane",
      "model","output_schema_sha256","post_observation_retries","profile",
      "prompt_sha256","provider_attempts","provider_dispatch_started",
      "runner_sha256","runner_source_commit","schema_version","status"] and
   .schema_version == "delegation_policy_annotation_preflight_receipt_v1" and
   .status == "READY_NO_PROVIDER_CALL" and
   .profile == "kimi-k3" and .model == "kimi-code/k3" and
   .backend == "native" and .effort == "max" and
   .lane == "policy-annotation" and
   .evaluation_manifest_sha256 == $manifest_sha and
   .prompt_sha256 == $prompt_sha and
   .runner_source_commit == $source_commit and
   .runner_sha256 == $runner_sha and
   .contract_sha256 == $contract_sha and
   .output_schema_sha256 == $output_schema_sha and
   .provider_dispatch_started == false and
   .provider_attempts == 0 and .post_observation_retries == 0' \
  "$TMP/results/preflight.stdout" >/dev/null || fail "preflight receipt mismatch"
# Any dispatch would have run the fake CLI and published PONG plus artifacts.
[ ! -e "$TMP/results/preflight.txt" ] &&
  [ ! -e "$TMP/results/preflight.txt.metrics.json" ] &&
  [ ! -e "$TMP/results/preflight.txt.commit.json" ] &&
  [ ! -e "$TMP/results/preflight.txt.stderr" ] \
  || fail "preflight created a caller-visible artifact"
! grep -q PONG "$TMP/results/preflight.stdout" || fail "preflight ran the provider CLI"
[ ! -e "$TMP/kimi-home/.delegation-kit-oauth.lock" ] &&
  [ ! -L "$TMP/kimi-home/.delegation-kit-oauth.lock" ] \
  || fail "preflight touched the OAuth lock"

# --preflight-only is rejected for ordinary (non-evaluation) runs.
rc=0
run_kimi run --lane scout --allow-provisional --preflight-only \
  --prompt-file "$TMP/prompt" --output "$TMP/results/preflight-ordinary.txt" \
  --workdir "$TMP/work" >/dev/null 2>&1 || rc=$?
[ "$rc" = 64 ] || fail "--preflight-only without --evaluation returned $rc"
[ ! -e "$TMP/results/preflight-ordinary.txt" ] || fail "rejected preflight created output"

# Manifest validation failures stay failures before provider use.
rc=0
run_kimi run --lane policy-annotation --evaluation \
  --evaluation-manifest "$TMP/missing-manifest.json" --preflight-only \
  --prompt-file "$TMP/prompt" --output "$TMP/results/preflight-missing.txt" \
  --workdir "$TMP/work" >/dev/null 2>&1 || rc=$?
[ "$rc" = 78 ] || fail "preflight with missing manifest returned $rc"
[ ! -e "$TMP/results/preflight-missing.txt" ] &&
  [ ! -e "$TMP/results/preflight-missing.txt.stderr" ] \
  || fail "manifest failure created artifacts"

rc=0
run_kimi run --lane policy-annotation --evaluation \
  --evaluation-manifest "$TMP/manifest.json" --prompt-file "$TMP/prompt" \
  --output "$TMP/results/kimi-collision.txt" \
  --metrics "$TMP/results/kimi-collision.txt.commit.json" --workdir "$TMP/work" \
  >/dev/null 2>&1 || rc=$?
[ "$rc" = 64 ] || fail "metrics/commit collision returned $rc"
[ ! -e "$TMP/results/kimi-collision.txt" ] \
  && [ ! -e "$TMP/results/kimi-collision.txt.commit.json" ] \
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
  out="$TMP/results/kimi-publish-$phase.txt"
  case "$phase" in
    output) target="$out" ;;
    metrics) target="$out.metrics.json" ;;
    commit) target="$out.commit.json" ;;
  esac
  target="$(cd "$(dirname "$target")" && pwd -P)/$(basename "$target")"
  rc=0
  FAIL_MV_TARGET="$target" PATH="$TMP/mv-fail:$PATH" \
    run_kimi run --lane policy-annotation --evaluation \
    --evaluation-manifest "$TMP/manifest.json" --prompt-file "$TMP/prompt" \
    --output "$out" --workdir "$TMP/work" >/dev/null 2>&1 || rc=$?
  [ "$rc" = 70 ] || fail "$phase publication failure returned $rc"
  [ ! -e "$out" ] && [ ! -e "$out.metrics.json" ] && [ ! -e "$out.commit.json" ] \
    || fail "$phase publication failure left a published member"
done

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
HOME="$TMP/ambient-home" KIMI_CODE_HOME="$TMP/kimi-home" \
  TMPDIR="$TMP/runtime" DELEGATION_DATA_HOME="$TMP/runtime" \
  PATH="$TMP/bin-receipt-fail:$TMP/bin:$PATH" \
  DELEGATION_KIMI_PLATFORM=Darwin \
  DELEGATION_KIMI_SANDBOX_BIN="$TMP/bin/sandbox-exec" \
  DELEGATION_KIMI_SHLOCK_BIN="$TMP/bin/shlock" \
  LEAK_ME=secret ZAI_API_KEY=secret \
  "$ROOT/bin/delegation-kimi" run --lane policy-annotation --evaluation \
  --evaluation-manifest "$TMP/manifest.json" --prompt-file "$TMP/prompt" \
  --output "$TMP/results/receipt-fail.txt" --workdir "$TMP/work" \
  >/dev/null 2>&1 || rc=$?
[ "$rc" = 70 ] || fail "receipt merge failure returned $rc"
[ ! -e "$TMP/results/receipt-fail.txt" ] || fail "receipt failure published output"
[ ! -e "$TMP/results/receipt-fail.txt.metrics.json" ] \
  || fail "receipt failure published metrics"

printf '%s\n' 'TIMEOUT_EVALUATION' >"$TMP/timeout-prompt"
cp "$TMP/manifest.json" "$TMP/timeout-manifest.json"
jq --arg prompt_sha256 "$(sha256 "$TMP/timeout-prompt")" '.prompt_sha256 = $prompt_sha256' \
  "$TMP/timeout-manifest.json" >"$TMP/timeout-manifest.next"
mv "$TMP/timeout-manifest.next" "$TMP/timeout-manifest.json"
TIMEOUT_MANIFEST_SHA="$(sha256 "$TMP/timeout-manifest.json")"
jq --arg first "$MANIFEST_SHA" --arg second "$TIMEOUT_MANIFEST_SHA" '
  .profiles["kimi-k3"].lanes["policy-annotation"].evaluation_manifest_sha256 = [$first, $second]
' "$ROOT/config/routing-gates.json" >"$TMP/gates-timeout.json"
mv "$TMP/gates-timeout.json" "$ROOT/config/routing-gates.json"
jq --arg first "$MANIFEST_SHA" --arg second "$TIMEOUT_MANIFEST_SHA" '
  .lanes["policy-annotation"].backends.native.evaluation_manifest_sha256 = [$first, $second]
' "$ROOT/config/kimi-k3-routing.json" >"$TMP/kimi-routing-timeout.json"
mv "$TMP/kimi-routing-timeout.json" "$ROOT/config/kimi-k3-routing.json"
git -C "$ROOT" add config/routing-gates.json config/kimi-k3-routing.json
git -C "$ROOT" commit -qm 'allowlist timeout fixture'
rc=0
run_kimi run --lane policy-annotation --evaluation \
  --evaluation-manifest "$TMP/timeout-manifest.json" --prompt-file "$TMP/timeout-prompt" \
  --output "$TMP/results/timeout.txt" --workdir "$TMP/work" \
  >/dev/null 2>&1 || rc=$?
[ "$rc" = 75 ] || fail "evaluation timeout returned $rc"
[ ! -e "$TMP/results/timeout.txt" ] && [ ! -e "$TMP/results/timeout.txt.metrics.json" ] \
  || fail "evaluation timeout published output or metrics"
grep -qx 'delegation-kimi: evaluation_timeout' "$TMP/results/timeout.txt.stderr" \
  || fail "evaluation timeout stderr receipt mismatch"
jq -e '
  .schema == "delegation_kimi_error_v1" and
  .phase == "dispatch" and .reason == "evaluation_timeout" and
  .exit_code == 75 and .vendor_exit_code == 124
' "$TMP/results/timeout.txt.error.json" >/dev/null \
  || fail "evaluation timeout diagnostic mismatch"

printf '%s\n' 'TIMEOUT_OPERATIONAL' >"$TMP/operational-timeout-prompt"
rc=0
run_kimi run --lane scout --allow-provisional \
  --prompt-file "$TMP/operational-timeout-prompt" \
  --output "$TMP/results/operational-timeout.txt" --workdir "$TMP/work" \
  >/dev/null 2>&1 || rc=$?
[ "$rc" = 75 ] || fail "operational timeout returned $rc"
jq -e '
  .reason == "operational_timeout" and .exit_code == 75 and
  .vendor_exit_code == 124 and .phase == "dispatch"
' "$TMP/results/operational-timeout.txt.error.json" >/dev/null \
  || fail "operational timeout diagnostic mismatch"

for failure_case in \
  'AUTH_FAILURE|69|authentication_unavailable' \
  'ENTITLEMENT_FAILURE|69|entitlement_unavailable' \
  'QUOTA_FAILURE|69|quota_unavailable' \
  'OVERLOAD_FAILURE|75|provider_overloaded' \
  'SERVER_FAILURE|75|provider_temporary_failure' \
  'SANDBOX_FAILURE|70|sandbox_failure'
do
  IFS='|' read -r marker expected_rc expected_reason <<<"$failure_case"
  failure_name="$(printf '%s' "$marker" | tr '[:upper:]_' '[:lower:]-')"
  printf '%s\n' "$marker" >"$TMP/$failure_name-prompt"
  rc=0
  if [ "$marker" = AUTH_FAILURE ]; then
    run_kimi run --lane scout --allow-provisional \
      --prompt-file "$TMP/$failure_name-prompt" \
      --output "$TMP/results/$failure_name.txt" --workdir "$TMP/work" \
      --debug-dir "$TMP/debug" >/dev/null 2>&1 || rc=$?
  else
    run_kimi run --lane scout --allow-provisional \
      --prompt-file "$TMP/$failure_name-prompt" \
      --output "$TMP/results/$failure_name.txt" --workdir "$TMP/work" \
      >/dev/null 2>&1 || rc=$?
  fi
  [ "$rc" = "$expected_rc" ] || fail "$marker returned $rc"
  jq -e --arg reason "$expected_reason" --argjson exit_code "$expected_rc" '
    .schema == "delegation_kimi_error_v1" and .reason == $reason and
    .exit_code == $exit_code and
    .captured_bytes.vendor_stderr > 0 and
    .tool_policy.process_exec == {mode:"allowlist",allowed:["rg"],attested:true} and
    (.search_runtime.sha256 | test("^[0-9a-f]{64}$"))
  ' "$TMP/results/$failure_name.txt.error.json" >/dev/null \
    || fail "$marker diagnostic mismatch"
  [ "$(wc -l <"$TMP/results/$failure_name.txt.stderr" | tr -d ' ')" = 1 ] \
    || fail "$marker stderr receipt is not one line"
  ! grep -q 'VENDOR_SECRET' "$TMP/results/$failure_name.txt.stderr" \
    || fail "$marker leaked vendor stderr in receipt"
  ! grep -q 'VENDOR_SECRET' "$TMP/results/$failure_name.txt.error.json" \
    || fail "$marker leaked vendor stderr in diagnostic"
done

AUTH_DEBUG_PATH="$(jq -r '.debug_path' "$TMP/results/auth-failure.txt.error.json")"
[ -d "$AUTH_DEBUG_PATH" ] && [ "$(file_mode "$AUTH_DEBUG_PATH")" = 700 ] \
  || fail "private debug directory was not created with mode 700"
grep -q 'VENDOR_SECRET' "$AUTH_DEBUG_PATH/stderr" \
  || fail "raw vendor stderr was not preserved in private debug directory"
! grep -q 'DEBUG_BEARER_SECRET' "$AUTH_DEBUG_PATH/stderr" \
  || fail "private debug stderr retained a bearer token"
grep -Fq '[REDACTED]' "$AUTH_DEBUG_PATH/stderr" \
  || fail "private debug stderr did not mark token redaction"

printf '%s\n' 'EVENT_TEXT_FAILURE' >"$TMP/event-text-failure-prompt"
rc=0
run_kimi run --lane scout --allow-provisional \
  --prompt-file "$TMP/event-text-failure-prompt" \
  --output "$TMP/results/event-text-failure.txt" --workdir "$TMP/work" \
  >/dev/null 2>&1 || rc=$?
[ "$rc" = 70 ] || fail "model-controlled event text changed failure exit to $rc"
jq -e '.reason == "dispatch_unclassified"' \
  "$TMP/results/event-text-failure.txt.error.json" >/dev/null \
  || fail "model-controlled event text changed failure classification"

printf '%s\n' 'AUTH_AND_BROKEN_OAUTH' >"$TMP/auth-broken-oauth-prompt"
rc=0
run_kimi run --lane scout --allow-provisional \
  --prompt-file "$TMP/auth-broken-oauth-prompt" \
  --output "$TMP/results/auth-broken-oauth.txt" --workdir "$TMP/work" \
  >/dev/null 2>&1 || rc=$?
[ "$rc" = 69 ] || fail "OAuth sync masked authentication failure with $rc"
jq -e '
  .reason == "authentication_unavailable" and .oauth_sync == "failed"
' "$TMP/results/auth-broken-oauth.txt.error.json" >/dev/null \
  || fail "secondary OAuth sync status was not retained"

run_kimi run --lane scout --allow-provisional --prompt-file "$TMP/prompt" \
  --output "$TMP/results/scout.txt" --workdir "$TMP/work"
[ "$(cat "$TMP/results/scout.txt")" = PONG ] || fail "scout output mismatch"
jq -e '
  .runtime_cli_version == "user-build-a" and .effort == "max" and
  .lane == "scout" and .write_scope == "scratch" and
  .sandbox == "macos-sandbox-exec" and
  .process_exec == {mode:"allowlist",allowed:["rg"],attested:true} and
  .terminal == false and .web_tools == false and
  .subagents == false and .skills == false and
  .oauth_refresh_persistence == "serialized-atomic-sync"
' "$TMP/results/scout.txt.metrics.json" >/dev/null || fail "scout metrics mismatch"
# Ordinary (non-evaluation) runs never claim the evaluation receipt.
jq -e 'has("evaluation_receipt") | not' "$TMP/results/scout.txt.metrics.json" >/dev/null \
  || fail "non-evaluation run claimed an evaluation receipt"
[ ! -e "$TMP/results/scout.txt.commit.json" ] \
  || fail "non-evaluation run wrote an evaluation commit marker"

printf '%s\n' 'USE_GREP' >"$TMP/grep-prompt"
run_kimi run --lane scout --allow-provisional --prompt-file "$TMP/grep-prompt" \
  --output "$TMP/results/grep.txt" --workdir "$TMP/work"
[ "$(cat "$TMP/results/grep.txt")" = PONG ] \
  || fail "scout Grep run did not complete through pinned rg"

printf '%s\n' 'HEARTBEAT_WAIT' >"$TMP/heartbeat-prompt"
DELEGATION_KIMI_HEARTBEAT_SECONDS=1 \
  run_kimi run --lane scout --allow-provisional \
  --prompt-file "$TMP/heartbeat-prompt" \
  --output "$TMP/results/heartbeat.txt" --workdir "$TMP/work" \
  2>"$TMP/results/heartbeat.log"
grep -Eq '^delegation-kimi: heartbeat duration=[0-9]+s events=[0-9]+ last_tool=Grep$' \
  "$TMP/results/heartbeat.log" || fail "sanitized heartbeat was not emitted"
! grep -q 'hidden-content' "$TMP/results/heartbeat.log" \
  || fail "heartbeat leaked tool content"

# Kimi rotates its refresh token inside the isolated HOME. The parent runner
# must copy the validated result back atomically so the next invocation starts
# from the new token instead of forcing another login.
printf '%s\n' 'ROTATE_OAUTH' >"$TMP/rotate-oauth-prompt"
run_kimi run --lane scout --allow-provisional \
  --prompt-file "$TMP/rotate-oauth-prompt" \
  --output "$TMP/results/rotate-oauth.txt" --workdir "$TMP/work"
jq -e '
  .access_token == "rotated-access" and .refresh_token == "rotated-refresh"
' "$TMP/kimi-home/credentials/kimi-code.json" >/dev/null \
  || fail "rotated OAuth credential was not persisted"
[ "$(file_mode "$TMP/kimi-home/credentials/kimi-code.json")" = 600 ] \
  || fail "persisted OAuth credential mode is not 600"
[ ! -e "$TMP/kimi-home/.delegation-kit-oauth.lock" ] &&
  [ ! -L "$TMP/kimi-home/.delegation-kit-oauth.lock" ] \
  || fail "OAuth lock survived a successful run"

printf '%s\n' 'INTERRUPT_ROTATE_OAUTH' >"$TMP/interrupt-oauth-prompt"
grep -Fq 'trap handle_cancel INT TERM' "$ROOT/bin/delegation-kimi" \
  || fail "runner does not register the shared INT/TERM cancellation handler"
start_kimi_background run --lane scout --allow-provisional \
  --prompt-file "$TMP/interrupt-oauth-prompt" \
  --output "$TMP/results/interrupt-oauth.txt" --workdir "$TMP/work"
interrupt_runner_pid="$KIMI_BACKGROUND_PID"
interrupt_ready=0
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if [ -e "$TMP/interrupt-ready" ]; then interrupt_ready=1; break; fi
  /bin/sleep 1
done
[ "$interrupt_ready" = 1 ] || fail "interrupt fixture did not start"
kill -TERM "$interrupt_runner_pid"
rc=0
wait "$interrupt_runner_pid" || rc=$?
[ "$rc" = 130 ] || fail "caller cancellation returned $rc"
jq -e '
  .reason == "caller_cancelled" and .exit_code == 130 and
  .phase == "dispatch"
' "$TMP/results/interrupt-oauth.txt.error.json" >/dev/null \
  || fail "caller cancellation diagnostic mismatch"
jq -e '
  .access_token == "interrupt-access" and .refresh_token == "interrupt-refresh"
' "$TMP/kimi-home/credentials/kimi-code.json" >/dev/null \
  || fail "OAuth refresh was not synchronized after cancellation"
[ ! -e "$TMP/kimi-home/.delegation-kit-oauth.lock" ] \
  || fail "OAuth lock survived caller cancellation"

printf '%s\n' 'INTERRUPT_STUBBORN' >"$TMP/interrupt-stubborn-prompt"
start_kimi_background run --lane scout --allow-provisional \
  --prompt-file "$TMP/interrupt-stubborn-prompt" \
  --output "$TMP/results/interrupt-stubborn.txt" --workdir "$TMP/work"
stubborn_runner_pid="$KIMI_BACKGROUND_PID"
stubborn_ready=0
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if [ -e "$TMP/stubborn-ready" ]; then stubborn_ready=1; break; fi
  /bin/sleep 1
done
[ "$stubborn_ready" = 1 ] || fail "stubborn child fixture did not start"
kill -TERM "$stubborn_runner_pid"
rc=0
wait "$stubborn_runner_pid" || rc=$?
[ "$rc" = 130 ] || fail "stubborn child cancellation returned $rc"
[ ! -e "$TMP/kimi-home/.delegation-kit-oauth.lock" ] \
  || fail "OAuth lock was released before stubborn child reaping"
! ps -axo command | grep -F "$TMP/interrupt-stubborn-prompt" | grep -v grep >/dev/null \
  || fail "stubborn Kimi child survived runner cancellation"

printf '%s\n' 'REQUIRE_INTERRUPT_OAUTH' >"$TMP/require-interrupt-oauth-prompt"
run_kimi run --lane scout --allow-provisional \
  --prompt-file "$TMP/require-interrupt-oauth-prompt" \
  --output "$TMP/results/require-interrupt-oauth.txt" --workdir "$TMP/work"
[ "$(cat "$TMP/results/require-interrupt-oauth.txt")" = PONG ] \
  || fail "post-interrupt run did not reuse refreshed OAuth"

run_kimi run --lane scout --allow-provisional \
  --prompt-file "$TMP/rotate-oauth-prompt" \
  --output "$TMP/results/rotate-oauth-again.txt" --workdir "$TMP/work"

printf '%s\n' 'REQUIRE_ROTATED_OAUTH' >"$TMP/require-rotated-oauth-prompt"
run_kimi run --lane scout --allow-provisional \
  --prompt-file "$TMP/require-rotated-oauth-prompt" \
  --output "$TMP/results/require-rotated-oauth.txt" --workdir "$TMP/work"
[ "$(cat "$TMP/results/require-rotated-oauth.txt")" = PONG ] \
  || fail "the next run did not receive the rotated OAuth credential"

# A concurrent ambient `kimi login` is authoritative. Even if the isolated
# process also rotates its copy, optimistic concurrency must preserve the
# externally replaced credential.
printf '%s\n' 'CONCURRENT_LOGIN' >"$TMP/concurrent-login-prompt"
rc=0
run_kimi run --lane scout --allow-provisional \
  --prompt-file "$TMP/concurrent-login-prompt" \
  --output "$TMP/results/concurrent-login.txt" --workdir "$TMP/work" \
  >/dev/null 2>&1 || rc=$?
[ "$rc" = 75 ] || fail "concurrent external login returned $rc"
[ ! -e "$TMP/results/concurrent-login.txt" ] \
  || fail "concurrent external login published output"
jq -e '
  .access_token == "external-access" and .refresh_token == "external-refresh"
' "$TMP/kimi-home/credentials/kimi-code.json" >/dev/null \
  || fail "isolated OAuth sync overwrote a concurrent login"

# Never publish output or replace the ambient credential when the isolated CLI
# leaves malformed OAuth state behind.
cp "$TMP/kimi-home/credentials/kimi-code.json" "$TMP/oauth-before-corruption.json"
printf '%s\n' 'CORRUPT_OAUTH' >"$TMP/corrupt-oauth-prompt"
rc=0
run_kimi run --lane scout --allow-provisional \
  --prompt-file "$TMP/corrupt-oauth-prompt" \
  --output "$TMP/results/corrupt-oauth.txt" --workdir "$TMP/work" \
  >/dev/null 2>&1 || rc=$?
[ "$rc" = 70 ] || fail "malformed refreshed OAuth credential returned $rc"
[ ! -e "$TMP/results/corrupt-oauth.txt" ] \
  || fail "malformed OAuth state published output"
cmp -s "$TMP/oauth-before-corruption.json" "$TMP/kimi-home/credentials/kimi-code.json" \
  || fail "malformed OAuth state replaced the ambient credential"
[ ! -e "$TMP/kimi-home/.delegation-kit-oauth.lock" ] &&
  [ ! -L "$TMP/kimi-home/.delegation-kit-oauth.lock" ] \
  || fail "OAuth lock survived a failed run"

# A changed access token without a refresh token is also invalid persistence:
# accepting it would merely postpone the next forced login by a few minutes.
printf '%s\n' 'ACCESS_ONLY_OAUTH' >"$TMP/access-only-oauth-prompt"
rc=0
run_kimi run --lane scout --allow-provisional \
  --prompt-file "$TMP/access-only-oauth-prompt" \
  --output "$TMP/results/access-only-oauth.txt" --workdir "$TMP/work" \
  >/dev/null 2>&1 || rc=$?
[ "$rc" = 70 ] || fail "access-only refreshed OAuth credential returned $rc"
cmp -s "$TMP/oauth-before-corruption.json" "$TMP/kimi-home/credentials/kimi-code.json" \
  || fail "access-only OAuth state replaced the ambient credential"

# Active refresh owners fail temporarily instead of racing token rotation.
printf '%s\n' "$$" >"$TMP/kimi-home/.delegation-kit-oauth.lock"
rc=0
run_kimi run --lane scout --allow-provisional --prompt-file "$TMP/prompt" \
  --output "$TMP/results/active-lock.txt" --workdir "$TMP/work" \
  >/dev/null 2>&1 || rc=$?
[ "$rc" = 75 ] || fail "active OAuth lock returned $rc"
rm -f -- "$TMP/kimi-home/.delegation-kit-oauth.lock"

# A lock whose owner no longer exists is recovered automatically.
printf '%s\n' '2147483647' >"$TMP/kimi-home/.delegation-kit-oauth.lock"
run_kimi run --lane scout --allow-provisional --prompt-file "$TMP/prompt" \
  --output "$TMP/results/stale-lock.txt" --workdir "$TMP/work"
[ ! -e "$TMP/kimi-home/.delegation-kit-oauth.lock" ] &&
  [ ! -L "$TMP/kimi-home/.delegation-kit-oauth.lock" ] \
  || fail "stale OAuth lock was not recovered"

printf '%s\n' 'WRITE_BUILDER' >"$TMP/builder-prompt"
run_kimi run --lane builder --allow-provisional --prompt-file "$TMP/builder-prompt" \
  --output "$TMP/results/builder.txt" --workdir "$TMP/work"
[ "$(cat "$TMP/work/value.txt")" = after ] || fail "builder did not edit workdir"
jq -e '.lane == "builder" and .write_scope == "workdir"' \
  "$TMP/results/builder.txt.metrics.json" >/dev/null || fail "builder metrics mismatch"
grep -q 'param "WORKDIR"' "$TMP/sandbox.profile" \
  || fail "builder sandbox did not carry a workdir exception"

# A different user-installed CLI version is accepted when the behavioral
# capability probes still pass; the observed version remains provenance.
KIMI_FAKE_VERSION=user-build-b run_kimi run --lane scout --allow-provisional \
  --prompt-file "$TMP/prompt" --output "$TMP/results/alternate-version.txt" \
  --workdir "$TMP/work"
jq -e '.runtime_cli_version == "user-build-b"' \
  "$TMP/results/alternate-version.txt.metrics.json" >/dev/null \
  || fail "alternate CLI version was not recorded as provenance"

# Ambient user preference may be high; the runner must attest and use max from
# its isolated config instead of treating the ambient default as qualification.
KIMI_FAKE_DEFAULT_EFFORT=high run_kimi run --lane scout --allow-provisional \
  --prompt-file "$TMP/prompt" --output "$TMP/results/ambient-high.txt" \
  --workdir "$TMP/work"
jq -e '.effort == "max"' "$TMP/results/ambient-high.txt.metrics.json" >/dev/null \
  || fail "isolated max effort was weakened by ambient high preference"

rc=0
KIMI_FAKE_DEFAULT_EFFORT=high KIMI_FAKE_IGNORE_ISOLATED_EFFORT=1 \
  run_kimi run --lane scout --allow-provisional \
  --prompt-file "$TMP/prompt" --output "$TMP/results/effort.txt" \
  --workdir "$TMP/work" >/dev/null 2>&1 || rc=$?
[ "$rc" = 69 ] || fail "isolated default-effort mismatch returned $rc"

printf '%s\n' existing >"$TMP/results/existing.txt"
rc=0
run_kimi run --lane scout --allow-provisional --prompt-file "$TMP/prompt" \
  --output "$TMP/results/existing.txt" --workdir "$TMP/work" \
  >/dev/null 2>&1 || rc=$?
[ "$rc" = 64 ] || fail "existing output was accepted"
[ "$(cat "$TMP/results/existing.txt")" = existing ] \
  || fail "existing output was modified"

rc=0
run_kimi run --lane builder --allow-provisional --prompt-file "$TMP/prompt" \
  --output "$TMP/results/home.txt" --workdir "$TMP/ambient-home" \
  >/dev/null 2>&1 || rc=$?
[ "$rc" = 64 ] || fail "user-home workdir was accepted"

# On macOS, exercise the actual OS policy independently of the fake CLI.
if [ "$(command uname)" = Darwin ] && command -v sandbox-exec >/dev/null 2>&1; then
  policy='(version 1)
    (allow default)
    (deny process-exec
      (require-all
        (require-not (literal (param "KIMI_BIN")))
        (require-not (literal "/usr/bin/true"))
        (require-not (literal (param "RG_BIN")))))
    (deny file-read-data
      (require-all
        (subpath (param "REAL_HOME"))
        (require-not (subpath (param "WORKDIR")))
        (require-not (subpath (param "SCRATCH")))
        (require-not (literal (param "KIMI_BIN")))))
    (deny file-write*
      (require-all
        (require-not (subpath (param "SCRATCH")))
        (require-not (subpath (param "WORKDIR")))))
    (deny file-write* (subpath (param "RG_DIR")))'
  mkdir -p "$TMP/os-scratch" "$TMP/os-rg"
  cp "$(command -v rg)" "$TMP/os-rg/rg"
  chmod 500 "$TMP/os-rg/rg"
  sandbox-exec -D "SCRATCH=$TMP/os-scratch" -D "WORKDIR=$TMP/work" \
    -D "REAL_HOME=$TMP/ambient-home" -D "KIMI_BIN=/usr/bin/touch" \
    -D "RG_BIN=$TMP/os-rg/rg" -D "RG_DIR=$TMP/os-rg" \
    -p "$policy" /usr/bin/touch "$TMP/work/os-inside"
  [ -e "$TMP/work/os-inside" ] || fail "OS sandbox blocked workdir write"
  rc=0
  sandbox-exec -D "SCRATCH=$TMP/os-scratch" -D "WORKDIR=$TMP/work" \
    -D "REAL_HOME=$TMP/ambient-home" -D "KIMI_BIN=/usr/bin/touch" \
    -D "RG_BIN=$TMP/os-rg/rg" -D "RG_DIR=$TMP/os-rg" \
    -p "$policy" /usr/bin/touch "$TMP/os-outside" >/dev/null 2>&1 || rc=$?
  [ "$rc" != 0 ] && [ ! -e "$TMP/os-outside" ] \
    || fail "OS sandbox allowed out-of-workdir write"

  rc=0
  sandbox-exec -D "SCRATCH=$TMP/os-scratch" -D "WORKDIR=$TMP/work" \
    -D "REAL_HOME=$TMP/ambient-home" -D "KIMI_BIN=/bin/cat" \
    -D "RG_BIN=$TMP/os-rg/rg" -D "RG_DIR=$TMP/os-rg" \
    -p "$policy" /bin/cat "$TMP/ambient-home/secret.txt" \
    >/dev/null 2>&1 || rc=$?
  [ "$rc" != 0 ] || fail "OS sandbox allowed ambient-home data read"
  sandbox-exec -D "SCRATCH=$TMP/os-scratch" -D "WORKDIR=$TMP/work" \
    -D "REAL_HOME=$TMP/ambient-home" -D "KIMI_BIN=/bin/cat" \
    -D "RG_BIN=$TMP/os-rg/rg" -D "RG_DIR=$TMP/os-rg" \
    -p "$policy" /bin/cat "$TMP/work/value.txt" >/dev/null \
    || fail "OS sandbox blocked workdir data read"

  rc=0
  sandbox-exec -D "SCRATCH=$TMP/os-scratch" -D "WORKDIR=$TMP/work" \
    -D "REAL_HOME=$TMP/ambient-home" -D "KIMI_BIN=/usr/bin/true" \
    -D "RG_BIN=$TMP/os-rg/rg" -D "RG_DIR=$TMP/os-rg" \
    -p "$policy" /bin/bash -c '/usr/bin/id >/dev/null' \
    >/dev/null 2>&1 || rc=$?
  [ "$rc" != 0 ] || fail "OS sandbox allowed shell execution"

  sandbox-exec -D "SCRATCH=$TMP/os-scratch" -D "WORKDIR=$TMP/work" \
    -D "REAL_HOME=$TMP/ambient-home" -D "KIMI_BIN=/usr/bin/true" \
    -D "RG_BIN=$TMP/os-rg/rg" -D "RG_DIR=$TMP/os-rg" \
    -p "$policy" "$TMP/os-rg/rg" after "$TMP/work" >/dev/null \
    || fail "OS sandbox blocked pinned rg inside readable workdir"
  rc=0
  sandbox-exec -D "SCRATCH=$TMP/os-scratch" -D "WORKDIR=$TMP/work" \
    -D "REAL_HOME=$TMP/ambient-home" -D "KIMI_BIN=/usr/bin/touch" \
    -D "RG_BIN=$TMP/os-rg/rg" -D "RG_DIR=$TMP/os-rg" \
    -p "$policy" /usr/bin/touch "$TMP/os-rg/rg" >/dev/null 2>&1 || rc=$?
  [ "$rc" != 0 ] || fail "OS sandbox allowed mutation of attested rg"
  rc=0
  sandbox-exec -D "SCRATCH=$TMP/os-scratch" -D "WORKDIR=$TMP/work" \
    -D "REAL_HOME=$TMP/ambient-home" -D "KIMI_BIN=/usr/bin/true" \
    -D "RG_BIN=$TMP/os-rg/rg" -D "RG_DIR=$TMP/os-rg" \
    -p "$policy" "$TMP/os-rg/rg" secret "$TMP/ambient-home" \
    >/dev/null 2>&1 || rc=$?
  [ "$rc" != 0 ] || fail "OS sandbox allowed rg to read ambient HOME"
fi

printf 'Kimi runner tests passed.\n'
