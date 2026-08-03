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
cp "$KIT/bin/delegation-schema" "$DATA_HOME/bin/delegation-schema"
chmod 755 "$DATA_HOME/bin/delegation-schema"
ln -sfn "$DATA_HOME/bin/delegation-schema" "$BIN_HOME/delegation-schema"
echo "Schema transport compiler -> $BIN_HOME/delegation-schema (Claude/Codex, read-only)"
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
# Kimi Code itself remains vendor-managed and is never updated here. Archive the
# currently selected ripgrep bytes for the Grep-only process allowlist. A
# different existing archive is retained unless the owner explicitly uses
# `delegation-kimi pin-rg --force`.
if command -v rg >/dev/null 2>&1; then
  if kimi_pin_out="$(DELEGATION_DATA_HOME="$DATA_HOME" \
      "$DATA_HOME/bin/delegation-kimi" pin-rg --from "$(command -v rg)" 2>&1)"; then
    printf '%s\n' "$kimi_pin_out" | sed 's/^/  + /'
  else
    echo "  ! verified ripgrep not pinned — inspect with 'delegation-kimi check --json'; replace deliberately with 'delegation-kimi pin-rg --force'"
  fi
else
  echo "  ! rg not on PATH — install ripgrep, then run 'delegation-kimi pin-rg'"
fi

cp "$KIT/bin/delegation-gemini" "$DATA_HOME/bin/delegation-gemini"
cp "$KIT/config/gemini-3.6-flash-routing.json" "$DATA_HOME/config/gemini-3.6-flash-routing.json"
chmod 755 "$DATA_HOME/bin/delegation-gemini"
ln -sfn "$DATA_HOME/bin/delegation-gemini" "$BIN_HOME/delegation-gemini"
echo "Gemini bridge -> $BIN_HOME/delegation-gemini (routing gate: $DATA_HOME/config/gemini-3.6-flash-routing.json)"

cp "$KIT/bin/delegation-qwen" "$DATA_HOME/bin/delegation-qwen"
cp "$KIT/config/qwen3.8-max-routing.json" "$DATA_HOME/config/qwen3.8-max-routing.json"
chmod 755 "$DATA_HOME/bin/delegation-qwen"
ln -sfn "$DATA_HOME/bin/delegation-qwen" "$BIN_HOME/delegation-qwen"
echo "Qwen bridge -> $BIN_HOME/delegation-qwen (provisional builder gate: $DATA_HOME/config/qwen3.8-max-routing.json)"

cp "$KIT/bin/delegation-grok" "$DATA_HOME/bin/delegation-grok"
cp "$KIT/config/grok-4.5-routing.json" "$DATA_HOME/config/grok-4.5-routing.json"
chmod 755 "$DATA_HOME/bin/delegation-grok"
ln -sfn "$DATA_HOME/bin/delegation-grok" "$BIN_HOME/delegation-grok"
echo "Grok bridge -> $BIN_HOME/delegation-grok (provisional builder gate: $DATA_HOME/config/grok-4.5-routing.json)"
# A vendor auto-update replaces the ambient Grok CLI and prunes its own download
# cache. Archive the currently compatible build so the selected bytes remain
# available independently of PATH.
if grok_pin_out="$(DELEGATION_DATA_HOME="$DATA_HOME" "$DATA_HOME/bin/delegation-grok" pin 2>&1)"; then
  printf '  + %s\n' "$(printf '%s\n' "$grok_pin_out" | head -1)"
else
  echo "  ! compatible Grok Build CLI not archived — run 'delegation-grok pin --from <path>'"
fi

