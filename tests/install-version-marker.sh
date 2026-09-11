#!/usr/bin/env bash
# Prove that an install records what it installed, and that doctor.sh notices
# when the installed tree falls behind the checkout.
#
# Without the marker a stale install is invisible: every other doctor check
# inspects the installed copy against itself and passes while it lags the repo.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Keep the Grok runtime-socket probe off the real filesystem: a Docker Desktop
# symlink on the developer machine must not change what install reports.
export DELEGATION_GROK_RUNTIME_SOCKET_ENDPOINTS=""
TMP="$(mktemp -d "${TMPDIR:-/tmp}/delegation-install-marker.XXXXXX")"
export DELEGATION_CONFIG_FILE="$TMP/user-config/config.json"
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

# Seed an upgrade-shaped install: the routing gates, executor contract,
# evidence snapshot, and retired commands a 0.24.0 install left behind, plus a
# digest-valid Grok archive. The installer must remove every retired file and
# recognize the retained archive.
mkdir -p "$DATA/config" "$DATA/bin" "$DATA/grok-cli/current" "$GROK_TEST_HOME" "$TMP/bin"
printf '%s\n' '{}' >"$GROK_TEST_HOME/auth.json"
# A key file the uninstaller backed up next to the data home must come back
# when the data home has none; an existing key file is never replaced.
( umask 077; printf 'ZAI_API_KEY=restored-from-backup\n' >"$DATA.zai.env.bak" )
( umask 077; printf 'DEEPSEEK_API_KEY=stale-backup\n' >"$DATA.deepseek.env.bak" )
( umask 077; printf 'DEEPSEEK_API_KEY=current\n' >"$DATA/config/deepseek.env" )
for retired_config in routing-gates.json grok-4.6-routing.json glm-5.3-flash-max-routing.json \
    kimi-k3-routing.json gemini-3.8-flash-routing.json qwen3.8-max-routing.json \
    deepseek-flash-routing.json external-executor-contract.json model-evidence.json; do
  printf '%s\n' '{}' >"$DATA/config/$retired_config"
done
for retired_command in delegation-schema delegation-evidence delegation-epoch delegation-executor-contract; do
  printf '#!/bin/sh\nexit 0\n' >"$DATA/bin/$retired_command"
  chmod 755 "$DATA/bin/$retired_command"
  ln -sfn "$DATA/bin/$retired_command" "$TMP/bin/$retired_command"
done
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

# Seed one retired profile and stale copies of the reviewer profiles. The
# installer must remove the retired name and overwrite both reviewers.
mkdir -p "$TMP/claude/agents" "$TMP/codex/agents"
printf '%s\n' stale >"$TMP/claude/agents/sonnet-builder.md"
printf '%s\n' stale >"$TMP/claude/agents/opus-reviewer.md"
printf '%s\n' stale >"$TMP/codex/agents/terra-scout.toml"
printf '%s\n' stale >"$TMP/codex/terra-scout.config.toml"
printf '%s\n' stale >"$TMP/codex/agents/terra-reviewer.toml"
printf '%s\n' stale >"$TMP/codex/terra-reviewer.config.toml"

# Install into fully isolated homes; never touch the real ones.
env CLAUDE_HOME="$TMP/claude" CODEX_HOME="$TMP/codex" \
    DELEGATION_BIN_HOME="$TMP/bin" DELEGATION_DATA_HOME="$DATA" \
    DELEGATION_GROK_HOME="$GROK_TEST_HOME" \
    "$ROOT/install.sh" </dev/null >"$TMP/install.log" 2>&1 \
  || { sed 's/^/    /' "$TMP/install.log" >&2; fail 'install.sh exited non-zero'; }

for retired_config in routing-gates.json grok-4.6-routing.json glm-5.3-flash-max-routing.json \
    kimi-k3-routing.json gemini-3.8-flash-routing.json qwen3.8-max-routing.json \
    deepseek-flash-routing.json external-executor-contract.json model-evidence.json; do
  [ ! -e "$DATA/config/$retired_config" ] || fail "upgrade retained the retired $retired_config"
done
for retired_command in delegation-schema delegation-evidence delegation-epoch delegation-executor-contract; do
  [ ! -e "$DATA/bin/$retired_command" ] && [ ! -e "$TMP/bin/$retired_command" ] && [ ! -L "$TMP/bin/$retired_command" ] \
    || fail "upgrade retained the retired command $retired_command"
