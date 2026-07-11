#!/usr/bin/env bash
# delegation-kit doctor — verifies the cross-tool bridge is actually WIRED, not
# just written. The failure mode this catches is silent: profiles can be present
# while the always-loaded policy blocks are missing, so neither model ever learns
# it may reach the other. Nothing errors — the bridge just never fires.
#
# Usage: ./doctor.sh [--ping]
#   --ping   also does a live round-trip (real API calls, costs a few tokens per
#            side). Off by default; static checks are free.
# Env overrides (for testing): CLAUDE_HOME (default ~/.claude), CODEX_HOME (~/.codex)
set -uo pipefail
shopt -s nullglob   # unmatched globs vanish instead of staying literal

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
BEGIN="<!-- >>> delegation-kit >>> -->"
DO_PING=0
case "${1:-}" in
  --ping) DO_PING=1 ;;
  # print only the leading header comment block (skip the shebang, stop at first non-comment)
  -h|--help) awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"; exit 0 ;;
  "") ;;
  *) echo "unknown arg: $1" >&2; exit 2 ;;
esac

pass=0; warn=0; fail=0
ok()   { printf '  [ OK ] %s\n' "$1"; pass=$((pass+1)); }
warn() { printf '  [WARN] %s\n' "$1"; warn=$((warn+1)); }
bad()  { printf '  [FAIL] %s\n' "$1"; fail=$((fail+1)); }
info() { printf '  [ .. ] %s\n' "$1"; }
hdr()  { printf '\n== %s ==\n' "$1"; }
have() { command -v "$1" >/dev/null 2>&1; }
# true if a file named $2 exists anywhere under dir $1 (capture avoids SIGPIPE/pipefail)
found_name() { [ -d "$1" ] && [ -n "$(find "$1" -type f -name "$2" 2>/dev/null)" ]; }
found_path() { [ -d "$1" ] && [ -n "$(find "$1" -path "$2" 2>/dev/null)" ]; }

# portable timeout: GNU `timeout`, macOS Homebrew `gtimeout`, else run without one
if have timeout; then _TO="timeout 120"; elif have gtimeout; then _TO="gtimeout 120"; else _TO=""; fi
run_to() { if [ -n "$_TO" ]; then $_TO "$@"; else "$@"; fi; }

# ---- CLIs on PATH + versions ----
hdr "CLIs"
have codex && ok "codex on PATH ($(codex --version 2>&1 | head -1))" \
  || bad "codex NOT on PATH — the Claude->Codex bridge cannot run"
have claude && ok "claude on PATH ($(claude --version 2>&1 | head -1))" \
  || bad "claude NOT on PATH — the Codex->Claude bridge cannot run"

# ---- auth (accept the several ways each tool can be authenticated) ----
hdr "Auth"
if [ -f "$CODEX_HOME/auth.json" ]; then ok "codex authenticated ($CODEX_HOME/auth.json)"
elif [ -n "${OPENAI_API_KEY:-}" ]; then ok "codex authenticated (OPENAI_API_KEY in env)"
else warn "no $CODEX_HOME/auth.json and no \$OPENAI_API_KEY — run: codex login (if the bridge 401s)"; fi
if [ -f "$CLAUDE_HOME/.credentials.json" ]; then ok "claude credentials present (file)"
elif [ "$(uname)" = Darwin ] && security find-generic-password -s "Claude Code-credentials" >/dev/null 2>&1; then
  ok "claude credentials present (macOS Keychain)"
else warn "no $CLAUDE_HOME/.credentials.json and no Keychain item — run 'claude' to log in if the bridge fails"; fi

