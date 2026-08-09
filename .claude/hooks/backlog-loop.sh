#!/usr/bin/env bash
# backlog-loop.sh — the [backlog-loop] control skeleton (T902, spec 004
# US1.AC2/AC3; neutral model: .claude/workflow/backlog-loop.md, T901).
#
# Deterministic stop-condition enforcement + activation gating for the bounded
# unattended loop. This script is ONLY the control skeleton: it owns iteration
# sequencing, the skip/ineligible bookkeeping, and the closed stop-condition
# set, and it consumes each iteration's outcome from the invoked command's
# return ALONE. It never merges, never writes any git ref, and never reads any
# report file (constitution P5) — it only DRIVES the T904 report emitter
# (write-only, under an opt-in run id; see BACKLOG_LOOP_RUN_ID below). The real
# selection/iteration bindings are backlog-loop-select.sh and
# backlog-loop-iterate.sh (T905), composed by the [scheduled run] launcher
# template docs/launchers/backlog-loop.sh.
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
#       The contract is ENFORCED: output must be exactly one task ID (`T` +
#       digits, the format every deterministic consumer parses — see
#       .claude/PROJECT.md "Task & branch conventions") or empty. Anything
#       else (multiple tokens, multiple lines, a non-ID word) is the selector
#       misbehaving -> condition (d), fail closed — never a concatenated
#       bogus identity, never misread as a drained backlog.
#   BACKLOG_LOOP_ITERATION_CMD   REQUIRED. Runs ONE complete next-task cycle
#       for the candidate (invoked with the task ID as its argument); prints
#       the outcome on stdout: `pass <pr-ref>` | `fail-discard` | `refused` |
#       `aborted`. An empty or unrecognized outcome, or a non-zero exit,
#       reads as `aborted` (fail closed).
#   SELECT/ITERATION carry NO defaults on purpose: a missing seam is a loud
#   usage error (exit 2), never a silent default that touches real state.
#   BACKLOG_LOOP_SWEEP_CMD       optional. The [isolated workspace] crash-recovery
#       sweep (T906), invoked ONCE at loop start with the run's session id as its
#       single argument — after [autonomy activation] has resolved autonomous, so
#       a review-mode run takes no destructive action. WRITE-ONLY and
#       silent-to-the-run: output and exit status are discarded, exactly like the
#       report drive below, so a broken or missing sweep can never stall the loop,
#       change an outcome, or steer selection. Unset -> no sweep (the pre-T906
#       behavior, unchanged). The real binding is
#       `bash .claude/hooks/isolated-workspace.sh sweep --session`.
#   BACKLOG_LOOP_LOCK_DIR        optional. Path of the mutual-exclusion lock
#       directory; defaults to a per-checkout path under ${TMPDIR:-/tmp} derived
#       from this script's own location, so two clones never share a lock and two
#       runs of the SAME checkout always do. Tests point it at a scratch dir.
#   BACKLOG_LOOP_SESSION_ID      optional. This run's session identity, passed to
#       the sweep seam and recorded in the lock. Defaults to a pid+timestamp
#       token. Deliberately SEPARATE from BACKLOG_LOOP_RUN_ID: the run id names
#       the observe-only report channel, and wiring a control path (the lock, the
#       sweep) to that identity would hand the measurement channel authority it
#       must never have (constitution P5).
#   BACKLOG_LOOP_RUN_ID          optional. When set, the loop DRIVES the T904
#       run-report emitter (backlog-loop-report.sh) under this run id — one
#       iteration record per completed cycle (outcome mapped to the emitter's
#       own-form arity: pass -> verdict PASS + the PR ref; fail-discard ->
#       verdict FAIL; refused/aborted -> the outcome alone) plus the terminal
#       summary record from finish(). WRITE-ONLY and silent-to-the-run: the
#       drive's output and exit status are discarded — the loop reads outcomes
#       from each run's return ALONE, never from the report (constitution P5;
#       the report fence line-scopes exactly this drive). Unset -> no drive
#       (the T902 behavior, unchanged).
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
# Exit 0 on any clean stop, 2 on a usage error; a run stopped by a signal exits
# 128+signo. The skeleton mutates no repository state, runs no gh, and touches no
# network — everything that touches real state goes through a seam. Its ONE git
# call is a read-only `rev-parse` used to key the lock to the repository (see
# Concurrency); it reads no refs, no diffs, and no repo content. Tests:
# .claude/hooks/backlog-loop.test.sh (wired into CI verify).
#
# Concurrency (T906): the loop is SINGLE-INSTANCE per REPOSITORY — not per
# checkout, because the crash-recovery sweep acts on the repository's worktree
# registry, which every linked worktree of a repo shares (see the lock-key note
# below). Before anything else it acquires an ATOMIC lock — `mkdir` on a lock
# directory, whose creation is atomic on every POSIX filesystem. `flock` is
# deliberately NOT used: it is
# absent on macOS (as are `timeout` and `setsid`) and shell-lint does not flag
# it, so an flock-based lock would pass CI and be silently dead in production.
# Without this, two overlapping invocations (a cron fire crossing a manual run)
# both reach selection and can pick the SAME task, with only an incidental
# `git worktree add -b` name collision as an accidental mutex (#267).
#   * contended by a LIVE holder -> decline: a diagnostic naming the holder on
#     stderr, and on stdout the ordinary terminal line `stop: fail-closed`. This
#     is stop condition (d) — "a lifecycle check failed closed" — so the closed
#     stop-condition set above is UNCHANGED, exactly as review mode already
#     reports a loop that never started;
#   * contended by a DEAD holder (the crash case) -> reclaimed, so an ordinary
#     SIGKILL cannot wedge every future run. The reclaim removes the owner file
#     and `rmdir`s the lock — never `rm -rf`, and never a move, so a misconfigured
#     LOCK_DIR pointing at a populated directory makes the reclaim decline rather
#     than destroy what it found. The right to perform that rebuild is itself
#     taken atomically, with a second `mkdir` on a sibling INTENT directory
#     `<lock>.reclaim`: of two runs racing the same stale lock, only the one that
#     creates the intent rebuilds and the other declines. THE TRADE: a run killed
#     inside that takeover window leaves the intent directory behind, and every
#     later run that meets a stale lock then declines until an operator removes
#     `<lock>.reclaim`. That is fail-CLOSED and deliberate — the alternative
#     (rebuilding in place with no intent) lets two runs BOTH end up holding the
#     lock, and the second one's startup sweep would then treat the first's LIVE
#     workspaces as foreign-session orphans;
#   * released from a `trap` on EXIT/INT/TERM/HUP, and only while we still own
#     it, so a normal run always frees the lock for the next one (no deadlock)
#     and never removes a lock another run has taken over.
set -u

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
ACTIVATION_CMD="${BACKLOG_LOOP_ACTIVATION_CMD:-bash .claude/hooks/autonomy-mode.sh}"
SELECT_CMD="${BACKLOG_LOOP_SELECT_CMD:-}"
ITERATION_CMD="${BACKLOG_LOOP_ITERATION_CMD:-}"
RUN_ID="${BACKLOG_LOOP_RUN_ID:-}"
SWEEP_CMD="${BACKLOG_LOOP_SWEEP_CMD:-}"
# Per-REPOSITORY lock path. The lock's scope must be at least as wide as the blast
# radius of everything it protects, and the widest of those is the crash-recovery
# sweep, which acts on the repository's WORKTREE REGISTRY — shared by every linked
# worktree of one repo. Keying on this script's own directory (the obvious choice)
# is therefore too narrow: two linked worktrees of the same repo hold two different
# script paths, would take two different locks, and would both proceed — at which
# point the second run's startup sweep sees the FIRST run's live, marker-owned
# workspaces as foreign-session orphans and force-removes them. So the key is the
# common git dir, which every linked worktree of a repo shares, resolved to an
# absolute path. Outside a repository (or with git unavailable) there is no registry
# to protect and no sweep to run, so the script's own directory is the safe fallback.
# cksum gives a stable, portable tag with no hashing-tool dependency (md5sum/sha1sum/
# shasum differ across BSD and GNU); the value only has to be collision-free between
# repositories, not secure.
# `pwd -P` (physical), not `pwd`: git prints `--git-common-dir` as a RELATIVE path from the
# main tree but an ABSOLUTE one from a linked worktree, and on macOS $TMPDIR lives under
# /var/folders -> /private/var/folders. Resolving logically would therefore yield
# /var/... from one tree and /private/var/... from the other — two different strings for
# one directory, two different locks, and the cross-worktree reap this key exists to stop.
# Capture the common dir BEFORE resolving it: `cd ""` SUCCEEDS (it is a no-op), so
# feeding an empty rev-parse result straight into `cd … && pwd -P` would silently
# yield the CALLER'S cwd instead of taking the fallback below — a cwd-scoped lock
# wearing a repo-scoped comment.
lock_common_dir="$(git rev-parse --git-common-dir 2>/dev/null)" || lock_common_dir=""
lock_key=""
[ -z "$lock_common_dir" ] || lock_key="$(cd "$lock_common_dir" 2>/dev/null && pwd -P)" || lock_key=""
[ -n "$lock_key" ] || lock_key="$(cd "$SELF_DIR" 2>/dev/null && pwd -P)" || lock_key=""
[ -n "$lock_key" ] || lock_key="$SELF_DIR"
lock_tag="$(printf '%s' "$lock_key" | cksum 2>/dev/null)" || lock_tag=""
lock_tag="${lock_tag%% *}"
LOCK_DIR="${BACKLOG_LOOP_LOCK_DIR:-${TMPDIR:-/tmp}/creance-loop-${lock_tag:-0}.lock}"
# This run's session identity — passed to the sweep seam and recorded in the lock, so
# a workspace's marker can be told apart from THIS run's. Separate from RUN_ID by
# design (P5: the observe-only report channel never gains control authority).
SESSION_ID="${BACKLOG_LOOP_SESSION_ID:-loop-$$-$(date +%s 2>/dev/null)}"
# Exported so an iteration's own child processes — the cycle binding, and the
# [isolated workspace] `enter` it drives — can record THIS run as the workspace's
# owner. Without an owner recorded, nothing is ever reapable and the sweep, though
# wired and running, would have no orphan it is allowed to touch.
export BACKLOG_LOOP_SESSION_ID="$SESSION_ID"
LOCK_HELD=0

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
  echo "backlog-loop.sh: BACKLOG_LOOP_SELECT_CMD is required (no silent default; the real selector is backlog-loop-select.sh)" >&2
  usage