done
[ "$(find "$DATA/config" -maxdepth 1 -name '*.json' | sort | xargs -n1 basename)" = external-patch-policy.json ] \
  || fail "install left unexpected JSON files in $DATA/config: $(ls "$DATA/config")"
[ -x "$DATA/bin/delegation-deepseek" ] || fail 'install did not include the DeepSeek runner'
[ "$(cat "$DATA/config/zai.env")" = 'ZAI_API_KEY=restored-from-backup' ] \
  || fail 'install did not restore the Z.AI key from the uninstaller backup'
[ "$(stat -f '%Lp' "$DATA/config/zai.env" 2>/dev/null || stat -c '%a' "$DATA/config/zai.env")" = 600 ] \
  || fail 'restored Z.AI key file is not mode 600'
[ "$(cat "$DATA/config/deepseek.env")" = 'DEEPSEEK_API_KEY=current' ] \
  || fail 'install replaced an existing DeepSeek key with the backup'
grep -Fq 'zai key restored from' "$TMP/install.log" || fail 'install did not report the restored key'
# The runners source the shared library from the installed tree, so it must be
# present and an installed runner must run through its PATH symlink.
[ -f "$DATA/bin/lib/delegation-runner-common.sh" ] && [ -f "$DATA/bin/lib/delegation-chat-completions.sh" ] \
  || fail 'install did not include the shared runner library'
[ ! -e "$TMP/bin/lib" ] || fail 'install linked the shared runner library onto the bin path'
"$TMP/bin/delegation-deepseek" check --json >"$TMP/deepseek-check.json" 2>"$TMP/deepseek-check.err" \
  || { sed 's/^/    /' "$TMP/deepseek-check.err" >&2; fail 'the installed DeepSeek runner could not source the shared library'; }
jq -e '.model == "deepseek-flash" and .adapter == "deepseek-api" and (.roles | index("builder") != null)' "$TMP/deepseek-check.json" >/dev/null \
  || fail 'the installed DeepSeek runner reported the wrong model or adapter contract'
# The personal-configuration commands ship with the kit and the installer
# initializes the configuration file (isolated here via DELEGATION_CONFIG_FILE).
for command in delegation-config delegation-run delegation-openai-compatible; do
  [ -L "$TMP/bin/$command" ] && [ -x "$DATA/bin/$command" ] \
    || fail "install did not link $command onto the bin path"
done
[ -f "$DATA/bin/lib/delegation_config.py" ] || fail 'install did not include delegation_config.py'
[ -f "$DELEGATION_CONFIG_FILE" ] || fail 'install did not initialize the personal configuration'
jq -e '.schema_version == 1 and .review_policy == "optional" and (.profiles | length) > 0' "$DELEGATION_CONFIG_FILE" >/dev/null \
  || fail 'the initialized personal configuration is not the optional-review preset'
[ -f "$(dirname "$DELEGATION_CONFIG_FILE")/managed/profiles.json" ] \
  || fail 'install did not generate the managed host snippets'
# The text-patch trust boundary: the verifier and the versioned policy it
# enforces are installed together.
[ -f "$DATA/config/external-patch-policy.json" ] && [ -x "$DATA/bin/delegation-patch-verify" ] \
  || fail 'install did not include the external patch policy and its verifier'
[ -L "$TMP/bin/delegation-patch-verify" ] \
  || fail 'install did not link delegation-patch-verify onto the bin path'
"$DATA/bin/delegation-patch-verify" policy --json >"$TMP/patch-policy.json" 2>"$TMP/patch-policy.err" \
  || { sed 's/^/    /' "$TMP/patch-policy.err" >&2; fail 'the installed patch verifier could not read its policy'; }
jq -e '.schema_version == 1 and .verifier == "delegation-patch-verify" and
       .applies_to_permission_class == "text-patch" and
       .authority.applies_patch == false and .authority.writes_worktree == false and
       .authority.grants_permissions == false and .authority.applied_by == "lead" and
       .operations.delete == "denied-by-default" and .operations.rename == "denied" and
       .file_modes.mode_change_denied == true and
       (.git_apply.never_passed | index("--unsafe-paths")) != null' \
  "$TMP/patch-policy.json" >/dev/null \
  || fail 'the installed patch policy is not the fail-closed policy this kit ships'
[ -f "$TMP/claude/skills/deepseek-executor/SKILL.md" ] && [ -f "$TMP/codex/skills/deepseek-executor/SKILL.md" ] \
  || fail 'install did not include the DeepSeek executor skill on both surfaces'

