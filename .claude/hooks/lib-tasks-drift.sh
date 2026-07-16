#!/usr/bin/env bash
# lib-tasks-drift.sh — shared "done-but-unchecked" drift detection (issues #69, #80).
#
# ONE definition of "which unchecked tasks have committed/merged work", sourced by all five
# consumers so they can never disagree (the T602 anti-duplication lesson; DESIGN-NOTES §12):
#   * check-tasks-consistency.sh rule 3 — the CI gate (whole backlog, #69);
#   * reconcile-task-selection.sh      — the runtime /next-task selection precondition
#                                        (per-candidate, #80/T608);
#   * announce-task-selection.sh       — the runtime /next-task announce/confirm decision
#                                        (per-candidate, #103/T614);
#   * guard.sh rule 8                  — the pre-commit tasks-drift check (the pending
#                                        commit's ids vs tasks_drift_unchecked_ids,
#                                        #202/T633);
#   * status-map.sh                    — the observe-only orientation map's drift line
#                                        (whole backlog, read-only, #234/T638). The ONLY
#                                        consumer with no control authority: it renders
#                                        drift for a human to read and decides nothing.
#
# A commit subject follows `<type>: [<task-id>] <desc>` (PROJECT.md conventions), so a
# reachable commit carrying `[T<nnn>]` means T<nnn> has landed work; a still-`- [ ]` box for
# that id is drift. Bash + git + grep only — no GitHub API, so the core stays available
# offline and the callers own their fail-open posture. Functions read CWD's specs/*/tasks.md
# and `git log`; the CALLER sets CWD (and `set -u`). This file only defines functions — no
# top-level side effects, so sourcing it is safe under any caller's options.

# tasks_drift_committed_ids — task IDs whose [T<nnn>] appears in a reachable commit subject.
tasks_drift_committed_ids() {
  git log --format='%s' 2>/dev/null | grep -oE '\[T[0-9]+\]' | tr -d '[]' | sort -u
}

# tasks_drift_unchecked_ids — task IDs whose box is still `- [ ]` in a live tasks file
# (specs/*/tasks.md; *.template.md skeletons are out of scope, matching rules 1-2).
tasks_drift_unchecked_ids() {
  grep -hoE '^- \[ \] T[0-9]+' specs/*/tasks.md 2>/dev/null | grep -oE 'T[0-9]+' | sort -u
}

# tasks_drift_hit <id> — the newest commit (short-sha + subject) carrying [<id>], or empty.
# Whole-id, bracket-anchored match, so [T90] never matches T901.
tasks_drift_hit() {
  git log --format='%h %s' 2>/dev/null | grep -F "[$1]" | head -1
}

# tasks_drift_is_drifted <id> — exit 0 iff <id>'s box is unchecked AND a commit carries its
# id (done-but-unchecked drift); exit 1 otherwise. Whole-line `grep -qxF` so a [T90] commit
# never trips an unchecked T901.
tasks_drift_is_drifted() {
  local id="$1"
  tasks_drift_unchecked_ids | grep -qxF "$id" || return 1
  tasks_drift_committed_ids | grep -qxF "$id"
}