# ---- Claude side install (direct dir OR plugin cache) ----
hdr "Claude Code install ($CLAUDE_HOME)"
total=0; miss=0; via_plugin=0
for f in "$KIT"/agents/*.md; do
  total=$((total+1)); name="$(basename "$f")"
  if [ -f "$CLAUDE_HOME/agents/$name" ]; then continue; fi
  if found_name "$CLAUDE_HOME/plugins" "$name"; then via_plugin=1; continue; fi
  miss=$((miss+1))
done
if [ "$total" = 0 ]; then bad "no source profiles in $KIT/agents — is this the kit root?"
elif [ "$miss" = 0 ]; then
  [ "$via_plugin" = 1 ] && ok "all $total subagent profiles installed (some via plugin cache)" \
    || ok "all $total subagent profiles installed"
else bad "$miss/$total subagent profile(s) missing from $CLAUDE_HOME/agents/ (and plugin cache) — run ./install.sh or /plugin install"; fi
# skill + the co-located scored table the skill points at
if [ -f "$CLAUDE_HOME/skills/model-routing/SKILL.md" ]; then
  [ -f "$CLAUDE_HOME/skills/model-routing/model-routing.md" ] \
    && ok "model-routing skill installed (+ scored table)" \
    || warn "model-routing skill installed but model-routing.md is missing beside it (dangling pointer) — re-run ./install.sh"
elif found_path "$CLAUDE_HOME/plugins" '*model-routing/SKILL.md'; then
  ok "model-routing skill installed (via plugin cache)"
else bad "model-routing skill missing — run ./install.sh or /plugin install"; fi
# always-loaded policy (the plugin path does NOT install this — install.sh does)
if [ -f "$CLAUDE_HOME/CLAUDE.md" ] && grep -qF "$BEGIN" "$CLAUDE_HOME/CLAUDE.md"; then
  ok "delegation policy registered in CLAUDE.md (@import present)"
else bad "CLAUDE.md has NO delegation-kit block -> Claude->Codex policy is NOT loaded. Run ./install.sh"; fi

# ---- Codex side install ----
hdr "Codex install ($CODEX_HOME)"
total=0; miss=0
for f in "$KIT"/codex/agents/*.toml; do
  total=$((total+1)); [ -f "$CODEX_HOME/agents/$(basename "$f")" ] || miss=$((miss+1))
done
if [ "$total" = 0 ]; then bad "no source profiles in $KIT/codex/agents"
elif [ "$miss" = 0 ]; then ok "all $total native subagent profiles installed"
else bad "$miss/$total native profile(s) missing from $CODEX_HOME/agents/ — run ./install.sh"; fi
total=0; miss=0
for f in "$KIT"/codex/profiles/*.config.toml; do
  total=$((total+1)); [ -f "$CODEX_HOME/$(basename "$f")" ] || miss=$((miss+1))
done
if [ "$total" = 0 ]; then bad "no source profiles in $KIT/codex/profiles"
elif [ "$miss" = 0 ]; then ok "all $total ephemeral -p profiles installed"
else bad "$miss/$total ephemeral profile(s) missing from $CODEX_HOME/ — run ./install.sh"; fi
if [ -f "$CODEX_HOME/AGENTS.md" ] && grep -qF "$BEGIN" "$CODEX_HOME/AGENTS.md"; then
  ok "collaboration policy registered in AGENTS.md"
else bad "AGENTS.md has NO delegation-kit block -> Codex->Claude policy is NOT loaded. Run ./install.sh"; fi

# ---- Codex config: multi_agent + sandbox/network posture ----
hdr "Codex config"
cfg="$CODEX_HOME/config.toml"
if [ -f "$cfg" ]; then
  # strip inline comments and quotes before comparing values
  ma="$(grep -E '^[[:space:]]*multi_agent[[:space:]]*=' "$cfg" | head -1 | sed 's/#.*//; s/.*=[[:space:]]*//; s/[[:space:]]*$//')"
  [ "$ma" = "true" ] && ok "[features] multi_agent = true — native Codex delegation can fire" \
    || warn "multi_agent is not true — Codex cannot spawn its native luna/terra/sol subagents (the cross-tool bridge still works). Merge codex/config.snippet.toml"
  sbx="$(grep -E '^[[:space:]]*sandbox_mode[[:space:]]*=' "$cfg" | head -1 | sed 's/#.*//; s/.*=[[:space:]]*//; s/"//g; s/[[:space:]]*$//')"
  # network may be a plain key or inside an inline table — match the word, then look for true
  netline="$(grep -E 'network_access' "$cfg" | head -1)"
  net=false; printf '%s' "$netline" | grep -q 'true' && net=true
  case "$sbx" in
    danger-full-access) ok "sandbox_mode=danger-full-access — Codex can spawn claude with network" ;;
    workspace-write)
      [ "$net" = true ] && ok "sandbox_mode=workspace-write + network_access=true — Codex->Claude hop OK" \
        || warn "sandbox_mode=workspace-write without network_access=true — 'claude -p' spawned by Codex may be network-blocked; set network_access=true or call the bridge with -s danger-full-access" ;;
    read-only) warn "sandbox_mode=read-only — Codex cannot spawn the claude subprocess; the reverse bridge needs -s workspace-write/full-access at call time" ;;
    "") info "sandbox_mode not set (Codex default applies) — verify network is reachable if Codex->Claude fails" ;;
    *) info "sandbox_mode=$sbx — verify it allows process spawn + network for the claude subprocess" ;;
  esac
else
  warn "no $cfg — Codex defaults apply; merge codex/config.snippet.toml"
fi

# ---- optional: the codex@openai-codex plugin (preferred Claude->Codex path) ----
hdr "codex@openai-codex plugin (recommended for interactive Claude->Codex)"
if [ -n "$(find "$CLAUDE_HOME/plugins" -maxdepth 4 -iname '*codex*' 2>/dev/null)" ]; then
  ok "plugin detected — suggest /codex:review, /codex:transfer (user-run) and the codex:codex-rescue agent for interactive flows"
else
  info "plugin not detected — install with: /plugin marketplace add openai/codex-plugin-cc ; /plugin install codex@openai-codex (raw 'codex exec' still works without it)"
fi

# ---- optional live round-trip ----
if [ "$DO_PING" = 1 ]; then
  hdr "Live round-trip (--ping)"
  [ -z "$_TO" ] && info "no timeout/gtimeout found — running pings without a timeout guard"
  if have codex; then
    out="$(run_to codex exec -s read-only --ephemeral -p terra-scout "Reply with exactly the single word: PONG and nothing else." </dev/null 2>/dev/null)"
    printf '%s' "$out" | grep -q PONG && ok "Claude->Codex round-trip returned PONG (traverses codex exec)" || bad "Claude->Codex ping failed (no PONG)"
  fi
  if have claude; then
    out="$(run_to claude -p "Reply with exactly the single word: PONG and nothing else." --model sonnet --effort low --permission-mode plan </dev/null 2>/dev/null)"
    printf '%s' "$out" | grep -q PONG \
      && ok "Claude CLI endpoint OK (Anthropic side reachable, model+effort accepted) — the Codex->Claude *hop* is gated by the sandbox check above, not by this call" \
      || bad "claude CLI ping failed (no PONG)"
  fi
else
  hdr "Live round-trip"
  info "skipped — re-run with ./doctor.sh --ping to make real calls (costs a few tokens per side)"
fi

# ---- verdict ----
printf '\n== Summary: %d OK, %d WARN, %d FAIL ==\n' "$pass" "$warn" "$fail"
if [ "$fail" -gt 0 ]; then
  echo "Bridge is NOT fully operational. Most FAILs are fixed by: ./install.sh"
  exit 1
fi
[ "$warn" -gt 0 ] && echo "Bridge is wired; review WARNs above." || echo "Bridge fully wired."
exit 0
