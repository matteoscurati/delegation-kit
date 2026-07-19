#!/usr/bin/env bash
# delegation-kit installer — copies the routing profiles into Claude Code and
# Codex, and registers the policy prose. Idempotent; backs up before editing.
#
# Usage: ./install.sh [--claude-only | --codex-only]
# Env overrides (for testing): CLAUDE_HOME, CODEX_HOME, DELEGATION_BIN_HOME,
# DELEGATION_DATA_HOME
set -euo pipefail

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
BIN_HOME="${DELEGATION_BIN_HOME:-$HOME/.local/bin}"
DATA_HOME="${DELEGATION_DATA_HOME:-$HOME/.local/share/delegation-kit}"
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
  local backed=""
  if [ -f "$file" ] && grep -qF "$BEGIN" "$file"; then
    cp "$file" "$file.delegation-kit.bak"
    backed=" (backup: $file.delegation-kit.bak)"
    local stripped
    stripped="$(mktemp "${TMPDIR:-/tmp}/delegation-kit-policy.XXXXXX")"
    sed "/^${BEGIN}$/,/^${END}$/d" "$file" >"$stripped"
    mv "$stripped" "$file"
  else
    mkdir -p "$(dirname "$file")"
    [ -f "$file" ] && { cp "$file" "$file.delegation-kit.bak"; backed=" (backup: $file.delegation-kit.bak)"; }
  fi
  [ -s "$file" ] && printf '\n' >>"$file"
  printf '%s\n%s\n%s\n' "$BEGIN" "$content" "$END" >>"$file"
  echo "  + registered/refreshed in $file$backed"
}

# Shared optional external-model bridges. Installing a command does not make its
# model routable: the runtime check and versioned evaluation manifest must pass.
mkdir -p "$BIN_HOME" "$DATA_HOME/bin" "$DATA_HOME/config"
cp "$KIT/bin/delegation-glm" "$DATA_HOME/bin/delegation-glm"
cp "$KIT/config/glm-5.2-routing.json" "$DATA_HOME/config/glm-5.2-routing.json"
chmod 755 "$DATA_HOME/bin/delegation-glm"
ln -sfn "$DATA_HOME/bin/delegation-glm" "$BIN_HOME/delegation-glm"
echo "GLM bridge -> $BIN_HOME/delegation-glm (routing gate: $DATA_HOME/config/glm-5.2-routing.json)"

# GLM's only transport is the Z.AI API, so without a key the lane is dead. Ask
# once, interactively, and never overwrite an existing key without consent.
# Every `read` is guarded: unguarded, an EOF (Ctrl-D, or a piped installer) would
# trip errexit and silently abandon the rest of the install — Kimi bridge,
# profiles and all.
ZAI_KEY_FILE="$DATA_HOME/config/zai.env"
zai_store_key() { # $1=key
  ( umask 077; printf 'ZAI_API_KEY=%s\n' "$1" >"$ZAI_KEY_FILE" )
  chmod 600 "$ZAI_KEY_FILE"
  echo "  + Z.AI key stored in $ZAI_KEY_FILE (mode 600)"
}
zai_ask=1
if [ -f "$ZAI_KEY_FILE" ]; then
  if [ ! -t 0 ]; then
    echo "  + Z.AI key already stored in $ZAI_KEY_FILE"
    zai_ask=0
  else
    printf '  Z.AI key already stored in %s. Replace it? [y/N] ' "$ZAI_KEY_FILE"
    read -r zai_replace || zai_replace=""
    case "$zai_replace" in [yY]*) ;; *) zai_ask=0 ;; esac
  fi
