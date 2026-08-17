#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/delegation-gemini-test.XXXXXX")"
trap 'rm -rf -- "$TMP"' EXIT
export HOME="$TMP/home"
# Run the whole suite as if it were launched over SSH, so the stub's marker
# assertion is exercised rather than passing for lack of anything to catch.
export SSH_CLIENT='203.0.113.7 51234 22' SSH_CONNECTION='203.0.113.7 51234 198.51.100.9 22' SSH_TTY=/dev/ttys999
mkdir -p "$TMP/bin" "$TMP/work" "$TMP/results" "$TMP/runtime" "$TMP/debug" "$HOME/Library/Keychains"
printf 'Respond with PONG.\n' >"$TMP/prompt"
cat >"$TMP/bin/agy" <<'EOF'
#!/usr/bin/env bash
# The real agy abandons the macOS Keychain for a file-based token store whenever
# it sees these markers, which would make a signed-in user look signed out. The
# runner must clear them before every call that can touch credentials.
no_ssh_markers() {
  [ -z "${SSH_CLIENT:-}${SSH_CONNECTION:-}${SSH_TTY:-}" ] && return 0
  printf 'SSH markers reached agy: client=%s connection=%s tty=%s\n' \
    "${SSH_CLIENT:-}" "${SSH_CONNECTION:-}" "${SSH_TTY:-}" >&2
  exit 90
}
if [ "${1:-}" = --help ]; then printf '%s\n' 'agy --print --model --effort --mode --sandbox --print-timeout'; exit 0; fi
if [ "${1:-}" = plugin ] && [ "${2:-}" = list ]; then no_ssh_markers; printf '%s\n' "${FAKE_AGY_PLUGINS:-No imported plugins.}"; exit 0; fi
if [ "${1:-}" = models ]; then
  no_ssh_markers
  printf '%s\n' ${FAKE_AGY_MODELS:-gemini-3.7-flash-medium}
  exit 0
fi
no_ssh_markers
case "${FAKE_AGY_CASE:-success}" in
 success)
   expected_model="${FAKE_EXPECT_MODEL:-gemini-3.7-flash-medium}"
   expected_effort="${FAKE_EXPECT_EFFORT:-medium}"
   case "$PWD" in */delegation-gemini.*/workspace) ;; *) printf 'unsafe cwd: %s\n' "$PWD" >&2; exit 91 ;; esac
   [[ " $* " = *" --model $expected_model "* ]] || exit 92
   [[ " $* " = *" --effort $expected_effort "* ]] || exit 93
   [[ " $* " = *" --mode plan "* ]] || exit 94
   [[ " $* " = *" --sandbox "* ]] || exit 95
   [[ " $* " != *" --dangerously-skip-permissions "* ]] || exit 96
   case "$HOME" in */delegation-gemini.*/home) ;; *) printf 'unsafe HOME: %s\n' "$HOME" >&2; exit 97 ;; esac
   jq -e '.permissions.allow == [] and
     (.permissions.deny | index("read_file(*)") != null) and
     (.permissions.deny | index("write_file(*)") != null) and
     (.permissions.deny | index("command(*)") != null) and
     (.permissions.deny | index("read_url(*)") != null) and
     (.permissions.deny | index("mcp(*)") != null)' \
     "$HOME/.gemini/antigravity-cli/settings.json" >/dev/null || exit 98
   printf 'PONG\n'
   ;;
 process_exit) printf 'SECRET_PAYLOAD\n' >&2; exit 42 ;; empty) : ;;
 permission) printf 'jetski: no output produced — a tool required the "read_file" permission and was auto-denied. SECRET_PAYLOAD\n' >&2 ;;
 auth) printf '401 Unauthorized SECRET_PAYLOAD\n' >&2; exit 1 ;; rate) printf '429 rate limit SECRET_PAYLOAD\n' >&2; exit 1 ;;
 *) exit 64 ;;
