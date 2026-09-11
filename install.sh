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

# Preserve edits made after the first managed installation. The initial host
# profile is backed up once before migration, independently of the config backup.
copy_managed() {
  python3 - "$1" "$2" "$DATA_HOME" <<'PYMANAGED'
import hashlib, json, os, shutil, sys, tempfile
from pathlib import Path
source, target, data = map(Path, sys.argv[1:])
data.mkdir(parents=True, exist_ok=True)
manifest = data / 'managed-profile-hashes.json'
hashes = json.loads(manifest.read_text()) if manifest.exists() else {}
key = str(target)
if target.exists() and key in hashes and hashlib.sha256(target.read_bytes()).hexdigest() != hashes[key]:
    print('  + preserved edited profile: ' + key)
    sys.exit(0)
if target.exists() and key not in hashes:
    backup = Path(str(target) + '.pre-config-v1.bak')
    if not backup.exists(): shutil.copy2(target, backup)
shutil.copy2(source, target)
hashes[key] = hashlib.sha256(target.read_bytes()).hexdigest()
fd, temporary = tempfile.mkstemp(dir=data, prefix='.managed-profile-')
with os.fdopen(fd, 'w') as stream: json.dump(hashes, stream)
os.replace(temporary, manifest)
PYMANAGED
}

# Snapshot legacy configuration before updating any distributed files. User
# configuration lives separately and an existing v1 file is never overwritten.
"$KIT/bin/delegation-config" init