# The resident files must be the user-direction guard, not an orchestration
# policy that dispatches agents on its own authority.
grep -Fq "@$ROOT/claude/CLAUDE.delegation.md" "$TMP/claude/CLAUDE.md" \
  || fail 'Claude install did not register the user-direction guard'
grep -Fq 'No standing permission to delegate' "$ROOT/claude/CLAUDE.delegation.md" \
  || fail 'Claude resident policy is not the user-direction guard'
grep -Fq 'No standing permission to delegate' "$TMP/codex/AGENTS.md" \
  || fail 'Codex resident policy is not the user-direction guard'
! grep -Fq 'mandatory consult' "$ROOT/claude/CLAUDE.delegation.md" \
  || fail 'Claude resident policy still mandates automatic agent calls'

# Every executor/routing skill must be explicitly user-triggered, and the
# orchestrate skill must no longer hide mandatory agent calls behind prose.
for skill in model-routing orchestrate glm-executor gemini-executor kimi-executor \
             grok-executor qwen-executor deepseek-executor; do
  grep -Fq 'User direction and selection' "$ROOT/skills/$skill/SKILL.md" \
    || fail "$skill does not require user direction"
done
! grep -Fq 'mandatory consult' "$ROOT/skills/orchestrate/SKILL.md" \
  || fail 'orchestrate still mandates hidden agent calls'
ok
[ -f "$TMP/claude/agents/opus-builder.md" ] \
  && grep -Fxq 'model: claude-opus-5' "$TMP/claude/agents/opus-builder.md" \
  && grep -Fxq 'effort: max' "$TMP/claude/agents/opus-builder.md" \
  || fail 'install did not include opus-builder at max'
[ -f "$TMP/claude/agents/fable-judge.md" ] \
  && grep -Fxq 'model: claude-fable-5-1' "$TMP/claude/agents/fable-judge.md" \
  && grep -Fxq 'effort: max' "$TMP/claude/agents/fable-judge.md" \
  && grep -Fxq 'tools: Read, Grep, Glob' "$TMP/claude/agents/fable-judge.md" \
  || fail 'install did not include fable-judge at max'
[ ! -e "$TMP/claude/agents/sonnet-builder.md" ] \
  || fail 'upgrade retained the retired Sonnet builder profile'
[ -f "$TMP/claude/agents/opus-reviewer.md" ] \
  && grep -Fxq 'effort: max' "$TMP/claude/agents/opus-reviewer.md" \
  && grep -Fxq 'tools: Read, Grep, Glob' "$TMP/claude/agents/opus-reviewer.md" \
  && grep -Fq 'configured review policy' "$TMP/claude/agents/opus-reviewer.md" \
  || fail 'install did not refresh opus-reviewer at max with the cross-family rule'
[ -f "$TMP/claude/agents/sonnet-reviewer.md" ] \
  && grep -Fxq 'model: sonnet' "$TMP/claude/agents/sonnet-reviewer.md" \
  && grep -Fxq 'effort: medium' "$TMP/claude/agents/sonnet-reviewer.md" \
  && grep -Fxq 'tools: Read, Grep, Glob' "$TMP/claude/agents/sonnet-reviewer.md" \
  && grep -Fq 'configured review policy' "$TMP/claude/agents/sonnet-reviewer.md" \
  || fail 'install did not refresh the Sonnet tool-read-only cross-family reviewer'
[ ! -e "$TMP/codex/agents/terra-scout.toml" ] && [ ! -e "$TMP/codex/terra-scout.config.toml" ] \
  || fail 'upgrade retained the retired Terra scout profile'
[ -f "$TMP/codex/agents/terra-builder.toml" ] && [ -f "$TMP/codex/terra-builder.config.toml" ] \
  || fail 'install did not retain Terra builder profiles'
[ -f "$TMP/codex/agents/terra-reviewer.toml" ] && [ -f "$TMP/codex/terra-reviewer.config.toml" ] \
  && grep -Fxq 'model = "gpt-5.6-terra"' "$TMP/codex/agents/terra-reviewer.toml" \
  && grep -Fxq 'model = "gpt-5.6-terra"' "$TMP/codex/terra-reviewer.config.toml" \
  && grep -Fxq 'model_reasoning_effort = "max"' "$TMP/codex/agents/terra-reviewer.toml" \
  && grep -Fxq 'model_reasoning_effort = "max"' "$TMP/codex/terra-reviewer.config.toml" \
  && grep -Fxq 'sandbox_mode = "read-only"' "$TMP/codex/agents/terra-reviewer.toml" \
  && grep -Fxq 'sandbox_mode = "read-only"' "$TMP/codex/terra-reviewer.config.toml" \
  || fail 'install did not include the Terra max read-only reviewer profiles'
