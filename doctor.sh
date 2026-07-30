#!/usr/bin/env bash
# delegation-kit doctor — verifies the cross-tool bridge is actually WIRED, not
# just written. The failure mode this catches is silent: profiles can be present
# while the always-loaded policy blocks are missing, so neither model ever learns
# it may reach the other. Nothing errors — the bridge just never fires.
#
# Usage: ./doctor.sh [--ping] [--ping-glm] [--ping-kimi] [--ping-grok]
#   --ping   also does a live round-trip (real API calls, costs a few tokens per
#            side). Off by default; static checks are free.
#   --ping-glm does a separate paid GLM-5.2 ping, but only for a qualified lane.
#   --ping-kimi does a separate Kimi K3 ping, but only for a qualified lane.
#   --ping-grok does a paid Grok 4.5 ping through its provisional builder gate.
# Env overrides (for testing): CLAUDE_HOME (default ~/.claude), CODEX_HOME (~/.codex),
#   DELEGATION_DATA_HOME (~/.local/share/delegation-kit)
set -uo pipefail
shopt -s nullglob   # unmatched globs vanish instead of staying literal
# CONVENTION — never test a search as `find … | grep -q` under `pipefail`: grep -q exits
# on the first match and closes the pipe, find takes SIGPIPE and exits non-zero, and
# pipefail reads that as failure — a false negative that appears only once the output
# fills the pipe buffer (a real, large tree; not in tests). Capture and test instead:
# `[ -n "$(find …)" ]`, or a pure-bash `case`, like found_name/found_path below.

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
DATA_HOME="${DELEGATION_DATA_HOME:-$HOME/.local/share/delegation-kit}"
BEGIN="<!-- >>> delegation-kit >>> -->"
DO_PING=0
DO_GLM_PING=0
DO_KIMI_PING=0
DO_GROK_PING=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --ping) DO_PING=1 ;;
    --ping-glm) DO_GLM_PING=1 ;;
    --ping-kimi) DO_KIMI_PING=1 ;;
    --ping-grok) DO_GROK_PING=1 ;;
    # print only the leading header comment block (skip the shebang, stop at first non-comment)
    -h|--help) awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

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
elif [ -n "${ANTHROPIC_API_KEY:-}" ]; then ok "claude authenticated (ANTHROPIC_API_KEY in env)"
elif [ "$(uname)" = Darwin ] && security find-generic-password -s "Claude Code-credentials" >/dev/null 2>&1; then
  ok "claude credentials present (macOS Keychain)"
else warn "no $CLAUDE_HOME/.credentials.json, no \$ANTHROPIC_API_KEY, and no Keychain item — run 'claude' to log in if the bridge fails"; fi

