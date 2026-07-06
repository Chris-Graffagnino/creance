#!/usr/bin/env bash
# Regression tests for token-budget-check.sh (T1201, spec 007 US1; epic #166).
#
# The constitution-P2 pairing: the budget check ships with the tests that prove
# it FIRES (a planted over-budget fixture fails naming the offending artifact
# and its measured count — US1.AC3's failure direction) AND does not false-fire
# (a within-budget control passes — the other direction), plus the
# deferred-gating semantics, the fail-open/--require-counter split, the
# registry-shape guards, and the CI-wiring assertions (US1.AC2). Each case runs
# the REAL check with a throwaway dir as CWD holding a fixture registry +
# files, then asserts exit code and (where the criterion demands it) output.
#
# The counter itself (tiktoken, o200k_base — identity per
# .claude/context-budgets.md) is REQUIRED here: a run that skipped the
# measuring cases would be the silently-dead-machinery class. CI installs the
# counter in the verify job before running this.
# Run: bash .claude/hooks/token-budget-check.test.sh
set -u

HOOKS="$(cd "$(dirname "$0")" && pwd)"
CHECK="$HOOKS/token-budget-check.sh"
REPO_ROOT="$(cd "$HOOKS/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
pass=0
fail=0

if ! python3 -c 'import tiktoken' >/dev/null 2>&1; then
  echo "FAIL: these tests need the counter (python3 + tiktoken, o200k_base per .claude/context-budgets.md)." >&2
  echo "      A skipped measuring test is dead machinery (P2) — install tiktoken and re-run." >&2
  exit 1
fi

ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); printf 'FAIL %s\n' "$1" >&2; }

# run_check <dir> [args...] — run the real check with <dir> as CWD; capture
# combined output in $OUT and exit code in $GOT.
run_check() {
  local dir="$1"; shift
  GOT=0
  OUT="$( (cd "$dir" && bash "$CHECK" "$@") 2>&1 )" || GOT=$?
}

# mkfixture <dir> <registry-rows...> — a fixture repo dir whose registry holds
# the given table rows (one argument per row).
mkfixture() {
  local d="$1"; shift
  mkdir -p "$d/.claude"
  {
    echo '| surface | mode | budget (tokens) | gating | composition |'
    echo '|---|---|---|---|---|'
    local row
    for row in "$@"; do echo "$row"; done
  } > "$d/.claude/context-budgets.md"
}

# --- A/B: the US1.AC3 pair — planted over-budget FAILs naming artifact +
#     measured count; within-budget control passes. -------------------------
A="$TMP/a-over"
mkfixture "$A" '| `fat-doc` | `total` | `3` | `active` | `fat.md` |'
printf 'a planted fixture holding clearly more than three tokens of text\n' > "$A/fat.md"
run_check "$A"
if [ "$GOT" -eq 1 ]; then ok; else bad "A over-budget active fixture must exit 1 (got $GOT)"; fi
if printf '%s' "$OUT" | grep -q "surface 'fat-doc' measured [0-9][0-9]* tokens, over its 3-token budget"; then
  ok
else
  bad "A failure output must name the artifact and its measured count"
fi
if printf '%s' "$OUT" | grep -q 'override path'; then ok; else bad "A failure output must point at the override/repair path"; fi

B="$TMP/b-within"
mkfixture "$B" '| `fat-doc` | `total` | `100000` | `active` | `fat.md` |'
cp "$A/fat.md" "$B/fat.md"
run_check "$B"
if [ "$GOT" -eq 0 ]; then ok; else bad "B within-budget active control must pass (got $GOT)"; fi

# --- C: boundary is inclusive and the comparison is exact — a surface AT its
#     measured count passes; one token under FAILs. -------------------------
C="$TMP/c-boundary"
mkfixture "$C" '| `doc` | `total` | `100000` | `active` | `doc.md` |'
printf 'boundary fixture: measure me exactly\n' > "$C/doc.md"
run_check "$C"
measured="$(printf '%s' "$OUT" | sed -n 's/^  total: \([0-9][0-9]*\) tokens$/\1/p' | head -1)"
if [ -n "$measured" ] && [ "$measured" -gt 1 ]; then ok; else bad "C could not read the measured total from the report"; fi
mkfixture "$C" "| \`doc\` | \`total\` | \`$measured\` | \`active\` | \`doc.md\` |"
run_check "$C"
if [ "$GOT" -eq 0 ]; then ok; else bad "C at-budget surface must pass (inclusive boundary; got $GOT)"; fi
mkfixture "$C" "| \`doc\` | \`total\` | \`$((measured - 1))\` | \`active\` | \`doc.md\` |"
run_check "$C"
if [ "$GOT" -eq 1 ]; then ok; else bad "C one-token-under budget must FAIL (got $GOT)"; fi

