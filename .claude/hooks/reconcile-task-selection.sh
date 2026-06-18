#!/usr/bin/env bash
# reconcile-task-selection.sh — runtime selection precondition for /next-task (#80, T608).
#
# Before /next-task commits to a candidate task, reconcile its tasks-file checkbox against
# authoritative live state and REFUSE stale work — the deterministic replacement for the
# prose "cross-check git/PRs before starting" habit (constitution P3: a check, not model
# judgment). It is the RUNTIME counterpart of the CI drift gate (check-tasks-consistency.sh
# rule 3) and SHARES its detection via lib-tasks-drift.sh — one definition, two consumers
# (DESIGN-NOTES §12), so the gate and the selector can never disagree.
#
# Git-based (a merged task lands a `[T<nnn>]` commit on the base branch), so it needs no
# network and is always available locally. It FAILS OPEN (warn + exit 0) when live state
# can't be read — degrade to pre-T608 behavior with a surfaced warning, never a hard stall
# (done-when 5). This detects MERGED/LANDED work only (a `[T<nnn>]` commit subject). An
# *in-flight* candidate — an open PR/branch with no merge commit yet — is OUT of scope here
# and is not refused anywhere in /next-task §3 today; deterministic in-flight refusal (a
# fail-open `gh` tracker read in the adapter) is tracked as #105.
#
# Run from the repo root:  bash .claude/hooks/reconcile-task-selection.sh <task-id>
# Exit: 0 selectable (or fail-open) · 2 usage · 3 drift (candidate is stale — do not start).
set -u

DRIFT_EXIT=3

usage() {
  echo "usage: $(basename "$0") <task-id>   e.g. $(basename "$0") T608" >&2
  exit 2
}

[ "$#" -eq 1 ] || usage
id="$1"
case "$id" in
  T[0-9]*) ;;
  *) echo "reconcile: '$id' is not a T<nnn> task id" >&2; usage ;;
esac

# shellcheck source=lib-tasks-drift.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib-tasks-drift.sh"

# Fail open: if git history is unreadable (not a repo), we cannot reconcile — warn and allow
# selection rather than blocking honest work (done-when 5).
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "reconcile: live git state unavailable — proceeding without reconciliation (fail-open); verify $id by hand." >&2
  exit 0
fi

if tasks_drift_is_drifted "$id"; then
  hit="$(tasks_drift_hit "$id")"
  {
    echo "reconcile: REFUSING $id — its box is unchecked but committed/merged work exists:"
    echo "    $hit"
    echo "  Done-but-unchecked drift: the checkbox lags reality, so selecting $id would start"
    echo "  stale work. Tick $id's box to match the landed work, or pick another task."
  } >&2
  exit "$DRIFT_EXIT"
fi

echo "reconcile: $id is selectable — no conflicting live state (no landed commit for an unchecked box)."
exit 0
