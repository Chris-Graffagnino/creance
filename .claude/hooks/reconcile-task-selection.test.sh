#!/usr/bin/env bash
# Regression tests for reconcile-task-selection.sh — the runtime /next-task selection
# precondition (issue #80, T608). The script reads `git log` + specs/*/tasks.md, so each
# case runs the REAL script inside a throwaway git repo (the check-tasks-consistency.test.sh
# idiom) seeded with a fixture tasks file plus fixture commits, then asserts the exit code.
#
# The load-bearing case is the PAIRED harness (done-when 2): ONE repo whose ONE tasks file
# holds an open task AND a drifted task — the same setup must SELECT the open one (exit 0)
# AND REFUSE the drifted one (exit 3), so "no false positives" cannot be satisfied by a
# precondition that never fires (or that flags every live-state read as drift). Plus the
# fail-open path (done-when 5), usage guards, and two wiring assertions: both consumers
# source the shared lib (done-when 4 "share, not duplicate", as a live check) and CI runs
# this test. Bash + git only, <1s; wired into the `verify` CI job (.github/workflows/ci.yml).
# Run: bash .claude/hooks/reconcile-task-selection.test.sh
set -u

HOOKS="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HOOKS/reconcile-task-selection.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
pass=0
fail=0

ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); printf 'FAIL %s\n' "$1" >&2; }

# run_recon <expected-exit> <repo-dir> <name> [script-args...] — run with the repo as CWD
# (so the script's specs/*/tasks.md glob and `git log` resolve against the fixture).
run_recon() {
  local want="$1" dir="$2" name="$3"; shift 3
  local got=0
  ( cd "$dir" && bash "$SCRIPT" "$@" >/dev/null 2>&1 ) || got=$?
  if [ "$got" -eq "$want" ]; then ok; else bad "$name (want exit $want, got $got)"; fi
}

# new_repo <dir> — a throwaway repo with one task-id-free bootstrap commit so `git log`
# works; the caller writes the fixture tasks file (working tree) and adds task-bearing commits.
new_repo() {
  local d="$1"
  mkdir -p "$d"
  git init -q -b main "$d"
  git -C "$d" config user.email t@example.com
  git -C "$d" config user.name test
  git -C "$d" commit -q --allow-empty -m "chore: bootstrap (no task id)"
}

# ── The paired harness (done-when 1 + 2): one repo, one tasks file, two tasks.
#    T910 is open (no commit carries its id); T911 is drifted (box `[ ]` but a [T911]
#    commit landed). The SAME setup must select T910 and refuse T911.
P="$TMP/paired"; new_repo "$P"; mkdir -p "$P/specs/feat"
printf -- '- [ ] T910 [cheap] genuinely open, no work yet (US1)\n- [ ] T911 [cheap] merged but box still unchecked (US1)\n' \
  > "$P/specs/feat/tasks.md"
git -C "$P" commit -q --allow-empty -m "feat: [T911] merged work for the drifted task"
run_recon 0 "$P" "paired: open task T910 is SELECTED (no false positive)" T910
run_recon 3 "$P" "paired: drifted task T911 is REFUSED" T911

# ── A ticked box with committed work is NOT drift (the normal done state).
C="$TMP/checked"; new_repo "$C"; mkdir -p "$C/specs/feat"
printf -- '- [x] T912 [cheap] done and ticked (US1)\n' > "$C/specs/feat/tasks.md"
git -C "$C" commit -q --allow-empty -m "feat: [T912] done work"
run_recon 0 "$C" "checked: a ticked box with committed work is selectable (not drift)" T912

# ── Whole-id match: a [T91] commit must NOT make an unchecked T913 look drifted.
S="$TMP/substr"; new_repo "$S"; mkdir -p "$S/specs/feat"
printf -- '- [ ] T913 [cheap] open task (US1)\n' > "$S/specs/feat/tasks.md"
git -C "$S" commit -q --allow-empty -m "fix: [T91] an unrelated, lower task"
run_recon 0 "$S" "substring: [T91] commit does not trip unchecked T913" T913

# ── Fail-open (done-when 5): no git state available -> exit 0 WITH a surfaced warning,
#    never a hard stall. A bare temp dir under $TMP is outside any repo.
NOGIT="$TMP/nogit"; mkdir -p "$NOGIT/specs/feat"
printf -- '- [ ] T914 [cheap] open task (US1)\n' > "$NOGIT/specs/feat/tasks.md"
run_recon 0 "$NOGIT" "fail-open: unreadable git state still allows selection" T914
warn="$( cd "$NOGIT" && bash "$SCRIPT" T914 2>&1 )"
case "$warn" in
  *fail-open*) ok ;;
  *) bad "fail-open: missing surfaced warning (got: $warn)" ;;
esac

# ── Usage guards: no argument and a non-task argument both exit 2.
run_recon 2 "$P" "usage: no argument exits 2"
run_recon 2 "$P" "usage: a non-task argument exits 2" not-a-task

# ── Share, not duplicate (done-when 4): BOTH the CI gate and the selector source the shared
#    lib, so the drift definition has exactly one home. A future fork that re-implements the
#    detection would drop one of these source lines and FAIL here.
for consumer in check-tasks-consistency.sh reconcile-task-selection.sh; do
  if grep -qE 'lib-tasks-drift\.sh' "$HOOKS/$consumer"; then ok
  else bad "share: $consumer does not source lib-tasks-drift.sh (forked drift logic?)"; fi
done

# ── CI wiring: ci.yml must run this test, else the precondition's machinery is unproven
#    (the silently-dead-machinery class, P2 — same posture as check-tasks-consistency.test.sh).
CI="$HOOKS/../../.github/workflows/ci.yml"
if grep -qE 'reconcile-task-selection\.test\.sh' "$CI"; then ok
else bad "wiring: ci.yml verify does not run reconcile-task-selection.test.sh"; fi

printf 'reconcile-task-selection.test.sh: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
