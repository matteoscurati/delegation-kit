#!/usr/bin/env bash
# Shared core of the text-only OpenAI-compatible chat-completions runners
# (delegation-deepseek, delegation-qwen). Functions only; nothing runs at load.
#
# The provider runner sets these before sourcing this file (after sourcing
# delegation-runner-common.sh):
#
#   RUNNER_NAME       command name, error prefix and temp-dir prefix
#   PROVIDER_LABEL    human label printed by `check`
#   MODEL             exact model id
#   BACKEND           adapter key reported by `check` and in receipts
#   API_URL           chat-completions endpoint
#   API_KEY_VAR       name of the environment variable that carries the key
#   KEY_FILE          mode-600 file holding `API_KEY_VAR=...`
#   DEFAULT_EFFORT    effort used when the caller passes --effort auto
#   BILLING           receipt billing class: api or credits
#
# and may override ROLES (space-separated roles the adapter supports; the
# text-only default below) and EFFORTS (JSON array printed by `check`).
#
# and defines these hooks:
#
#   provider_request_body <prompt_file> <effort> <max_tokens>   required; JSON on stdout
#   provider_validate_key                                        optional; sets
#                                                                PROVIDER_REASON and returns 1 to refuse
#   provider_usage_extra <response>                              optional; JSON object with
#                                                                reasoning and cache_read counts
#   provider_check_extra_json                                    optional; JSON object merged
#                                                                into `check --json`
#   provider_check_extra_text                                    optional; extra `check` lines

RUN_TMP="" RUN_OUTPUT_TMP="" RUN_METRICS_TMP=""
DEBUG_RUN_DIR=""
PROVIDER_REASON="" PROVIDER_KEY_PROBLEM=""
ROLES="${ROLES:-builder clerk scout reviewer senior judgement policy-annotation}"
EFFORTS="${EFFORTS:-[\"minimal\",\"low\",\"medium\",\"high\",\"xhigh\",\"max\"]}"

cleanup_run() {
  [ -z "$RUN_OUTPUT_TMP" ] || rm -f -- "$RUN_OUTPUT_TMP"
  [ -z "$RUN_METRICS_TMP" ] || rm -f -- "$RUN_METRICS_TMP"
  [ -z "$RUN_TMP" ] || rm -rf -- "$RUN_TMP"
}

