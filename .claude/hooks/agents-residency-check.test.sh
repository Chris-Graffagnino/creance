#!/usr/bin/env bash
# Regression tests for agents-residency-check.sh (issue #91). The check bounds
# AGENTS.md's line count because it is the L1 always-resident file (DESIGN-NOTES
# §11). Each case runs the REAL check with a throwaway dir as CWD (containing a
# fixture AGENTS.md of a known size), then asserts the exit code. This is the
# constitution-P2 backstop: the residency check ships with the test that proves
# it fires AND proves it does not false-fire. Bash + wc only, <1s; wired into the
# `verify` CI job (.github/workflows/ci.yml).
# Run: bash .claude/hooks/agents-residency-check.test.sh
set -u

CHECK="$(cd "$(dirname "$0")" && pwd)/agents-residency-check.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
pass=0
fail=0

# The ceiling the check enforces, read FROM the script so these tests track a
# tune to CEILING instead of hardcoding it twice.
CEILING=$(grep -E '^CEILING=' "$CHECK" | head -1 | cut -d= -f2)

# run_check <expected-exit> <dir> <name> — run the check with <dir> as CWD, so
# its AGENTS.md resolves against the fixture.
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

# mkfixture <dir> <nlines> — a dir holding an AGENTS.md of exactly <nlines> lines.
mkfixture() {
  local d="$1" n="$2"
  mkdir -p "$d"
  yes '# rule' | head -n "$n" > "$d/AGENTS.md"
}

# A: at the ceiling exactly -> pass (the boundary is inclusive).
A="$TMP/a-at-ceiling"; mkfixture "$A" "$CEILING"
run_check 0 "$A" "A boundary: AGENTS.md at the ceiling passes"

# B: one line over -> FAIL.
B="$TMP/b-over"; mkfixture "$B" "$((CEILING + 1))"
run_check 1 "$B" "B over: AGENTS.md one line over the ceiling FAILs"

# C: a terse file well under -> pass.
C="$TMP/c-under"; mkfixture "$C" 10
run_check 0 "$C" "C under: a terse AGENTS.md passes"

# D: no AGENTS.md in CWD -> FAIL loudly. A wrong CWD or a missing file is a
#    misconfiguration, never a clean result (no silent pass — the silent-death
#    class, DESIGN-NOTES §"the guard was silently dead").
D="$TMP/d-missing"; mkdir -p "$D"
run_check 1 "$D" "D missing: absent AGENTS.md FAILs (no silent pass)"

# CI wiring (the silent-death backstop): the check and its test are only live if
# the REQUIRED `verify` job actually RUNS them. A bare filename grep over the whole
# file is too loose (Codex review, #92): a commented, disabled, or moved-to-another-
# job copy would still satisfy it while `verify` no longer runs the gate. So scope
# to the `verify` job's body (the required check, PROJECT.md) and require an ACTIVE
# `run: bash <script>` step.
CI="$(cd "$(dirname "$0")" && pwd)/../../.github/workflows/ci.yml"
# Lines belonging to the `verify:` job: from its 2-space-indented key to the next
# 2-space-indented job key (or EOF). No awk interval syntax (portable to BSD awk).
verify_steps() { awk '/^  [A-Za-z]/ { inblk = ($0 ~ /^  verify:/) } inblk { print }' "$CI"; }
# 0 iff an active (uncommented) `run: bash <path>` step invokes $1 within verify.
runs_in_verify() { verify_steps | grep -qE "^[[:space:]]*run:[[:space:]]+bash[[:space:]]+$1([[:space:]]|\$)"; }
if runs_in_verify '\.claude/hooks/agents-residency-check\.sh'; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  printf 'FAIL %-58s verify must RUN agents-residency-check.sh (active run: step)\n' "wiring: residency check is an active verify step" >&2
fi
if runs_in_verify '\.claude/hooks/agents-residency-check\.test\.sh'; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  printf 'FAIL %-58s verify must RUN agents-residency-check.test.sh (active run: step)\n' "wiring: residency test is an active verify step" >&2
fi

printf 'agents-residency-check.test.sh: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