fi
if [ -z "$ITERATION_CMD" ]; then
  echo "backlog-loop.sh: BACKLOG_LOOP_ITERATION_CMD is required (no silent default; the real cycle binding is backlog-loop-iterate.sh)" >&2
  usage
fi

iterations=0
failed_once=""  # newline list: identities with ONE gate FAIL so far (fails[id]=1)
ineligible=""   # space list: identities refused by [live-state reconciliation]
skip=""         # identity passed over for exactly ONE selection

# Report drive (T905): write-only, silent-to-the-run — output and exit status
# discarded, so a dead emitter can never stall or steer the loop. Active only
# under a run id. The outcome is mapped to the emitter's own-form arity; the
# loop's control flow never reads anything back.
report_iteration() { # <task-id> <outcome...>
  [ -n "$RUN_ID" ] || return 0
  local task="$1" out="$2"
  case "$out" in
    pass\ ?*)
      bash "$SELF_DIR/backlog-loop-report.sh" iteration "$RUN_ID" "$task" pass PASS "${out#pass }" >/dev/null 2>&1 || : ;;
    fail-discard)
      bash "$SELF_DIR/backlog-loop-report.sh" iteration "$RUN_ID" "$task" fail-discard FAIL >/dev/null 2>&1 || : ;;
    refused | aborted)
      bash "$SELF_DIR/backlog-loop-report.sh" iteration "$RUN_ID" "$task" "$out" >/dev/null 2>&1 || : ;;
  esac
  return 0
}

