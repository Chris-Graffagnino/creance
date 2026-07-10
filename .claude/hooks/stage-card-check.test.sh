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
  mkdir -p "$root/.claude/workflow/next-task" "$root/docs"
  {
    printf '# next-task index\n\n'
    printf '1. [Alpha](next-task/01-alpha.md)\n'
    printf '2. [Beta](next-task/02-beta.md)\n'
  } > "$root/.claude/workflow/next-task.md"
  printf '# Alpha\n\n## 1. Alpha stage\n\nAlpha obligation.\n\nNext: [Beta](02-beta.md)\n' > "$root/.claude/workflow/next-task/01-alpha.md"
  printf '# Beta\n\n## 2. Beta stage\n\nBeta obligation.\n\nNext: stop.\n' > "$root/.claude/workflow/next-task/02-beta.md"
  printf 'See `.claude/workflow/next-task.md` §1.\n' > "$root/docs/reference.md"
  {
    printf '%s\t1\t%s\n' "$(block_hash '# Alpha')" '# Alpha'
    printf '%s\t1\t%s\n' "$(block_hash '## 1. Alpha stage')" '## 1. Alpha stage'
    printf '%s\t1\t%s\n' "$(block_hash 'Alpha obligation.')" 'Alpha obligation.'
    printf '%s\t1\t%s\n' "$(block_hash '# Beta')" '# Beta'
    printf '%s\t1\t%s\n' "$(block_hash '## 2. Beta stage')" '## 2. Beta stage'
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

# A broken next-card transition must fail before an ordinary run can dead-end.
E="$TMP/e-transition"; mkfixture "$E"
printf '# Alpha\n\n## 1. Alpha stage\n\nAlpha obligation.\n\nNext: [Missing](03-missing.md)\n' > "$E/.claude/workflow/next-task/01-alpha.md"
run_check "$E"
if [ "$GOT" -eq 1 ] && printf '%s' "$OUT" | grep -q '01-alpha.md' && printf '%s' "$OUT" | grep -q '02-beta.md'; then
  ok
else
  bad "a wrong next-card transition must fail with current and expected cards (got $GOT: $OUT)"
fi

# A stale section reference must fail deterministically with its file and target.
F="$TMP/f-stale-reference"; mkfixture "$F"
printf 'See `.claude/workflow/next-task.md` §99.\n' > "$F/docs/reference.md" # stage-card-reference-fixture
run_check "$F"
if [ "$GOT" -eq 1 ] && printf '%s' "$OUT" | grep -q 'docs/reference.md' && printf '%s' "$OUT" | grep -q '§99'; then
  ok
else
  bad "a stale next-task section reference must fail with its source and target (got $GOT: $OUT)"
fi

# Wrapped prose references are one logical paragraph and must not evade resolution.
G="$TMP/g-wrapped-reference"; mkfixture "$G"
printf 'See `.claude/workflow/next-task.md` for the rule in this\nwrapped citation paragraph at\n§98.\n' > "$G/docs/reference.md" # stage-card-reference-fixture
run_check "$G"
if [ "$GOT" -eq 1 ] && printf '%s' "$OUT" | grep -q 'docs/reference.md' && printf '%s' "$OUT" | grep -q '§98'; then
  ok
else
  bad "a wrapped stale next-task reference must fail with its source and target (got $GOT: $OUT)"
fi

# The Codex adapter entrypoints obey the same compact-packet + first-card contract.
CODEX_ADAPTER="$ROOT/.claude/adapters/codex-cli.md"
CODEX_DRY_RUN="$ROOT/.claude/adapters/codex-cli-dry-run.md"
codex_entrypoints() {
  python3 - "$1" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8")
on_demand = text.split("- **On-demand (user) path:**", 1)[1].split(
    "- **Scheduler/headless path:**", 1
)[0]
headless = text.split("- **Scheduler/headless path:**", 1)[1].split(
    "- **The one rule:**", 1
)[0]
required = (
    ".claude/PROJECT.compact.md",
    ".claude/workflow/next-task/00-foundations.md",
    "Next:",
    "without preloading the index or other cards",
)
raise SystemExit(0 if all(all(item in clause for item in required) for clause in (on_demand, headless)) else 1)
PY
}
if codex_entrypoints "$CODEX_ADAPTER" &&
  grep -qF '.claude/PROJECT.compact.md' "$CODEX_DRY_RUN" &&
  grep -qF '.claude/workflow/next-task/00-foundations.md' "$CODEX_DRY_RUN" &&
  grep -qF 'bash .claude/hooks/neutrality-scan-coverage.test.sh' "$CODEX_DRY_RUN" &&
  ! grep -qF 'zero edits to any `workflow/**` file' "$CODEX_DRY_RUN" &&
  ! grep -qF 'Read .claude/workflow/next-task.md and execute it' "$CODEX_DRY_RUN"; then
  ok
else
  bad "Codex entrypoints and dry-run evidence must encode the demand-loaded neutral contract"
fi
MUTATED_CODEX="$TMP/mutated-codex-adapter.md"
python3 - "$CODEX_ADAPTER" "$MUTATED_CODEX" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text(encoding="utf-8")
Path(sys.argv[2]).write_text(
    source.replace(".claude/PROJECT.compact.md", ".claude/PROJECT.md", 1),
    encoding="utf-8",
)
PY
if codex_entrypoints "$MUTATED_CODEX"; then
  bad "Codex entrypoint test must reject one regressed path while the other stays correct"
else
  ok
fi
INVERTED_CODEX="$TMP/inverted-codex-adapter.md"
python3 - "$CODEX_ADAPTER" "$INVERTED_CODEX" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text(encoding="utf-8")
Path(sys.argv[2]).write_text(
    source.replace("without preloading", "by preloading"),
    encoding="utf-8",
)
PY
if codex_entrypoints "$INVERTED_CODEX"; then
  bad "Codex entrypoint test must reject an inverted no-preload policy"
else
  ok
fi

# The real tree is the independently captured pre-split oracle applied to all cards.
run_check "$ROOT"
if [ "$GOT" -eq 0 ]; then ok; else bad "real stage-card set must pass (got $GOT: $OUT)"; fi

# The frozen oracle remains a deliberate change ratchet after the migration.
INVENTORY="$ROOT/.claude/workflow/next-task-obligations.tsv"
if grep -qF 'Intentional obligation edits update the corresponding row manually in the same human-reviewed PR' "$INVENTORY"; then
  ok
else
  bad "frozen oracle must document its post-migration update procedure"
fi

INDEX="$ROOT/.claude/workflow/next-task.md"
if grep -qF 'The inventory guards preservation, not accretion; the active per-card token budget bounds new material.' "$INDEX"; then
  ok
else
  bad "stage-card index must document the separate preservation and growth controls"
fi

if grep -qF 'The association scan is deliberately conservative: ambiguous matches are skipped' "$CHECK"; then
  ok
else
  bad "reference scanner must document its fail-open precision limit"
fi

# The active binding pins the demand-loading contract, including explicit escalation.
BINDING="$ROOT/.claude/skills/next-task/SKILL.md"
binding_contract() {
  local binding="$1"
  grep -qF '.claude/PROJECT.compact.md' "$binding" &&
    grep -qF 'next-task/00-foundations.md' "$binding" &&
    grep -qF "follow that card's \`Next:\` link" "$binding" &&
    grep -qF 'Do **not** preload the ordered `.claude/workflow/next-task.md`' "$binding" &&
    grep -qF 'another card, or the old full procedure' "$binding" &&
    grep -qF 'Escalate to the index' "$binding"
}
if binding_contract "$BINDING"; then ok; else bad "binding must encode compact packet + one-card demand loading"; fi
MUTATED_BINDING="$TMP/mutated-binding.md"
sed '/Do \*\*not\*\* preload/,/only to resume/d' "$BINDING" > "$MUTATED_BINDING"
if binding_contract "$MUTATED_BINDING"; then
  bad "binding contract test must reject a planted preload-policy deletion"
else
  ok
fi

# Review mode, like isolated mode, must dispatch against an explicit HEAD-verified ref.
GATE_CARD="$ROOT/.claude/workflow/next-task/07-pre-pr-gate.md"
if grep -qF 'explicit audited ref' "$GATE_CARD" &&
  grep -qF 'before every dispatch and re-dispatch' "$GATE_CARD" &&
  grep -qF 'fail loud' "$GATE_CARD"; then
  ok
else
  bad "§7 must require an explicit, HEAD-verified ref for every review-mode dispatch"
fi

# The per-card token budget is active, and the standing counter measures every card.
REGISTRY="$ROOT/.claude/context-budgets.md"
if grep -q '^| `stage-cards` | `each` | `1500` | `active` | `.claude/workflow/next-task/\*.md` |$' "$REGISTRY"; then
  ok
else
  bad "stage-cards must activate the owner-ratified 1,500-token gate"
fi
if grep -q '^| `next-task-bundle` | `total` | `18000` | `deferred` | .*`\.claude/workflow/next-task/\*.md`' "$REGISTRY"; then
  ok
else
  bad "the over-budget accumulated next-task bundle must stay truthful and deferred"
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
