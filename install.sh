#!/usr/bin/env bash
# delegation-kit installer — copies the routing profiles into Claude Code and
# Codex, and registers the policy prose. Idempotent; backs up before editing.
#
# Usage: ./install.sh [--claude-only | --codex-only]
# Env overrides (for testing): CLAUDE_HOME (default ~/.claude), CODEX_HOME (~/.codex)
set -euo pipefail

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
BEGIN="<!-- >>> delegation-kit >>> -->"
END="<!-- <<< delegation-kit <<< -->"

do_claude=1; do_codex=1
case "${1:-}" in
  --claude-only) do_codex=0 ;;
  --codex-only)  do_claude=0 ;;
  -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  "") ;;
  *) echo "unknown arg: $1" >&2; exit 2 ;;
esac

append_guarded() { # $1=file  $2=content
  local file="$1" content="$2"
  if [ -f "$file" ] && grep -qF "$BEGIN" "$file"; then
    echo "  = already registered in $file (run ./uninstall.sh first to refresh)"
    return 0
  fi
  mkdir -p "$(dirname "$file")"
  local backed=""
  [ -f "$file" ] && { cp "$file" "$file.delegation-kit.bak"; backed=" (backup: $file.delegation-kit.bak)"; }
  { [ -s "$file" ] && printf '\n'; printf '%s\n%s\n%s\n' "$BEGIN" "$content" "$END"; } >> "$file"
  echo "  + registered in $file$backed"
}

if [ "$do_claude" = 1 ]; then
  echo "Claude Code -> $CLAUDE_HOME"
  mkdir -p "$CLAUDE_HOME/agents" "$CLAUDE_HOME/skills"
  cp "$KIT"/agents/*.md "$CLAUDE_HOME/agents/"
  echo "  + 5 subagent profiles -> $CLAUDE_HOME/agents/"
  cp -R "$KIT/skills/model-routing" "$CLAUDE_HOME/skills/"
  cp "$KIT/model-routing.md" "$CLAUDE_HOME/skills/model-routing/"   # co-locate the scored table so the skill's pointer resolves
  echo "  + model-routing skill (+ scored table) -> $CLAUDE_HOME/skills/model-routing/"
  append_guarded "$CLAUDE_HOME/CLAUDE.md" "@$KIT/claude/CLAUDE.delegation.md"
fi

if [ "$do_codex" = 1 ]; then
  echo "Codex -> $CODEX_HOME"
  mkdir -p "$CODEX_HOME/agents"
  cp "$KIT"/codex/agents/*.toml "$CODEX_HOME/agents/"
  echo "  + 4 native subagent profiles -> $CODEX_HOME/agents/"
  cp "$KIT"/codex/profiles/*.config.toml "$CODEX_HOME/"
  echo "  + 4 ephemeral -p profiles -> $CODEX_HOME/"
  append_guarded "$CODEX_HOME/AGENTS.md" "$(cat "$KIT/codex/AGENTS.md")"
  echo
  echo "  Codex config is NOT auto-edited. Review and merge into $CODEX_HOME/config.toml:"
  echo "  ------------------------------------------------------------------"
  sed 's/^/  | /' "$KIT/codex/config.snippet.toml"
  echo "  ------------------------------------------------------------------"
fi

echo
echo "Done. Restart Claude Code / open a new Codex session to pick up the changes."
echo "Verify the bridge is wired:  $KIT/doctor.sh   (add --ping for a live round-trip)"
echo "Adapt the models to your own tiers: see $KIT/ADAPTING.md"
