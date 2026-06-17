#!/usr/bin/env bash
# Regression tests for next-task-budget-check.sh (issue #93). The check bounds
# .claude/workflow/next-task.md's line count (the harness's accretion-sink hub
# doc). Each case runs the REAL check with a throwaway dir as CWD (containing a
# fixture .claude/workflow/next-task.md of a known size), then asserts the exit
# code. Constitution-P2 backstop: the budget gate ships with the test that proves
# it fires AND proves it does not false-fire. Bash + wc only, <1s; wired into the
# `verify` CI job (.github/workflows/ci.yml).
# Run: bash .claude/hooks/next-task-budget-check.test.sh
set -u

CHECK="$(cd "$(dirname "$0")" && pwd)/next-task-budget-check.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
pass=0
fail=0

# Read the budget AND the measured file FROM the script, so these tests track a
# tune to CEILING or a path change instead of hardcoding either twice.
CEILING=$(grep -E '^CEILING=' "$CHECK" | head -1 | cut -d= -f2)
REL=$(grep -E '^FILE=' "$CHECK" | head -1 | cut -d= -f2 | tr -d '"')

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

# mkfixture <dir> <nlines> — a dir holding <REL> with exactly <nlines> lines.
mkfixture() {
  local d="$1" n="$2"
  mkdir -p "$d/$(dirname "$REL")"
  # content is irrelevant (we count lines); the leading '#' matters — GNU `yes`
  # parses a dash-leading arg as options ("yes: invalid option"), so the fixture
  # string must never start with '-'. (Caught by CI; macOS `yes` tolerates it.)
  yes '# step' | head -n "$n" > "$d/$REL"
}

# A: at the budget exactly -> pass (the boundary is inclusive).
A="$TMP/a-at-budget"; mkfixture "$A" "$CEILING"
run_check 0 "$A" "A boundary: next-task.md at the budget passes"

# B: one line over -> FAIL.
B="$TMP/b-over"; mkfixture "$B" "$((CEILING + 1))"
run_check 1 "$B" "B over: next-task.md one line over the budget FAILs"

# C: well under -> pass.
C="$TMP/c-under"; mkfixture "$C" 50
run_check 0 "$C" "C under: a tight next-task.md passes"

# D: missing -> FAIL loudly (no silent pass; a wrong CWD / missing file is a
#    misconfiguration, the silent-death class).
D="$TMP/d-missing"; mkdir -p "$D"
run_check 1 "$D" "D missing: absent next-task.md FAILs (no silent pass)"

# CI wiring (the silent-death backstop): the check and its test are only live if
# the REQUIRED `verify` job actually RUNS them. A bare filename grep over the whole
# file is too loose (tightened to match the sibling residency test after Codex's P2
# on #92): a commented, disabled, or moved-to-another-job copy would still satisfy
# it while `verify` no longer runs the gate. So scope to the `verify` job's body
# (the required check, PROJECT.md) and require an ACTIVE `run: bash <script>` step.
CI="$(cd "$(dirname "$0")" && pwd)/../../.github/workflows/ci.yml"
# Lines belonging to the `verify:` job: from its 2-space-indented key to the next
# 2-space-indented job key (or EOF). No awk interval syntax (portable to BSD awk).
verify_steps() { awk '/^  [A-Za-z]/ { inblk = ($0 ~ /^  verify:/) } inblk { print }' "$CI"; }
# 0 iff an active (uncommented) `run: bash <path>` step invokes $1 within verify.
runs_in_verify() { verify_steps | grep -qE "^[[:space:]]*run:[[:space:]]+bash[[:space:]]+$1([[:space:]]|\$)"; }
if runs_in_verify '\.claude/hooks/next-task-budget-check\.sh'; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  printf 'FAIL %-58s verify must RUN next-task-budget-check.sh (active run: step)\n' "wiring: budget check is an active verify step" >&2
fi
if runs_in_verify '\.claude/hooks/next-task-budget-check\.test\.sh'; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  printf 'FAIL %-58s verify must RUN next-task-budget-check.test.sh (active run: step)\n' "wiring: budget test is an active verify step" >&2
fi

printf 'next-task-budget-check.test.sh: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
