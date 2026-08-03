#!/usr/bin/env bash
# Prove that an install records what it installed, and that doctor.sh notices
# when the installed tree falls behind the checkout.
#
# Without the marker a stale install is invisible: every other doctor check
# inspects the installed copy against itself and passes while it lags the repo.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/delegation-install-marker.XXXXXX")"
trap 'rm -rf -- "$TMP"' EXIT

command -v jq >/dev/null 2>&1 || { printf 'jq is required\n' >&2; exit 69; }

pass=0
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
ok() { pass=$((pass + 1)); }
DATA="$TMP/data"
MARKER="$DATA/installed-version.json"

# Install into fully isolated homes; never touch the real ones.
env CLAUDE_HOME="$TMP/claude" CODEX_HOME="$TMP/codex" \
    DELEGATION_BIN_HOME="$TMP/bin" DELEGATION_DATA_HOME="$DATA" \
    "$ROOT/install.sh" </dev/null >"$TMP/install.log" 2>&1 \
  || { sed 's/^/    /' "$TMP/install.log" >&2; fail 'install.sh exited non-zero'; }

[ -f "$MARKER" ] || fail "install.sh wrote no marker at $MARKER"
ok
jq -e . "$MARKER" >/dev/null 2>&1 || fail 'marker is not valid JSON'
ok

expected_version="$(jq -r '.version' "$ROOT/.claude-plugin/plugin.json")"
[ "$(jq -r '.version' "$MARKER")" = "$expected_version" ] \
  || fail "marker version is $(jq -r '.version' "$MARKER"), expected $expected_version"
ok
[ "$(jq -r '.schema_version' "$MARKER")" = 1 ] || fail 'marker schema_version is not 1'
ok
[ "$(jq -r '.scope' "$MARKER")" = "claude+codex" ] \
  || fail "marker scope is $(jq -r '.scope' "$MARKER")"
ok
jq -e '.installed_at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")' \
  "$MARKER" >/dev/null || fail 'marker installed_at is not an ISO-8601 UTC stamp'
ok

if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  [ "$(jq -r '.commit' "$MARKER")" = "$(git -C "$ROOT" rev-parse HEAD)" ] \
    || fail 'marker commit does not match the checkout HEAD'
  ok
  # A dirty checkout must be recorded: the commit alone would misdescribe it.
  want_dirty=false
  [ -z "$(git -C "$ROOT" status --porcelain)" ] || want_dirty=true
  [ "$(jq -r '.commit_dirty' "$MARKER")" = "$want_dirty" ] \
    || fail "marker commit_dirty is not $want_dirty"
  ok
fi

# A partial install must say so rather than claim a full one.
env CLAUDE_HOME="$TMP/claude2" CODEX_HOME="$TMP/codex2" \
    DELEGATION_BIN_HOME="$TMP/bin2" DELEGATION_DATA_HOME="$TMP/data2" \
    "$ROOT/install.sh" --claude-only </dev/null >"$TMP/install2.log" 2>&1 \
  || { sed 's/^/    /' "$TMP/install2.log" >&2; fail '--claude-only install failed'; }
[ "$(jq -r '.scope' "$TMP/data2/installed-version.json")" = "claude-only" ] \
  || fail 'a --claude-only install did not record a claude-only scope'
ok

doctor_section() { # runs doctor against $1 as DATA_HOME, prints its version block
  # doctor exits non-zero whenever it reports a FAIL, which is precisely what
  # the drift cases below assert — so its status must not abort this script.
  env DELEGATION_DATA_HOME="$1" CLAUDE_HOME="$TMP/claude" CODEX_HOME="$TMP/codex" \
    "$ROOT/doctor.sh" 2>&1 | awk '/^== Installed version ==/{f=1;next} /^== /{f=0} f' \
    || true
}

# In sync: doctor confirms both version and commit.
sec="$(doctor_section "$DATA")"
printf '%s' "$sec" | grep -q "installed version $expected_version matches" \
  || { printf '%s\n' "$sec" >&2; fail 'doctor did not confirm a matching version'; }
ok

# Version drift: doctor must FAIL, not merely mention it.
jq '.version = "0.0.1"' "$MARKER" >"$TMP/m" && mv "$TMP/m" "$MARKER"
sec="$(doctor_section "$DATA")"
printf '%s' "$sec" | grep -q "\[FAIL\].*installed 0.0.1 but this checkout is $expected_version" \
  || { printf '%s\n' "$sec" >&2; fail 'doctor did not fail on a stale installed version'; }
ok

# Commit drift at the same version: a warning, since unreleased work is normal.
jq --arg v "$expected_version" \
  '.version = $v | .commit = "0000000000000000000000000000000000000000"' \
  "$MARKER" >"$TMP/m" && mv "$TMP/m" "$MARKER"
sec="$(doctor_section "$DATA")"
if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  printf '%s' "$sec" | grep -q "\[WARN\].*installed from commit 00000000" \
    || { printf '%s\n' "$sec" >&2; fail 'doctor did not warn on a stale installed commit'; }
  ok
fi

# Missing marker on an otherwise-populated tree: warn and tell the user the fix.
rm -f "$MARKER"
sec="$(doctor_section "$DATA")"
printf '%s' "$sec" | grep -q "\[WARN\].*no version marker" \
  || { printf '%s\n' "$sec" >&2; fail 'doctor did not warn about a missing marker'; }
ok

# Not installed at all is a failure, not a warning.
sec="$(doctor_section "$TMP/nowhere")"
printf '%s' "$sec" | grep -q "\[FAIL\].*not installed" \
  || { printf '%s\n' "$sec" >&2; fail 'doctor did not fail when the kit is absent'; }
ok

printf 'install version marker tests: %s passed\n' "$pass"