# Populate $API_KEY_VAR from the key file unless the environment already has it.
load_key() {
  PROVIDER_KEY_PROBLEM=""
  [ -z "${!API_KEY_VAR:-}" ] || return 0
  [ -f "$KEY_FILE" ] || return 0
  local perms raw
  perms="$(key_file_mode)"
  case "$perms" in ""|?00) ;; *) PROVIDER_KEY_PROBLEM="key file $KEY_FILE is mode $perms; run: chmod 600 $KEY_FILE"; return 0 ;; esac
  raw="$(sed -n 's/^[[:space:]]*\(export[[:space:]][[:space:]]*\)\{0,1\}'"$API_KEY_VAR"'=//p' "$KEY_FILE" 2>/dev/null | head -1)"
  raw="${raw%$'\r'}"; raw="${raw#"${raw%%[![:space:]]*}"}"; raw="${raw%"${raw##*[![:space:]]}"}"
  case "$raw" in \"*\") raw="${raw#\"}"; raw="${raw%\"}" ;; \'*\') raw="${raw#\'}"; raw="${raw%\'}" ;; esac
  if [ -n "$raw" ]; then printf -v "$API_KEY_VAR" '%s' "$raw"; else PROVIDER_KEY_PROBLEM="key file $KEY_FILE holds no $API_KEY_VAR line"; fi
}

runtime_status() {
  PROVIDER_REASON=""
  have curl || { PROVIDER_REASON="curl not on PATH"; return 1; }
  have jq || { PROVIDER_REASON="jq not on PATH"; return 1; }
  [ "${AUTH_OPTIONAL:-0}" != 1 ] || return 0
  load_key
  if [ -z "${!API_KEY_VAR:-}" ]; then PROVIDER_REASON="${PROVIDER_KEY_PROBLEM:-$API_KEY_VAR is unset and $KEY_FILE holds no key}"; return 1; fi
  if declare -F provider_validate_key >/dev/null; then provider_validate_key || return 1; fi
  PROVIDER_REASON="ready"; return 0
}

is_allowed() {
  local role="$1" candidate
  for candidate in $ROLES; do [ "$candidate" != "$role" ] || return 0; done
  return 1
}

preserve_debug() {
  local parent="$1" response_file="$2" stderr_file="$3"
  DEBUG_RUN_DIR=""
  [ -n "$parent" ] || return 0
  DEBUG_RUN_DIR="$(mktemp -d "$parent/$RUNNER_NAME.XXXXXX")" || return 1
  chmod 700 "$DEBUG_RUN_DIR"
  cp "$response_file" "$DEBUG_RUN_DIR/response.json"
  cp "$stderr_file" "$DEBUG_RUN_DIR/stderr.txt"
  chmod 600 "$DEBUG_RUN_DIR/response.json" "$DEBUG_RUN_DIR/stderr.txt"
}

write_diagnostic() {
  local diagnostic="$1" response_file="$2" stderr_file="$3" started="$4"
  local effort="$5" lane="$6" phase="$7" reason="$8" http_code="$9"
  local curl_exit="${10}" debug_path="${11}"
  local parent name tmp finished response_bytes stderr_bytes
  response_bytes="$(wc -c <"$response_file" | tr -d ' ')"
  stderr_bytes="$(wc -c <"$stderr_file" | tr -d ' ')"
  finished="$(date +%s)"
  parent="$(dirname "$diagnostic")"
  name="$(basename "$diagnostic")"
  tmp="$(mktemp "$parent/.$name.XXXXXX")"
  jq -n --arg model "$MODEL" --arg backend "$BACKEND" --arg effort "$effort" \
    --arg lane "$lane" --arg phase "$phase" --arg reason "$reason" \
    --arg http_code "$http_code" --arg debug_dir "$debug_path" \
    --argjson curl_exit "$curl_exit" --argjson response_bytes "$response_bytes" \
    --argjson stderr_bytes "$stderr_bytes" \
    --argjson elapsed_seconds "$((finished - started))" \
    '{schema_version:1,model:$model,backend:$backend,effort:$effort,lane:$lane,
      phase:$phase,reason:$reason,http_code:$http_code,curl_exit_code:$curl_exit,
      response_bytes:$response_bytes,stderr_bytes:$stderr_bytes,
      elapsed_seconds:$elapsed_seconds,
      debug_dir:(if $debug_dir == "" then null else $debug_dir end)}' >"$tmp"
  chmod 600 "$tmp"
  mv "$tmp" "$diagnostic"
}

print_check() {
  local as_json="${1:-0}" ready=false selected=none extra_json='{}' roles
  runtime_status && ready=true || true
  [ "$ready" = true ] && selected="$BACKEND"
  roles="$(printf '%s\n' $ROLES | jq -R . | jq -sc .)"
  if [ "$as_json" = 1 ]; then
    if declare -F provider_check_extra_json >/dev/null; then extra_json="$(provider_check_extra_json)"; fi
    jq -n --arg model "$MODEL" --arg selected "$selected" --arg reason "$PROVIDER_REASON" \
      --arg backend "$BACKEND" --arg default_effort "$DEFAULT_EFFORT" \
      --argjson roles "$roles" --argjson efforts "$EFFORTS" \
      --argjson available "$ready" --argjson extra "$extra_json" \
      '{model:$model,adapter:$backend,roles:$roles,efforts:$efforts,default_effort:$default_effort,selected_backend:$selected}
       + $extra
       + {backends:{($backend):{available:$available,reason:$reason}}}'
  else
    printf '%s: selected=%s roles=%s efforts=%s\n' "$PROVIDER_LABEL" "$selected" "$(printf '%s' "$ROLES" | tr ' ' ',')" "$EFFORTS"
    printf '  %s: %s (%s; default effort=%s)\n' "$BACKEND" "$ready" "$PROVIDER_REASON" "$DEFAULT_EFFORT"
    if declare -F provider_check_extra_text >/dev/null; then provider_check_extra_text; fi
  fi
}

