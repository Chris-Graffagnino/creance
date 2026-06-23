#!/usr/bin/env bash
# lib-neutrality-scan.sh — shared runtime-neutral workflow-doc mechanism scan (#122).
#
# The workflow layer may name bracketed [roles] and project/profile pointers, but not
# concrete runtime mechanisms. Keep the banned-token set here so distributed encoding
# tests do not drift. `git` remains exempt by constitution P1.
#
# Per-adapter mechanism vocabularies accumulate in this ONE shared set as adapters are
# added — never a forked per-adapter scanner (constitution P2: one drift definition, many
# consumers). Currently banned:
#   * Claude Code adapter: gh / GitHub CLI, claude/opus/sonnet/fable/haiku, --model,
#     --json, PreToolUse, settings.json.
#   * Omnigent adapter (T617): omnigent, polly, policy_modules, POLICY_REGISTRY,
#     openai-agents, the sys_os_*/sys_session_send tool names, executor.harness/.model.
#     (claude-sdk needs no entry — \bclaude\b already matches it.)

neutral_mechanism_pattern() {
  printf '%s' '\bgh\b|GitHub([[:space:]]+[[:alnum:]_-]+){0,5}[[:space:]]+CLI|\bclaude\b|\bopus\b|\bsonnet\b|\bfable\b|\bhaiku\b|--model|--json|PreToolUse|settings\.json|\bomnigent\b|\bpolly\b|policy_modules|POLICY_REGISTRY|openai-agents|sys_os_shell|sys_os_edit|sys_session_send|executor\.harness|executor\.model'
}

neutral_mechanism_scan_error() {
  printf 'FAIL: %s\n' "$1" >&2
  printf 'NEUTRALITY_SCAN_ERROR: %s\n' "$1"
}

neutral_mechanism_leaks() {
  local f bad
  if [ "$#" -eq 0 ]; then
    neutral_mechanism_scan_error "neutral_mechanism_leaks needs at least one file"
    return 1
  fi

  bad=0
  for f in "$@"; do
    if [ ! -f "$f" ]; then
      neutral_mechanism_scan_error "missing file: $f"
      bad=1
    elif [ ! -r "$f" ]; then
      neutral_mechanism_scan_error "unreadable file: $f"
      bad=1
    elif [ ! -s "$f" ]; then
      neutral_mechanism_scan_error "empty file: $f"
      bad=1
    fi
  done
  [ "$bad" -eq 0 ] || return 1

  for f in "$@"; do
    sed 's#\.claude/#PROFILEPTR/#g' "$f" | tr -s '[:space:]' ' ' \
      | grep -oiE "$(neutral_mechanism_pattern)" || true
  done \
    | sort -u \
    | tr '\n' ' '
}
