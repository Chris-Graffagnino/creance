#!/usr/bin/env bash
# Regression tests for restore-task-branch.sh — the review-mode §7 gate backstop (#140, T622).
# The script reads/writes real git branch state, so each case runs the REAL script inside a
# throwaway git repo (the reconcile-task-selection.test.sh idiom) and asserts both the exit
# code and the resulting HEAD.
#
# The done-when criteria (#140) drive the cases:
#   DW1 — the maker's branch survives a switching auditor. The LOAD-BEARING case proves the
#         auditor's `git switch main` DID drift HEAD (fail-before — so the harness is not a
#         tautology) and the helper puts it back (pass-after). Without the helper HEAD stays
#         on main, so the "restored" assertion fails against unfixed behavior and passes after.
#   DW2 — auditors still read base state (penalizes over-restriction). After the restore the
#         NON-SWITCHING base reads (`git show main:<path>`, `git diff main..HEAD`) still return
#         correct base content — the fix does not blind the auditors.
#   DW3 — the restore runs on EVERY gate return path: exercised after BOTH a PASS-outcome state
#         (a fix-round commit on the branch) and a FAIL-outcome state (branch unchanged).
# Plus the no-op happy path, a detached-HEAD restore, the fail-LOUD paths (branch gone /
# unreadable git — the deliberate inverse of the reconcile hooks' fail-OPEN posture), usage
# guards, and two wiring assertions (CI runs this test; the dispatcher actually invokes the
# helper) — the P2 "machinery proves it is live" discipline, same as guard.test.sh.
# Bash + git only, <1s; wired into the `verify` CI job (.github/workflows/ci.yml).
# Run: bash .claude/hooks/restore-task-branch.test.sh
set -u

HOOKS="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HOOKS/restore-task-branch.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
pass=0
fail=0

ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); printf 'FAIL %s\n' "$1" >&2; }

# Current branch of repo <dir> ('' when detached).
head_branch() { git -C "$1" symbolic-ref --quiet --short HEAD 2>/dev/null || true; }

# run_restore <expected-exit> <dir> <name> [args...] — run the helper with <dir> as CWD, so
# its bare `git` resolves against the fixture repo.
run_restore() {
  local want="$1" dir="$2" name="$3"; shift 3
  local got=0
  ( cd "$dir" && bash "$SCRIPT" "$@" >/dev/null 2>&1 ) || got=$?
  if [ "$got" -eq "$want" ]; then ok; else bad "$name (want exit $want, got $got)"; fi
}

# new_repo <dir> — a repo on main with f="BASE" committed, plus a task branch feat/x one
# commit ahead changing f to "WORK" (so `git diff main..HEAD` is non-empty), left checked
# out ON feat/x — the gate's starting state (the maker sits on the task branch).
new_repo() {
  local d="$1"
  mkdir -p "$d"
  git init -q -b main "$d"
  git -C "$d" config user.email t@example.com
  git -C "$d" config user.name test
  printf 'BASE\n' > "$d/f"
  git -C "$d" add f
  git -C "$d" commit -q -m "chore: base content on main"
  git -C "$d" switch -q -c feat/x
  printf 'WORK\n' > "$d/f"
  git -C "$d" add f
  git -C "$d" commit -q -m "feat: [T999] the maker's work on the task branch"
}

# ── DW1 (load-bearing): an auditor's `git switch main` DID drift HEAD (fail-before), and the
#    helper restores it (pass-after). The fail-before assertion proves the drift really happens,
#    so the pass-after restore is not a tautology.
D="$TMP/dw1"; new_repo "$D"
git -C "$D" switch -q main          # the auditor step: a branch-switching git call in the shared tree
if [ "$(head_branch "$D")" = "main" ]; then ok; else bad "dw1 fail-before: auditor switch did not drift HEAD to main"; fi
run_restore 0 "$D" "dw1 pass-after: helper restores HEAD to the task branch" feat/x
if [ "$(head_branch "$D")" = "feat/x" ]; then ok; else bad "dw1 pass-after: HEAD not restored to feat/x"; fi

# ── DW2 (penalizes over-restriction): after the restore the auditors' NON-SWITCHING base reads
#    still return correct base content — the fix does not blind them. ($D is on feat/x now.)
base="$(git -C "$D" show main:f)"
if [ "$base" = "BASE" ]; then ok; else bad "dw2: git show main:f wrong after restore (got '$base')"; fi
if git -C "$D" diff main..HEAD | grep -q 'WORK'; then ok; else bad "dw2: git diff main..HEAD lost the task change after restore"; fi

