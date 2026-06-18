#!/usr/bin/env bash
# autonomy-mode.sh — the [autonomy activation] check for the [isolated workspace]
# role (T610 / epic #81; model in .claude/workflow/README.md, rationale in
# DESIGN-NOTES §13).
#
# Deterministic, default-OFF activation decision. Isolated autonomous mode — the
# path by which §7-gated work could reach the base branch WITHOUT human review —
# engages ONLY when at least one explicit signal is present:
#   * config opt-in:  the profile carries exactly one  `autonomy-opt-in: enabled`; OR
#   * in-session authorization:  the caller passes --session-authorized (the runtime
#     sets this when the user authorizes autonomy in the session; the explicit-context
#     rule — the signal arrives in the invocation, never inferred from ambient env).
# With NEITHER signal the decision is "review".
#
# This check is the deliberate INVERSE of guard.sh: it FAILS CLOSED to review on any
# uncertainty (unreadable/absent profile, a non-`enabled` value, an ambiguous/duplicate
# declaration) — a fail-OPEN activation check would silently switch autonomy on, the one
# thing the blast wall must never do (constitution P3/P4).
#
# Output: prints exactly `review` or `autonomous` on stdout; exit 0 on a decision, 2 on
# a usage error. Bash + grep only — no git, no network. The CALLER (the autonomous
# next-task path, T611) interprets the printed word; on `review` nothing isolated runs
# and nothing reaches the base branch outside the normal human-merge path.
set -u

PROFILE=".claude/PROJECT.md"
OPT_IN_KEY="autonomy-opt-in"
session_authorized=0

usage() {
  echo "usage: autonomy-mode.sh [--session-authorized] [--profile <path>]" >&2
  echo "  prints 'autonomous' iff engaged (config opt-in or in-session auth), else 'review'" >&2
  exit 2
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --session-authorized) session_authorized=1; shift ;;
    --profile) [ "$#" -ge 2 ] || usage; PROFILE="$2"; shift 2 ;;
    *) usage ;;
  esac
done

# Config opt-in: engaged ONLY when the profile carries EXACTLY ONE declaration whose
# value is `enabled`. Zero matches, a non-`enabled` value (e.g. the default `disabled`),
# an unreadable/absent profile, or multiple/conflicting declarations all fall through to
# NOT-opted-in — the fail-closed posture.
opt_in=0
if [ -f "$PROFILE" ] && [ -r "$PROFILE" ]; then
  values=$(grep -oE "${OPT_IN_KEY}:[[:space:]]*[A-Za-z]+" "$PROFILE" 2>/dev/null \
    | grep -oE '[A-Za-z]+$')
  count=$(printf '%s\n' "$values" | grep -c .)
  if [ "$count" = "1" ] && [ "$values" = "enabled" ]; then
    opt_in=1
  fi
fi

if [ "$session_authorized" = "1" ] || [ "$opt_in" = "1" ]; then
  echo "autonomous"
else
  echo "review"
fi
exit 0
