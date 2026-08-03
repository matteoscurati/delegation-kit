#!/usr/bin/env bash
# Run every regression suite, in parallel by default.
#
# The suites are independent — each builds its own mktemp workspace and none
# writes into this checkout — so running them concurrently on one machine cuts
# wall clock roughly threefold without allocating a second runner.
#
# Usage:
#   ./run-tests.sh              all suites in parallel
#   ./run-tests.sh --sequential one at a time, interleaved output (for debugging)
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT" || exit 1

mode=parallel
case "${1:-}" in
  --sequential) mode=sequential ;;
  -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  "") ;;
  *) printf 'unknown argument: %s\n' "$1" >&2; exit 64 ;;
esac

suites=(tests/*.sh)
[ "${#suites[@]}" -gt 0 ] || { printf 'no suites found under tests/\n' >&2; exit 1; }

LOGS="$(mktemp -d "${TMPDIR:-/tmp}/delegation-test-logs.XXXXXX")"
trap 'rm -rf -- "$LOGS"' EXIT
start="$(date +%s)"

if [ "$mode" = sequential ]; then
  for t in "${suites[@]}"; do
    printf '\n===== %s =====\n' "$t"
    bash "$t" 2>&1 | tee "$LOGS/$(basename "$t" .sh).log"
    printf '%s\n' "${PIPESTATUS[0]}" >"$LOGS/$(basename "$t" .sh).rc"
  done
else
  pids=""
  for t in "${suites[@]}"; do
    b="$(basename "$t" .sh)"
    ( bash "$t" >"$LOGS/$b.log" 2>&1; printf '%s\n' "$?" >"$LOGS/$b.rc" ) &
    pids="$pids $!"
  done
  # bash 3.2 on macOS has no `wait -n`; waiting on each pid is portable and the
  # slowest suite bounds the total either way.
  for p in $pids; do wait "$p"; done
fi

elapsed=$(( $(date +%s) - start ))
rc=0
failed=""
for t in "${suites[@]}"; do
  b="$(basename "$t" .sh)"
  r="$(cat "$LOGS/$b.rc" 2>/dev/null || echo 1)"
  if [ "$r" = 0 ]; then
    printf '  ok   %-34s %s\n' "$b" "$(tail -1 "$LOGS/$b.log" 2>/dev/null)"
  else
    printf '  FAIL %-34s rc=%s\n' "$b" "$r"
    failed="$failed $b"
    rc=1
  fi
done

# Print the full log of anything that failed; a parallel run interleaves output,
# so the per-suite log is the only readable record.
for b in $failed; do
  printf '\n===== %s (failed) =====\n' "$b"
  sed 's/^/  /' "$LOGS/$b.log"
done

printf '\n%s suites, %ss wall clock (%s)\n' "${#suites[@]}" "$elapsed" "$mode"
exit "$rc"
