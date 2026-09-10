#!/usr/bin/env bash
# Operational routing v2: configuration and capabilities, independent of evidence.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/delegation-routing-tests.XXXXXX")"
trap 'rm -rf -- "$TMP"' EXIT
export DELEGATION_CONFIG_FILE="$TMP/config.json"
export DELEGATION_DATA_HOME="$TMP/data"
"$ROOT/bin/delegation-config" init >/dev/null
"$ROOT/bin/delegation-route" check --json | jq -e '.schema_version == 2 and .valid and .authorization_granted == false' >/dev/null
"$ROOT/bin/delegation-route" resolve --lane clerk --selected-profile deepseek-flash --json | jq -e '.selection_validated and .selected.technical_compatibility and .selected.evidence.status == "candidate"' >/dev/null
"$ROOT/bin/delegation-route" resolve --lane routine-review --producer-profile terra-builder --selected-profile terra-reviewer --json | jq -e '.selection_validated and .review_policy == "optional"' >/dev/null
jq '.review_policy = "cross-family"' "$DELEGATION_CONFIG_FILE" >"$TMP/strict.json"
DELEGATION_CONFIG_FILE="$TMP/strict.json" "$ROOT/bin/delegation-route" resolve --lane routine-review --producer-profile terra-builder --json | jq -e 'all(.choices[]; .family != "openai")' >/dev/null
# Kimi has no implementation for senior/reviewer/judgement: quality changes
# cannot manufacture a tool configuration for those roles.
"$ROOT/bin/delegation-route" resolve --lane senior --json | jq -e 'all(.choices[]; .adapter != "kimi-code-cli")' >/dev/null
for f in "$ROOT/config/"*routing*.json "$ROOT/config/model-evidence.json"; do jq -e . "$f" >/dev/null; done
for file in "$ROOT/codex/AGENTS.md" "$ROOT/claude/CLAUDE.delegation.md"; do
  grep -q 'Authorization is per dispatch' "$file"
  grep -q 'optional' "$file"
done
printf 'configuration routing, technical restrictions, historical JSON and explicit dispatch guard passed\n'
