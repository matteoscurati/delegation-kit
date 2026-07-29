#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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
  "$TMP/kimi-home/credentials" "$TMP/ambient-home"
printf '%s\n' '{"access_token":"test-token","refresh_token":""}' \
  >"$TMP/kimi-home/credentials/kimi-code.json"
printf '%s\n' 'ambient secret' >"$TMP/ambient-home/secret.txt"
printf '%s\n' 'Respond with PONG.' >"$TMP/prompt"
printf '%s\n' 'before' >"$TMP/work/value.txt"

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
grep -q 'deny file-read-data' "$root/sandbox.profile"
grep -q 'deny file-write' "$root/sandbox.profile"
grep -q '^SCRATCH=' "$root/sandbox-defines.txt"
grep -q '^WORKDIR=' "$root/sandbox-defines.txt"
grep -q '^REAL_HOME=' "$root/sandbox-defines.txt"
grep -q '^KIMI_BIN=' "$root/sandbox-defines.txt"
exec "$@"
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
    printf '%s\n' '--prompt --model --output-format'
    exit 0
    ;;
  provider)
    [ "${2:-}" = list ] || exit 64
    if [ "${3:-}" = --json ]; then
      jq -n --arg effort "${KIMI_FAKE_DEFAULT_EFFORT:-max}" '
        {models:{"kimi-code/k3":{
          provider:"managed:kimi-code",model:"k3",
          supportEfforts:["low","high","max"],defaultEffort:$effort}}}
      '
    else
      printf '%s\n' 'managed:kimi-code source=oauth'
    fi
    exit 0
    ;;
esac

[ -z "${LEAK_ME:-}" ] || { printf 'environment leak\n' >&2; exit 91; }
[ -z "${ZAI_API_KEY:-}" ] || { printf 'credential leak\n' >&2; exit 92; }
[ "$SHELL" = /usr/bin/true ] || { printf 'unsafe shell\n' >&2; exit 93; }
config="$HOME/.kimi-code/config.toml"
grep -Fq 'default_model = "kimi-code/k3"' "$config" \
  || { printf 'model not pinned\n' >&2; exit 94; }
grep -Fq 'effort = "max"' "$config" \
  || { printf 'effort not pinned\n' >&2; exit 95; }
! grep -Eq '^\[\[hooks\]\]|^\[services\.' "$config" \
  || { printf 'ambient config leaked\n' >&2; exit 96; }

prompt=""
args=" $* "
[[ "$args" == *" --model kimi-code/k3 "* ]] \
  || { printf 'model argument missing\n' >&2; exit 97; }
[[ "$args" == *" --output-format stream-json "* ]] \
  || { printf 'output format missing\n' >&2; exit 98; }
while [ "$#" -gt 0 ]; do
  case "$1" in
    --prompt) prompt="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done
case "$prompt" in
  *WRITE_BUILDER*) printf 'after\n' >"$PWD/value.txt" ;;
esac
jq -nc '{role:"assistant",content:"PONG"}'
EOF
chmod 755 "$TMP/bin/uname" "$TMP/bin/sandbox-exec" "$TMP/bin/kimi"

run_kimi() {
  HOME="$TMP/ambient-home" KIMI_CODE_HOME="$TMP/kimi-home" \
    TMPDIR="$TMP/runtime" PATH="$TMP/bin:$PATH" \
    DELEGATION_KIMI_PLATFORM="${DELEGATION_KIMI_PLATFORM:-Darwin}" \
    DELEGATION_KIMI_SANDBOX_BIN="${DELEGATION_KIMI_SANDBOX_BIN:-$TMP/bin/sandbox-exec}" \
    LEAK_ME=secret ZAI_API_KEY=secret \
    "$ROOT/bin/delegation-kimi" "$@"
}

run_kimi check --json >"$TMP/check.json"
jq -e '
  .runtime_cli_version == "user-build-a" and
  .selected_backend == "native" and
  .backends.native.available == true and
  .backends.native.isolated_home == true and
  .backends.native.environment_mode == "allowlist" and
  .backends.native.ambient_home_read == false and
  .backends.native.process_exec == false and
  .backends.native.hooks == false and
  .backends.native.services == false and
  .backends.native.builder_write_scope == "workdir" and
  .backends.native.read_only_write_scope == "scratch"
