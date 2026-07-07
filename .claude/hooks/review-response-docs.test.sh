#!/usr/bin/env bash
# Encoding tests for issue #255 acceptance criteria (T640 — review-response workflow + skill).
#
# review-response is runtime-neutral prose executed by the engine —
# `.claude/workflow/review-response.md` (and its Claude binding
# `.claude/skills/review-response/SKILL.md`) ARE the implementation; there is no
# executable code path to unit-test. These tests encode each DONE-WHEN criterion
# (#255 DW1–DW7) against that surface, so a later edit that drops a load-bearing
# clause fails the `verify` CI job (constitution P3: a rule a deterministic check
# can enforce must have that check). It is the write-direction mirror of
# pr-review-docs.test.sh: the defining bound here is that a fix RE-ENTERS the §7
# gate (maker ≠ checker) and is never self-certified, and the workflow never merges.
#
# Run: bash .claude/hooks/review-response-docs.test.sh
set -u

DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib-neutrality-scan.sh
. "$DIR/hooks/lib-neutrality-scan.sh"
WF="$DIR/workflow/review-response.md"
SK="$DIR/skills/review-response/SKILL.md"

pass=0
fail=0

# Normalize whitespace so assertions survive prose re-wrapping.
flat() { tr -s '[:space:]' ' ' < "$1"; }

check() { # check <name> <haystack> <needle (grep -F fixed string)>
  local name="$1" hay="$2" needle="$3"
  if printf '%s' "$hay" | grep -qF -- "$needle"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL %s\n     missing: %s\n' "$name" "$needle" >&2
  fi
}

for f in "$WF" "$SK"; do
  if [ ! -f "$f" ]; then
    echo "FAIL: required file missing: $f" >&2
    exit 1
  fi
done

WF_FLAT="$(flat "$WF")"
SK_FLAT="$(flat "$SK")"

# ── DW1 — neutral procedure in workflow/**, composes roles, adds no new binding row ──
check "DW1 neutral: composes existing roles" "$WF_FLAT" \
  "composes existing roles"
check "DW1 neutral: no new binding-contract row" "$WF_FLAT" \
  "introduces no new binding-contract row"
# Neutrality is enforced negatively too: no concrete runtime mechanism (CLI/tool/model
# name) may appear in the neutral doc. `git` is the assumed VCS substrate (exempt per
# constitution P1); the `.claude/` profile pointer is stripped before scanning.
mech="$(neutral_mechanism_leaks "$WF")"
if [ -z "$mech" ]; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  printf 'FAIL DW1 neutral: concrete runtime mechanism leaked into the neutral doc\n     found: %s\n' "$mech" >&2
fi

# ── DW2 — Claude skill binding, points at the neutral doc, references single-copy blocks ──
check "DW2 binding: points at the neutral doc" "$SK_FLAT" \
  ".claude/workflow/review-response.md"
check "DW2 binding: read-and-execute handoff (mirrors other skills)" "$SK_FLAT" \
  "read that file now and execute it."
check "DW2 binding: references the single-copy comment marker" "$SK_FLAT" \
  "The [comment marker] concrete form"
check "DW2 binding: references the single-copy environment block" "$SK_FLAT" \
  "This environment's concrete forms"

# ── DW3 — a fix RE-ENTERS the §7 gate (maker ≠ checker); no self-certified repair ──
check "DW3 neutral: heading names the maker-not-checker re-gate" "$WF_FLAT" \
  "Re-gate the fixes (maker is not the checker"
check "DW3 neutral: a fix is fresh maker work (premise of the re-gate)" "$WF_FLAT" \
  "A fix is fresh maker work"
check "DW3 neutral: re-run the pre-PR gate on the fix commit" "$WF_FLAT" \
  "pre-PR gate on the fix commit"
check "DW3 neutral: no self-certified repair" "$WF_FLAT" \
  "self-certify a repair"
check "DW3 binding: re-gate is not optional" "$SK_FLAT" \
  "Re-gate is not optional"
