#!/usr/bin/env bash
# Regression tests for governance-coverage-check.sh (T1206/#252; spec 007
# US6.AC1/AC3). Two-sided per the US6.AC1 rule for new checks: every planted
# violation direction FAILs *naming its repair target* (US6.AC3), and the
# in-sync fixture AND the real repo both pass — so the check is proven to fire
# and proven not to false-fire. Each case builds a throwaway fixture root
# replicating the repo layout (registry + check files + wiring file), cds
# there, and runs the REAL check (the agents-residency-check.test.sh pattern).
# Bash + grep only, <1s; wired into the `verify` CI job
# (.github/workflows/ci.yml), and section W below asserts that wiring.
# Run: bash .claude/hooks/governance-coverage-check.test.sh
set -u

CHECK="$(cd "$(dirname "$0")" && pwd)/governance-coverage-check.sh"
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
pass=0
fail=0

# run_case <expected-exit> <dir> <name> [<must-name-in-stderr>] — run the check
# with <dir> as CWD; assert the exit code, and (when given) that stderr names
# the expected repair target (the US6.AC3 half of the assertion).
run_case() {
  local want="$1" dir="$2" name="$3" must="${4:-}" got=0 out
  out="$( (cd "$dir" && bash "$CHECK") 2>&1 )" || got=$?
  if [ "$got" -ne "$want" ]; then
    fail=$((fail + 1))
    printf 'FAIL %-62s want exit %s, got %s\n' "$name" "$want" "$got" >&2
    return
  fi
  if [ -n "$must" ] && ! printf '%s' "$out" | grep -qF -- "$must"; then
    fail=$((fail + 1))
    printf 'FAIL %-62s diagnostics must name: %s\n' "$name" "$must" >&2
    return
  fi
  pass=$((pass + 1))
}

# mkfixture <dir> — an in-sync fixture root: 3-row registry (carried, cited,
# prose-P3), check files carrying their anchors, wiring file running both.
mkfixture() {
  local d="$1"
  mkdir -p "$d/.claude/hooks" "$d/.github/workflows"
  printf '%s\n' \
    '# case: settings #165: no gh pr merge pre-approval' \
    > "$d/.claude/hooks/guard.test.sh"
  printf '%s\n' \
    '# flag: --require-counter' \
    > "$d/.claude/hooks/token-budget-check.sh"
  printf '%s\n' \
    'run: bash .claude/hooks/guard.test.sh' \
    'run: bash .claude/hooks/token-budget-check.sh --require-counter' \
    > "$d/.github/workflows/ci.yml"
  cat > "$d/.claude/governance-rules.md" <<'REG'
| rule | status | check | anchor | wiring |
|---|---|---|---|---|
| `merge-not-pre-approved` | `encoded-carried` | `.claude/hooks/guard.test.sh` | `settings #165: no gh pr merge pre-approval` | `.github/workflows/ci.yml` |
| `budget-checks-wired` | `encoded-cited` | `.claude/hooks/token-budget-check.sh` | `--require-counter` | `.github/workflows/ci.yml` |
| `pr-creation-after-documented-review` | `prose-P3` | — | — | — |

### P3 justification — pr-creation-after-documented-review
procedural; see the real registry.
REG
}

# --- passing direction ---
D="$TMP/ok"; mkfixture "$D"
run_case 0 "$D" "in-sync fixture passes"

run_case 0 "$REPO_ROOT" "real repo passes (in-sync control)"

# --- planted violations: each FAILs naming its repair target (US6.AC3) ---
D="$TMP/anchor-gone"; mkfixture "$D"
printf '# the case was deleted\n' > "$D/.claude/hooks/guard.test.sh"
run_case 1 "$D" "carried anchor removed -> FAIL names the check file" \
  "no longer appears in .claude/hooks/guard.test.sh"