fi
if [ "$zai_ask" = 1 ]; then
  # An exported ZAI_API_KEY only serves the shell that has it — not a subagent,
  # cron job or another terminal — so offer to persist it rather than treat it as
  # a substitute for the key file.
  if [ -n "${ZAI_API_KEY:-}" ]; then
    if [ ! -t 0 ]; then
      zai_store_key "$ZAI_API_KEY"
    else
      printf '  Store the ZAI_API_KEY from your environment in %s? [Y/n] ' "$ZAI_KEY_FILE"
      read -r zai_use_env || zai_use_env=""
      case "$zai_use_env" in
        [nN]*) echo "  ! not stored — GLM only works where ZAI_API_KEY is exported" ;;
        *) zai_store_key "$ZAI_API_KEY" ;;
      esac
    fi
  elif [ ! -t 0 ]; then
    echo "  ! no Z.AI key configured — GLM stays unavailable (re-run interactively, or set ZAI_API_KEY)"
  else
    printf '  Z.AI API key for GLM-5.2 (input hidden, Enter to skip): '
    read -rs zai_key || zai_key=""
    printf '\n'
    if [ -n "$zai_key" ]; then
      zai_store_key "$zai_key"
    else
      echo "  ! skipped — GLM stays unavailable until ZAI_API_KEY is set or the key is stored"
    fi
    unset zai_key
  fi
fi
cp "$KIT/bin/delegation-kimi" "$DATA_HOME/bin/delegation-kimi"
cp "$KIT/config/kimi-k3-routing.json" "$DATA_HOME/config/kimi-k3-routing.json"
chmod 755 "$DATA_HOME/bin/delegation-kimi"
ln -sfn "$DATA_HOME/bin/delegation-kimi" "$BIN_HOME/delegation-kimi"
echo "Kimi bridge -> $BIN_HOME/delegation-kimi (routing gate: $DATA_HOME/config/kimi-k3-routing.json)"

if [ "$do_claude" = 1 ]; then
  echo "Claude Code -> $CLAUDE_HOME"
  mkdir -p "$CLAUDE_HOME/agents" "$CLAUDE_HOME/skills"
  cp "$KIT"/agents/*.md "$CLAUDE_HOME/agents/"
  echo "  + 6 subagent profiles -> $CLAUDE_HOME/agents/"
  # register the always-loaded policy first — it is the linchpin, so a missing optional
  # skill source below cannot abort install (set -e) before the bridge is wired
  append_guarded "$CLAUDE_HOME/CLAUDE.md" "@$KIT/claude/CLAUDE.delegation.md"
  cp -R "$KIT/skills/model-routing" "$CLAUDE_HOME/skills/"
  cp "$KIT/model-routing.md" "$CLAUDE_HOME/skills/model-routing/"   # co-locate the scored table so the skill's pointer resolves
  echo "  + model-routing skill (+ scored table) -> $CLAUDE_HOME/skills/model-routing/"
  cp -R "$KIT/skills/orchestrate" "$CLAUDE_HOME/skills/"
  echo "  + orchestrate skill -> $CLAUDE_HOME/skills/orchestrate/"
  cp -R "$KIT/skills/glm-executor" "$CLAUDE_HOME/skills/"
  echo "  + optional GLM executor skill -> $CLAUDE_HOME/skills/glm-executor/"
  cp -R "$KIT/skills/kimi-executor" "$CLAUDE_HOME/skills/"
  echo "  + optional Kimi executor skill -> $CLAUDE_HOME/skills/kimi-executor/"
fi

if [ "$do_codex" = 1 ]; then
  echo "Codex -> $CODEX_HOME"
  mkdir -p "$CODEX_HOME/agents" "$CODEX_HOME/skills"
  cp "$KIT"/codex/agents/*.toml "$CODEX_HOME/agents/"
  echo "  + 4 native subagent profiles -> $CODEX_HOME/agents/"
  cp "$KIT"/codex/profiles/*.config.toml "$CODEX_HOME/"
  echo "  + 4 ephemeral -p profiles -> $CODEX_HOME/"
  cp -R "$KIT/skills/glm-executor" "$CODEX_HOME/skills/"
  echo "  + optional GLM executor skill -> $CODEX_HOME/skills/glm-executor/"
  cp -R "$KIT/skills/kimi-executor" "$CODEX_HOME/skills/"
  echo "  + optional Kimi executor skill -> $CODEX_HOME/skills/kimi-executor/"
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