esac
EOF
chmod +x "$TMP/bin/agy"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
json() { jq -e "$2" "$1" >/dev/null || fail "$1 did not satisfy $2"; }
run() { local name="$1" expected="$2"; shift 2; local rc=0; PATH="$TMP/bin:$PATH" TMPDIR="$TMP/runtime" FAKE_AGY_CASE="$name" "$ROOT/bin/delegation-gemini" run --lane scout --effort auto --backend auto --evaluation --prompt-file "$TMP/prompt" --output "$TMP/results/$name.out" --workdir "$TMP/work" "$@" >"$TMP/results/$name.stdout" 2>"$TMP/results/$name.stderr" || rc=$?; [ "$rc" = "$expected" ] || fail "$name returned $rc, expected $expected"; }

# The test deliberately uses the checked-in gates; fake agy makes every probe local.
PATH="$TMP/bin:$PATH" "$ROOT/bin/delegation-gemini" check --json >"$TMP/check.json"
json "$TMP/check.json" '.model == "gemini-3.7-flash" and .backends.agy.available == true and .provisional_lanes == []'
run success 0
[ "$(cat "$TMP/results/success.out")" = PONG ] || fail 'success output mismatch'
json "$TMP/results/success.out.metrics.json" '.runtime_model == "gemini-3.7-flash-medium" and .context_mode == "prompt_only" and .workspace_mode == "isolated_empty" and .home_mode == "isolated_keychain_oauth" and .tokens == null and .provider_cost_usd == null'
[ ! -e "$TMP/results/success.out.error.json" ] || fail 'success left diagnostic'

FAKE_AGY_PLUGINS='example-plugin 1.0 enabled' PATH="$TMP/bin:$PATH" "$ROOT/bin/delegation-gemini" check --json >"$TMP/plugin-check.json"
json "$TMP/plugin-check.json" '.selected_backend == "none" and .backends.agy.available == false'

rc=0
FAKE_EXPECT_MODEL=gemini-3.7-flash-high FAKE_EXPECT_EFFORT=high FAKE_AGY_MODELS=gemini-3.7-flash-high \
  PATH="$TMP/bin:$PATH" TMPDIR="$TMP/runtime" "$ROOT/bin/delegation-gemini" run \
  --lane builder --effort auto --backend agy --evaluation --prompt-file "$TMP/prompt" \
  --output "$TMP/results/evaluation-builder.out" --workdir "$TMP/work" >/dev/null 2>&1 || rc=$?
[ "$rc" = 0 ] || fail "isolated builder evaluation returned $rc"
[ "$(cat "$TMP/results/evaluation-builder.out")" = PONG ] || fail 'builder evaluation output mismatch'
rc=0
PATH="$TMP/bin:$PATH" "$ROOT/bin/delegation-gemini" run --lane reviewer --evaluation \
  --prompt-file "$TMP/prompt" --output "$TMP/results/evaluation-reviewer.out" \
  --workdir "$TMP/work" >/dev/null 2>&1 || rc=$?
[ "$rc" = 78 ] || fail "disabled reviewer evaluation returned $rc"

rc=0; PATH="$TMP/bin:$PATH" "$ROOT/bin/delegation-gemini" run --lane scout --prompt-file "$TMP/prompt" --output "$TMP/results/refusal.out" --workdir "$TMP/work" >/dev/null 2>&1 || rc=$?
[ "$rc" = 78 ] || fail "candidate refusal returned $rc"
for case in process_exit empty permission auth rate; do
  case "$case" in
    process_exit|empty|permission) expected=70 ;;
    auth) expected=69 ;;
    rate) expected=75 ;;
  esac
  run "$case" "$expected"
done
for spec in 'process_exit process_exit dispatch 42' 'empty empty_output extract null' 'permission tool_permission_denied dispatch 0' 'auth authentication_failed dispatch 1' 'rate rate_limited dispatch 1'; do
  read -r name reason phase code <<EOF
