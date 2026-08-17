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
GROK_TEST_HOME="$TMP/grok-home"
TEST_TOOLS="$TMP/test-tools"

# Keep doctor checks hermetic. A broken or stale user-global Claude binary must
# not hang this installer fixture or cause it to inspect a global GLM runner.
mkdir -p "$TEST_TOOLS"
cat >"$TEST_TOOLS/claude" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  --version) printf 'claude test-build\n' ;;
  --help) printf '%s\n' '--effort' ;;
  auth) [ "${2:-}" = status ] ;;
  *) exit 2 ;;
esac
EOF
chmod 700 "$TEST_TOOLS/claude"

# Seed an upgrade-shaped install: stale Grok 4.5 and GLM 5.2/high gates plus a
# digest-valid Grok archive. The installer must remove the stale gates and
# recognize the retained archive only after current routing files exist.
mkdir -p "$DATA/config" "$DATA/grok-cli/current" "$GROK_TEST_HOME"
printf '%s\n' '{}' >"$GROK_TEST_HOME/auth.json"
printf '%s\n' '{}' >"$DATA/config/grok-4.5-routing.json"
printf '%s\n' '{}' >"$DATA/config/glm-5.2-routing.json"
printf '%s\n' '{}' >"$DATA/config/glm-5.3-high-routing.json"
printf '%s\n' '{}' >"$DATA/config/gemini-3.6-flash-routing.json"
cat >"$DATA/grok-cli/current/grok" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  --version) printf 'grok test-build\n' ;;
  models) printf 'You are logged in with grok.com.\n  * grok-4.6 (default)\n' ;;
  inspect)
    case " $* " in
      *' --help '*) printf '%s\n' '--json' ;;
      *) printf '%s\n' '{"sources":[],"compatibilityImports":[],"plugins":[],"mcpServers":[],"permissions":{"sources":[]},"hooks":[]}' ;;
    esac
    ;;
  *) printf '%s\n' '  models' '  inspect' ;;
esac
EOF
chmod 700 "$DATA/grok-cli/current/grok"
if command -v shasum >/dev/null 2>&1; then
  archive_sha="$(shasum -a 256 "$DATA/grok-cli/current/grok" | awk '{print $1}')"
else
  archive_sha="$(sha256sum "$DATA/grok-cli/current/grok" | awk '{print $1}')"
fi
printf '%s  grok\n' "$archive_sha" >"$DATA/grok-cli/current/grok.sha256"

# Install into fully isolated homes; never touch the real ones.
env CLAUDE_HOME="$TMP/claude" CODEX_HOME="$TMP/codex" \
    DELEGATION_BIN_HOME="$TMP/bin" DELEGATION_DATA_HOME="$DATA" \
    DELEGATION_GROK_HOME="$GROK_TEST_HOME" \
    "$ROOT/install.sh" </dev/null >"$TMP/install.log" 2>&1 \
  || { sed 's/^/    /' "$TMP/install.log" >&2; fail 'install.sh exited non-zero'; }

[ ! -e "$DATA/config/grok-4.5-routing.json" ] \
  || fail 'upgrade retained the stale Grok 4.5 gate'
[ -f "$DATA/config/grok-4.6-routing.json" ] \
  || fail 'upgrade did not install the Grok 4.6 gate'
[ ! -e "$DATA/config/glm-5.2-routing.json" ] \
  || fail 'upgrade retained the stale GLM 5.2 gate'
[ ! -e "$DATA/config/glm-5.3-high-routing.json" ] \
  || fail 'upgrade retained the stale GLM 5.3/high gate'
[ -f "$DATA/config/glm-5.3-max-routing.json" ] \
  || fail 'upgrade did not install the GLM 5.3/max gate'
[ ! -e "$DATA/config/gemini-3.6-flash-routing.json" ] \
  || fail 'upgrade retained the stale Gemini 3.6 gate'
[ -f "$DATA/config/gemini-3.7-flash-routing.json" ] \
  || fail 'upgrade did not install the Gemini 3.7 gate'
[ -f "$DATA/config/deepseek-v4-pro-routing.json" ] && [ -x "$DATA/bin/delegation-deepseek" ] \
  || fail 'install did not include the DeepSeek V4 Pro gate and runner'
[ -f "$TMP/claude/skills/deepseek-executor/SKILL.md" ] && [ -f "$TMP/codex/skills/deepseek-executor/SKILL.md" ] \
  || fail 'install did not include the DeepSeek executor skill on both surfaces'
grep -q 'existing compatible Grok Build CLI archive retained' "$TMP/install.log" \
  || { sed 's/^/    /' "$TMP/install.log" >&2; fail 'upgrade falsely warned that the compatible Grok archive was unavailable'; }
ok

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
    DELEGATION_GROK_HOME="$GROK_TEST_HOME" \
    "$ROOT/install.sh" --claude-only </dev/null >"$TMP/install2.log" 2>&1 \
  || { sed 's/^/    /' "$TMP/install2.log" >&2; fail '--claude-only install failed'; }
[ "$(jq -r '.scope' "$TMP/data2/installed-version.json")" = "claude-only" ] \
  || fail 'a --claude-only install did not record a claude-only scope'
ok

doctor_section() { # runs doctor against $1 as DATA_HOME, prints its version block
  # doctor exits non-zero whenever it reports a FAIL, which is precisely what
  # the drift cases below assert — so its status must not abort this script.
  env PATH="$TMP/bin:$TEST_TOOLS:$PATH" DELEGATION_DATA_HOME="$1" \
    CLAUDE_HOME="$TMP/claude" CODEX_HOME="$TMP/codex" \
    DELEGATION_DOCTOR_PROBE_TIMEOUT_SECONDS=1 \
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