# ---- Claude side install (direct dir OR plugin cache) ----
hdr "Claude Code install ($CLAUDE_HOME)"
total=0; miss=0; via_plugin=0
# One walk of the plugin cache up front, instead of a fresh find per missing agent.
# This broad inventory is only a presence check; exact profile validation below
# resolves a direct install or a plugin listed as active by Claude Code.
plugin_md=""; [ -d "$CLAUDE_HOME/plugins" ] && plugin_md="$(find "$CLAUDE_HOME/plugins" -type f -name '*.md' 2>/dev/null)"
for f in "$KIT"/agents/*.md; do
  total=$((total+1)); name="$(basename "$f")"
  if [ -f "$CLAUDE_HOME/agents/$name" ]; then continue; fi
  # pure-bash substring test — a `printf | grep -q` pipe would SIGPIPE find/printf on
  # early match under `set -o pipefail`, a flaky false-miss on a large plugin tree
  case "$plugin_md" in *"/$name"*) via_plugin=1; continue ;; esac
  miss=$((miss+1))
done
if [ "$total" = 0 ]; then bad "no source profiles in $KIT/agents — is this the kit root?"
elif [ "$miss" = 0 ]; then
  [ "$via_plugin" = 1 ] && ok "all $total subagent profiles installed (some via plugin cache)" \
    || ok "all $total subagent profiles installed"
else bad "$miss/$total subagent profile(s) missing from $CLAUDE_HOME/agents/ (and plugin cache) — run ./install.sh or /plugin install"; fi
opus_profile=""
if [ -f "$CLAUDE_HOME/agents/opus-reviewer.md" ]; then
  opus_profile="$CLAUDE_HOME/agents/opus-reviewer.md"
elif have jq && [ -r "$CLAUDE_HOME/plugins/installed_plugins.json" ]; then
  while IFS= read -r plugin_root; do
    candidate="$plugin_root/agents/opus-reviewer.md"
    if [ -f "$candidate" ]; then opus_profile="$candidate"; break; fi
  done < <(jq -r '.plugins[][]? | .installPath // empty' "$CLAUDE_HOME/plugins/installed_plugins.json" 2>/dev/null)
fi
if [ -z "$opus_profile" ]; then
  bad "cannot resolve the active opus-reviewer profile — run ./install.sh or reinstall the plugin"
elif grep -Fxq 'model: claude-opus-5' "$opus_profile" \
    && grep -Fxq 'effort: high' "$opus_profile" \
    && grep -Fq 'Opus 5 senior reviewer' "$opus_profile"; then
  ok "opus-reviewer pinned to claude-opus-5/high"
else
  bad "active opus-reviewer is stale or not pinned to claude-opus-5/high — re-run ./install.sh"
fi
# skill + the co-located evidence-backed policy the skill points at
if [ -f "$CLAUDE_HOME/skills/model-routing/SKILL.md" ]; then
  [ -f "$CLAUDE_HOME/skills/model-routing/model-routing.md" ] \
    && ok "model-routing skill installed (+ evidence-backed policy)" \
    || warn "model-routing skill installed but model-routing.md is missing beside it (dangling pointer) — re-run ./install.sh"
elif found_path "$CLAUDE_HOME/plugins" '*model-routing/SKILL.md'; then
  if found_path "$CLAUDE_HOME/plugins" '*model-routing/model-routing.md'; then
    ok "model-routing skill installed (via plugin cache, + evidence-backed policy)"
  else
    warn "model-routing skill installed via plugin cache, but model-routing.md is not beside it — the skill's pointer dangles; run ./install.sh to co-locate it (the policy also lives at the kit root)"
  fi
else bad "model-routing skill missing — run ./install.sh or /plugin install"; fi
# orchestrate skill (the fan-out loop runbook; optional add-on to the routing policy)
if [ -f "$CLAUDE_HOME/skills/orchestrate/SKILL.md" ]; then
  ok "orchestrate skill installed"
elif found_path "$CLAUDE_HOME/plugins" '*orchestrate/SKILL.md'; then
  ok "orchestrate skill installed (via plugin cache)"
else warn "orchestrate skill missing — run ./install.sh or /plugin install to get the fan-out loop"; fi
if [ -f "$CLAUDE_HOME/skills/glm-executor/SKILL.md" ]; then
  ok "optional GLM executor skill installed"
elif found_path "$CLAUDE_HOME/plugins" '*glm-executor/SKILL.md'; then
  ok "optional GLM executor skill installed (via plugin cache; universal install still required for runner)"
else warn "optional GLM executor skill missing — GLM cannot be selected even after evaluation"; fi
if [ -f "$CLAUDE_HOME/skills/gemini-executor/SKILL.md" ]; then
  ok "optional Gemini executor skill installed"
elif found_path "$CLAUDE_HOME/plugins" '*gemini-executor/SKILL.md'; then
  ok "optional Gemini executor skill installed (via plugin cache; universal install still required for runner)"
else warn "optional Gemini executor skill missing — Gemini cannot be selected even after evaluation"; fi
if [ -f "$CLAUDE_HOME/skills/kimi-executor/SKILL.md" ]; then
  ok "optional Kimi executor skill installed"
elif found_path "$CLAUDE_HOME/plugins" '*kimi-executor/SKILL.md'; then
  ok "optional Kimi executor skill installed (via plugin cache; universal install still required for runner)"
else warn "optional Kimi executor skill missing — Kimi cannot be selected even after evaluation"; fi
if [ -f "$CLAUDE_HOME/skills/qwen-executor/SKILL.md" ]; then
  ok "blocked Qwen candidate skill installed"
elif found_path "$CLAUDE_HOME/plugins" '*qwen-executor/SKILL.md'; then
  ok "blocked Qwen candidate skill installed (via plugin cache; universal install still required for runner)"
else warn "Qwen candidate skill missing — re-run ./install.sh"; fi
if [ -f "$CLAUDE_HOME/skills/grok-executor/SKILL.md" ]; then
  ok "provisional Grok builder skill installed"
elif found_path "$CLAUDE_HOME/plugins" '*grok-executor/SKILL.md'; then
  ok "provisional Grok builder skill installed (via plugin cache; universal install still required for runner)"
else warn "Grok builder skill missing — re-run ./install.sh"; fi
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
if [ -f "$CODEX_HOME/skills/glm-executor/SKILL.md" ]; then
  ok "optional GLM executor skill installed for Codex"
else warn "optional GLM executor skill missing for Codex"; fi
if [ -f "$CODEX_HOME/skills/gemini-executor/SKILL.md" ]; then
  ok "optional Gemini executor skill installed for Codex"
else warn "optional Gemini executor skill missing for Codex"; fi
if [ -f "$CODEX_HOME/skills/kimi-executor/SKILL.md" ]; then
  ok "optional Kimi executor skill installed for Codex"
else warn "optional Kimi executor skill missing for Codex"; fi
if [ -f "$CODEX_HOME/skills/qwen-executor/SKILL.md" ]; then
  ok "blocked Qwen candidate skill installed for Codex"
else warn "Qwen candidate skill missing for Codex"; fi
if [ -f "$CODEX_HOME/skills/grok-executor/SKILL.md" ]; then
  ok "provisional Grok builder skill installed for Codex"
else warn "Grok builder skill missing for Codex"; fi

# ---- external evidence snapshot ----
hdr "Model-routing evidence"
if ! have jq; then
  warn "jq not on PATH — model evidence cannot be validated"
elif have delegation-evidence; then
  evidence_check="$(delegation-evidence check --json 2>/dev/null || true)"
  if [ -n "$evidence_check" ] && printf '%s' "$evidence_check" | jq -e '.valid == true' >/dev/null 2>&1; then
    evidence_age="$(printf '%s' "$evidence_check" | jq -r '.age_days')"
    ok "external model evidence snapshot valid (${evidence_age}d old)"
    info "external evidence is advisory; versioned routing gates remain authoritative"
  else
    warn "model evidence missing, invalid, or stale — refresh/reinstall before changing lane qualifications"
  fi
else
  warn "delegation-evidence not installed — re-run ./install.sh"
fi
if ! have python3; then
  warn "python3 not on PATH — Epoch ZIP evidence cannot be inspected"
elif have delegation-epoch; then
  ok "Epoch ZIP advisory importer installed (live download not run by doctor)"
else
  warn "delegation-epoch not installed — re-run ./install.sh"
fi

hdr "Central routing gates"
if ! have jq; then
  warn "jq not on PATH — central routing gates cannot be validated"
elif have delegation-route; then
  route_check="$(delegation-route check --json 2>/dev/null || true)"
  if [ -n "$route_check" ] && printf '%s' "$route_check" | jq -e '.valid == true and .read_only == true' >/dev/null 2>&1; then
    ok "central routing gates valid ($(printf '%s' "$route_check" | jq -r '.profiles') profiles)"
    info "judgement and super-judgement require explicit selection; the router never dispatches"
  else
    bad "central routing gates are missing or invalid — re-run ./install.sh"
  fi
else
  warn "delegation-route not installed — re-run ./install.sh"
fi

# ---- installed exact evaluation pack (Dipylon AI jury v2) ----
# Static check: the installed runners resolve contract_path/output_schema_path
# relative to $DATA_HOME, so the installed pack must mirror the source pack
# exactly — same six regular non-symlink JSON files, byte-for-byte. Missing,
# extra, symlinked, or divergent members are FAIL, not WARN.
hdr "Dipylon AI jury v2 evaluation pack"
pack_src="$KIT/evaluation/dipylon-ai-jury-v2"
pack_dest="$DATA_HOME/evaluation/dipylon-ai-jury-v2"
# NUL-delimited enumeration throughout: a filename may embed a newline, and
# line-splitting find output would read one such entry as two apparent names —
# which could let an extra destination entry escape the membership check below.
# find's exit status is captured via a mktemp listing file: a plain process
# substitution discards it, and an unreadable directory (find exit 1) would
# otherwise enumerate as an empty — and therefore innocent — set.
pack_src_listing="$(mktemp "${TMPDIR:-/tmp}/delegation-doctor-pack-src.XXXXXX")"
pack_src_enum=0
find "$pack_src" -maxdepth 1 -type f -name '*.json' -print0 >"$pack_src_listing" 2>/dev/null || pack_src_enum=$?
pack_src_files=()
while IFS= read -r -d '' pack_file; do
  pack_src_files+=("$pack_file")
done <"$pack_src_listing"
rm -f "$pack_src_listing"
if [ "$pack_src_enum" -ne 0 ]; then
  bad "cannot enumerate source pack $pack_src (find exit $pack_src_enum) — is this the kit root?"
elif [ "${#pack_src_files[@]}" != 6 ]; then
  bad "source pack $pack_src has ${#pack_src_files[@]} regular JSON files, expected 6 — is this the kit root?"
elif [ -L "$pack_dest" ] || [ ! -d "$pack_dest" ]; then
  bad "evaluation pack not installed at $pack_dest — re-run ./install.sh"
else
  pack_bad=0
  pack_src_names=()
  for pack_file in "${pack_src_files[@]}"; do
    pack_name="$(basename "$pack_file")"
    pack_src_names+=("$pack_name")
    if [ -L "$pack_dest/$pack_name" ]; then
      bad "pack member $pack_name is a symlink — re-run ./install.sh"; pack_bad=1
    elif [ ! -f "$pack_dest/$pack_name" ]; then
      bad "pack member $pack_name is missing — re-run ./install.sh"; pack_bad=1
    elif ! cmp -s "$pack_file" "$pack_dest/$pack_name"; then
      bad "pack member $pack_name diverges from the source — re-run ./install.sh"; pack_bad=1
    fi
  done
  # Same status capture for the destination: with an execute-only (chmod 111)
  # pack directory the member files still compare fine above, but find exits 1
  # on Permission denied — trusting that partial set would let extras pass.
  pack_dest_listing="$(mktemp "${TMPDIR:-/tmp}/delegation-doctor-pack-dest.XXXXXX")"
  pack_dest_enum=0
  find "$pack_dest" -mindepth 1 -maxdepth 1 -print0 >"$pack_dest_listing" 2>/dev/null || pack_dest_enum=$?
  if [ "$pack_dest_enum" -ne 0 ]; then
    rm -f "$pack_dest_listing"
    bad "cannot enumerate installed pack at $pack_dest (find exit $pack_dest_enum) — re-run ./install.sh"; pack_bad=1
  else
    while IFS= read -r -d '' pack_entry; do
      pack_name="$(basename "$pack_entry")"
      pack_known=0
      for pack_src_name in "${pack_src_names[@]}"; do
        [ "$pack_name" = "$pack_src_name" ] && { pack_known=1; break; }
      done
      if [ "$pack_known" = 0 ]; then
        bad "unexpected entry in installed pack: $pack_name — re-run ./install.sh"; pack_bad=1
      fi
    done <"$pack_dest_listing"
    rm -f "$pack_dest_listing"
  fi
  [ "$pack_bad" = 0 ] && ok "evaluation pack installed: 6/6 regular JSON files byte-identical to the source"
fi

# ---- optional GLM-5.2 external executor ----
hdr "GLM-5.2 optional executor"
if ! have jq; then
  warn "jq not on PATH — delegation-glm cannot run"
elif have delegation-glm; then
  glm_check="$(delegation-glm check --json 2>/dev/null || true)"
  if [ -n "$glm_check" ] && printf '%s' "$glm_check" | jq -e '.model == "glm-5.2"' >/dev/null 2>&1; then
    ok "delegation-glm installed and pinned to glm-5.2"
    glm_selected="$(printf '%s' "$glm_check" | jq -r '.selected_backend')"
    glm_lanes="$(printf '%s' "$glm_check" | jq -r '.qualified_lanes | join(",")')"
    glm_provisional="$(printf '%s' "$glm_check" | jq -r '.provisional_lanes | join(",")')"
    [ "$glm_selected" = none ] \
      && info "GLM runtime unavailable — optional lane will not be selected" \
      || ok "GLM backend available ($glm_selected)"
    [ -n "$glm_lanes" ] \
      && ok "GLM evaluation-qualified lanes: $glm_lanes" \
      || info "GLM has no automatically qualified lanes"
    [ -z "$glm_provisional" ] || info "GLM provisional lanes (explicit flag required): $glm_provisional"
  else
    bad "delegation-glm check failed or is not pinned to glm-5.2"
  fi
else
  warn "delegation-glm not installed — re-run ./install.sh after evaluating GLM"
fi

# ---- optional Gemini 3.6 Flash external executor ----
hdr "Gemini 3.6 Flash optional executor"
if ! have jq; then
  warn "jq not on PATH — delegation-gemini cannot run"
elif have delegation-gemini; then
  gemini_check="$(delegation-gemini check --json 2>/dev/null || true)"
  if [ -n "$gemini_check" ] && printf '%s' "$gemini_check" | jq -e '.model == "gemini-3.6-flash"' >/dev/null 2>&1; then
    ok "delegation-gemini installed and pinned to gemini-3.6-flash"
    gemini_selected="$(printf '%s' "$gemini_check" | jq -r '.selected_backend')"
    gemini_lanes="$(printf '%s' "$gemini_check" | jq -r '.qualified_lanes | join(",")')"
    gemini_provisional="$(printf '%s' "$gemini_check" | jq -r '.provisional_lanes | join(",")')"
    [ "$gemini_selected" = none ] \
      && info "Gemini Antigravity runtime unavailable — optional lane will not be selected" \
      || ok "Gemini backend available ($gemini_selected)"
    [ -n "$gemini_lanes" ] \
      && ok "Gemini evaluation-qualified lanes: $gemini_lanes" \
      || info "Gemini has no automatically qualified lanes"
    [ -z "$gemini_provisional" ] || info "Gemini provisional lanes (explicit flag required): $gemini_provisional"
  else
    bad "delegation-gemini check failed or is not pinned to gemini-3.6-flash"
  fi
else
  warn "delegation-gemini not installed — re-run ./install.sh"
fi

# ---- optional Kimi K3 external executor ----
hdr "Kimi K3 optional executor"
if ! have jq; then
  warn "jq not on PATH — delegation-kimi cannot run"
elif have delegation-kimi; then
  kimi_check="$(delegation-kimi check --json 2>/dev/null || true)"
  if [ -n "$kimi_check" ] && printf '%s' "$kimi_check" | jq -e '
      .model == "kimi-k3" and
      (.selected_backend == "native" or .selected_backend == "none") and
      (.backends.native.available == (.selected_backend == "native")) and
      (if .selected_backend == "native"
       then (.runtime_cli_version | type == "string" and length > 0)
       else (.runtime_cli_version == null or
             (.runtime_cli_version | type == "string" and length > 0))
       end) and
      .backends.native.sandbox == "macos-sandbox-exec" and
      .backends.native.isolated_home == true and
      .backends.native.environment_mode == "allowlist" and
      .backends.native.ambient_home_read == false and
      .backends.native.process_exec == false and
      .backends.native.hooks == false and
      .backends.native.services == false and
      .backends.native.builder_write_scope == "workdir" and
      .backends.native.read_only_write_scope == "scratch"
    ' >/dev/null 2>&1; then
    ok "delegation-kimi installed for kimi-k3/max with sandboxed runtime controls"
    kimi_selected="$(printf '%s' "$kimi_check" | jq -r '.selected_backend')"
    kimi_lanes="$(printf '%s' "$kimi_check" | jq -r '.qualified_lanes | join(",")')"
    kimi_provisional="$(printf '%s' "$kimi_check" | jq -r '.provisional_lanes | join(",")')"
    [ "$kimi_selected" = none ] \
      && info "Kimi runtime unavailable — optional lanes will not be selected" \
      || ok "Kimi backend available ($kimi_selected)"
    [ -n "$kimi_lanes" ] \
      && ok "Kimi evaluation-qualified lanes: $kimi_lanes" \
      || info "Kimi has no automatically qualified lanes"
    [ -z "$kimi_provisional" ] || info "Kimi provisional lanes (explicit flag required): $kimi_provisional"
  else
    bad "delegation-kimi check failed or does not enforce the current Kimi sandbox contract"
  fi
else
  warn "delegation-kimi not installed — re-run ./install.sh to install the gated candidate"
fi

# ---- optional Grok 4.5 builder executor ----
hdr "Grok 4.5 builder executor"
if ! have jq; then
  warn "jq not on PATH — delegation-grok cannot run"
elif have delegation-grok; then
  grok_check="$(delegation-grok check --json 2>/dev/null || true)"
  if [ -n "$grok_check" ] && printf '%s' "$grok_check" | jq -e '
      .model == "grok-4.5" and
      .runtime_cli_compatibility == "capability-probed" and
      (.runtime_cli_version | type == "string" and length > 0) and
      .backends["grok-build"].sandbox == "delegation-kit" and
      .backends["grok-build"].permission_mode == "dontAsk" and
      .backends["grok-build"].isolated_home == true and
      .backends["grok-build"].plugins == false and
      .backends["grok-build"].mcp == false and
      .backends["grok-build"].terminal == false and
      .backends["grok-build"].max_turns == 40 and
      .backends["grok-build"].timeout_seconds == 900
    ' >/dev/null 2>&1; then
    ok "delegation-grok installed for grok-4.5/high with capability-probed runtime controls"
    grok_selected="$(printf '%s' "$grok_check" | jq -r '.selected_backend')"
    grok_provisional="$(printf '%s' "$grok_check" | jq -r '.provisional_lanes | join(",")')"
    if [ "$grok_selected" = none ]; then
      info "Grok Build runtime unavailable: $(printf '%s' "$grok_check" | jq -r '.backends["grok-build"].reason')"
    else
      grok_cli_source="$(printf '%s' "$grok_check" | jq -r '.runtime_cli_source')"
      ok "Grok Build backend available ($grok_selected; CLI resolved from $grok_cli_source)"
      [ "$grok_cli_source" = pinned ] \
        || info "the compatible CLI is not privately archived — run 'delegation-grok pin' to preserve the selected bytes"
    fi
    [ -z "$grok_provisional" ] || info "Grok provisional lanes (explicit flag required): $grok_provisional"
  else
    bad "delegation-grok check failed or is not capability-compatible with grok-4.5/high"
  fi
else
  warn "delegation-grok not installed — re-run ./install.sh"
fi

# ---- Qwen3.8 Max Preview blocked candidate ----
hdr "Qwen3.8 Max Preview candidate"
if ! have jq; then
  warn "jq not on PATH — delegation-qwen cannot run"
elif have delegation-qwen; then
  qwen_check="$(delegation-qwen check --json 2>/dev/null || true)"
  if [ -n "$qwen_check" ] && printf '%s' "$qwen_check" | jq -e '.model == "qwen3.8-max-preview"' >/dev/null 2>&1; then
    ok "delegation-qwen installed and pinned to qwen3.8-max-preview"
    qwen_selected="$(printf '%s' "$qwen_check" | jq -r '.selected_backend')"
    qwen_candidates="$(printf '%s' "$qwen_check" | jq -r '.candidate_lanes | join(",")')"
    [ "$qwen_selected" = none ] \
      && info "Qwen Token Plan runtime unavailable" \
      || ok "Qwen Token Plan runtime available ($qwen_selected)"
    info "Qwen remains blocked candidate: ${qwen_candidates:-none}; availability is not qualification"
  else
    bad "delegation-qwen check failed or is not pinned to qwen3.8-max-preview"
  fi
else
  warn "delegation-qwen not installed — re-run ./install.sh to install the blocked candidate"
fi

# ---- Codex config: multi_agent + sandbox/network posture ----
hdr "Codex config"
cfg="$CODEX_HOME/config.toml"
if [ -f "$cfg" ]; then
  # multi_agent may be a [features] table key OR the inline-table form
  # `features = { multi_agent = true }`; strip comments, then require an explicit = true
  ma=false; sed 's/#.*//' "$cfg" | grep -Eq 'multi_agent[[:space:]]*=[[:space:]]*true' && ma=true
  [ "$ma" = true ] && ok "multi_agent = true — native Codex delegation can fire" \
    || warn "multi_agent is not true — Codex cannot spawn its native luna/terra/sol subagents (the cross-tool bridge still works). Merge codex/config.snippet.toml"
  # sandbox_mode is a root-level key: read only the region before the first [table] so a
  # [profiles.*] override isn't mistaken for the effective posture
  sbx="$(sed '/^[[:space:]]*\[/q' "$cfg" | grep -E '^[[:space:]]*sandbox_mode[[:space:]]*=' | head -1 | sed 's/#.*//; s/.*=[[:space:]]*//; s/"//g; s/[[:space:]]*$//')"
  # network_access may be a plain key or inside an inline table; strip comments first and
  # require an explicit = true so a commented reminder never reads as live
  net=false; sed 's/#.*//' "$cfg" | grep -Eq 'network_access[[:space:]]*=[[:space:]]*true' && net=true
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

