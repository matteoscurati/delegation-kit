#!/usr/bin/env bash
# delegation-route: read-only discovery over the personal configuration.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/delegation-route-tests.XXXXXX")"
trap 'rm -rf -- "$TMP"' EXIT
export DELEGATION_CONFIG_FILE="$TMP/config.json"
export DELEGATION_DATA_HOME="$TMP/data"
pass=0
ok() { pass=$((pass + 1)); }
"$ROOT/bin/delegation-config" init >/dev/null
# check: schema 3, valid, never authorizing
"$ROOT/bin/delegation-route" check --json | jq -e '.schema_version == 3 and .valid and .authorization_granted == false and .automatic_dispatch == false' >/dev/null; ok
# the shipped preset is what init wrote
[ "$(jq -r '.profiles | length' "$DELEGATION_CONFIG_FILE")" = "$(jq -r '.profiles | length' "$ROOT/config/presets.json")" ]; ok
# resolve validates a technically compatible selection and reports capabilities, no evidence
"$ROOT/bin/delegation-route" resolve --lane clerk --selected-profile deepseek-flash --json \
  | jq -e '.selection_validated and .selected.technical_compatibility and (.selected.capabilities | index("text-patch") != null) and (.selected | has("evidence") | not)' >/dev/null; ok
# an unsupported role is refused (65) and listed under blocked
if "$ROOT/bin/delegation-route" resolve --lane senior --selected-profile kimi-k3 --json >/dev/null 2>&1; then exit 1; fi; ok
"$ROOT/bin/delegation-route" resolve --lane senior --json | jq -e 'all(.choices[]; .adapter != "kimi-code-cli") and any(.blocked[]; .profile == "kimi-k3")' >/dev/null; ok
# review lanes: optional accepts the same family, cross-family excludes it
"$ROOT/bin/delegation-route" resolve --lane routine-review --producer-profile terra-builder --selected-profile terra-reviewer --json | jq -e '.selection_validated and .review_policy == "optional"' >/dev/null; ok
jq '.review_policy = "cross-family"' "$DELEGATION_CONFIG_FILE" >"$TMP/strict.json"
DELEGATION_CONFIG_FILE="$TMP/strict.json" "$ROOT/bin/delegation-route" resolve --lane routine-review --producer-profile terra-builder --json | jq -e 'all(.choices[]; .family != "openai") and any(.blocked[]; .profile == "terra-reviewer")' >/dev/null; ok
# table: one row per profile x role, no historical fields
"$ROOT/bin/delegation-route" table --json | jq -e '(.profiles | length) > 0 and all(.profiles[]; has("technical_compatibility") and has("capabilities") and (has("evidence") | not)) and (has("compound_lanes") | not)' >/dev/null; ok
# unknown lane and unknown profile fail closed
if "$ROOT/bin/delegation-route" resolve --lane nope --json >/dev/null 2>&1; then exit 1; fi; ok
if "$ROOT/bin/delegation-route" profile nope --json >/dev/null 2>&1; then exit 1; fi; ok
# the resident guards still describe per-dispatch authorization and the review policies
for file in "$ROOT/codex/AGENTS.md" "$ROOT/claude/CLAUDE.delegation.md"; do
  grep -q 'Authorization is per dispatch' "$file"; grep -q 'optional' "$file"
done; ok
printf 'route tests: %s passed\n' "$pass"
