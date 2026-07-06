#!/usr/bin/env bash
# gate-diff.sh — review-mode §7 gate: HEAD-stability-verified committed diff (T639, #240).
#
# The review-mode [orchestrated run] (gate-loop) audits the committed diff of the SHARED main
# working tree. When the invoker passes no explicit worktree it historically read `git diff
# main..HEAD` in that shared tree — so a CONCURRENT session that switched the shared checkout to
# its own branch between the gate's dispatch and its fan-out made all the auditors grade the
# WRONG branch's diff: a vacuous / wrong-diff pass (issue #240). This helper closes that class.
# It emits the committed diff ONLY while the shared tree's HEAD still matches the task branch;
# otherwise it emits a distinct mismatch marker and NO diff, so the gate fails LOUD instead of
# grading someone else's branch.
#
# It is the review-mode analogue of the T612 gate-in-place mechanism: audit an EXPLICIT ref, never
# an inferred HEAD. It runs once per dispatch round (the gate re-invokes it after every fix), so the
# HEAD-stability check fires at dispatch AND at each re-dispatch.
#
# Distinct from restore-task-branch.sh (#140/T622): that HEALS drift caused by the loop's OWN
# shell-holding agents before a fix commit; THIS DETECTS drift caused by a SECOND session and
# refuses to produce a diff for it (grading is safe to abort; committing is what restore protects).
# Distinct from #214 (a dispatcher rooted OUTSIDE the repo). The mechanism here is a second session
# switching the shared HEAD plus the absence of an explicit pinned ref.
#
# Output contract (consumed by gate-loop.js `classifyProvidedDiff` — the two markers are the SAME
# literals that file checks; gate-diff.test.sh pins that agreement):
#   stable HEAD  -> the committed `git diff <base>..<branch-tip>`, then GATE-DIFF-COMPLETE  (exit 0)
#   drifted HEAD -> a one-line diagnostic, then GATE-HEAD-MISMATCH                          (exit 3)
#   abort        -> a one-line diagnostic, then GATE-HEAD-MISMATCH                          (exit 1)
#                   (unreadable git, a missing ref, or a `git diff` that failed mid-patch)
# The gate keys on the FINAL stdout line (the marker), never the exit code — but the exit code is
# distinct so a human or CI running the hook directly still gets a loud non-zero on any refusal.
#
# Run from the repo root:  bash .claude/hooks/gate-diff.sh <task-branch> [<base-ref>]
set -u

DIFF_COMPLETE_MARKER='-----GATE-DIFF-COMPLETE-----'
HEAD_MISMATCH_MARKER='-----GATE-HEAD-MISMATCH-----'

usage() {
  echo "usage: $(basename "$0") <task-branch> [<base-ref>]   e.g. $(basename "$0") fix/240-gate-head-verified-diff main" >&2
  exit 2
}

[ "$#" -ge 1 ] && [ "$#" -le 2 ] || usage
branch="$1"
base="${2:-main}"
[ -n "$branch" ] || usage
[ -n "$base" ] || usage

# refuse <exit> <stdout-diagnostic> — emit the diagnostic then the mismatch marker as the FINAL
# stdout line (so the gate's classifier records the reason) and exit loud. Never prints a diff and
# never the completion marker: a refused round must be a fail-closed gate, not a graded diff.
refuse() {
  echo "gate-diff: $2 — refusing to produce a diff (the gate must fail closed, not grade a wrong/absent diff)." >&2
  printf '%s\n' "$2"
  printf '%s\n' "$HEAD_MISMATCH_MARKER"
  exit "$1"
}

# Fail closed (loud) when git state is unreadable or a required ref is missing — an abort, exit 1.
git rev-parse --git-dir >/dev/null 2>&1 || refuse 1 "live git state is unreadable"
git rev-parse --verify --quiet "refs/heads/$branch" >/dev/null || refuse 1 "task branch '$branch' does not exist"
git rev-parse --verify --quiet "$base" >/dev/null || refuse 1 "base ref '$base' does not resolve"

head_sha="$(git rev-parse --verify --quiet HEAD || true)"
branch_sha="$(git rev-parse --verify --quiet "refs/heads/$branch" || true)"
current="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || echo 'detached HEAD')"

# The HEAD-stability pre-flight: the shared tree must still be ON the task branch (HEAD at its tip).
# A concurrent session's branch switch moves HEAD off it -> mismatch -> loud refusal, exit 3.
# A fix-round commit advances HEAD and the branch tip together, so this still holds after a fix.
if [ -z "$head_sha" ] || [ "$head_sha" != "$branch_sha" ]; then
  refuse 3 "HEAD-stability check failed — expected the shared working tree on '$branch' (${branch_sha:-unknown}) but HEAD is '$current' (${head_sha:-unknown}); a concurrent session switched the shared checkout (issue #240)"
fi

# Stable: the shared tree is on the task branch. Emit the committed diff, then the completion marker
# as the FINAL line. Two guards keep the marker HONEST — it crowns ONLY a complete, correct diff:
#   * Pin the diff to the already-verified $branch_sha (== the just-checked $head_sha), never live
#     HEAD. Between the SHA check above and this command a concurrent session could still switch the
#     shared checkout; re-resolving HEAD here would grade the OTHER branch's patch and reintroduce
#     the very #240 race this hook closes. A pinned commit object is immune to a checkout switch.
#   * Print the completion marker ONLY if `git diff` exits 0. A diff driver that dies mid-patch (e.g.
#     a failing GIT_EXTERNAL_DIFF) leaves a truncated patch on stdout and exits non-zero; crowning
#     that with the marker would hand the reviewers a partial diff as "verified". On failure, refuse
#     loud (mismatch marker, NO completion marker) so the gate fails closed, not on a partial patch.
# (An empty diff — a wrong/empty branch — still emits only the completion marker; gate-loop.js's
# classifier fails THAT closed as a vacuous grade.)
git diff "$base..$branch_sha" || refuse 1 "git diff '$base..$branch_sha' exited non-zero (a truncated or unreliable patch)"
printf '%s\n' "$DIFF_COMPLETE_MARKER"
exit 0