report_summary() { # <stop-condition>
  [ -n "$RUN_ID" ] || return 0
  bash "$SELF_DIR/backlog-loop-report.sh" summary "$RUN_ID" "$1" "$iterations" "$N" >/dev/null 2>&1 || :
  return 0
}

finish() {
  report_summary "$1"
  printf 'stop: %s after %s of %s\n' "$1" "$iterations" "$N"
  exit 0
}

# ── Single-instance lock (T906, #267). See the header's "Concurrency" note for
# why this is a mkdir lockdir and not flock.

# lock_owner_pid — echo the pid recorded in the lock's owner file, or return
# non-zero when there is none (no file, or a file with no pid= line).
lock_owner_pid() {
  local line
  [ -f "$LOCK_DIR/owner" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in pid=*) printf '%s\n' "${line#pid=}"; return 0 ;; esac
  done < "$LOCK_DIR/owner"
  return 1
}

# holder_alive <pid> — is the recorded holder still running? `ps -p` rather than
# `kill -0`, because kill reports EPERM (i.e. "dead") for a LIVE process owned by
# another user, and a false "dead" is the one answer that must never happen here:
# it would let a second run reclaim a lock a live run is holding. A false "alive"
# only costs a declined start, which is the safe direction.
holder_alive() {
  case "${1:-}" in '' | *[!0-9]*) return 1 ;; esac
  ps -p "$1" >/dev/null 2>&1
}

