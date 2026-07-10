#!/usr/bin/env bash
# Falsification tests for the T1204 stage-card completeness backstop.
set -u

HOOKS="$(cd "$(dirname "$0")" && pwd)"
CHECK="$HOOKS/stage-card-check.py"
ROOT="$(cd "$HOOKS/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
pass=0
fail=0

ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); printf 'FAIL %s\n' "$1" >&2; }

if [ ! -x "$CHECK" ]; then
  echo "FAIL: missing executable checker: $CHECK" >&2
  exit 1
fi

block_hash() {
  python3 - "$1" <<'PY'
import hashlib
import sys

normalized = " ".join(sys.argv[1].split())
print(hashlib.sha256(normalized.encode("utf-8")).hexdigest())
PY
}

mkfixture() {
  local root="$1"
  mkdir -p "$root/.claude/workflow/next-task"
  {
    printf '# next-task index\n\n'
    printf '1. [Alpha](next-task/01-alpha.md)\n'
    printf '2. [Beta](next-task/02-beta.md)\n'
  } > "$root/.claude/workflow/next-task.md"
  printf '# Alpha\n\nAlpha obligation.\n' > "$root/.claude/workflow/next-task/01-alpha.md"
  printf '# Beta\n\nBeta obligation.\n' > "$root/.claude/workflow/next-task/02-beta.md"
  {
    printf '%s\t1\t%s\n' "$(block_hash '# Alpha')" '# Alpha'
    printf '%s\t1\t%s\n' "$(block_hash 'Alpha obligation.')" 'Alpha obligation.'
    printf '%s\t1\t%s\n' "$(block_hash '# Beta')" '# Beta'
    printf '%s\t1\t%s\n' "$(block_hash 'Beta obligation.')" 'Beta obligation.'
  } > "$root/.claude/workflow/next-task-obligations.tsv"
}

run_check() {
  local root="$1"
  GOT=0
  OUT="$(python3 "$CHECK" --root "$root" 2>&1)" || GOT=$?
}

# In-sync control: every independently inventoried block occurs once in an indexed card.
A="$TMP/a-control"; mkfixture "$A"; run_check "$A"
if [ "$GOT" -eq 0 ]; then ok; else bad "in-sync cards must pass (got $GOT: $OUT)"; fi

# Dropped obligation: deleting one inventoried block fails and names it.
B="$TMP/b-dropped"; mkfixture "$B"
printf '# Beta\n' > "$B/.claude/workflow/next-task/02-beta.md"
run_check "$B"
if [ "$GOT" -eq 1 ] && printf '%s' "$OUT" | grep -q 'Beta obligation'; then
  ok
else
  bad "a dropped obligation must fail with its label (got $GOT: $OUT)"
fi

# Duplicate obligation: copying one block into another card fails with count + label.
C="$TMP/c-duplicate"; mkfixture "$C"
printf '\nAlpha obligation.\n' >> "$C/.claude/workflow/next-task/02-beta.md"
run_check "$C"
if [ "$GOT" -eq 1 ] && printf '%s' "$OUT" | grep -q 'Alpha obligation' && printf '%s' "$OUT" | grep -q 'found 2'; then
  ok
else
  bad "a duplicate obligation must fail with count and label (got $GOT: $OUT)"
fi

# An unindexed card is a silent stage escape and must fail by path.
D="$TMP/d-unindexed"; mkfixture "$D"
printf '# Hidden\n' > "$D/.claude/workflow/next-task/03-hidden.md"
run_check "$D"
if [ "$GOT" -eq 1 ] && printf '%s' "$OUT" | grep -q '03-hidden.md'; then
  ok
else
  bad "an unindexed card must fail naming its path (got $GOT: $OUT)"
fi

# The real tree is the independently captured pre-split oracle applied to all cards.
run_check "$ROOT"
if [ "$GOT" -eq 0 ]; then ok; else bad "real stage-card set must pass (got $GOT: $OUT)"; fi

# The per-card token budget is active, and the standing counter measures every card.
REGISTRY="$ROOT/.claude/context-budgets.md"
if grep -q '^| `stage-cards` | `each` | `1500` | `active` | `.claude/workflow/next-task/\*.md` |$' "$REGISTRY"; then
  ok
else
  bad "stage-cards must activate the owner-ratified 1,500-token gate"
fi
if grep -q '^| `next-task-bundle` | `total` | `18000` | `active` |' "$REGISTRY"; then
  ok
else
  bad "the restructured ordinary next-task bundle must activate its 18,000-token gate"
fi
BUDGET_OUT="$(cd "$ROOT" && bash .claude/hooks/token-budget-check.sh --require-counter 2>&1)"; BUDGET_GOT=$?
if [ "$BUDGET_GOT" -eq 0 ]; then ok; else bad "active stage-card token budget must pass (got $BUDGET_GOT: $BUDGET_OUT)"; fi
while IFS= read -r card; do
  rel="${card#"$ROOT/"}"
  if printf '%s\n' "$BUDGET_OUT" | grep -qF "$rel"; then ok; else bad "token report omitted $rel"; fi
done < <(find "$ROOT/.claude/workflow/next-task" -type f -name '*.md' | sort)

# CI wiring: both checker and falsification test run in the required verify job.
CI="$ROOT/.github/workflows/ci.yml"
verify_steps() { awk '/^  [A-Za-z]/ { inblk = ($0 ~ /^  verify:/) } inblk { print }' "$CI"; }
for command in 'python3 .claude/hooks/stage-card-check.py' 'bash .claude/hooks/stage-card-check.test.sh'; do
  if verify_steps | grep -qF "run: $command"; then ok; else bad "verify must actively run $command"; fi
done

printf 'stage-card-check.test.sh: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