D="$TMP/unwired"; mkfixture "$D"
printf 'run: something else entirely\n' > "$D/.github/workflows/ci.yml"
run_case 1 "$D" "wiring dropped -> FAIL names the wiring file" \
  "no active run: step in .github/workflows/ci.yml invokes .claude/hooks/guard.test.sh"

# The named check must run in an ACTIVE run: step; a comment merely naming it
# must NOT satisfy the backstop. The real ci.yml is full of "same as
# guard.test.sh" prose, so a raw whole-file grep (the pre-#253 shape) let a
# comment keep a removed rule reported "live" — this plants exactly that.
D="$TMP/wiring-comment-only"; mkfixture "$D"
printf '%s\n' \
  '# bash .claude/hooks/guard.test.sh  # (moved out of verify but still named here)' \
  'run: bash .claude/hooks/token-budget-check.sh --require-counter' \
  > "$D/.github/workflows/ci.yml"
run_case 1 "$D" "check named only in a comment (no run: step) -> FAIL" \
  "no active run: step in .github/workflows/ci.yml invokes .claude/hooks/guard.test.sh"

D="$TMP/check-gone"; mkfixture "$D"
rm "$D/.claude/hooks/guard.test.sh"
run_case 1 "$D" "check file missing -> FAIL names it" \
  "check file .claude/hooks/guard.test.sh is missing"

D="$TMP/cited-anchor-gone"; mkfixture "$D"
printf '# flag renamed\n' > "$D/.claude/hooks/token-budget-check.sh"
run_case 1 "$D" "cited anchor (leading dashes) removed -> FAIL names the file" \
  "'--require-counter' no longer appears in .claude/hooks/token-budget-check.sh"

D="$TMP/no-justification"; mkfixture "$D"
sed -i.bak '/P3 justification/d' "$D/.claude/governance-rules.md" && rm -f "$D/.claude/governance-rules.md.bak"
run_case 1 "$D" "P3 justification dropped -> FAIL names the registry" \
  "lacks its '### P3 justification — pr-creation-after-documented-review'"

D="$TMP/bad-status"; mkfixture "$D"
sed -i.bak 's/encoded-carried/encoded-someday/' "$D/.claude/governance-rules.md" && rm -f "$D/.claude/governance-rules.md.bak"
run_case 1 "$D" "unknown status -> FAIL names the registry" \
  "unknown status 'encoded-someday'"

# --- registry-shape guards: never a vacuous pass ---
D="$TMP/no-registry"; mkdir -p "$D"
run_case 1 "$D" "missing registry -> FAIL loud" \
  "governance registry .claude/governance-rules.md not found"

D="$TMP/empty-table"; mkfixture "$D"
grep -v '^|' "$D/.claude/governance-rules.md" > "$D/.claude/governance-rules.md.tmp" \
  && mv "$D/.claude/governance-rules.md.tmp" "$D/.claude/governance-rules.md"
run_case 1 "$D" "registry with no table rows -> FAIL loud" \
  "no rules parsed"

# --- W: CI wiring (the silent-death backstop, same discipline as the token-budget
# tests, token-budget-check.test.sh §J): the verify job must actively RUN both the
# check and this test file in a run: step — a comment merely naming them must NOT
# count (#253 review) — else the coverage assertion is itself silently dead (P2).
# Scoped to the verify job body, active run: lines only (the token-budget idiom).
CI="$REPO_ROOT/.github/workflows/ci.yml"
verify_steps() { awk '/^  [A-Za-z]/ { inblk = ($0 ~ /^  verify:/) } inblk { print }' "$CI"; }
for f in governance-coverage-check.sh governance-coverage-check.test.sh; do
  esc="${f//./\\.}"                                  # escape dots for the -E pattern
  if verify_steps | grep -qE "^[[:space:]]*run:[[:space:]]+bash[[:space:]]+\.claude/hooks/${esc}([[:space:]]|\$)"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL %-62s verify (ci.yml) must actively RUN %s in a run: step\n' "wiring: ci.yml runs $f" "$f" >&2
  fi
done

printf 'governance-coverage-check.test.sh: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