# write_lock_owner — record this run as the holder. Written to a temp file BESIDE
# the lock dir and renamed in, so (1) a reader never sees a half-written owner
# file, and (2) the lock dir only ever contains `owner`, which is what lets the
# stale-lock reclaim below use rmdir instead of rm -rf.
write_lock_owner() {
  local tmp="$LOCK_DIR.tmp.$$"
  printf 'pid=%s\nsession=%s\n' "$$" "$SESSION_ID" > "$tmp" 2>/dev/null || return 1
  mv -f "$tmp" "$LOCK_DIR/owner" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; return 1; }
  return 0
}

# acquire_lock — 0 when this run may proceed, non-zero when it must decline.
acquire_lock() {
  if mkdir "$LOCK_DIR" 2>/dev/null; then # atomic: exactly one creator wins
    write_lock_owner || return 1
    LOCK_HELD=1
    return 0
  fi
  local holder
  holder="$(lock_owner_pid)" || holder=""
  if holder_alive "$holder"; then
    printf 'backlog-loop.sh: another run holds the loop lock %s (pid %s) — declining to start a second selection/iteration\n' \
      "$LOCK_DIR" "$holder" >&2
    return 1
  fi
  # Stale: the recorded holder is gone (SIGKILL, crash, machine sleep) or never
  # recorded itself. Reclaim, so one hard kill cannot wedge every future run.
  #
  # The takeover must be SINGLE-WINNER, and a rebuild-in-place (rm owner, rmdir,
  # mkdir, write, re-read) is NOT: if one racer finishes the whole sequence before
  # the other starts, the second deletes the FIRST's fresh owner file, removes its
  # live lock dir, and recreates its own — leaving BOTH runs believing they hold
  # the lock, which is precisely the double-start this lock exists to prevent (and
  # worse than the original bug, since the second run's startup sweep would then
  # see the first's LIVE workspaces as foreign-session orphans). So the right to
  # rebuild is itself taken atomically, with one more mkdir: exactly one racer can
  # create the intent directory, and only that one touches the stale lock.
  #
  # A crash inside the intent window leaves the intent dir behind and every later
  # run declines — fail-CLOSED, the safe direction, and recoverable by removing it.
  # That is deliberately preferred over the double-hold a fail-open reclaim allows.
  printf 'backlog-loop.sh: reclaiming a stale loop lock %s (recorded holder %s is not running)\n' \
    "$LOCK_DIR" "${holder:-none}" >&2
  if ! mkdir "$LOCK_DIR.reclaim" 2>/dev/null; then
    printf 'backlog-loop.sh: another run is already reclaiming the stale loop lock %s — declining\n' "$LOCK_DIR" >&2
    return 1
  fi
  # Sole reclaimer from here. Every exit path below drops the intent directory.
  local reclaimed=1
  # Only something that actually LOOKS like our lock may be torn down: empty, or
  # holding nothing but the owner file. A populated directory a misconfigured
  # LOCK_DIR points at is never removed and never moved — the run declines and the
  # content is left exactly as found (there is no rm -rf on this path at all).
  case "$(ls -A "$LOCK_DIR" 2>/dev/null | tr '\n' ' ')" in
    '' | 'owner ') : ;;
    *)
      printf 'backlog-loop.sh: refusing to reclaim %s — it holds content this lock did not write\n' "$LOCK_DIR" >&2
      reclaimed=0
      ;;
  esac
  if [ "$reclaimed" -eq 1 ]; then
    rm -f "$LOCK_DIR/owner" 2>/dev/null
    rmdir "$LOCK_DIR" 2>/dev/null || reclaimed=0
  fi
  [ "$reclaimed" -eq 0 ] || mkdir "$LOCK_DIR" 2>/dev/null || reclaimed=0
  [ "$reclaimed" -eq 0 ] || write_lock_owner || reclaimed=0
  rmdir "$LOCK_DIR.reclaim" 2>/dev/null || :
  [ "$reclaimed" -eq 1 ] || return 1
  LOCK_HELD=1
  return 0
}