$spec
EOF
  f="$TMP/results/$name.out.error.json"; [ -f "$f" ] || fail "$name diagnostic missing"; json "$f" ".reason == \"$reason\" and .phase == \"$phase\" and .cli_exit_code == $code"; ! grep -q SECRET_PAYLOAD "$f" || fail "$name diagnostic leaked raw content"
  [ ! -e "$TMP/results/$name.out" ] || fail "$name left partial output"
  [ ! -e "$TMP/results/$name.out.metrics.json" ] || fail "$name left partial metrics"
done
rm -f "$TMP/results/process_exit.out.error.json"
run process_exit 70 --debug-dir "$TMP/debug"
debug="$(find "$TMP/debug" -maxdepth 1 -type d -name 'delegation-gemini.*' | head -1)"; [ -n "$debug" ] || fail 'debug artifacts missing'
grep -q SECRET_PAYLOAD "$debug/stderr.txt" || fail 'debug raw stderr was not preserved'
[ -f "$debug/stdout.txt" ] && [ -f "$debug/stderr.txt" ] && [ -f "$debug/diagnostic.json" ] || fail 'debug files missing'
mode="$(stat -f '%Lp' "$debug" 2>/dev/null || stat -c '%a' "$debug")"; [ "$mode" = 700 ] || fail "debug dir mode $mode"
for f in "$debug"/*; do mode="$(stat -f '%Lp' "$f" 2>/dev/null || stat -c '%a' "$f")"; [ "$mode" = 600 ] || fail "debug file mode $mode"; done
mkdir "$TMP/outdir" "$TMP/metricsdir"
rc=0; PATH="$TMP/bin:$PATH" "$ROOT/bin/delegation-gemini" run --lane scout --evaluation --prompt-file "$TMP/prompt" --output "$TMP/outdir" --workdir "$TMP/work" >/dev/null 2>&1 || rc=$?; [ "$rc" = 64 ] || fail 'output directory accepted'
rc=0; PATH="$TMP/bin:$PATH" "$ROOT/bin/delegation-gemini" run --lane scout --evaluation --prompt-file "$TMP/prompt" --output "$TMP/results/metrics-dir.out" --metrics "$TMP/metricsdir" --workdir "$TMP/work" >/dev/null 2>&1 || rc=$?; [ "$rc" = 64 ] || fail 'metrics directory accepted'
rc=0; PATH="$TMP/bin:$PATH" "$ROOT/bin/delegation-gemini" run --lane scout --evaluation --prompt-file "$TMP/prompt" --output "$TMP/results/collision.out" --metrics "$TMP/results/collision.out" --workdir "$TMP/work" >/dev/null 2>&1 || rc=$?; [ "$rc" = 64 ] || fail 'collision accepted'
printf 'existing\n' >"$TMP/results/existing.out"
rc=0; PATH="$TMP/bin:$PATH" "$ROOT/bin/delegation-gemini" run --lane scout --evaluation --prompt-file "$TMP/prompt" --output "$TMP/results/existing.out" --workdir "$TMP/work" >/dev/null 2>&1 || rc=$?; [ "$rc" = 64 ] || fail 'existing output accepted'
ln -s "$TMP/results/success.out" "$TMP/results/symlink.out"
rc=0; PATH="$TMP/bin:$PATH" "$ROOT/bin/delegation-gemini" run --lane scout --evaluation --prompt-file "$TMP/prompt" --output "$TMP/results/symlink.out" --workdir "$TMP/work" >/dev/null 2>&1 || rc=$?; [ "$rc" = 64 ] || fail 'symlink output accepted'
[ -z "$(find "$TMP/runtime" -mindepth 1 -maxdepth 1 -name 'delegation-gemini.*' -print)" ] || fail 'temporary directories not cleaned'
printf 'Gemini runner diagnostics tests passed.\n'
