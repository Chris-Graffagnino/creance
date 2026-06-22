#!/usr/bin/env bash
# lib-neutrality-scan.sh — shared runtime-neutral workflow-doc mechanism scan (#122).
#
# The workflow layer may name bracketed [roles] and project/profile pointers, but not
# concrete runtime mechanisms. Keep the banned-token set here so distributed encoding
# tests do not drift. `git` remains exempt by constitution P1.

neutral_mechanism_pattern() {
  printf '%s' '\bgh\b|GitHub[[:space:]]+CLI|\bclaude\b|\bopus\b|\bsonnet\b|\bfable\b|\bhaiku\b|--model|--json|PreToolUse|settings\.json'
}

neutral_mechanism_leaks() {
  [ "$#" -gt 0 ] || return 0
  for f in "$@"; do
    sed 's#\.claude/#PROFILEPTR/#g' "$f" | tr -s '[:space:]' ' ' \
      | grep -oiE "$(neutral_mechanism_pattern)" || true
  done \
    | sort -u \
    | tr '\n' ' '
}
