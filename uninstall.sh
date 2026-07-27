#!/usr/bin/env bash
# delegation-kit uninstaller — removes the copied profiles and strips the
# registered policy blocks. Leaves *.delegation-kit.bak backups in place.
#
# Usage: ./uninstall.sh
# Env overrides: CLAUDE_HOME, CODEX_HOME, DELEGATION_BIN_HOME,
# DELEGATION_DATA_HOME
set -euo pipefail

CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
BIN_HOME="${DELEGATION_BIN_HOME:-$HOME/.local/bin}"
DATA_HOME="${DELEGATION_DATA_HOME:-$HOME/.local/share/delegation-kit}"
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
rm -rf "$CLAUDE_HOME/skills/model-routing" "$CLAUDE_HOME/skills/orchestrate" \
  "$CLAUDE_HOME/skills/glm-executor" "$CLAUDE_HOME/skills/kimi-executor"
rm -rf "$CLAUDE_HOME/skills/qwen-executor" "$CLAUDE_HOME/skills/gemini-executor" \
  "$CLAUDE_HOME/skills/grok-executor"
echo "  - removed 6 subagent profiles + model-routing, orchestrate, GLM, Gemini, Kimi, Qwen & Grok skills"
strip_guarded "$CLAUDE_HOME/CLAUDE.md"

echo "Codex -> $CODEX_HOME"
for a in luna-clerk terra-scout terra-builder sol-reviewer sol-judge; do
  rm -f "$CODEX_HOME/agents/$a.toml" "$CODEX_HOME/$a.config.toml"
done
rm -rf "$CODEX_HOME/skills/glm-executor" "$CODEX_HOME/skills/gemini-executor" \
  "$CODEX_HOME/skills/kimi-executor" "$CODEX_HOME/skills/qwen-executor" \
  "$CODEX_HOME/skills/grok-executor"
echo "  - removed 5 native + 5 ephemeral profiles"
strip_guarded "$CODEX_HOME/AGENTS.md"
rm -f "$BIN_HOME/delegation-glm" "$BIN_HOME/delegation-gemini" "$BIN_HOME/delegation-kimi" "$BIN_HOME/delegation-qwen" "$BIN_HOME/delegation-grok" \
  "$BIN_HOME/delegation-evidence" "$BIN_HOME/delegation-epoch" "$BIN_HOME/delegation-route"
# Everything else under $DATA_HOME is a byte-for-byte copy of a repo file that
# re-running install.sh restores; the keys and the archived Grok CLI are the
# unrecoverable things here — a superseded vendor build is no longer downloadable
# once the vendor prunes it. Back them up rather than destroy them, matching the
# *.delegation-kit.bak convention below.
zai_key_backup=""
qwen_key_backup=""
if [ -f "$DATA_HOME/config/zai.env" ]; then
  zai_key_backup="$DATA_HOME.zai.env.bak"
  ( umask 077; cp "$DATA_HOME/config/zai.env" "$zai_key_backup" )
  chmod 600 "$zai_key_backup"
fi
if [ -f "$DATA_HOME/config/qwen-token-plan.env" ]; then
  qwen_key_backup="$DATA_HOME.qwen-token-plan.env.bak"
  ( umask 077; cp "$DATA_HOME/config/qwen-token-plan.env" "$qwen_key_backup" )
  chmod 600 "$qwen_key_backup"
fi
grok_cli_backup=""
if [ -d "$DATA_HOME/grok-cli" ]; then
  grok_cli_backup="$DATA_HOME.grok-cli.bak"
  rm -rf "$grok_cli_backup"
  mv "$DATA_HOME/grok-cli" "$grok_cli_backup"
fi
rm -rf "$DATA_HOME"
echo "  - removed optional GLM/Gemini/Kimi/Qwen/Grok bridges, central routing gates, evidence snapshot, and Epoch ZIP importer"
[ -z "$grok_cli_backup" ] \
  || echo "  - archived Grok Build CLI preserved at $grok_cli_backup — delete it yourself when done"
[ -z "$zai_key_backup" ] \
  || echo "  - Z.AI API key preserved at $zai_key_backup (mode 600) — delete it yourself when done"
[ -z "$qwen_key_backup" ] \
  || echo "  - Qwen Token Plan API key preserved at $qwen_key_backup (mode 600) — delete it yourself when done"
echo
echo "Done. config.toml was never auto-edited, so nothing to revert there."
echo "Backups (*.delegation-kit.bak) left in place; delete when satisfied."
