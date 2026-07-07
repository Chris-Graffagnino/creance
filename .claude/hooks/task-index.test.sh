#!/usr/bin/env bash
# Regression tests for task-index.py (T1205, spec 007 US5; epic #166).
#
# The constitution-P2 pairing, both directions in one suite (US5.AC2): a PLANTED-STALE
# index FAILs `--check` NAMING the drifted task entry — across every drift shape (a
# checkbox flip, a title/tier change, an added task, a removed task) — AND a
# freshly-regenerated control PASSES. A stale index that passed, or a fresh one that
# failed, is the silently-dead-guard / false-fire class. Plus fail-loud on a missing index
# and an empty backlog (never a vacuous pass), generator determinism, and the wiring /
# budget-active / index-first selection pins (US5.AC1, US5.AC2, US5.AC3).
#
# Each case builds a throwaway `specs/<n>/tasks.md` fixture tree and runs the real tool
# with that dir as CWD (the compact-packet-drift.test.sh / token-budget-check.test.sh
# idiom); the tool is CWD-relative, so no real repo file is touched. Fixtures are written
# whole (no in-place sed) to stay BSD/GNU-portable.
# Run: bash .claude/hooks/task-index.test.sh
set -u
export LC_ALL=C

HOOKS="$(cd "$(dirname "$0")" && pwd)"
TOOL="$HOOKS/task-index.py"
REPO_ROOT="$(cd "$HOOKS/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
pass=0
fail=0

ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); printf 'FAIL %s\n' "$1" >&2; }

# run <dir> <mode> — run the real tool (--check|--write) with <dir> as CWD; combined
# output in $OUT, exit code in $GOT.
run() {
  GOT=0
  OUT="$( (cd "$1" && python3 "$TOOL" "$2") 2>&1 )" || GOT=$?
}

# mk_tasks <dir> <specdir> <heredoc-content-via-stdin> — write a fixture tasks file.
mk_tasks() {
  mkdir -p "$1/specs/$2"
  cat > "$1/specs/$2/tasks.md"
}

# tasks_A <dir> — the baseline fixture: three tasks, a criterion-ownership table.
tasks_A() {
  mk_tasks "$1" "900-fixture" <<'EOF'
# Tasks — Fixture

## Phase 1 — Fixture

- [ ] T9001 [strong] First fixture task — carries a dash so the title is cut early;
      and wraps onto a continuation line (US1)
- [ ] T9002 [cheap] Second fixture task (US1)
- [x] T9003 [strong] Third fixture task, already done (US2)

## Criterion ownership (multi-task user stories)

| Criterion | Owning task |
|---|---|
| US1.AC1 | T9001 |
| US1.AC2 | T9002 |
| US2.AC1 | T9003 |
EOF
}

# expect_stale_naming <label> <task-id> — after run --check: exit 1 AND the output names
# that task ID as the drifted entry.
expect_stale_naming() {
  if [ "$GOT" -eq 1 ]; then ok; else bad "$1 must exit 1 (got $GOT): $OUT"; fi
  if printf '%s' "$OUT" | grep -q "$2"; then
    ok
  else
    bad "$1 stale failure must name entry $2 (got: $OUT)"
  fi
}

# --- A: the real-tree control — the committed specs/TASK_INDEX.md matches the real
#     tasks files (the exact surface CI grades). No false fire. --------------------
run "$REPO_ROOT" --check
if [ "$GOT" -eq 0 ]; then ok; else bad "A committed-index real-tree control must PASS (got $GOT): $OUT"; fi
if printf '%s' "$OUT" | grep -q 'task index: OK'; then ok; else bad "A control must report OK"; fi

# --- B: the fresh control (US5.AC2 passing direction) — generate, then --check passes. --
B="$TMP/b"
tasks_A "$B"
run "$B" --write
if [ "$GOT" -eq 0 ] && [ -f "$B/specs/TASK_INDEX.md" ]; then ok; else bad "B --write must create the index (got $GOT)"; fi
run "$B" --check
if [ "$GOT" -eq 0 ]; then ok; else bad "B freshly-regenerated control must PASS --check (got $GOT): $OUT"; fi
# the index actually carries the selection-critical fields (US5.AC1), per task
idx="$B/specs/TASK_INDEX.md"
grep -q '^## specs/900-fixture/spec.md' "$idx" && ok || bad "B index must carry the spec path as a section heading"
grep -qE '^\| T9002 \| cheap \| \[ \] \| US1\.AC2 \|' "$idx" && ok || bad "B index row must carry id+tier+state+criteria for T9002"
grep -qE '^\| T9003 \| strong \| \[x\] \|' "$idx" && ok || bad "B index must carry the done state for T9003"

