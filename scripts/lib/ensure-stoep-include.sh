#!/usr/bin/env bash
# Registers a compose file in the host umbrella include list ($STOEP_COMPOSE).
# Caller must set STOEP_COMPOSE before sourcing.

ensure_stoep_include() {
  local include_path="$1"

  local grep_cmd=(grep) sed_cmd=(sed) using_sudo=0
  if ! cat "$STOEP_COMPOSE" >/dev/null 2>&1; then
    grep_cmd=(sudo grep)
    sed_cmd=(sudo sed)
    using_sudo=1
  fi

  local grep_stderr grep_rc
  set +e
  grep_stderr="$("${grep_cmd[@]}" -qF "${include_path}" "$STOEP_COMPOSE" 2>&1 1>/dev/null)"
  grep_rc=$?
  set -e

  if [ "$using_sudo" -eq 1 ] && printf '%s' "$grep_stderr" | grep -q '^sudo:'; then
    echo "ERROR: ${STOEP_COMPOSE} is not readable by $(whoami), and sudo denied grep/sed." >&2
    exit 1
  fi

  if [ "$grep_rc" -eq 0 ]; then
    echo "${include_path} already in ${STOEP_COMPOSE}"
    return 0
  fi

  echo "Adding ${include_path} to ${STOEP_COMPOSE}..."
  local sibling_prefix="${include_path%/*}/"
  local last_line
  last_line="$("${grep_cmd[@]}" -n "${sibling_prefix}" "$STOEP_COMPOSE" 2>/dev/null | tail -1 | cut -d: -f1 || true)"
  if [ -z "$last_line" ]; then
    last_line="$("${grep_cmd[@]}" -n 'compose/\$HOSTNAME/' "$STOEP_COMPOSE" 2>/dev/null | tail -1 | cut -d: -f1 || true)"
  fi
  if [ -n "$last_line" ]; then
    "${sed_cmd[@]}" -i "${last_line}a\\  - ${include_path}" "$STOEP_COMPOSE"
    echo "Added after line ${last_line}"
  else
    echo "WARNING: Could not auto-add include. Add manually to ${STOEP_COMPOSE}:"
    echo "  - ${include_path}"
  fi
}