# --- D: deferred gating — an over-budget deferred surface is reported, never
#     failed (US1.AC1's deferred-activation rule). --------------------------
D="$TMP/d-deferred"
mkfixture "$D" '| `fat-doc` | `total` | `3` | `deferred` | `fat.md` |'
cp "$A/fat.md" "$D/fat.md"
run_check "$D"
if [ "$GOT" -eq 0 ]; then ok; else bad "D over-budget deferred surface must still pass (got $GOT)"; fi
if printf '%s' "$OUT" | grep -q 'deferred'; then ok; else bad "D deferred overage must still be reported"; fi

# --- E: each-mode — the per-file budget FAILs the offending card only, and
#     per-file counts are reported (US1.AC1 per-file reporting). ------------
E="$TMP/e-each"
mkfixture "$E" '| `cards` | `each` | `4` | `active` | `cards/*.md` |'
mkdir -p "$E/cards"
printf 'tiny\n' > "$E/cards/small.md"
printf 'this card clearly exceeds a four token per-file budget by some margin\n' > "$E/cards/big.md"
run_check "$E"
if [ "$GOT" -eq 1 ]; then ok; else bad "E each-mode over-budget card must exit 1 (got $GOT)"; fi
if printf '%s' "$OUT" | grep -q "cards/big.md measured [0-9][0-9]* tokens, over the 4-token per-file budget"; then
  ok
else
  bad "E failure must name the offending card and its measured count"
fi
if printf '%s' "$OUT" | grep -q 'cards/small.md measured'; then
  bad "E must not fail the within-budget card"
else
  ok
fi
if printf '%s' "$OUT" | grep -Eq '^  [0-9]+	cards/small\.md$'; then ok; else bad "E report must carry per-file counts"; fi

# --- F: registered-but-unlanded — a deferred surface matching no files is
#     reported and passes; an ACTIVE surface matching no files FAILs loud
#     (misconfiguration, never a silent pass). ------------------------------
F="$TMP/f-unlanded"
mkfixture "$F" '| `future` | `total` | `100` | `deferred` | `not-yet.md` |'
run_check "$F"
if [ "$GOT" -eq 0 ] && printf '%s' "$OUT" | grep -q 'not yet landed'; then ok; else bad "F deferred unlanded surface must pass with a registered note (got $GOT)"; fi
mkfixture "$F" '| `future` | `total` | `100` | `active` | `not-yet.md` |'
run_check "$F"
if [ "$GOT" -eq 1 ]; then ok; else bad "F active surface with no files must FAIL loud (got $GOT)"; fi

# --- F2: partial composition miss — an ACTIVE surface with one matched file
#     and one unmatched token FAILs naming the token (a renamed/typo'd path
#     must never silently under-count past a gate); the same partial miss on a
#     deferred surface passes with a note. ----------------------------------
F2="$TMP/f2-partial"
mkfixture "$F2" '| `bundle` | `total` | `100000` | `active` | `real.md` `renamed-away.md` |'
printf 'the file that still exists\n' > "$F2/real.md"
run_check "$F2"
if [ "$GOT" -eq 1 ]; then ok; else bad "F2 active surface with an unmatched token must FAIL (got $GOT)"; fi
if printf '%s' "$OUT" | grep -q 'renamed-away.md match no files'; then ok; else bad "F2 failure must name the unmatched token"; fi
mkfixture "$F2" '| `bundle` | `total` | `100000` | `deferred` | `real.md` `renamed-away.md` |'
run_check "$F2"
if [ "$GOT" -eq 0 ] && printf '%s' "$OUT" | grep -q 'unmatched composition token'; then ok; else bad "F2 deferred partial miss must pass with a note (got $GOT)"; fi

# --- F3: the composition grammar is `*`-only (documented in the registry) — a
#     token using another glob metacharacter is a literal path, so it stays
#     unmatched even when files the pattern *would* match exist. -------------
F3="$TMP/f3-star-only"
mkfixture "$F3" '| `bundle` | `total` | `100000` | `active` | `cards/[ab].md` |'
mkdir -p "$F3/cards"
printf 'exists, but only a star-glob may match me\n' > "$F3/cards/a.md"
run_check "$F3"
if [ "$GOT" -eq 1 ] && printf '%s' "$OUT" | grep -q 'cards/\[ab\]\.md match no files'; then
  ok
else
  bad "F3 non-star glob token must stay literal (unmatched -> active FAIL; got $GOT)"
fi

