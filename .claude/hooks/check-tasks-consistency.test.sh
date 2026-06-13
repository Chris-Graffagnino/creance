#!/usr/bin/env bash
# Regression tests for check-tasks-consistency.sh rule 3 — the "done-but-
# unchecked" checkbox-drift gate (issue #69). Rule 3 reads `git log` commit
# subjects, so each case runs the REAL check inside a throwaway git repo (the
# guard.test.sh idiom for stubbing git state) seeded with a fixture
# specs/<f>/tasks.md on disk plus fixture commits, then asserts the exit code.
# This is the constitution-P2 backstop: the drift gate ships with the test that
# proves it fires AND proves it does not false-fire. Bash + git only, <1s;
# wired into the `verify` CI job (.github/workflows/ci.yml).
# Run: bash .claude/hooks/check-tasks-consistency.test.sh
set -u

CHECK="$(cd "$(dirname "$0")" && pwd)/check-tasks-consistency.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
pass=0
fail=0

# run_check <expected-exit> <repo-dir> <name> — run the check with the repo as
# CWD (so its specs/*/tasks.md glob and git log resolve against the fixture).
run_check() {
  local want="$1" dir="$2" name="$3" got=0
  ( cd "$dir" && bash "$CHECK" >/dev/null 2>&1 ) || got=$?
  if [ "$got" -eq "$want" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL %-58s want exit %s, got %s\n' "$name" "$want" "$got" >&2
  fi
}

# new_repo <dir> — a throwaway repo with one task-id-free bootstrap commit so
# `git log` works; the caller writes the fixture tasks file (working tree only —
# the check globs the filesystem, not the index) and adds task-bearing commits.
new_repo() {
  local d="$1"
  mkdir -p "$d"
  git init -q -b main "$d"
  git -C "$d" config user.email t@example.com
  git -C "$d" config user.name test
  git -C "$d" commit -q --allow-empty -m "chore: bootstrap (no task id)"
}

# A: drift — task is `[ ]` but a reachable commit carries its [id] -> FAIL.
A="$TMP/a-drift"; new_repo "$A"; mkdir -p "$A/specs/feat"
printf -- '- [ ] T901 [cheap] build the widget (US1)\n' > "$A/specs/feat/tasks.md"
git -C "$A" commit -q --allow-empty -m "feat: [T901] build the widget"
run_check 1 "$A" "A drift: unchecked task with committed work FAILs"

# B: clean — the same task ticked `[x]` -> pass.
B="$TMP/b-clean"; new_repo "$B"; mkdir -p "$B/specs/feat"
printf -- '- [x] T901 [cheap] build the widget (US1)\n' > "$B/specs/feat/tasks.md"
git -C "$B" commit -q --allow-empty -m "feat: [T901] build the widget"
run_check 0 "$B" "B clean: checked task with committed work passes"

# C: not-yet-done — task `[ ]` with NO commit carrying its id -> pass. This is
#    the T302/T303/T401/T402 class: genuinely unstarted tasks must not trip it.
C="$TMP/c-future"; new_repo "$C"; mkdir -p "$C/specs/feat"
printf -- '- [ ] T902 [cheap] not started yet (US1)\n' > "$C/specs/feat/tasks.md"
run_check 0 "$C" "C future: unchecked task with no committed work passes"

# D: substring — a [T90] commit must NOT trip an unchecked T901 (whole-id match,
#    not a substring search).
D="$TMP/d-substr"; new_repo "$D"; mkdir -p "$D/specs/feat"
printf -- '- [ ] T901 [cheap] build the widget (US1)\n' > "$D/specs/feat/tasks.md"
git -C "$D" commit -q --allow-empty -m "fix: [T90] an unrelated, lower task"
run_check 0 "$D" "D substring: [T90] commit does not trip unchecked T901"

# E: template scope — *.template.md tasks files are outside rule 3's glob, the
#    same live-backlog scope rules 1-2 use (only specs/*/tasks.md counts).
E="$TMP/e-template"; new_repo "$E"; mkdir -p "$E/specs/000-template"
printf -- '- [ ] T903 [cheap] skeleton placeholder (US1)\n' > "$E/specs/000-template/tasks.template.md"
git -C "$E" commit -q --allow-empty -m "docs: [T903] skeleton example"
run_check 0 "$E" "E template: drift rule ignores *.template.md tasks files"

# F: multiple live tasks files — drift in any one of them is still caught.
F="$TMP/f-multi"; new_repo "$F"; mkdir -p "$F/specs/one" "$F/specs/two"
printf -- '- [x] T801 [cheap] done and ticked (US1)\n' > "$F/specs/one/tasks.md"
printf -- '- [ ] T802 [cheap] done but unticked (US1)\n' > "$F/specs/two/tasks.md"
git -C "$F" commit -q --allow-empty -m "feat: [T801] one"
git -C "$F" commit -q --allow-empty -m "feat: [T802] two"
run_check 1 "$F" "F multi-file: drift in a second live tasks file FAILs"

# CI wiring (the silent-death backstop, #70): rule 3 walks `git log`, but
# actions/checkout fetches a single commit by default — on a pull_request that
# is the merge commit (subject "Merge pull request ...", no [T###]), so
# committed_ids is empty and rule 3 passes vacuously: the gate silently dead in
# CI (the DESIGN-NOTES §"the guard was silently dead" class). Assert ci.yml's
# checkout sets fetch-depth: 0 so a future edit cannot re-introduce the silent
# death undetected — same posture as guard.test.sh's PreToolUse-matcher assertion.
CI="$(cd "$(dirname "$0")" && pwd)/../../.github/workflows/ci.yml"
if grep -qE '(^|[[:space:]])uses:[[:space:]]*actions/checkout' "$CI" \
   && grep -qE '(^|[[:space:]])fetch-depth:[[:space:]]*0([[:space:]]|$)' "$CI"; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  printf 'FAIL %-58s ci.yml checkout must set fetch-depth: 0 (rule 3 needs full history)\n' "wiring: CI fetches full history for rule 3" >&2
fi

printf 'check-tasks-consistency.test.sh: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