# ── DW3: the restore runs on EVERY gate return path — the dispatcher invokes it after the gate
#    returns regardless of outcome. The helper is outcome-agnostic, so prove restoration in BOTH
#    a PASS-outcome state (a fix-round commit added to the branch) and a FAIL-outcome state (the
#    branch unchanged).
PASS_D="$TMP/dw3pass"; new_repo "$PASS_D"
printf 'WORK2\n' >> "$PASS_D/f"                        # a fix-round commit → the PASS-after-fix branch state
git -C "$PASS_D" add f
git -C "$PASS_D" commit -q -m "fix: [T999] address gate findings (round 1)"
git -C "$PASS_D" switch -q main                        # auditor drift
run_restore 0 "$PASS_D" "dw3 PASS outcome: restore after a passing gate (fix-round commit present)" feat/x
if [ "$(head_branch "$PASS_D")" = "feat/x" ]; then ok; else bad "dw3 PASS: HEAD not restored"; fi

FAIL_D="$TMP/dw3fail"; new_repo "$FAIL_D"
git -C "$FAIL_D" switch -q main                        # auditor drift
run_restore 0 "$FAIL_D" "dw3 FAIL outcome: restore after a failing gate (branch unchanged)" feat/x
if [ "$(head_branch "$FAIL_D")" = "feat/x" ]; then ok; else bad "dw3 FAIL: HEAD not restored"; fi

# ── No-op happy path: HEAD already on the task branch (no auditor drifted it) → exit 0, branch
#    unchanged, and SILENT on stdout (the backstop is cheap and quiet when nothing went wrong).
N="$TMP/noop"; new_repo "$N"
out="$( cd "$N" && bash "$SCRIPT" feat/x 2>/dev/null )"
run_restore 0 "$N" "no-op: already on the task branch exits 0" feat/x
if [ "$(head_branch "$N")" = "feat/x" ]; then ok; else bad "no-op: branch changed unexpectedly"; fi
if [ -z "$out" ]; then ok; else bad "no-op: happy path should be silent on stdout (got '$out')"; fi

# ── Detached HEAD: an auditor `git checkout --detach` detaches the shared tree; the helper
#    still reattaches HEAD to the task branch.
DET="$TMP/detached"; new_repo "$DET"
git -C "$DET" checkout -q --detach HEAD
if [ -z "$(head_branch "$DET")" ]; then ok; else bad "detached: setup did not detach HEAD"; fi
run_restore 0 "$DET" "detached: helper reattaches HEAD to the task branch" feat/x
if [ "$(head_branch "$DET")" = "feat/x" ]; then ok; else bad "detached: HEAD not reattached to feat/x"; fi

# ── Fail loud (branch gone): cannot restore onto a branch that does not exist → exit 1, never a
#    silent exit 0 that would strand the dispatcher on a drifted HEAD.
run_restore 1 "$D" "fail-loud: a nonexistent task branch exits 1" no/such-branch

# ── Fail loud (no repo): unreadable git state → exit 1. The INVERSE of the reconcile hooks'
#    fail-open posture — a state-protection backstop must not green-light an unverified HEAD.
NOGIT="$TMP/nogit"; mkdir -p "$NOGIT"
run_restore 1 "$NOGIT" "fail-loud: unreadable git state exits 1 (not fail-open)" feat/x

# ── Usage guards: no argument and an empty argument both exit 2.
run_restore 2 "$D" "usage: no argument exits 2"
run_restore 2 "$D" "usage: an empty argument exits 2" ""

# ── Wiring 1 (P2 "machinery proves it is live"): ci.yml must run this test, else the backstop's
#    own proof is dead.
CI="$HOOKS/../../.github/workflows/ci.yml"
if grep -qE 'restore-task-branch\.test\.sh' "$CI"; then ok
else bad "wiring: ci.yml verify does not run restore-task-branch.test.sh"; fi

# ── Wiring 2: the DISPATCHER must actually invoke the helper, else it is dead machinery — the
#    [orchestrated run] binding (next-task skill) references it on the post-gate path.
SKILL="$HOOKS/../skills/next-task/SKILL.md"
if grep -qE 'restore-task-branch\.sh' "$SKILL"; then ok
else bad "wiring: the [orchestrated run] binding (next-task SKILL.md) does not invoke restore-task-branch.sh"; fi

printf 'restore-task-branch.test.sh: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