# --- C: planted stale via a CHECKBOX FLIP — the tasks file changes, the committed index
#     does not; --check must FAIL naming exactly the flipped task. -----------------
C="$TMP/c"
tasks_A "$C"
run "$C" --write
mk_tasks "$C" "900-fixture" <<'EOF'
# Tasks — Fixture

## Phase 1 — Fixture

- [ ] T9001 [strong] First fixture task — carries a dash so the title is cut early;
      and wraps onto a continuation line (US1)
- [x] T9002 [cheap] Second fixture task (US1)
- [x] T9003 [strong] Third fixture task, already done (US2)

## Criterion ownership (multi-task user stories)

| Criterion | Owning task |
|---|---|
| US1.AC1 | T9001 |
| US1.AC2 | T9002 |
| US2.AC1 | T9003 |
EOF
run "$C" --check
expect_stale_naming "C checkbox flip" "T9002"
# the OTHER tasks are not spuriously named as drifted
if printf '%s' "$OUT" | grep -q 'T9001'; then bad "C must not name the unchanged T9001"; else ok; fi

# --- D: planted stale via a TITLE / TIER change — same shape, different field. --------
D="$TMP/d"
tasks_A "$D"
run "$D" --write
mk_tasks "$D" "900-fixture" <<'EOF'
# Tasks — Fixture

## Phase 1 — Fixture

- [ ] T9001 [strong] First fixture task — carries a dash so the title is cut early;
      and wraps onto a continuation line (US1)
- [ ] T9002 [frontier] Second fixture task RETITLED (US1)
- [x] T9003 [strong] Third fixture task, already done (US2)

## Criterion ownership (multi-task user stories)

| Criterion | Owning task |
|---|---|
| US1.AC1 | T9001 |
| US1.AC2 | T9002 |
| US2.AC1 | T9003 |
EOF
run "$D" --check
expect_stale_naming "D title/tier change" "T9002"

# --- E: planted stale via an ADDED task — present in the tasks file, missing from the
#     index; --check must FAIL naming the missing entry. --------------------------
E="$TMP/e"
tasks_A "$E"
run "$E" --write
mk_tasks "$E" "900-fixture" <<'EOF'
# Tasks — Fixture

## Phase 1 — Fixture

- [ ] T9001 [strong] First fixture task — carries a dash so the title is cut early;
      and wraps onto a continuation line (US1)
- [ ] T9002 [cheap] Second fixture task (US1)
- [x] T9003 [strong] Third fixture task, already done (US2)
- [ ] T9004 [cheap] A brand-new task the stale index has never seen (US2)

## Criterion ownership (multi-task user stories)

| Criterion | Owning task |
|---|---|
| US1.AC1 | T9001 |
| US1.AC2 | T9002 |
| US2.AC1 | T9003 |
EOF
run "$E" --check
expect_stale_naming "E added task" "T9004"

# --- F: planted stale via a REMOVED task — in the index, gone from the tasks file;
#     --check must FAIL naming the now-stale entry. -------------------------------
F="$TMP/f"
tasks_A "$F"
run "$F" --write
mk_tasks "$F" "900-fixture" <<'EOF'
# Tasks — Fixture

## Phase 1 — Fixture

- [ ] T9001 [strong] First fixture task — carries a dash so the title is cut early;
      and wraps onto a continuation line (US1)
- [ ] T9002 [cheap] Second fixture task (US1)

## Criterion ownership (multi-task user stories)

| Criterion | Owning task |
|---|---|
| US1.AC1 | T9001 |
| US1.AC2 | T9002 |
EOF
run "$F" --check
expect_stale_naming "F removed task" "T9003"

# --- G: the regenerate-fixes-it control — after any drift, --write then --check passes
#     (the documented repair path actually clears the gate). ----------------------
run "$F" --write
if [ "$GOT" -eq 0 ]; then ok; else bad "G --write must succeed after drift (got $GOT)"; fi
run "$F" --check
if [ "$GOT" -eq 0 ]; then ok; else bad "G regenerate must clear the stale gate (got $GOT): $OUT"; fi

# --- H: a missing index FAILs loud naming it — the check never passes on absence. -----
H="$TMP/h"
tasks_A "$H"
run "$H" --check
if [ "$GOT" -eq 1 ] && printf '%s' "$OUT" | grep -q 'TASK_INDEX.md not found'; then
  ok
else
  bad "H missing index must FAIL naming it (got $GOT): $OUT"
fi

# --- I: an empty backlog FAILs loud, never a silent empty index (a vacuous pass would
#     let any later drift slip through). -----------------------------------------
I="$TMP/i-empty"
mkdir -p "$I/specs"
run "$I" --write
if [ "$GOT" -ne 0 ] && printf '%s' "$OUT" | grep -q 'no tasks parsed'; then
  ok
else
  bad "I empty backlog must FAIL loud on --write (got $GOT): $OUT"
