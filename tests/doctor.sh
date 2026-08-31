#!/usr/bin/env bash
# Ensure doctor always reaches its summary when a valid Codex config omits the
# optional root-level sandbox_mode key. A prior review probe accidentally enabled
# errexit halfway through the script and made this shape terminate silently.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/delegation-doctor-tests.XXXXXX")"
trap 'rm -rf -- "$TMP"' EXIT
command -v jq >/dev/null 2>&1 || { printf 'jq is required\n' >&2; exit 69; }

TEST_TOOLS="$TMP/test-tools"
mkdir -p "$TMP/claude" "$TMP/codex" "$TMP/data" "$TEST_TOOLS"
cat >"$TEST_TOOLS/codex" <<'EOF'
#!/usr/bin/env bash
[ "${1:-}" = --version ] && { printf 'codex test-build\n'; exit 0; }
exit 2
EOF
cat >"$TEST_TOOLS/claude" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  --version) printf 'claude test-build\n' ;;
  auth) [ "${2:-}" = status ] ;;
  *) exit 2 ;;
esac
EOF
chmod 700 "$TEST_TOOLS/codex" "$TEST_TOOLS/claude"
cat >"$TMP/codex/config.toml" <<'EOF'
[features]
multi_agent = true
EOF

# A diagnostic may legitimately exit non-zero in these intentionally empty
# homes; completion and the final summary are the contract under test.
if env PATH="$TEST_TOOLS:$PATH" CLAUDE_HOME="$TMP/claude" CODEX_HOME="$TMP/codex" \
    DELEGATION_DATA_HOME="$TMP/data" \
    "$ROOT/doctor.sh" >"$TMP/doctor.log" 2>&1; then
  :
else
  :
fi

grep -Fq 'sandbox_mode not set (Codex default applies)' "$TMP/doctor.log" || {
  sed 's/^/    /' "$TMP/doctor.log" >&2
  printf 'doctor did not reach the root sandbox_mode diagnostic\n' >&2
  exit 1
}
grep -Eq '^== Summary: [0-9]+ OK, [0-9]+ WARN, [0-9]+ FAIL ==$' "$TMP/doctor.log" || {
  sed 's/^/    /' "$TMP/doctor.log" >&2
  printf 'doctor did not print its final summary\n' >&2
  exit 1
}