# Qwen Token Plan credentials are isolated from DashScope and from ai-consultants.
# Never copy a key from another tool silently; accept an explicit environment
# value or ask once, preserving an existing mode-600 file by default.
QWEN_KEY_FILE="$DATA_HOME/config/qwen-token-plan.env"
qwen_store_key() { # $1=key
  ( umask 077; printf 'QWEN_TOKEN_PLAN_API_KEY=%s\n' "$1" >"$QWEN_KEY_FILE" )
  chmod 600 "$QWEN_KEY_FILE"
  echo "  + Qwen Token Plan key stored in $QWEN_KEY_FILE (mode 600)"
}
qwen_ask=1
if [ -f "$QWEN_KEY_FILE" ]; then
  if [ ! -t 0 ]; then
    echo "  + Qwen Token Plan key already stored in $QWEN_KEY_FILE"
    qwen_ask=0
  else
    printf '  Qwen Token Plan key already stored in %s. Replace it? [y/N] ' "$QWEN_KEY_FILE"
    read -r qwen_replace || qwen_replace=""
    case "$qwen_replace" in [yY]*) ;; *) qwen_ask=0 ;; esac
  fi
fi
if [ "$qwen_ask" = 1 ]; then
  if [ -n "${QWEN_TOKEN_PLAN_API_KEY:-}" ]; then
    case "$QWEN_TOKEN_PLAN_API_KEY" in sk-sp-*) ;; *) echo "  ! QWEN_TOKEN_PLAN_API_KEY is not a Token Plan key (expected sk-sp- prefix)"; QWEN_TOKEN_PLAN_API_KEY="" ;; esac
    if [ -n "$QWEN_TOKEN_PLAN_API_KEY" ]; then
      if [ ! -t 0 ]; then qwen_store_key "$QWEN_TOKEN_PLAN_API_KEY"
      else
        printf '  Store QWEN_TOKEN_PLAN_API_KEY in %s? [Y/n] ' "$QWEN_KEY_FILE"
        read -r qwen_use_env || qwen_use_env=""
        case "$qwen_use_env" in [nN]*) echo "  ! not stored — Qwen works only where the variable is exported" ;; *) qwen_store_key "$QWEN_TOKEN_PLAN_API_KEY" ;; esac
      fi
    fi
  elif [ ! -t 0 ]; then
    echo "  ! no Qwen Token Plan key configured — candidate runtime stays unavailable"
  else
    printf '  Qwen Token Plan API key (sk-sp-..., input hidden, Enter to skip): '
    read -rs qwen_key || qwen_key=""; printf '\n'
    case "$qwen_key" in "") echo "  ! skipped — Qwen candidate runtime stays unavailable" ;; sk-sp-*) qwen_store_key "$qwen_key" ;; *) echo "  ! rejected — expected a Token Plan key with sk-sp- prefix" ;; esac
    unset qwen_key
  fi
fi

# Shared, read-only evidence inspector. This snapshot informs routing decisions
# but deliberately has no code path that mutates either executor gate.
cp "$KIT/bin/delegation-evidence" "$DATA_HOME/bin/delegation-evidence"
cp "$KIT/bin/delegation-epoch" "$DATA_HOME/bin/delegation-epoch"
cp "$KIT/config/model-evidence.json" "$DATA_HOME/config/model-evidence.json"
chmod 755 "$DATA_HOME/bin/delegation-evidence" "$DATA_HOME/bin/delegation-epoch"
ln -sfn "$DATA_HOME/bin/delegation-evidence" "$BIN_HOME/delegation-evidence"
ln -sfn "$DATA_HOME/bin/delegation-epoch" "$BIN_HOME/delegation-epoch"
echo "Model evidence -> $BIN_HOME/delegation-evidence (snapshot: $DATA_HOME/config/model-evidence.json)"
echo "Epoch ZIP feed -> $BIN_HOME/delegation-epoch (advisory only; raw data is not persisted)"

cp "$KIT/bin/delegation-route" "$DATA_HOME/bin/delegation-route"
cp "$KIT/config/routing-gates.json" "$DATA_HOME/config/routing-gates.json"
chmod 755 "$DATA_HOME/bin/delegation-route"
ln -sfn "$DATA_HOME/bin/delegation-route" "$BIN_HOME/delegation-route"
echo "Routing gates -> $BIN_HOME/delegation-route (decisions: $DATA_HOME/config/routing-gates.json)"

