#!/usr/bin/env bash
# delegation-kit uninstaller — removes the copied profiles and strips the
# registered policy blocks. Leaves *.delegation-kit.bak backups in place.
#
# Usage: ./uninstall.sh
# Env overrides: CLAUDE_HOME (default ~/.claude), CODEX_HOME (~/.codex)
set -euo pipefail

CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
BEGIN="<!-- >>> delegation-kit >>> -->"
END="<!-- <<< delegation-kit <<< -->"

strip_guarded() { # $1=file
  local file="$1"
  [ -f "$file" ] || return 0
  if grep -qF "$BEGIN" "$file"; then
    cp "$file" "$file.delegation-kit.bak"
    sed "/$BEGIN/,/$END/d" "$file" > "$file.tmp" && mv "$file.tmp" "$file"
    echo "  - stripped delegation-kit block from $file"
  fi
}

echo "Claude Code -> $CLAUDE_HOME"
for a in sonnet-clerk sonnet-scout sonnet-builder sonnet-reviewer opus-reviewer fable-judge; do
  rm -f "$CLAUDE_HOME/agents/$a.md"
done
rm -rf "$CLAUDE_HOME/skills/model-routing" "$CLAUDE_HOME/skills/orchestrate"
echo "  - removed 6 subagent profiles + model-routing & orchestrate skills"
strip_guarded "$CLAUDE_HOME/CLAUDE.md"

echo "Codex -> $CODEX_HOME"
for a in luna-clerk terra-scout terra-builder sol-reviewer; do
  rm -f "$CODEX_HOME/agents/$a.toml" "$CODEX_HOME/$a.config.toml"
done
echo "  - removed 4 native + 4 ephemeral profiles"
strip_guarded "$CODEX_HOME/AGENTS.md"
echo
echo "Done. config.toml was never auto-edited, so nothing to revert there."
echo "Backups (*.delegation-kit.bak) left in place; delete when satisfied."