# Exact-profile checks must resolve active plugin-cache installs as well as
# direct ~/.claude/agents copies.
PLUGIN_ROOT="$TMP/plugin/delegation-kit"
mkdir -p "$PLUGIN_ROOT/agents" "$TMP/claude/plugins"
cp "$ROOT"/agents/*.md "$PLUGIN_ROOT/agents/"
cat >"$TMP/claude/plugins/installed_plugins.json" <<EOF
{"plugins":{"delegation-kit@test":[{"installPath":"$PLUGIN_ROOT"}]}}
EOF
if env PATH="$TEST_TOOLS:$PATH" CLAUDE_HOME="$TMP/claude" CODEX_HOME="$TMP/codex" \
    DELEGATION_DATA_HOME="$TMP/data" \
    "$ROOT/doctor.sh" >"$TMP/plugin-doctor.log" 2>&1; then
  :
else
  :
fi
grep -Fq '[ OK ] opus-builder pinned to claude-opus-5/max' "$TMP/plugin-doctor.log"
grep -Fq '[ OK ] opus-reviewer pinned to claude-opus-5/max and cross-family only' "$TMP/plugin-doctor.log"
grep -Fq '[ OK ] fable-judge pinned to fable/max and read-only judgement' "$TMP/plugin-doctor.log"
grep -Fq '[ OK ] sonnet-reviewer pinned to sonnet/medium, tool-read-only, and cross-family only' "$TMP/plugin-doctor.log"
grep -Fq '== External executor contract ==' "$TMP/plugin-doctor.log" || {
  printf 'doctor did not report on the external executor contract\n' >&2
  exit 1
}

# With the contract command and gates installed, doctor must validate them
# statically — no provider is contacted — and say who still enforces.
CONTRACT_DATA="$TMP/contract-data"
CONTRACT_BIN="$TMP/contract-bin"
mkdir -p "$CONTRACT_DATA/bin" "$CONTRACT_DATA/config" "$CONTRACT_BIN"
cp "$ROOT/bin/delegation-executor-contract" "$CONTRACT_DATA/bin/delegation-executor-contract"
cp "$ROOT/bin/delegation-patch-verify" "$CONTRACT_DATA/bin/delegation-patch-verify"
cp "$ROOT"/config/*.json "$CONTRACT_DATA/config/"
chmod 755 "$CONTRACT_DATA/bin/delegation-executor-contract" \
  "$CONTRACT_DATA/bin/delegation-patch-verify"
ln -sfn "$CONTRACT_DATA/bin/delegation-executor-contract" \
  "$CONTRACT_BIN/delegation-executor-contract"
ln -sfn "$CONTRACT_DATA/bin/delegation-patch-verify" \
  "$CONTRACT_BIN/delegation-patch-verify"
if env PATH="$CONTRACT_BIN:$TEST_TOOLS:$PATH" CLAUDE_HOME="$TMP/claude" \
    CODEX_HOME="$TMP/codex" DELEGATION_DATA_HOME="$CONTRACT_DATA" \
    "$ROOT/doctor.sh" >"$TMP/contract-doctor.log" 2>&1; then
  :
else
  :
fi
grep -Fq '[ OK ] external executor contract valid' "$TMP/contract-doctor.log" || {
  sed 's/^/    /' "$TMP/contract-doctor.log" >&2
  printf 'doctor did not validate the installed external executor contract\n' >&2
  exit 1
}
grep -Fq 'each provider runner still enforces its own permissions' "$TMP/contract-doctor.log" || {
  printf 'doctor did not restate the runner-enforcement boundary\n' >&2
  exit 1
}

# The patch verifier is checked statically too: policy shape, fail-closed
# defaults, and that every text-patch lane names this exact policy version.
# Nothing here parses a patch or contacts a provider.
grep -Fq '== External patch verifier ==' "$TMP/contract-doctor.log" || {
  printf 'doctor did not report on the external patch verifier\n' >&2
  exit 1
}
grep -Fq '[ OK ] external patch policy 1.0.0 valid and fail-closed' "$TMP/contract-doctor.log" || {
  sed 's/^/    /' "$TMP/contract-doctor.log" >&2
  printf 'doctor did not validate the installed patch policy\n' >&2
  exit 1
}
grep -Fq 'it never applies one — the lead applies and tests' "$TMP/contract-doctor.log" || {
  printf 'doctor did not restate that the verifier never applies a patch\n' >&2
  exit 1
}
grep -Fq '[ OK ] every text-patch lane declares patch policy 1.0.0' "$TMP/contract-doctor.log" || {
  sed 's/^/    /' "$TMP/contract-doctor.log" >&2
  printf 'doctor did not cross-check the text-patch lanes against the installed policy\n' >&2
  exit 1
}

# A patch policy that has drifted open is a FAIL, not a pass.
jq '.operations.delete = "allowed"' "$ROOT/config/external-patch-policy.json" \
  >"$CONTRACT_DATA/config/external-patch-policy.json"
if env PATH="$CONTRACT_BIN:$TEST_TOOLS:$PATH" CLAUDE_HOME="$TMP/claude" \
    CODEX_HOME="$TMP/codex" DELEGATION_DATA_HOME="$CONTRACT_DATA" \
    "$ROOT/doctor.sh" >"$TMP/patch-drift.log" 2>&1; then
  :
else
  :
fi
grep -Fq '[FAIL] installed patch policy is missing, invalid, or has drifted open' "$TMP/patch-drift.log" || {
  sed 's/^/    /' "$TMP/patch-drift.log" >&2
  printf 'doctor accepted a patch policy that allows deletions by default\n' >&2
  exit 1
}

# A policy version no text-patch lane declares breaks the contract check, and
# doctor must say the cross-check could not be made rather than report a pass.
jq '.policy_version = "9.9.9"' "$ROOT/config/external-patch-policy.json" \
  >"$CONTRACT_DATA/config/external-patch-policy.json"
if env PATH="$CONTRACT_BIN:$TEST_TOOLS:$PATH" CLAUDE_HOME="$TMP/claude" \
    CODEX_HOME="$TMP/codex" DELEGATION_DATA_HOME="$CONTRACT_DATA" \
    "$ROOT/doctor.sh" >"$TMP/patch-version-drift.log" 2>&1; then
  :
else
  :
fi
grep -Fq '[FAIL] external executor contract is missing, invalid' "$TMP/patch-version-drift.log" || {
  sed 's/^/    /' "$TMP/patch-version-drift.log" >&2
  printf 'doctor accepted a patch policy version no text-patch lane declares\n' >&2
  exit 1
}
grep -Fq 'text-patch lanes could not be cross-checked' "$TMP/patch-version-drift.log" || {
  sed 's/^/    /' "$TMP/patch-version-drift.log" >&2
  printf 'doctor claimed a text-patch cross-check it could not make\n' >&2
  exit 1
}
if grep -Fq '[ OK ] every text-patch lane declares patch policy' "$TMP/patch-version-drift.log"; then
  printf 'doctor reported a text-patch lane pass while the contract was invalid\n' >&2
  exit 1
fi
cp "$ROOT/config/external-patch-policy.json" \
  "$CONTRACT_DATA/config/external-patch-policy.json"

# A contract that disagrees with the installed gates is a FAIL, not a pass.
jq '.families["grok-4.6"].lanes.builder.permission_class = "read-only"' \
  "$ROOT/config/external-executor-contract.json" \
  >"$CONTRACT_DATA/config/external-executor-contract.json"
if env PATH="$CONTRACT_BIN:$TEST_TOOLS:$PATH" CLAUDE_HOME="$TMP/claude" \
    CODEX_HOME="$TMP/codex" DELEGATION_DATA_HOME="$CONTRACT_DATA" \
    "$ROOT/doctor.sh" >"$TMP/contract-drift.log" 2>&1; then
  :
else
  :
fi
grep -Fq '[FAIL] external executor contract is missing, invalid' "$TMP/contract-drift.log" || {
  sed 's/^/    /' "$TMP/contract-drift.log" >&2
  printf 'doctor accepted a contract that contradicts the installed gates\n' >&2
  exit 1
}

printf 'doctor end-to-end regression passed\n'