fi

# --- J: determinism — two --write runs over the same input are byte-identical (the pure
#     generator the staleness gate depends on). ----------------------------------
J="$TMP/j"
tasks_A "$J"
run "$J" --write
cp "$J/specs/TASK_INDEX.md" "$TMP/j-first.md"
run "$J" --write
if cmp -s "$TMP/j-first.md" "$J/specs/TASK_INDEX.md"; then ok; else bad "J generator must be deterministic (two --writes differ)"; fi

# --- K: CI wiring (US5.AC2 'wired into standing verification, wiring asserted') — the
#     verify job actively RUNS the check and this test. ---------------------------
CI="$REPO_ROOT/.github/workflows/ci.yml"
verify_steps() { awk '/^  [A-Za-z]/ { inblk = ($0 ~ /^  verify:/) } inblk { print }' "$CI"; }
if verify_steps | grep -qE '^[[:space:]]*run:[[:space:]]+python3[[:space:]]+\.claude/hooks/task-index\.py[[:space:]]+--check([[:space:]]|$)'; then
  ok
else
  bad "K wiring: verify must RUN task-index.py --check (active run: step)"
fi
if verify_steps | grep -qE '^[[:space:]]*run:[[:space:]]+bash[[:space:]]+\.claude/hooks/task-index\.test\.sh([[:space:]]|$)'; then
  ok
else
  bad "K wiring: verify must RUN task-index.test.sh (active run: step)"
fi

# --- L: the budget gate is ACTIVE (US5.AC1's same-diff activation) — the registry row
#     for task-index gates, not defers. --------------------------------------------
if grep -qE '^\| `task-index` \| `total` \| `[0-9]+` \| `active` \|' "$REPO_ROOT/.claude/context-budgets.md"; then
  ok
else
  bad "L the task-index budget row must be gating 'active' (US5.AC1)"
fi

# --- M: index-first selection with the preconditions unchanged (US5.AC3) — the neutral
#     procedure reads the index first, and all three deterministic preconditions still
#     run on the candidate; the adapter binding names the concrete index. ----------
NT_DOC="$REPO_ROOT/.claude/workflow/next-task.md"
if grep -qi 'task index' "$NT_DOC"; then ok; else bad "M next-task.md §1 must read the task index first (US5.AC3)"; fi
# the index is framed as a PREFILTER and eligibility (not-blocked / deps-met) is confirmed
# from the candidate's full context, not read off the index (US5.AC3; the index omits that
# state) — the property the engineering-craft review flagged (a blocked task looks selectable).
if grep -qi 'prefilter' "$NT_DOC"; then ok; else bad "M next-task.md §1 must frame the index as a selection prefilter (US5.AC3)"; fi
if grep -qi 'not blocked' "$NT_DOC"; then ok; else bad "M next-task.md §1 must confirm the candidate is not blocked from its full context (US5.AC3)"; fi
for role in 'live-state reconciliation' 'in-flight' 'announce-and-confirm'; do
  if grep -qi "$role" "$NT_DOC"; then
    ok
  else
    bad "M next-task.md must still carry the [$role] selection precondition (US5.AC3 'run unchanged')"
  fi
done
NT_SKILL="$REPO_ROOT/.claude/skills/next-task/SKILL.md"
if grep -qF 'specs/TASK_INDEX.md' "$NT_SKILL"; then ok; else bad "M the next-task binding must name the concrete task index (specs/TASK_INDEX.md)"; fi

# --- N: the Issue/PR column is REAL, not a hardcoded blank (US5.AC1 'when known') — a task
#     whose line ends with a `[#NNN]` marker gets that reference; a task without stays blank
#     (honest omission), and the marker never leaks into the title. --------------------
N="$TMP/n"
mk_tasks "$N" "901-fixture" <<'EOF'
# Tasks — Issue-link fixture

## Phase 1 — Fixture

- [ ] T9101 [cheap] Task that records its issue link [#4242] (US1)
- [ ] T9102 [cheap] Task with no recorded issue link (US1)
EOF
run "$N" --write
nidx="$N/specs/TASK_INDEX.md"
grep -qE '^\| T9101 \| cheap \| \[ \] \| US1 \| #4242 \|' "$nidx" && ok || bad "N T9101 must carry its extracted issue link #4242 (got: $(grep -E '^\| T9101' "$nidx"))"
grep -qE '^\| T9102 \| cheap \| \[ \] \| US1 \|  \| ' "$nidx" && ok || bad "N T9102 must leave the issue cell blank — honest omission (got: $(grep -E '^\| T9102' "$nidx"))"
if grep -E '^\| T9101 \|' "$nidx" | grep -q '\[#4242\]'; then bad "N the [#NNN] link marker must not leak into the title"; else ok; fi

printf 'task-index.test.sh: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