if [ "$do_claude" = 1 ]; then
  echo "Claude Code -> $CLAUDE_HOME"
  mkdir -p "$CLAUDE_HOME/agents" "$CLAUDE_HOME/skills"
  cp "$KIT"/agents/*.md "$CLAUDE_HOME/agents/"
  echo "  + 6 subagent profiles -> $CLAUDE_HOME/agents/"
  # register the always-loaded policy first — it is the linchpin, so a missing optional
  # skill source below cannot abort install (set -e) before the bridge is wired
  append_guarded "$CLAUDE_HOME/CLAUDE.md" "@$KIT/claude/CLAUDE.delegation.md"
  cp -R "$KIT/skills/model-routing" "$CLAUDE_HOME/skills/"
  cp "$KIT/model-routing.md" "$CLAUDE_HOME/skills/model-routing/"   # co-locate the evidence-backed policy so the skill's pointer resolves
  echo "  + model-routing skill (+ evidence-backed policy) -> $CLAUDE_HOME/skills/model-routing/"
  cp -R "$KIT/skills/orchestrate" "$CLAUDE_HOME/skills/"
  echo "  + orchestrate skill -> $CLAUDE_HOME/skills/orchestrate/"
  cp -R "$KIT/skills/glm-executor" "$CLAUDE_HOME/skills/"
  echo "  + optional GLM executor skill -> $CLAUDE_HOME/skills/glm-executor/"
  cp -R "$KIT/skills/kimi-executor" "$CLAUDE_HOME/skills/"
  echo "  + optional Kimi executor skill -> $CLAUDE_HOME/skills/kimi-executor/"
  cp -R "$KIT/skills/gemini-executor" "$CLAUDE_HOME/skills/"
  echo "  + optional Gemini executor skill -> $CLAUDE_HOME/skills/gemini-executor/"
  cp -R "$KIT/skills/qwen-executor" "$CLAUDE_HOME/skills/"
  echo "  + provisional Qwen builder skill -> $CLAUDE_HOME/skills/qwen-executor/"
  cp -R "$KIT/skills/grok-executor" "$CLAUDE_HOME/skills/"
  echo "  + provisional Grok builder skill -> $CLAUDE_HOME/skills/grok-executor/"
fi

if [ "$do_codex" = 1 ]; then
  echo "Codex -> $CODEX_HOME"
  mkdir -p "$CODEX_HOME/agents" "$CODEX_HOME/skills"
  cp "$KIT"/codex/agents/*.toml "$CODEX_HOME/agents/"
  echo "  + 5 native subagent profiles -> $CODEX_HOME/agents/"
  cp "$KIT"/codex/profiles/*.config.toml "$CODEX_HOME/"
  echo "  + 5 ephemeral -p profiles -> $CODEX_HOME/"
  cp -R "$KIT/skills/glm-executor" "$CODEX_HOME/skills/"
  echo "  + optional GLM executor skill -> $CODEX_HOME/skills/glm-executor/"
  cp -R "$KIT/skills/kimi-executor" "$CODEX_HOME/skills/"
  echo "  + optional Kimi executor skill -> $CODEX_HOME/skills/kimi-executor/"
  cp -R "$KIT/skills/gemini-executor" "$CODEX_HOME/skills/"
  echo "  + optional Gemini executor skill -> $CODEX_HOME/skills/gemini-executor/"
  cp -R "$KIT/skills/qwen-executor" "$CODEX_HOME/skills/"
  echo "  + provisional Qwen builder skill -> $CODEX_HOME/skills/qwen-executor/"
  cp -R "$KIT/skills/grok-executor" "$CODEX_HOME/skills/"
  echo "  + provisional Grok builder skill -> $CODEX_HOME/skills/grok-executor/"
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