if [ "$DO_GLM_PING" = 1 ]; then
  hdr "GLM-5.2 live ping (--ping-glm)"
  if ! have delegation-glm; then
    bad "GLM ping unavailable — delegation-glm is not installed"
  else
    glm_check="$(delegation-glm check --json 2>/dev/null || true)"
    glm_lane="$(printf '%s' "$glm_check" | jq -r '.qualified_lanes[0] // empty' 2>/dev/null)"
    if [ -z "$glm_lane" ]; then
      info "skipped — no GLM lane has passed the evaluation gate"
    else
      ping_dir="$(mktemp -d "${TMPDIR:-/tmp}/delegation-glm-ping.XXXXXX")"
      printf 'Reply with exactly PONG and do not edit files.\n' >"$ping_dir/prompt.txt"
      if delegation-glm run --lane "$glm_lane" --effort auto --backend auto \
          --prompt-file "$ping_dir/prompt.txt" --output "$ping_dir/out.txt" --workdir "$ping_dir" \
          >/dev/null 2>&1 && grep -Fxq PONG "$ping_dir/out.txt"; then
        ok "GLM-5.2 qualified-lane ping returned PONG"
      else
        bad "GLM-5.2 ping failed"
      fi
      rm -rf "$ping_dir"
    fi
  fi