' "$TMP/check.json" >/dev/null || fail "check contract mismatch"

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

rc=0
run_kimi run --lane scout --prompt-file "$TMP/prompt" \
  --output "$TMP/results/refused.txt" --workdir "$TMP/work" \
  >/dev/null 2>&1 || rc=$?
[ "$rc" = 78 ] || fail "provisional run without explicit flag returned $rc"

run_kimi run --lane scout --allow-provisional --prompt-file "$TMP/prompt" \
  --output "$TMP/results/scout.txt" --workdir "$TMP/work"
[ "$(cat "$TMP/results/scout.txt")" = PONG ] || fail "scout output mismatch"
jq -e '
  .runtime_cli_version == "user-build-a" and .effort == "max" and
  .lane == "scout" and .write_scope == "scratch" and
  .sandbox == "macos-sandbox-exec" and .process_exec == false
' "$TMP/results/scout.txt.metrics.json" >/dev/null || fail "scout metrics mismatch"

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

rc=0
KIMI_FAKE_DEFAULT_EFFORT=high run_kimi run --lane scout --allow-provisional \
  --prompt-file "$TMP/prompt" --output "$TMP/results/effort.txt" \
  --workdir "$TMP/work" >/dev/null 2>&1 || rc=$?
[ "$rc" = 69 ] || fail "default-effort mismatch returned $rc"

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
        (require-not (literal "/usr/bin/true"))))
    (deny file-read-data
      (require-all
        (subpath (param "REAL_HOME"))
        (require-not (subpath (param "WORKDIR")))
        (require-not (subpath (param "SCRATCH")))
        (require-not (literal (param "KIMI_BIN")))))
    (deny file-write*
      (require-all
        (require-not (subpath (param "SCRATCH")))
        (require-not (subpath (param "WORKDIR")))))'
  mkdir -p "$TMP/os-scratch"
  sandbox-exec -D "SCRATCH=$TMP/os-scratch" -D "WORKDIR=$TMP/work" \
    -D "REAL_HOME=$TMP/ambient-home" -D "KIMI_BIN=/usr/bin/touch" \
    -p "$policy" /usr/bin/touch "$TMP/work/os-inside"
  [ -e "$TMP/work/os-inside" ] || fail "OS sandbox blocked workdir write"
  rc=0
  sandbox-exec -D "SCRATCH=$TMP/os-scratch" -D "WORKDIR=$TMP/work" \
    -D "REAL_HOME=$TMP/ambient-home" -D "KIMI_BIN=/usr/bin/touch" \
    -p "$policy" /usr/bin/touch "$TMP/os-outside" >/dev/null 2>&1 || rc=$?
  [ "$rc" != 0 ] && [ ! -e "$TMP/os-outside" ] \
    || fail "OS sandbox allowed out-of-workdir write"

  rc=0
  sandbox-exec -D "SCRATCH=$TMP/os-scratch" -D "WORKDIR=$TMP/work" \
    -D "REAL_HOME=$TMP/ambient-home" -D "KIMI_BIN=/bin/cat" \
    -p "$policy" /bin/cat "$TMP/ambient-home/secret.txt" \
    >/dev/null 2>&1 || rc=$?
  [ "$rc" != 0 ] || fail "OS sandbox allowed ambient-home data read"
  sandbox-exec -D "SCRATCH=$TMP/os-scratch" -D "WORKDIR=$TMP/work" \
    -D "REAL_HOME=$TMP/ambient-home" -D "KIMI_BIN=/bin/cat" \
    -p "$policy" /bin/cat "$TMP/work/value.txt" >/dev/null \
    || fail "OS sandbox blocked workdir data read"

  rc=0
  sandbox-exec -D "SCRATCH=$TMP/os-scratch" -D "WORKDIR=$TMP/work" \
    -D "REAL_HOME=$TMP/ambient-home" -D "KIMI_BIN=/bin/bash" \
    -p "$policy" /bin/bash -c '/usr/bin/id >/dev/null' \
    >/dev/null 2>&1 || rc=$?
  [ "$rc" != 0 ] || fail "OS sandbox allowed arbitrary child execution"
fi

printf 'Kimi runner tests passed.\n'
