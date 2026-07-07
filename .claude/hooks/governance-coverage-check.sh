#!/usr/bin/env bash
# Governance-rule coverage check (T1206/#252; spec 007 US6.AC1/AC3).
#
# The registry .claude/governance-rules.md accounts for the US6 candidate set:
# which governance rules are encoded as deterministic checks (carried or cited)
# and which stay prose with an explicit P3 justification. An accounting that
# nothing verifies is the hand-maintained-summary class spec 007 exists to
# prevent (constitution P2), so this check parses the registry table and FAILs
# when an accounted row stops being true:
#   encoded-*  -> the named check file exists, still carries the named anchor
#                 (the carried test-case name / the load-bearing flag), and the
#                 named wiring file still references the check file's basename
#                 ("asserted still running" as a grep, not a promise).
#   prose-P3   -> the registry itself still carries that rule's
#                 "### P3 justification — <rule>" section (never silently
#                 dropped, US6.AC1).
# Every failure names the source file that needs repair (US6.AC3).
#
# Bash + grep only; no git, no network. Resolves paths relative to CWD (the
# same repo-root CWD contract as check-tasks-consistency.sh; CI runs it from
# the repo root, the .test.sh runs it from fixture roots).
# Run: bash .claude/hooks/governance-coverage-check.sh
set -u

REGISTRY=".claude/governance-rules.md"

if [ ! -f "$REGISTRY" ]; then
  echo "FAIL: governance registry $REGISTRY not found — restore it (or run from the repo root)" >&2
  exit 1
fi

fail=0
rows=0

# trim <str> -> stdout: strip surrounding whitespace and backticks.
trim() {
  printf '%s' "$1" | sed -E 's/^[[:space:]`]+//; s/[[:space:]`]+$//'
}

# Table rows: pipe-led lines minus the header and |---| separator.
while IFS='|' read -r _ f_rule f_status f_check f_anchor f_wiring _; do
  rule="$(trim "${f_rule:-}")"
  status="$(trim "${f_status:-}")"
  check="$(trim "${f_check:-}")"
  anchor="$(trim "${f_anchor:-}")"
  wiring="$(trim "${f_wiring:-}")"
  [ -n "$rule" ] || continue
  case "$rule" in rule) continue ;; esac            # header row
  case "$status" in ---*|'') continue ;; esac       # separator / blank
  rows=$((rows + 1))

  case "$status" in
    encoded-carried|encoded-cited)
      if [ ! -f "$check" ]; then
        echo "FAIL: rule '$rule': check file $check is missing — restore it, or update the row in $REGISTRY" >&2
        fail=1
        continue
      fi
      if ! grep -qF -- "$anchor" "$check"; then
        echo "FAIL: rule '$rule': anchor '$anchor' no longer appears in $check — restore that case in $check, or update the row in $REGISTRY" >&2
        fail=1
      fi
      if [ ! -f "$wiring" ]; then
        echo "FAIL: rule '$rule': wiring file $wiring is missing — restore it, or update the row in $REGISTRY" >&2
        fail=1
      elif ! grep -qF -- "$(basename "$check")" "$wiring"; then
        echo "FAIL: rule '$rule': $wiring no longer runs $(basename "$check") — restore the verify step in $wiring, or update the row in $REGISTRY" >&2
        fail=1
      fi
      ;;
    prose-P3)
      if ! grep -qF -- "### P3 justification — $rule" "$REGISTRY"; then
        echo "FAIL: rule '$rule': $REGISTRY lacks its '### P3 justification — $rule' section — a non-encodable candidate is never silently dropped; restore the justification in $REGISTRY" >&2
        fail=1
      fi
      ;;
    *)
      echo "FAIL: rule '$rule': unknown status '$status' in $REGISTRY — use encoded-carried, encoded-cited, or prose-P3 (repair $REGISTRY)" >&2
      fail=1
      ;;
  esac
done < <(grep -E '^\|' "$REGISTRY")

if [ "$rows" -eq 0 ]; then
  echo "FAIL: no rules parsed from $REGISTRY — the accounting table is missing or malformed; repair $REGISTRY" >&2
  exit 1
fi

if [ "$fail" -ne 0 ]; then
  exit 1
fi
echo "governance coverage: OK ($rows rule(s) accounted and live)"
