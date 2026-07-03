#!/usr/bin/env bash
# backlog-loop.sh — the [backlog-loop] control skeleton (T902, spec 004
# US1.AC2/AC3; neutral model: .claude/workflow/backlog-loop.md, T901).
#
# Deterministic stop-condition enforcement + activation gating for the bounded
# unattended loop. This script is ONLY the control skeleton: it owns iteration
# sequencing, the skip/ineligible bookkeeping, and the closed stop-condition
# set, and it consumes each iteration's outcome from the invoked command's
# return ALONE. It never merges, never writes any git ref, and never reads any
# report file (constitution P5) — the run report is T904's surface, and the
# real selection/iteration mechanisms are bound later (T905).
#
# Usage: backlog-loop.sh run <N>
#   N — the iteration budget, resolved from the invocation only (never
#       hardcoded in the loop body). A missing or non-numeric N is a usage
#       error (exit 2). N=0 is a valid no-op run: stop condition (a) fires
#       before any iteration is attempted.
#
# Injectable seams (each a command string, run via `bash -c`):
#   BACKLOG_LOOP_ACTIVATION_CMD  the [autonomy activation] check; default
#       `bash .claude/hooks/autonomy-mode.sh` (run from the repo root). Must
#       print exactly `autonomous` for the loop to start/continue; anything
#       else — including a missing or failing command — resolves to review
#       (FAIL CLOSED, the same posture as autonomy-mode.sh itself). Consulted
#       at the top of EVERY loop head — at loop start (the neutral doc's
#       pre-loop gate: in review the loop never starts) and again between
#       every iteration (condition (d)) — never mid-task.
#   BACKLOG_LOOP_SELECT_CMD      REQUIRED. Candidate selection; invoked with
#       the excluded task identities as arguments; prints the lowest
#       unblocked candidate task ID, or nothing when no candidate remains.
#   BACKLOG_LOOP_ITERATION_CMD   REQUIRED. Runs ONE complete next-task cycle
#       for the candidate (invoked with the task ID as its argument); prints
#       the outcome on stdout: `pass <pr-ref>` | `fail-discard` | `refused` |
#       `aborted`. An empty or unrecognized outcome, or a non-zero exit,
#       reads as `aborted` (fail closed).
#   SELECT/ITERATION carry NO defaults on purpose: a missing seam is a loud
#   usage error (exit 2), never a silent default that touches real state.
#
# Stop conditions (the closed set; evaluated only BETWEEN iterations — a
# started iteration always runs to its own terminal state first):
#   (a) iterations = N                           -> stop max-N
#   (b) no unblocked candidate remains           -> stop backlog-drained
#   (c) same identity gate-FAILs twice this run  -> stop repeated-gate-fail
#   (d) activation no longer autonomous, or an
#       iteration aborted (a check failed closed)-> stop fail-closed
# Per-outcome handling: pass -> continue; fail-discard -> first FAIL of an
# identity sets skip (advance one selection), second FAIL of the SAME stable
# identity stops (c); refused -> the identity joins `ineligible` for the rest
# of the run; aborted -> stop (d). Every started iteration increments the
# budget counter whatever its outcome. `skip` is consumed by the very next
# selection, whatever that iteration's outcome: when no other unblocked
# candidate exists the selector is re-consulted excluding only `ineligible`,
# so the skipped identity is re-selected rather than mistaken for a drained
# backlog.
#
# Output: one parseable line per iteration —
#     iteration <n> task <id> outcome <pass <pr-ref>|fail-discard|refused|aborted>
# and one terminal line —
#     stop: <max-N|backlog-drained|repeated-gate-fail|fail-closed> after <i> of <N>
# Exit 0 on any clean stop, 2 on a usage error. Bash only — no git, no gh, no
# network. Tests: .claude/hooks/backlog-loop.test.sh (wired into CI verify).
set -u

ACTIVATION_CMD="${BACKLOG_LOOP_ACTIVATION_CMD:-bash .claude/hooks/autonomy-mode.sh}"
SELECT_CMD="${BACKLOG_LOOP_SELECT_CMD:-}"
ITERATION_CMD="${BACKLOG_LOOP_ITERATION_CMD:-}"

usage() {
  echo "usage: backlog-loop.sh run <N>" >&2
  echo "  N: iteration budget (non-negative integer, from the invocation only)" >&2
  echo "  required seams: BACKLOG_LOOP_SELECT_CMD, BACKLOG_LOOP_ITERATION_CMD" >&2
  exit 2
}

[ "$#" -eq 2 ] || usage
[ "$1" = "run" ] || usage
N="$2"
case "$N" in '' | *[!0-9]*) usage ;; esac
if [ -z "$SELECT_CMD" ]; then
  echo "backlog-loop.sh: BACKLOG_LOOP_SELECT_CMD is required (no silent default; T905 binds the real selector)" >&2
  usage