run_command() {
  local lane="" effort=auto backend=auto prompt_file="" output="" workdir="" metrics="" debug_dir=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --lane) lane="${2:-}"; shift 2 ;; --effort) effort="${2:-}"; shift 2 ;;
      --backend) backend="${2:-}"; shift 2 ;; --prompt-file) prompt_file="${2:-}"; shift 2 ;;
      --output) output="${2:-}"; shift 2 ;; --workdir) workdir="${2:-}"; shift 2 ;;
      --metrics) metrics="${2:-}"; shift 2 ;; --debug-dir) debug_dir="${2:-}"; shift 2 ;;
      --allow-provisional) printf "%s\n" "--allow-provisional is deprecated and has no effect" >&2; shift ;;
      -h|--help) usage; exit 0 ;; *) die 64 "unknown run argument: $1" ;;
    esac
  done
  [ -n "$lane" ] || die 64 "--lane is required"
  case "$effort" in auto|none|minimal|low|medium|high|xhigh|max) ;; *) die 64 "invalid effort: $effort" ;; esac
  case "$backend" in auto|"$BACKEND") ;; *) die 64 "invalid backend: $backend" ;; esac
  [ -f "$prompt_file" ] || die 64 "prompt file missing: $prompt_file"
  [ -d "$workdir" ] || die 64 "workdir missing: $workdir"
  [ -n "$output" ] || die 64 "--output is required"
  [ -z "$debug_dir" ] || {
    [ -d "$debug_dir" ] && [ ! -L "$debug_dir" ] || die 64 "debug directory missing or symlinked: $debug_dir"
    debug_dir="$(cd "$debug_dir" && pwd -P)"
  }
  is_allowed "$lane" || die 78 "unsupported role for $BACKEND: $lane"
  backend="$BACKEND"
  [ "$effort" != auto ] || effort="${DELEGATION_PROFILE_EFFORT:-$DEFAULT_EFFORT}"
  if [ "$BACKEND" != openai-compatible ] && [ "$effort" = none ]; then
    die 64 "$MODEL requires thinking; effort none is unsupported"
  fi
  local tmp dispatch_prompt="$prompt_file"
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/$RUNNER_NAME.XXXXXX")"
  RUN_TMP="$tmp"
  trap cleanup_run EXIT
  runtime_status || die 69 "$PROVIDER_REASON"

  metrics="${metrics:-$output.metrics.json}"
  local diagnostic="$output.error.json"
  local output_parent metrics_parent diagnostic_parent output_name metrics_name diagnostic_name
  output_parent="$(dirname "$output")"; output_name="$(basename "$output")"
  metrics_parent="$(dirname "$metrics")"; metrics_name="$(basename "$metrics")"
  diagnostic_parent="$(dirname "$diagnostic")"; diagnostic_name="$(basename "$diagnostic")"
  [ -d "$output_parent" ] || die 64 "output parent directory must already exist: $output_parent"
  [ -d "$metrics_parent" ] || die 64 "metrics parent directory must already exist: $metrics_parent"
  [ -d "$diagnostic_parent" ] || die 64 "diagnostic parent directory must already exist: $diagnostic_parent"
  output="$(cd "$output_parent" && pwd -P)/$output_name"
  metrics="$(cd "$metrics_parent" && pwd -P)/$metrics_name"
  diagnostic="$(cd "$diagnostic_parent" && pwd -P)/$diagnostic_name"
  workdir="$(cd "$workdir" && pwd -P)"
  if [ -n "$debug_dir" ]; then
    case "$debug_dir" in
      "$workdir"|"$workdir"/*) die 64 "non-editing runner debug directory must be outside workdir" ;;
    esac
  fi
  if [ -e "$output" ] || [ -e "$metrics" ] || [ -e "$diagnostic" ]; then
    die 64 "output, metrics, and diagnostic paths must not already exist"
  fi
  if [ -L "$output" ] || [ -L "$metrics" ] || [ -L "$diagnostic" ]; then
    die 64 "output, metrics, and diagnostic paths must not be symlinks"
  fi
  local norm_output norm_metrics norm_diagnostic
  norm_output="$(normalized_destination "$output")"
  norm_metrics="$(normalized_destination "$metrics")"
  norm_diagnostic="$(normalized_destination "$diagnostic")"
  [ "$norm_output" != "$norm_metrics" ] || die 64 "output and metrics paths resolve to the same file"
  [ "$norm_output" != "$norm_diagnostic" ] && [ "$norm_metrics" != "$norm_diagnostic" ] \
    || die 64 "path collides with reserved diagnostic path"
  case "$output" in "$workdir"/*) die 64 "non-editing runner output must be outside workdir" ;; esac
  case "$metrics" in "$workdir"/*) die 64 "non-editing runner metrics must be outside workdir" ;; esac
  case "$diagnostic" in "$workdir"/*) die 64 "non-editing runner diagnostic must be outside workdir" ;; esac

  local body response stderr_file http_code started curl_rc=0 curl_config provider_model=""
  local phase="" reason="" final_rc=0
  body="$tmp/request.json"; response="$tmp/response.json"; stderr_file="$tmp/stderr"
  curl_config="$tmp/curl.conf"; started="$(date +%s)"
  : >"$response"; : >"$stderr_file"
  RUN_OUTPUT_TMP="$(mktemp "$output_parent/.$output_name.XXXXXX")"
  RUN_METRICS_TMP="$(mktemp "$metrics_parent/.$metrics_name.XXXXXX")"
  local max_tokens="${DELEGATION_MAX_TOKENS:-4096}"
  provider_request_body "$dispatch_prompt" "$effort" "$max_tokens" >"$body"
  # Keep the bearer token out of the process argv. The runner-wide umask makes
  # this transient curl config mode 600, and the EXIT trap removes it.
  printf 'header = "Content-Type: application/json"\n' >"$curl_config"
  if [ -n "${!API_KEY_VAR:-}" ]; then
    case "${!API_KEY_VAR}" in *$'\n'*|*$'\r'*|*'"'*|*'\'*) die 64 "invalid credential characters" ;; esac
    printf 'header = "Authorization: Bearer %s"\n' "${!API_KEY_VAR}" >>"$curl_config"
  fi
  local max_time="${DELEGATION_TIMEOUT:-600}"
  http_code="$(curl -q --config "$curl_config" -sS -o "$response" -w '%{http_code}' \
    --connect-timeout 20 --max-time "$max_time" --data-binary "@$body" "$API_URL" 2>"$stderr_file")" || curl_rc=$?
  if [ "$curl_rc" -ne 0 ]; then
    http_code=000; phase=dispatch; reason=transport_failure; final_rc=75
    # curl exit 28 is the --max-time deadline; report it distinctly so a bound
    # timeout is not collapsed into a generic transport failure.
    [ "$curl_rc" -ne 28 ] || reason=deadline_exceeded
  else
    case "$http_code" in
      200) ;;
      401|403) phase=dispatch; reason=authentication_failed; final_rc=69 ;;
      429) phase=dispatch; reason=rate_limited; final_rc=75 ;;
      5??) phase=dispatch; reason=provider_temporary_failure; final_rc=75 ;;
      *) phase=dispatch; reason=provider_error; final_rc=70 ;;
    esac
  fi
  local identity_source=requested-only
  if [ "$final_rc" -eq 0 ]; then
    if ! jq -e 'type == "object" and (.model == null or (.model | type == "string"))' "$response" >/dev/null 2>&1; then
      phase=extract; reason=invalid_or_empty_response; final_rc=70
    else
      provider_model="$(jq -r '.model // empty' "$response")"
      if [ -n "$provider_model" ]; then
        if [ "$provider_model" = "$MODEL" ] || jq -en --arg m "$provider_model" --argjson aliases "${DELEGATION_MODEL_ALIASES:-[]}" '$aliases | index($m) != null' >/dev/null; then
          identity_source=provider-reported
        else
          phase=extract; reason=provider_identity_mismatch; final_rc=70
        fi
      fi
    fi
  fi
  if [ "$final_rc" -eq 0 ] && [ "$(jq -r '.choices[0].finish_reason // empty' "$response")" = length ]; then
    phase=extract; reason=output_truncated; final_rc=70
  fi
  if [ "$final_rc" -eq 0 ] && ! jq -e '
    (.choices[0].message.tool_calls // [] | length == 0) and
    (.choices[0].finish_reason == null or .choices[0].finish_reason == "stop") and
    ([.usage.prompt_tokens?, .usage.completion_tokens?] |
      all(.[]; . == null or (type == "number" and . >= 0)))
  ' "$response" >/dev/null 2>&1; then
    phase=extract; reason=invalid_or_empty_response; final_rc=70
  fi
  if [ "$final_rc" -eq 0 ] && ! jq -er \
    '.choices[0].message.content | select(type == "string" and length > 0)' \
    "$response" >"$RUN_OUTPUT_TMP"; then
    phase=extract; reason=invalid_or_empty_response; final_rc=70
  fi
  local usage_extra='{"reasoning":0,"cache_read":0}'
  if [ "$final_rc" -eq 0 ] && declare -F provider_usage_extra >/dev/null; then
    usage_extra="$(provider_usage_extra "$response")" || usage_extra='{"reasoning":0,"cache_read":0}'
  fi
  if [ "$final_rc" -eq 0 ] && ! jq -n --arg model "$provider_model" --arg requested_model "$MODEL" --arg identity_source "$identity_source" --arg effort "$effort" \
    --arg lane "$lane" --arg backend "$BACKEND" --arg billing "$BILLING" --argjson started "$started" \
    --argjson input "$(jq '.usage.prompt_tokens // 0' "$response")" \
    --argjson output_tokens "$(jq '.usage.completion_tokens // 0' "$response")" \
    --argjson usage_extra "$usage_extra" \
    '{schema_version:2,model:$requested_model,requested_model:$requested_model,provider_reported_model:(if $model == "" then null else $model end),model_identity_source:$identity_source,backend:$backend,effort:$effort,lane:$lane,
      started_at_epoch:$started,finished_at_epoch:now,billing:$billing,
      provider_cost_usd:null,tokens:{input:$input,output:$output_tokens,
      reasoning:($usage_extra.reasoning // 0),cache_read:($usage_extra.cache_read // 0),cache_write:0}}' >"$RUN_METRICS_TMP"; then
    phase=extract; reason=metrics_write_failed; final_rc=70
  fi
  if [ "$final_rc" -eq 0 ]; then
    if ! mv "$RUN_OUTPUT_TMP" "$output"; then
      rm -f -- "$output"
      phase=publish; reason=output_publish_failed; final_rc=70
    else
      RUN_OUTPUT_TMP=""
      if ! mv "$RUN_METRICS_TMP" "$metrics"; then
        rm -f -- "$output" "$metrics"
        phase=publish; reason=metrics_publish_failed; final_rc=70
      else
        RUN_METRICS_TMP=""
      fi
    fi
  fi
  if [ "$final_rc" -ne 0 ]; then
    preserve_debug "$debug_dir" "$response" "$stderr_file" || DEBUG_RUN_DIR=""
    write_diagnostic "$diagnostic" "$response" "$stderr_file" "$started" \
      "$effort" "$lane" "$phase" "$reason" "$http_code" "$curl_rc" "$DEBUG_RUN_DIR"
    if [ -n "$DEBUG_RUN_DIR" ]; then
      cp "$diagnostic" "$DEBUG_RUN_DIR/diagnostic.json" \
        && chmod 600 "$DEBUG_RUN_DIR/diagnostic.json" || true
    fi
    printf '%s: %s (details: %s)\n' "$RUNNER_NAME" "$reason" "$diagnostic" >&2
    exit "$final_rc"
  fi
}

# Shared entry point: runners call this after defining their hooks.
chat_completions_main() {
  case "${1:-}" in
    check) shift; if [ "${1:-}" = --json ]; then print_check 1; else print_check 0; fi ;;
    run) shift; run_command "$@" ;; -h|--help|"") usage ;; *) die 64 "unknown command: $1" ;;
  esac
}
