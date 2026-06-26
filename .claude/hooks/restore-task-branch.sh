#!/usr/bin/env bash
# restore-task-branch.sh — review-mode §7 gate backstop (#140, T622).
#
# The review-mode [orchestrated run] (gate-loop) dispatches read-only auditor subagents in
# the SHARED main working tree. Those agents are read-only as to file-mutation tools but DO
# have Bash, so a stray `git checkout`/`git switch` in an auditor step can silently relocate
# the maker's HEAD off the task branch onto the base branch — stranding uncommitted work, or
# producing a push/PR from the wrong branch state (the #139 reflog drift this fix closes).
# The runtime that executes the gate loop has no git access, so the deterministic restore
# lives in the DISPATCHER and is bound here: after the gate returns (on EVERY outcome, before
# it reads HEAD for telemetry), the dispatcher runs this helper to put HEAD back on the task
# branch — a no-op when no auditor drifted it.
#
# This is a STATE-PROTECTION backstop, so it FAILS LOUD (exit 1) when it cannot guarantee the
# branch — the deliberate INVERSE of the fail-OPEN selection hooks (reconcile-*-selection.sh),
# where blocking honest work is the worse error. Here the worse error is silently reporting
# "fine" while HEAD sits on the wrong branch, so the dispatcher would push / stamp telemetry
# from a drifted HEAD. (constitution P3: the deterministic restore is load-bearing; the
# auditors' non-switching base-read instruction in the gate loop is only the prevention layer.)
#
# Run from the repo root:  bash .claude/hooks/restore-task-branch.sh <task-branch>
# Exit: 0 already-correct (no-op) or restored · 1 cannot guarantee the branch (fail loud) · 2 usage.
set -u

usage() {
  echo "usage: $(basename "$0") <task-branch>   e.g. $(basename "$0") fix/140-gate-loop-restore" >&2
  exit 2
}

[ "$#" -eq 1 ] || usage
branch="$1"
[ -n "$branch" ] || usage

# Fail loud when git state is unreadable: a backstop that cannot read HEAD cannot promise the
# branch, and a silent exit 0 would let the dispatcher proceed (push / telemetry) on a HEAD it
# never verified. (The inverse of the reconcile hooks' fail-open posture, by design.)
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "restore-task-branch: live git state unreadable — cannot verify HEAD is on '$branch'." >&2
  exit 1
fi

# The task branch must still exist to restore onto it. If it is gone, fail loud rather than
# leave the dispatcher on a drifted HEAD believing the restore succeeded.
if ! git show-ref --verify --quiet "refs/heads/$branch"; then
  echo "restore-task-branch: branch '$branch' does not exist — cannot restore HEAD onto it." >&2
  exit 1
fi

# Current branch ('' when detached). No-op when HEAD is already where it belongs — the common
# case (no auditor drifted it), so the backstop stays silent and cheap on the happy path.
current="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
if [ "$current" = "$branch" ]; then
  exit 0
fi

# An auditor (or a detach) moved HEAD. Restore it. A failed switch (e.g. a conflicting tree
# state) is itself a fail-loud condition — the dispatcher must see it, not push from the wrong
# place believing the restore worked.
if git switch "$branch" >/dev/null 2>&1; then
  echo "restore-task-branch: restored HEAD to '$branch' (was '${current:-detached HEAD}') — an auditor had relocated the shared tree." >&2
  exit 0
fi

echo "restore-task-branch: FAILED to restore HEAD to '$branch' (currently '${current:-detached HEAD}') — resolve by hand before pushing." >&2
exit 1
