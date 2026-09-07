#!/usr/bin/env bash
# Helpers shared by the delegation-kit external runners. This file defines
# functions only; it executes nothing at load time. A runner sources it right
# after resolving ROOT and after setting the variables the helpers read:
#
#   RUNNER_NAME    the runner's command name, used as the error prefix
#   PROFILE        the central routing profile key (profile-keyed runners)
#   CENTRAL_GATES  path to the central routing gates
#   KEY_FILE       path to the runner's credential file (key-file runners)
#
# Evaluation binding: every runner's `runner_sha256` stays the hash of the
# runner file alone, exactly as the frozen manifests and the suites assert.
# This library is bound through `runner_source_commit` plus the "runner source
# checkout is dirty" refusal, which covers the whole tree including this file.

die() { local code="$1"; shift; printf '%s: %s\n' "${RUNNER_NAME:-delegation-runner}" "$*" >&2; exit "$code"; }
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

# Lane names of $PROFILE carrying status $1, as a sorted JSON array. Prints []
# rather than failing when the gate is unreadable, so `check` can still report.
profile_lanes_with_status() {
  if [ -f "$CENTRAL_GATES" ] && have jq; then
    jq -c --arg profile "$PROFILE" --arg status "$1" \
      '[.profiles[$profile].lanes | to_entries[] | select(.value.status == $status) | .key] | sort' \
      "$CENTRAL_GATES" 2>/dev/null || printf '[]'
  else
    printf '[]'
  fi
}
qualified_lanes() { profile_lanes_with_status qualified; }
provisional_lanes() { profile_lanes_with_status provisional; }
candidate_lanes() { profile_lanes_with_status candidate; }

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
