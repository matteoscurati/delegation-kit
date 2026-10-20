#!/usr/bin/env bash
# Helpers shared by the delegation-kit external runners. This file defines
# functions only; it executes nothing at load time. A runner sources it right
# after resolving ROOT and after setting the variables the helpers read:
#
#   RUNNER_NAME    the runner's command name, used as the error prefix
#   KEY_FILE       path to the runner's credential file (key-file runners)

die() { local code="$1"; shift; printf '%s: %s\n' "${RUNNER_NAME:-delegation-runner}" "$*" >&2; exit "$code"; }

# The personal .env beside the configuration file: NAME=value lines read, never
# sourced, into the variables not already set. Ignored when it is a symlink or
# readable by group or others, like the key files. A runner calls this right
# after sourcing this file.
load_kit_env() {
  local file mode line name value
  file="${DELEGATION_CONFIG_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/delegation-kit/config.json}"
  file="$(dirname "$file")/.env"
  if [ ! -f "$file" ] || [ -L "$file" ]; then return 0; fi
  mode="$(stat -f '%Lp' "$file" 2>/dev/null || stat -c '%a' "$file" 2>/dev/null)"
  case "$mode" in *00) ;; *) return 0 ;; esac
  while IFS= read -r line || [ -n "$line" ]; do
    [[ "$line" =~ ^[[:space:]]*(export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]] || continue
    name="${BASH_REMATCH[2]}"
    value="${BASH_REMATCH[3]}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    if [ "${#value}" -ge 2 ] && { [[ "$value" == \"*\" ]] || [[ "$value" == \'*\' ]]; }; then
      value="${value:1:${#value}-2}"
    fi
    if [ -n "$value" ] && [ -z "${!name:-}" ]; then export "$name=$value"; fi
  done <"$file"
  return 0
}
have() { command -v "$1" >/dev/null 2>&1; }

# Resolve a destination path to its physical parent plus its own basename, so
# two spellings of the same file compare equal without following a final symlink.
normalized_destination() {
  local parent name
  parent="$(cd "$(dirname "$1")" && pwd -P)" || return 1
  name="$(basename "$1")"
  printf '%s/%s' "$parent" "$name"
}

# Octal mode of $KEY_FILE on GNU or BSD stat; empty when unreadable.
key_file_mode() {
  local mode
  if mode="$(stat -c '%a' "$KEY_FILE" 2>/dev/null)"; then printf '%s' "$mode"; return 0; fi
  if mode="$(stat -f '%Lp' "$KEY_FILE" 2>/dev/null)"; then printf '%s' "$mode"; return 0; fi
  printf ''
}

sha256_file() {
  if have shasum; then shasum -a 256 "$1" | awk '{print $1}'
  elif have sha256sum; then sha256sum "$1" | awk '{print $1}'
  else return 1; fi
}


# Retry a provider-specific acquire_oauth_lock (return 2 = busy) until
# OAUTH_WAIT_SECONDS elapse. Any other return code is passed through.
acquire_oauth_lock_wait() {
  local deadline rc
  deadline="$(( $(date +%s) + OAUTH_WAIT_SECONDS ))"
  while :; do
    rc=0
    acquire_oauth_lock || rc=$?
    [ "$rc" -eq 2 ] || return "$rc"
    [ "$(date +%s)" -lt "$deadline" ] || return 2
    sleep 1
  done
}
