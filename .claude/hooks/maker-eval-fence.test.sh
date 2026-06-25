#!/usr/bin/env bash
# Regression tests for maker-eval-fence.sh — the deterministic P5 fence over the
# maker-eval channel (T804, #161, spec 003 US2.AC3). The fence scans the tracked tree
# for the eval channel's path/IO tokens and FAILs if any appear outside the writer/
# reader allowlist. So each case runs the REAL fence against a throwaway git repo (the
# check-tasks-consistency.test.sh idiom) holding one planted fixture file, then asserts
# the exit code. This is the constitution-P2 backstop: the fence ships with the test
# proving it FIRES on a planted cross-reference to EITHER path (US2.AC3) AND does not
# false-fire on the real tree or on the sanctioned writer/reader/test surface. Bash +
# git only, <1s; wired into the `verify` CI job (.github/workflows/ci.yml).
# Run: bash .claude/hooks/maker-eval-fence.test.sh
set -u

DIR="$(cd "$(dirname "$0")" && pwd)"
FENCE="$DIR/maker-eval-fence.sh"
REPO_ROOT="$(cd "$DIR/../.." && pwd)"
CI="$REPO_ROOT/.github/workflows/ci.yml"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
pass=0
fail=0

# run_fence <expected-exit> <root> <name> — run the REAL fence with MAKER_EVAL_FENCE_ROOT
# pointed at <root> and assert its exit code.
run_fence() {
  local want="$1" root="$2" name="$3" got=0
  MAKER_EVAL_FENCE_ROOT="$root" bash "$FENCE" >/dev/null 2>&1 || got=$?
  if [ "$got" -eq "$want" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL %-62s want exit %s, got %s\n' "$name" "$want" "$got" >&2
  fi
}

# mkfix <dir> <relpath> <line> — a throwaway git repo holding ONE fixture file at
# <relpath> containing <line>. git add (no commit needed — the fence reads `git
# ls-files`, the index). The lone file is what determines the fence verdict.
mkfix() {
  local d="$1" rel="$2" line="$3"
  mkdir -p "$d/$(dirname "$rel")"
  printf '%s\n' "$line" > "$d/$rel"
  git init -q -b main "$d"
  git -C "$d" config user.email t@example.com
  git -C "$d" config user.name test
  git -C "$d" add -A
}

# ── PASSES on the real tree (US2.AC3: "passes on the real tree") ────────────────
run_fence 0 "$REPO_ROOT" "PASSES: the real tracked tree"

# ── FIRES on a planted cross-reference to EITHER path, across all four danger
#    classes the AC names (gate / tier / guard / selection) ───────────────────────

# (a) records.jsonl (the eval-RECORD path) planted in a GUARD path.
A="$TMP/plant-records-guard"; mkfix "$A" ".claude/hooks/guard.sh" 'cat "$chan/records.jsonl"   # planted cross-reference'
run_fence 1 "$A" "FIRES: records.jsonl planted in guard.sh (guard path)"

# (b) packets/ (the transcript-PACKET storage) planted in a GATE path.
B="$TMP/plant-packets-gate"; mkfix "$B" ".claude/workflows/gate-loop.js" 'const p = "packets/" + runId + "/" + taskId; // planted'
run_fence 1 "$B" "FIRES: packets/ planted in gate-loop.js (gate path)"

# (c) the MAKER_EVAL_DIR access seam planted in a SELECTION path.
C="$TMP/plant-seam-selection"; mkfix "$C" ".claude/hooks/reconcile-task-selection.sh" 'eval_dir="${MAKER_EVAL_DIR:-}"  # planted'
run_fence 1 "$C" "FIRES: MAKER_EVAL_DIR planted in reconcile-task-selection.sh (selection)"

# (d) the channel dir name planted in a TIER path (the model table).
D="$TMP/plant-dir-tier"; mkfix "$D" ".claude/MODELS.md" 'resolve tier from ~/.claude/triage/creance-maker-eval/records.jsonl'
run_fence 1 "$D" "FIRES: creance-maker-eval dir planted in MODELS.md (tier path)"

# (e) invoking the writer planted in next-task.md (the gate+selection hub).
E="$TMP/plant-emit-nexttask"; mkfix "$E" ".claude/workflow/next-task.md" 'then call maker-eval-emit to fold the score into selection'
run_fence 1 "$E" "FIRES: maker-eval-emit invocation planted in next-task.md"

# (f) reading the eval-record path planted in CI ITSELF. CI is a gate (it decides the
#     merge), so a workflow step that reads records.jsonl to gate on it is a P5 breach.
#     The old whole-file allowlist masked this (PR #162 craft/Codex finding); ci.yml is
#     now scanned line-by-line, so the planted step survives the benign filter and fires.
F_CI="$TMP/plant-ci-gate"; mkfix "$F_CI" ".github/workflows/ci.yml" '        run: cat "$HOME/.claude/triage/creance-maker-eval/records.jsonl"  # gate on it'
run_fence 1 "$F_CI" "FIRES: records.jsonl read planted in ci.yml (CI gate surface)"

# ── does NOT false-fire on the sanctioned surface ───────────────────────────────

# (g) the eval WRITER may carry the tokens (it IS the channel writer).
F="$TMP/allow-writer"; mkfix "$F" ".claude/hooks/maker-eval-emit.sh" 'printf "%s" "$channel/records.jsonl"  # the writer'
run_fence 0 "$F" "no false fire: records.jsonl in the allowlisted writer"

# (h) the triage READER may carry the tokens.
G="$TMP/allow-reader"; mkfix "$G" ".claude/skills/triage/SKILL.md" 'Read `<channel>/records.jsonl` and the `packets/` subtree.'
run_fence 0 "$G" "no false fire: tokens in the allowlisted triage reader"

# (i) a *.test.sh harness may carry the tokens (tests exercise the channel; no authority).
#     This also proves the plant in cases (a)-(f) had to land in a NON-test file to fire.
H="$TMP/allow-test"; mkfix "$H" ".claude/hooks/guard.test.sh" 'echo "fixture: records.jsonl packets/ MAKER_EVAL_DIR"'
run_fence 0 "$H" "no false fire: tokens in a *.test.sh harness"

# (j) ci.yml is now scanned, but its sanctioned surface must NOT false-fire: a comment
#     naming the tokens cannot execute, so it is benign.
J="$TMP/allow-ci-comment"; mkfix "$J" ".github/workflows/ci.yml" '      # scans for records.jsonl / packets/ (the maker-eval channel)'
run_fence 0 "$J" "no false fire: ci.yml comment naming the channel tokens"

# (k) ...and a step that merely RUNS a maker-eval *.test.sh harness carries no control
#     authority, so it is benign too — this is the wiring ci.yml is allowlisted for.
K="$TMP/allow-ci-wiring"; mkfix "$K" ".github/workflows/ci.yml" '        run: bash .claude/hooks/maker-eval-emit.test.sh'
run_fence 0 "$K" "no false fire: ci.yml step running a maker-eval *.test.sh"

# ── fail-closed: an unscannable root is a LOUD failure, never a silent pass (P2) ─
run_fence 2 "$TMP/does-not-exist" "fail-closed: empty/unscannable root exits loud"

# ── CI wiring (the silent-death backstop, P2): the fence AND its test must run in
#    verify, else the machinery is dead while this file stays green. ───────────────
if grep -qE '(^|[[:space:]])bash[[:space:]]+[.]claude/hooks/maker-eval-fence[.]sh([[:space:]]|$)' "$CI"; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  printf 'FAIL %-62s ci.yml verify must run maker-eval-fence.sh\n' "wiring: fence runs in CI" >&2
fi
if grep -qE '(^|[[:space:]])bash[[:space:]]+[.]claude/hooks/maker-eval-fence[.]test[.]sh([[:space:]]|$)' "$CI"; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  printf 'FAIL %-62s ci.yml verify must run maker-eval-fence.test.sh\n' "wiring: fence test runs in CI" >&2
fi

printf 'maker-eval-fence.test.sh: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