fi

if [ "$DO_KIMI_PING" = 1 ]; then
  hdr "Kimi K3 live ping (--ping-kimi)"
  if ! have delegation-kimi; then
    bad "Kimi ping unavailable — delegation-kimi is not installed"
  else
    kimi_check="$(delegation-kimi check --json 2>/dev/null || true)"
    kimi_lane="$(printf '%s' "$kimi_check" | jq -r '
      ([.qualified_lanes[] | select(. != "builder")][0] // .qualified_lanes[0] // empty)
    ' 2>/dev/null)"
    if [ -z "$kimi_lane" ]; then
      info "skipped — no Kimi lane has passed the evaluation gate"
    else
      ping_dir="$(mktemp -d "${TMPDIR:-/tmp}/delegation-kimi-ping.XXXXXX")"
      mkdir -p "$ping_dir/work"
      printf 'Reply with exactly PONG and do not edit files.\n' >"$ping_dir/prompt.txt"
      if delegation-kimi run --lane "$kimi_lane" --effort auto --backend auto \
          --prompt-file "$ping_dir/prompt.txt" --output "$ping_dir/out.txt" --workdir "$ping_dir/work" \
          >/dev/null 2>&1 && grep -Fxq PONG "$ping_dir/out.txt"; then
        ok "Kimi K3 qualified-lane ping returned PONG"
      else
        bad "Kimi K3 ping failed"
      fi
      rm -rf "$ping_dir"
    fi
  fi
fi

if [ "$DO_GROK_PING" = 1 ]; then
  hdr "Grok 4.5 live ping (--ping-grok)"
  if ! have delegation-grok; then
    bad "Grok ping unavailable — delegation-grok is not installed"
  else
    grok_check="$(delegation-grok check --json 2>/dev/null || true)"
    if ! printf '%s' "$grok_check" | jq -e '.provisional_lanes | index("builder") != null' >/dev/null 2>&1; then
      info "skipped — Grok builder lane is not provisional"
    else
      ping_dir="$(mktemp -d "${TMPDIR:-/tmp}/delegation-grok-ping.XXXXXX")"
      mkdir -p "$ping_dir/work" "$ping_dir/results"
      printf 'Reply with exactly PONG and do not edit files.\n' >"$ping_dir/prompt.txt"
      if delegation-grok run --lane builder --allow-provisional \
          --effort auto --backend auto --prompt-file "$ping_dir/prompt.txt" \
          --output "$ping_dir/results/out.txt" --workdir "$ping_dir/work" \
          >/dev/null 2>&1 && grep -Fxq PONG "$ping_dir/results/out.txt"; then
        ok "Grok 4.5 provisional builder ping returned PONG"
      else
        bad "Grok 4.5 ping failed"
      fi
      rm -rf "$ping_dir"
    fi
  fi
fi

# ---- optional: the codex@openai-codex plugin (preferred Claude->Codex path) ----
hdr "codex@openai-codex plugin (recommended for interactive Claude->Codex)"
# match the plugin by its provenance (marketplace codex@openai-codex, repo
# openai/codex-plugin-cc), not a bare 'codex' name — the kit ships its own codex/ dir
# that a '*codex*' match would false-positive on
if [ -n "$(find "$CLAUDE_HOME/plugins" -maxdepth 6 \( -ipath '*openai-codex*' -o -ipath '*codex-plugin-cc*' \) 2>/dev/null)" ]; then
  ok "plugin detected — suggest /codex:review, /codex:transfer (user-run) and the codex:codex-rescue agent for interactive flows"
else
  info "plugin not detected — install with: /plugin marketplace add openai/codex-plugin-cc ; /plugin install codex@openai-codex (raw 'codex exec' still works without it)"
fi

# ---- optional live round-trip ----
if [ "$DO_PING" = 1 ]; then
  hdr "Live round-trip (--ping)"
  [ -z "$_TO" ] && info "no timeout/gtimeout found — running pings without a timeout guard"
  if have codex; then
    if [ -f "$CODEX_HOME/terra-scout.config.toml" ]; then
      # single controlled word, so a raw-stdout grep is acceptable here; the risk the
      # hardening warns about is a mis-pinned profile silently running the default model —
      # guarded above by requiring the profile file to exist
      out="$(run_to codex exec -s read-only --ephemeral -p terra-scout "Reply with exactly the single word: PONG and nothing else." </dev/null 2>/dev/null)"
      printf '%s' "$out" | grep -q PONG && ok "Claude->Codex round-trip returned PONG (traverses codex exec)" || bad "Claude->Codex ping failed (no PONG)"
    else
      warn "skipping Claude->Codex ping — profile $CODEX_HOME/terra-scout.config.toml not installed, so 'codex exec -p terra-scout' would silently fall back to the default model (a false PONG). Run ./install.sh"
    fi
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