# --- G: registry-shape guards — missing registry, empty table, bad
#     mode/gating/budget all FAIL loud naming the repair target. ------------
G="$TMP/g-shape"
mkdir -p "$G"
run_check "$G"
if [ "$GOT" -eq 1 ]; then ok; else bad "G missing registry must FAIL (got $GOT)"; fi
mkfixture "$G"
run_check "$G"
if [ "$GOT" -eq 1 ] && printf '%s' "$OUT" | grep -q 'no surface rows'; then ok; else bad "G empty surfaces table must FAIL loud (got $GOT)"; fi
mkfixture "$G" '| `doc` | `sideways` | `10` | `active` | `doc.md` |'
run_check "$G"
if [ "$GOT" -eq 1 ] && printf '%s' "$OUT" | grep -q "unknown mode 'sideways'"; then ok; else bad "G unknown mode must FAIL naming the repair (got $GOT)"; fi
mkfixture "$G" '| `doc` | `total` | `10` | `maybe` | `doc.md` |'
run_check "$G"
if [ "$GOT" -eq 1 ] && printf '%s' "$OUT" | grep -q "unknown gating 'maybe'"; then ok; else bad "G unknown gating must FAIL naming the repair (got $GOT)"; fi
mkfixture "$G" '| `doc` | `total` | `lots` | `active` | `doc.md` |'
run_check "$G"
if [ "$GOT" -eq 1 ] && printf '%s' "$OUT" | grep -q "non-numeric budget"; then ok; else bad "G non-numeric budget must FAIL naming the repair (got $GOT)"; fi

# --- H: the counter-availability split — unavailable counter fails OPEN
#     (warn, exit 0) by default and CLOSED under --require-counter (the CI
#     posture: verification never goes silently green unmeasured). ----------
H="$TMP/h-counter"
mkfixture "$H" '| `doc` | `total` | `3` | `active` | `doc.md` |'
cp "$A/fat.md" "$H/doc.md"
GOT=0
OUT="$( (cd "$H" && TOKEN_BUDGET_PYTHON=/nonexistent-interpreter bash "$CHECK") 2>&1 )" || GOT=$?
if [ "$GOT" -eq 0 ] && printf '%s' "$OUT" | grep -q 'WARN: token counter unavailable'; then
  ok
else
  bad "H missing counter must fail OPEN with a loud warning (got $GOT)"
fi
GOT=0
OUT="$( (cd "$H" && TOKEN_BUDGET_PYTHON=/nonexistent-interpreter bash "$CHECK" --require-counter) 2>&1 )" || GOT=$?
if [ "$GOT" -eq 1 ]; then ok; else bad "H --require-counter must turn a missing counter into a hard FAIL (got $GOT)"; fi

# --- K: a counting failure PAST the import probe (encoding fetch/load
#     failure, unreadable matched file) is a hard FAIL on any surface — never
#     a silent `total: 0` that lets --require-counter go green unmeasured. ---
K="$TMP/k-broken-counter"
mkfixture "$K" '| `doc` | `total` | `100000` | `active` | `doc.md` |'
printf 'a file the broken counter never measures\n' > "$K/doc.md"
cat > "$K/fake-python" <<'FAKE'
#!/usr/bin/env bash
# Passes the import probe (any -c invocation) but explodes during counting.
for a in "$@"; do [ "$a" = "-c" ] && exit 0; done
echo 'fake counter: counting exploded' >&2
exit 42
FAKE
chmod +x "$K/fake-python"
GOT=0
OUT="$( (cd "$K" && TOKEN_BUDGET_PYTHON="$K/fake-python" bash "$CHECK" --require-counter) 2>&1 )" || GOT=$?
if [ "$GOT" -eq 1 ] && printf '%s' "$OUT" | grep -q "surface 'doc': token counting failed (exit 42)"; then
  ok
else
  bad "K counting failure must be a hard FAIL naming the surface and exit code (got $GOT)"
fi
if printf '%s' "$OUT" | grep -q 'total: 0 tokens'; then
  bad "K an unmeasured surface must never report a zero total"
else
  ok
fi

# --- I: the real registry parses and carries the six US1.AC1 surfaces (the
#     ratified registry stays structurally consumable; values themselves are
#     owner-ratified there, not mirrored here — one home, no fork). ---------
for s in agents-resident compact-packet stage-cards task-index next-task-bundle pr-review-bundle; do
  if grep -q "^| \`$s\` |" "$REPO_ROOT/.claude/context-budgets.md"; then
    ok
  else
    bad "I real registry must carry surface '$s'"
  fi
done

# --- J: CI wiring (US1.AC2, the silent-death backstop): the required verify
#     job must actively RUN the check (with --require-counter, so CI never
#     fail-opens) and this test. Scoped to the verify job body, active steps
#     only (the agents-residency-check.test.sh idiom). ----------------------
CI="$REPO_ROOT/.github/workflows/ci.yml"
verify_steps() { awk '/^  [A-Za-z]/ { inblk = ($0 ~ /^  verify:/) } inblk { print }' "$CI"; }
if verify_steps | grep -qE '^[[:space:]]*run:[[:space:]]+bash[[:space:]]+\.claude/hooks/token-budget-check\.sh[[:space:]]+--require-counter([[:space:]]|$)'; then
  ok
else
  bad "wiring: verify must RUN token-budget-check.sh --require-counter (active run: step)"
fi
if verify_steps | grep -qE '^[[:space:]]*run:[[:space:]]+bash[[:space:]]+\.claude/hooks/token-budget-check\.test\.sh([[:space:]]|$)'; then
  ok
else
  bad "wiring: verify must RUN token-budget-check.test.sh (active run: step)"
fi

printf 'token-budget-check.test.sh: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