fi
if [ -z "$ITERATION_CMD" ]; then
  echo "backlog-loop.sh: BACKLOG_LOOP_ITERATION_CMD is required (no silent default; T905 binds the real cycle)" >&2
  usage
fi

iterations=0
failed_once=""  # newline list: identities with ONE gate FAIL so far (fails[id]=1)
ineligible=""   # space list: identities refused by [live-state reconciliation]
skip=""         # identity passed over for exactly ONE selection

finish() {
  printf 'stop: %s after %s of %s\n' "$1" "$iterations" "$N"
  exit 0
}

# in_list <id> <newline-list> — exact whole-line identity match (stable task
# identity, never a substring/prefix match).
in_list() { printf '%s\n' "$2" | grep -qxF "$1"; }

# [autonomy activation]: true only on an exact `autonomous`. A missing or
# failing command, empty output, or any other word resolves to review — the
# check FAILS CLOSED, never open (constitution P3/P4).
activation_autonomous() {
  local out
  out="$(bash -c "$ACTIVATION_CMD" 2>/dev/null)" || return 1
  [ "$out" = "autonomous" ]
}

# Selection seam: arguments are the excluded identities; prints the candidate
# or nothing. A selector that cannot run at all is a lifecycle check failing
# closed -> condition (d), never silently read as an empty backlog.
select_candidate() {
  bash -c "$SELECT_CMD \"\$@\"" backlog-loop-select "$@" 2>/dev/null
}

while :; do
  # ── loop head: every stop condition is evaluated HERE, between iterations,
  # never mid-task. [autonomy activation] is consulted once per head. At the
  # FIRST head that consult is the neutral doc's pre-loop gate and runs before
  # (a): in review the loop never starts, even when N=0. Between iterations
  # the doc's pseudocode lists (a) before (d), so an exhausted budget reports
  # max-N.
  if [ "$iterations" -eq 0 ]; then
    activation_autonomous || finish fail-closed # the loop never starts in review
    [ "$iterations" -lt "$N" ] || finish max-N  # (a): N=0 stops before any iteration
  else
    [ "$iterations" -lt "$N" ] || finish max-N  # (a)
    activation_autonomous || finish fail-closed # (d): re-checked between EVERY iteration
  fi

  # ── selection: the LOOP owns the skip/ineligible bookkeeping. First consult
  # excludes ineligible + skip; if that finds nothing and skip was set, the
  # skipped identity is the only remaining candidate — re-consult excluding
  # only ineligible so it is re-selected. skip is consumed either way.
  set --
  for id in $ineligible; do set -- "$@" "$id"; done
  [ -z "$skip" ] || set -- "$@" "$skip"
  candidate="$(select_candidate "$@")" || finish fail-closed
  candidate="$(printf '%s\n' "$candidate" | head -1 | tr -d '[:space:]')"
  if [ -z "$candidate" ] && [ -n "$skip" ]; then
    set --
    for id in $ineligible; do set -- "$@" "$id"; done
    candidate="$(select_candidate "$@")" || finish fail-closed
    candidate="$(printf '%s\n' "$candidate" | head -1 | tr -d '[:space:]')"
  fi
  skip="" # consumed: it applied to this one selection, whatever happens next
  [ -n "$candidate" ] || finish backlog-drained # (b)

  # ── one complete cycle. The outcome is read from the run's return ONLY —
  # never from a report file (constitution P5). A started iteration always
  # runs to its terminal state; no stop condition interrupts it.
  outcome="$(bash -c "$ITERATION_CMD \"\$@\"" backlog-loop-iter "$candidate" 2>/dev/null)" || outcome="aborted"
  outcome="$(printf '%s\n' "$outcome" | head -1)"
  case "$outcome" in
    pass\ ?* | fail-discard | refused | aborted) : ;;
    *) outcome="aborted" ;; # unrecognized/empty outcome fails closed
  esac
  iterations=$((iterations + 1)) # every started iteration consumes budget
  printf 'iteration %s task %s outcome %s\n' "$iterations" "$candidate" "$outcome"

  case "$outcome" in
    pass\ *) : ;; # PR opened by the cycle's own promotion path; continue
    fail-discard)
      if in_list "$candidate" "$failed_once"; then
        finish repeated-gate-fail # (c): second FAIL of the same stable identity
      fi
      failed_once="$(printf '%s\n%s' "$failed_once" "$candidate")"
      skip="$candidate" # first FAIL advances: pass over it for ONE selection
      ;;
    refused)
      ineligible="$ineligible $candidate" # re-selecting would refuse again
      ;;
    aborted)
      finish fail-closed # (d): a check failed closed mid-cycle; never retried around
      ;;
  esac
done