check "DW3 binding: never push a fix as resolved unilaterally" "$SK_FLAT" \
  "never push a fix as"

# ── DW4 — red→green proof for behavior fixes; out-of-scope → discovered work, not the diff ──
check "DW4 neutral: minimum scoped change" "$WF_FLAT" \
  "minimum scoped change"
check "DW4 neutral: red→green (fails on pre-fix, passes on fix)" "$WF_FLAT" \
  "fails on the pre-fix code and passes on the fix"
check "DW4 neutral: out-of-scope finding → discovered work, not the diff" "$WF_FLAT" \
  "File it as discovered work"

# ── DW5 — enumerate every inline comment (bots by [bot] suffix); reply ledger ──
check "DW5 neutral: enumerate first, filter second" "$WF_FLAT" \
  "Enumerate first, filter second"
check "DW5 neutral: bot/automated inline findings in scope (the Codex case)" "$WF_FLAT" \
  "bot/automated inline findings"
check "DW5 neutral: reply ledger is the none-skipped evidence" "$WF_FLAT" \
  "reply ledger"
check "DW5 binding: fetch inline review comments endpoint" "$SK_FLAT" \
  "pulls/<n>/comments"
check "DW5 binding: fetch review-summaries endpoint (some bots post here)" "$SK_FLAT" \
  "pulls/<n>/reviews"
check "DW5 binding: bots matched by their [bot] login suffix" "$SK_FLAT" \
  '`[bot]` login suffix'
check "DW5 binding: the concrete bot login that bit us" "$SK_FLAT" \
  "chatgpt-codex-connector[bot]"
check "DW5 binding: enumerate first, filter second" "$SK_FLAT" \
  "enumerate first, filter second"

# ── DW6 — never merges/closes; changes no §7 gate semantics; green-PR terminal ──
check "DW6 neutral: never merges" "$WF_FLAT" \
  "never merges"
check "DW6 neutral: do not merge (owner-only, session-explicit)" "$WF_FLAT" \
  "Do not merge"
check "DW6 neutral: terminal state is a green PR, every comment answered" "$WF_FLAT" \
  "green PR with every comment answered"
check "DW6 binding: merge/close pinned OUT OF SCOPE (the prohibition, not mere presence)" "$SK_FLAT" \
  '`gh pr merge` / `gh pr close` are out of scope'
check "DW6 binding: write posture pushes to the PR branch" "$SK_FLAT" \
  "pushes to the PR branch"
check "DW6 binding: adds no second gate (no new §7 semantics)" "$SK_FLAT" \
  "does not create a second gate"

# ── scoping — the fix + re-gate grade the PR's own head (checkout) ──
check "scoping (binding): check out the PR head before fixing/re-gating" "$SK_FLAT" \
  "Check out the PR head before fixing or re-gating"
check "scoping (binding): concrete checkout mechanism" "$SK_FLAT" \
  "gh pr checkout <n>"

# ── DW7 — CI wiring (the silent-death backstop): the REQUIRED verify job must RUN this test.
# A bare filename grep is too loose (Codex #92): a commented/moved copy would satisfy it while
# verify no longer runs the gate. Scope to the verify job body and require an ACTIVE run: step. ──
CI="$(cd "$(dirname "$0")" && pwd)/../../.github/workflows/ci.yml"
verify_steps() { awk '/^  [A-Za-z]/ { inblk = ($0 ~ /^  verify:/) } inblk { print }' "$CI"; }
runs_in_verify() { verify_steps | grep -qE "^[[:space:]]*run:[[:space:]]+bash[[:space:]]+$1([[:space:]]|\$)"; }
if runs_in_verify '\.claude/hooks/review-response-docs\.test\.sh'; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  printf 'FAIL %-58s verify must RUN review-response-docs.test.sh (active run: step)\n' "wiring: review-response test is an active verify step" >&2
fi

echo "review-response docs encoding tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