# Shared optional external-model bridges. Installing a command does not make its
# model routable: the runtime check and versioned evaluation manifest must pass.
mkdir -p "$BIN_HOME" "$DATA_HOME/bin" "$DATA_HOME/bin/lib" "$DATA_HOME/config"
# The runners resolve their own symlink back to $DATA_HOME/bin and source the
# shared helpers from the sibling lib/ directory, so the library is installed
# before any runner and is never linked onto PATH.
cp "$KIT"/bin/lib/*.sh "$DATA_HOME/bin/lib/"
cp "$KIT/bin/lib/delegation_config.py" "$DATA_HOME/bin/lib/"
for command in delegation-config delegation-run delegation-openai-compatible; do
  cp "$KIT/bin/$command" "$DATA_HOME/bin/$command"
  chmod 755 "$DATA_HOME/bin/$command"
  ln -sfn "$DATA_HOME/bin/$command" "$BIN_HOME/$command"
done
"$KIT/bin/delegation-config" apply

chmod 644 "$DATA_HOME"/bin/lib/*.sh
echo "Shared runner library -> $DATA_HOME/bin/lib (sourced by the external runners; not on PATH)"
# Routing gates, executor contract, evidence snapshot, and the schema compiler
# shipped until 0.24.0. The personal configuration replaced them; remove the
# installed copies and the commands that read them.
rm -f -- "$DATA_HOME"/config/*-routing.json \
  "$DATA_HOME/config/routing-gates.json" \
  "$DATA_HOME/config/external-executor-contract.json" \
  "$DATA_HOME/config/model-evidence.json"
for retired in delegation-schema delegation-evidence delegation-epoch delegation-executor-contract; do
  rm -f -- "$DATA_HOME/bin/$retired" "$BIN_HOME/$retired"
done
echo "Retired routing gates, executor contract, evidence, and schema commands removed from $DATA_HOME"
cp "$KIT/bin/delegation-glm" "$DATA_HOME/bin/delegation-glm"
chmod 755 "$DATA_HOME/bin/delegation-glm"
ln -sfn "$DATA_HOME/bin/delegation-glm" "$BIN_HOME/delegation-glm"
echo "GLM bridge -> $BIN_HOME/delegation-glm"

# GLM's only transport is the Z.AI API, so without a key the lane is dead. Ask
# once, interactively, and never overwrite an existing key without consent.
# Every `read` is guarded: unguarded, an EOF (Ctrl-D, or a piped installer) would
# trip errexit and silently abandon the rest of the install — Kimi bridge,
# profiles and all.
# uninstall.sh keeps each key file as $DATA_HOME.<name>.env.bak. A later
# install used to ask again and never look there, so a key could sit in the
# backup for days while the runner reported it missing. Restore it first.
restore_key_backup() { # $1=name (zai | qwen-token-plan | deepseek)
  local target="$DATA_HOME/config/$1.env" backup="$DATA_HOME.$1.env.bak"
  [ ! -f "$target" ] && [ -f "$backup" ] && [ ! -L "$backup" ] || return 0
  ( umask 077; cp "$backup" "$target" ) && chmod 600 "$target" || return 0
  echo "  + $1 key restored from $backup (mode 600)"
}
restore_key_backup zai
restore_key_backup qwen-token-plan
restore_key_backup deepseek
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
    printf '  Z.AI API key for GLM-5.3-Flash (input hidden, Enter to skip): '
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
chmod 755 "$DATA_HOME/bin/delegation-kimi"
ln -sfn "$DATA_HOME/bin/delegation-kimi" "$BIN_HOME/delegation-kimi"
echo "Kimi bridge -> $BIN_HOME/delegation-kimi"
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

for runner in delegation-gemini delegation-qwen delegation-deepseek delegation-grok; do
  cp "$KIT/bin/$runner" "$DATA_HOME/bin/$runner"
  chmod 755 "$DATA_HOME/bin/$runner"
  ln -sfn "$DATA_HOME/bin/$runner" "$BIN_HOME/$runner"
done
echo "Gemini bridge -> $BIN_HOME/delegation-gemini"
echo "Qwen bridge -> $BIN_HOME/delegation-qwen"
echo "DeepSeek bridge -> $BIN_HOME/delegation-deepseek"
echo "Grok bridge -> $BIN_HOME/delegation-grok"

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

# DeepSeek credentials belong to this bridge. Never copy a key from
# ai-consultants or another tool silently; accept an explicit environment value
# or ask once, preserving an existing mode-600 file by default.
DEEPSEEK_KEY_FILE="$DATA_HOME/config/deepseek.env"
deepseek_store_key() { # $1=key
  ( umask 077; printf 'DEEPSEEK_API_KEY=%s\n' "$1" >"$DEEPSEEK_KEY_FILE" )
  chmod 600 "$DEEPSEEK_KEY_FILE"
  echo "  + DeepSeek API key stored in $DEEPSEEK_KEY_FILE (mode 600)"
}
deepseek_ask=1
if [ -f "$DEEPSEEK_KEY_FILE" ]; then
  if [ ! -t 0 ]; then
    echo "  + DeepSeek API key already stored in $DEEPSEEK_KEY_FILE"
    deepseek_ask=0
  else
    printf '  DeepSeek API key already stored in %s. Replace it? [y/N] ' "$DEEPSEEK_KEY_FILE"
    read -r deepseek_replace || deepseek_replace=""
    case "$deepseek_replace" in [yY]*) ;; *) deepseek_ask=0 ;; esac
  fi
fi
if [ "$deepseek_ask" = 1 ]; then
  if [ -n "${DEEPSEEK_API_KEY:-}" ]; then
    if [ ! -t 0 ]; then deepseek_store_key "$DEEPSEEK_API_KEY"
    else
      printf '  Store DEEPSEEK_API_KEY in %s? [Y/n] ' "$DEEPSEEK_KEY_FILE"
      read -r deepseek_use_env || deepseek_use_env=""
      case "$deepseek_use_env" in [nN]*) echo "  ! not stored — DeepSeek works only where the variable is exported" ;; *) deepseek_store_key "$DEEPSEEK_API_KEY" ;; esac
    fi
  elif [ ! -t 0 ]; then
    echo "  ! no DeepSeek API key configured — provisional runtime stays unavailable"
  else
    printf '  DeepSeek API key (input hidden, Enter to skip): '
    read -rs deepseek_key || deepseek_key=""; printf '\n'
    case "$deepseek_key" in "") echo "  ! skipped — DeepSeek provisional runtime stays unavailable" ;; *) deepseek_store_key "$deepseek_key" ;; esac
    unset deepseek_key
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

# Read-only route discovery over the personal configuration.
cp "$KIT/bin/delegation-route" "$DATA_HOME/bin/delegation-route"
chmod 755 "$DATA_HOME/bin/delegation-route"
ln -sfn "$DATA_HOME/bin/delegation-route" "$BIN_HOME/delegation-route"
echo "Route discovery -> $BIN_HOME/delegation-route (reads the personal configuration)"

# The read-only patch verifier for text-patch adapters, and the versioned
# policy it enforces. The verifier validates and describes a patch; it never
# applies one — the lead remains the only actor that applies and tests.
cp "$KIT/bin/delegation-patch-verify" "$DATA_HOME/bin/delegation-patch-verify"
cp "$KIT/config/external-patch-policy.json" \
  "$DATA_HOME/config/external-patch-policy.json"
chmod 755 "$DATA_HOME/bin/delegation-patch-verify"
ln -sfn "$DATA_HOME/bin/delegation-patch-verify" "$BIN_HOME/delegation-patch-verify"
echo "Patch verifier -> $BIN_HOME/delegation-patch-verify (policy: $DATA_HOME/config/external-patch-policy.json; validates only, the lead applies)"

# A vendor auto-update replaces the ambient Grok CLI and prunes its own download
# cache. Validate/retain the archive only after the runners and the router
# have been installed.
if grok_pin_out="$(DELEGATION_DATA_HOME="$DATA_HOME" "$DATA_HOME/bin/delegation-grok" pin 2>&1)"; then
  printf '  + %s\n' "$(printf '%s\n' "$grok_pin_out" | head -1)"
elif grok_check_out="$(DELEGATION_DATA_HOME="$DATA_HOME" "$DATA_HOME/bin/delegation-grok" check --json 2>/dev/null)" \
    && printf '%s' "$grok_check_out" | jq -e '.runtime_cli_source == "pinned"' >/dev/null 2>&1; then
  # The archive is retained whether or not the runtime is usable right now; a
  # symlinked runtime socket or a logged-out CLI is reported by doctor, not here.
  echo "  + existing compatible Grok Build CLI archive retained"
else
  echo "  ! compatible Grok Build CLI not archived — run 'delegation-grok pin --from <path>'"
fi

if [ "$do_claude" = 1 ]; then
  echo "Claude Code -> $CLAUDE_HOME"
  mkdir -p "$CLAUDE_HOME/agents" "$CLAUDE_HOME/skills"
  # Remove the profile retired by the 2026-08-17 owner routing decision. A plain
  # glob copy cannot remove a stale name left by an older installation.
  rm -f "$CLAUDE_HOME/agents/sonnet-builder.md"
  for profile in "$KIT"/agents/*.md; do copy_managed "$profile" "$CLAUDE_HOME/agents/$(basename "$profile")"; done
  echo "  + 6 subagent profiles -> $CLAUDE_HOME/agents/"
  # register the user-direction guard first — it is the linchpin, so a missing
  # optional skill source below cannot abort install (set -e) before the bridge
  # is wired. append_guarded replaces any older guarded block (including a
  # previous orchestration policy) during the upgrade.
  append_guarded "$CLAUDE_HOME/CLAUDE.md" "@$KIT/claude/CLAUDE.delegation.md"
  cp -R "$KIT/skills/model-routing" "$CLAUDE_HOME/skills/"
  cp "$KIT/model-routing.md" "$CLAUDE_HOME/skills/model-routing/"   # co-locate the advisory policy so the skill's pointer resolves
  echo "  + model-routing skill (+ advisory policy) -> $CLAUDE_HOME/skills/model-routing/"
  cp -R "$KIT/skills/orchestrate" "$CLAUDE_HOME/skills/"
  echo "  + orchestrate skill -> $CLAUDE_HOME/skills/orchestrate/"
  cp -R "$KIT/skills/glm-executor" "$CLAUDE_HOME/skills/"
  echo "  + optional GLM executor skill -> $CLAUDE_HOME/skills/glm-executor/"
  cp -R "$KIT/skills/kimi-executor" "$CLAUDE_HOME/skills/"
  echo "  + optional Kimi executor skill -> $CLAUDE_HOME/skills/kimi-executor/"
  cp -R "$KIT/skills/gemini-executor" "$CLAUDE_HOME/skills/"
  echo "  + optional Gemini executor skill -> $CLAUDE_HOME/skills/gemini-executor/"
  cp -R "$KIT/skills/deepseek-executor" "$CLAUDE_HOME/skills/"
  echo "  + provisional DeepSeek builder skill -> $CLAUDE_HOME/skills/deepseek-executor/"
  cp -R "$KIT/skills/qwen-executor" "$CLAUDE_HOME/skills/"
  echo "  + provisional Qwen builder skill -> $CLAUDE_HOME/skills/qwen-executor/"
  cp -R "$KIT/skills/grok-executor" "$CLAUDE_HOME/skills/"
  echo "  + provisional Grok builder skill -> $CLAUDE_HOME/skills/grok-executor/"
fi

if [ "$do_codex" = 1 ]; then
  echo "Codex -> $CODEX_HOME"
  mkdir -p "$CODEX_HOME/agents" "$CODEX_HOME/skills"
  rm -f "$CODEX_HOME/agents/terra-scout.toml" "$CODEX_HOME/terra-scout.config.toml"
  for profile in "$KIT"/codex/agents/*.toml; do copy_managed "$profile" "$CODEX_HOME/agents/$(basename "$profile")"; done
  echo "  + 5 native subagent profiles -> $CODEX_HOME/agents/"
  for profile in "$KIT"/codex/profiles/*.config.toml; do copy_managed "$profile" "$CODEX_HOME/$(basename "$profile")"; done
  echo "  + 5 ephemeral -p profiles -> $CODEX_HOME/"
  cp -R "$KIT/skills/glm-executor" "$CODEX_HOME/skills/"
  echo "  + optional GLM executor skill -> $CODEX_HOME/skills/glm-executor/"
  cp -R "$KIT/skills/kimi-executor" "$CODEX_HOME/skills/"
  echo "  + optional Kimi executor skill -> $CODEX_HOME/skills/kimi-executor/"
  cp -R "$KIT/skills/gemini-executor" "$CODEX_HOME/skills/"
  echo "  + optional Gemini executor skill -> $CODEX_HOME/skills/gemini-executor/"
  cp -R "$KIT/skills/deepseek-executor" "$CODEX_HOME/skills/"
  echo "  + provisional DeepSeek builder skill -> $CODEX_HOME/skills/deepseek-executor/"
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

# Written last, so the marker exists only if the install reached the end. It is
# what lets doctor.sh answer "is this machine running the current kit?" without
# a manual byte-for-byte comparison of every installed file.
VERSION_FILE="$DATA_HOME/installed-version.json"
kit_version="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
  "$KIT/.claude-plugin/plugin.json" | head -1)"
kit_commit=""; kit_dirty=false
if git -C "$KIT" rev-parse --git-dir >/dev/null 2>&1; then
  kit_commit="$(git -C "$KIT" rev-parse HEAD 2>/dev/null || true)"
  # A dirty source means the commit does not fully describe what was installed.
  [ -z "$(git -C "$KIT" status --porcelain 2>/dev/null)" ] || kit_dirty=true
fi
install_scope=claude+codex
[ "$do_claude" = 1 ] || install_scope=codex-only
[ "$do_codex" = 1 ] || install_scope=claude-only
if command -v jq >/dev/null 2>&1; then
  jq -n --arg version "$kit_version" --arg commit "$kit_commit" \
    --arg source "$KIT" --arg scope "$install_scope" \
    --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson dirty "$kit_dirty" \
    '{schema_version:1,version:$version,
      commit:(if $commit == "" then null else $commit end),
      commit_dirty:$dirty,source:$source,scope:$scope,installed_at:$at}' \
    >"$VERSION_FILE"
else
  printf '{"schema_version":1,"version":"%s","commit":%s,"commit_dirty":%s,"source":"%s","scope":"%s","installed_at":"%s"}\n' \
    "$kit_version" \
    "$([ -n "$kit_commit" ] && printf '"%s"' "$kit_commit" || printf 'null')" \
    "$kit_dirty" "$KIT" "$install_scope" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    >"$VERSION_FILE"
fi
echo
echo "Installed version marker -> $VERSION_FILE (${kit_version:-unknown}$([ "$kit_dirty" = true ] && echo ', from a dirty checkout'))"

echo
echo "Done. Restart Claude Code / open a new Codex session to pick up the changes."
echo "Verify the bridge is wired:  $KIT/doctor.sh   (add --ping for a live round-trip)"
echo "Adapt the models to your own tiers: see $KIT/ADAPTING.md"