# release_lock — the trap. Idempotent, and a no-op unless we still own the lock,
# so a declined run never frees the live holder's lock and a reclaimed-from-under-us
# run never frees its successor's.
release_lock() {
  [ "$LOCK_HELD" -eq 1 ] || return 0
  if [ "$(lock_owner_pid 2>/dev/null)" = "$$" ]; then
    rm -f "$LOCK_DIR/owner" 2>/dev/null
    rmdir "$LOCK_DIR" 2>/dev/null
  fi
  LOCK_HELD=0
  return 0
}

# Crash-recovery startup sweep (T906): DRIVE the seam, exactly as report_iteration
# drives the report emitter — output and exit status discarded, so a broken sweep
# can never stall the run, alter an outcome, or steer selection. The loop learns
# nothing from it; it is cleanup, not a signal.
run_sweep() {
  [ -n "$SWEEP_CMD" ] || return 0
  bash -c "$SWEEP_CMD \"\$@\"" backlog-loop-sweep "$SESSION_ID" >/dev/null 2>&1 || :
  return 0
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

# valid_task_id <s> — whole-string match against the task-ID format every
# deterministic consumer parses (`T` + digits). Anchored over the ENTIRE
# output, so multi-token ("T901 T902"), multi-line, or non-ID output can
# never slip through as a candidate identity.
valid_task_id() { [[ "$1" =~ ^T[0-9]+$ ]]; }

# ── Single-instance gate, before any selection or iteration. A live holder means
# this invocation must not start a second selection/iteration, so it stops the
# same way review mode does: condition (d), a lifecycle check failing closed. The
# trap goes up only once the lock is ours, so a declined run cannot release it.
if acquire_lock; then
  # A bare `trap release_lock INT TERM HUP` would be a trap: bash RESUMES the
  # interrupted flow once the handler returns, so a signalled loop would free its
  # lock and then keep iterating — a running loop holding no lock, worse than
  # either outcome. Each signal handler therefore releases AND exits, with the
  # conventional 128+signo status so a killed run is visibly not a clean stop.
  trap release_lock EXIT
  trap 'release_lock; exit 130' INT
  trap 'release_lock; exit 143' TERM
  trap 'release_lock; exit 129' HUP
else
  finish fail-closed
fi
swept=0

while :; do
  # ── loop head: every stop condition is evaluated HERE, between iterations,
  # never mid-task. [autonomy activation] is consulted once per head. At the
  # FIRST head that consult is the neutral doc's pre-loop gate and runs before
  # (a): in review the loop never starts, even when N=0. Between iterations
  # the doc's pseudocode lists (a) before (d), so an exhausted budget reports
  # max-N.
  if [ "$iterations" -eq 0 ]; then
    activation_autonomous || finish fail-closed # the loop never starts in review
    # Crash-recovery startup sweep (T906), once per run and only on an ENGAGED
    # run: placed after the activation check so a review-mode invocation — which
    # never starts — also never takes a destructive action. It runs before the
    # first selection so this run cannot inherit a previous run's leaked state.
    if [ "$swept" -eq 0 ]; then
      swept=1
      run_sweep
    fi
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
  [ -z "$candidate" ] || valid_task_id "$candidate" || finish fail-closed
  if [ -z "$candidate" ] && [ -n "$skip" ]; then
    set --
    for id in $ineligible; do set -- "$@" "$id"; done
    candidate="$(select_candidate "$@")" || finish fail-closed
    [ -z "$candidate" ] || valid_task_id "$candidate" || finish fail-closed
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
  report_iteration "$candidate" "$outcome"

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