[ -f "$TMP/codex/agents/astra-reviewer.toml" ] && [ -f "$TMP/codex/astra-reviewer.config.toml" ] \
  && grep -Fxq 'model = "gpt-6-astra"' "$TMP/codex/agents/astra-reviewer.toml" \
  && grep -Fxq 'model = "gpt-6-astra"' "$TMP/codex/astra-reviewer.config.toml" \
  && grep -Fxq 'model_reasoning_effort = "high"' "$TMP/codex/agents/astra-reviewer.toml" \
  && grep -Fxq 'model_reasoning_effort = "high"' "$TMP/codex/astra-reviewer.config.toml" \
  && grep -Fxq 'sandbox_mode = "read-only"' "$TMP/codex/agents/astra-reviewer.toml" \
  && grep -Fxq 'sandbox_mode = "read-only"' "$TMP/codex/astra-reviewer.config.toml" \
  && grep -Fq 'configured review policy' "$TMP/codex/agents/astra-reviewer.toml" \
  || fail 'install did not include the Astra high read-only cross-family reviewer profiles'
[ -f "$TMP/codex/agents/astra-judge.toml" ] && [ -f "$TMP/codex/astra-judge.config.toml" ] \
  && grep -Fxq 'model = "gpt-6-astra"' "$TMP/codex/agents/astra-judge.toml" \
  && grep -Fxq 'model = "gpt-6-astra"' "$TMP/codex/astra-judge.config.toml" \
  && grep -Fxq 'model_reasoning_effort = "high"' "$TMP/codex/agents/astra-judge.toml" \
  && grep -Fxq 'model_reasoning_effort = "high"' "$TMP/codex/astra-judge.config.toml" \
  && grep -Fxq 'sandbox_mode = "read-only"' "$TMP/codex/agents/astra-judge.toml" \
  && grep -Fxq 'sandbox_mode = "read-only"' "$TMP/codex/astra-judge.config.toml" \
  || fail 'install did not include astra-judge at high'
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

# A repeat install preserves the personal policy and later host profile edits.
printf '%s\n' 'personal profile edit' >"$TMP/claude2/agents/opus-reviewer.md"
jq '.review_policy = "required"' "$DELEGATION_CONFIG_FILE" >"$TMP/personal.json"
mv "$TMP/personal.json" "$DELEGATION_CONFIG_FILE"
env CLAUDE_HOME="$TMP/claude2" CODEX_HOME="$TMP/codex2" \
    DELEGATION_BIN_HOME="$TMP/bin2" DELEGATION_DATA_HOME="$TMP/data2" \
    DELEGATION_GROK_HOME="$GROK_TEST_HOME" \
    "$ROOT/install.sh" --claude-only </dev/null >"$TMP/reinstall.log" 2>&1 \
  || { cat "$TMP/reinstall.log" >&2; fail 'repeat install failed'; }
grep -Fxq 'personal profile edit' "$TMP/claude2/agents/opus-reviewer.md" \
  || fail 'repeat install overwrote an edited profile'
[ "$(jq -r '.review_policy' "$DELEGATION_CONFIG_FILE")" = required ] \
  || fail 'repeat install overwrote personal review policy'
for command in delegation-config delegation-run delegation-openai-compatible; do
  [ -x "$TMP/bin2/$command" ] || fail "missing new command $command"
done
ok

# Uninstalling that second tree must remove the commands and their data
# without touching the credentials/archives the uninstaller deliberately keeps.
[ -f "$TMP/data2/config/external-patch-policy.json" ] \
  || fail 'the --claude-only install did not include the patch policy'
env CLAUDE_HOME="$TMP/claude2" CODEX_HOME="$TMP/codex2" \
    DELEGATION_BIN_HOME="$TMP/bin2" DELEGATION_DATA_HOME="$TMP/data2" \
    "$ROOT/uninstall.sh" </dev/null >"$TMP/uninstall2.log" 2>&1 \
  || { sed 's/^/    /' "$TMP/uninstall2.log" >&2; fail 'uninstall.sh exited non-zero'; }
[ ! -e "$TMP/bin2/delegation-patch-verify" ] \
  || fail 'uninstall left the patch verifier on the bin path'
[ ! -e "$TMP/data2/config/external-patch-policy.json" ] \
  || fail 'uninstall left the installed patch policy behind'
[ ! -e "$TMP/bin2/delegation-route" ] \
  || fail 'uninstall left the router on the bin path'
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
