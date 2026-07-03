#!/usr/bin/env bash
# Regression tests for backlog-loop-fence.sh — the deterministic P5 fence over the
# [backlog-loop] run report (T904, #229, spec 004 US1.AC5). The fence scans the
# tracked tree for the report's tokens (the two record discriminators + the
# channel seam) and FAILs if any appear outside the writer/reader allowlist. Each
# case runs the REAL fence against a throwaway git repo (the maker-eval-fence
# idiom) holding the two control files plus one planted fixture, then asserts the
# exit code. This is the constitution-P2 backstop paired per US1.AC5:
#   * PLANT — a channel-read planted in each danger class (gate-outcome /
#     model-tier / task-selection / guard / the loop-control skeleton) makes the
#     fence FAIL (exit 1), including a read WRAPPED across a shell
#     line-continuation in the line-scoped skeleton;
#   * PASS — the real tree and every sanctioned surface (writer, reader, tests,
#     CI comments/test-wiring, a bare writer DRIVE in the skeleton) do not fire;
#   * CONTROL — withholding the writer's (or reader's) channel resolution makes
#     the fence FAIL (exit 3), so it can never rot into scanning for a token
#     nothing uses (non-vacuity).
# Bash + git only, <2s; wired into the `verify` CI job (.github/workflows/ci.yml).
# Run: bash .claude/hooks/backlog-loop-fence.test.sh
set -u

DIR="$(cd "$(dirname "$0")" && pwd)"
FENCE="$DIR/backlog-loop-fence.sh"
REPO_ROOT="$(cd "$DIR/../.." && pwd)"
CI="$REPO_ROOT/.github/workflows/ci.yml"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
pass=0
fail=0

# run_fence <expected-exit> <root> <name> — run the REAL fence with
# BACKLOG_LOOP_FENCE_ROOT pointed at <root> and assert its exit code.
run_fence() {
  local want="$1" root="$2" name="$3" got=0
  BACKLOG_LOOP_FENCE_ROOT="$root" bash "$FENCE" >/dev/null 2>&1 || got=$?
  if [ "$got" -eq "$want" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL %-68s want exit %s, got %s\n' "$name" "$want" "$got" >&2
  fi
}

# addfile <dir> <relpath> <line> — add one file to a fixture tree and stage it.
addfile() {
  local d="$1" rel="$2" line="$3"
  mkdir -p "$d/$(dirname "$rel")"
  printf '%s\n' "$line" > "$d/$rel"
  git -C "$d" add -A
}

# mkfix <dir> [<relpath> <line>] — a throwaway git repo holding the two
# NON-VACUITY CONTROL files (the report writer resolving the channel, the triage
# reader surfacing the records) plus an optional planted fixture file. The
# controls make a clean fixture exit 0, so a plant case's exit 1 is
# unambiguously the violation, never a control failure.
mkfix() {
  local d="$1"
  mkdir -p "$d"
  git init -q -b main "$d"
  git -C "$d" config user.email t@example.com
  git -C "$d" config user.name test
  addfile "$d" ".claude/hooks/backlog-loop-report.sh" 'f="${BACKLOG_LOOP_REPORT_FILE:-}"  # the writer resolves the channel; emits backlog-loop-iteration lines'
  addfile "$d" ".claude/workflow/triage.md" 'surface the latest backlog-loop-summary record and its backlog-loop-iteration lines'
  if [ "$#" -ge 3 ]; then
    addfile "$d" "$2" "$3"
  fi
}

# ── PASSES on the real tree and on a clean fixture ────────────────────────────────
run_fence 0 "$REPO_ROOT" "PASSES: the real tracked tree"
CLEAN="$TMP/clean"; mkfix "$CLEAN"
run_fence 0 "$CLEAN" "PASSES: controls-only fixture (writer + reader resolve the channel)"

# ── FIRES on a planted channel-read in EVERY danger class (US1.AC5) ───────────────

# (a) gate-outcome path: the gate dispatcher reading iteration records to shade a verdict.
A="$TMP/plant-gate"; mkfix "$A" ".claude/workflows/gate-loop.js" 'const prior = lines.filter(l => l.record === "backlog-loop-iteration"); // planted read'
run_fence 1 "$A" "FIRES: backlog-loop-iteration read planted in gate-loop.js (gate-outcome)"

# (b) model-tier assignment: the model table resolving a tier from the run summary.
B="$TMP/plant-tier"; mkfix "$B" ".claude/MODELS.md" 'resolve the tier from the last backlog-loop-summary record   <!-- planted -->'
run_fence 1 "$B" "FIRES: backlog-loop-summary read planted in MODELS.md (model-tier)"

# (c) task-selection paths: the channel seam resolved in selection reconciliation…
C="$TMP/plant-selection-seam"; mkfix "$C" ".claude/hooks/reconcile-task-selection.sh" 'stream="${BACKLOG_LOOP_REPORT_FILE:-}"  # planted channel resolve'
run_fence 1 "$C" "FIRES: BACKLOG_LOOP_REPORT_FILE seam planted in reconcile-task-selection.sh (selection)"
# …a record read in the announce decision…
C2="$TMP/plant-selection-announce"; mkfix "$C2" ".claude/hooks/announce-task-selection.sh" 'skip="$(grep -c backlog-loop-iteration "$stream")"  # planted read'
run_fence 1 "$C2" "FIRES: iteration-record read planted in announce-task-selection.sh (selection)"
# …and in the shared drift library / the in-flight half.
C3="$TMP/plant-selection-drift"; mkfix "$C3" ".claude/hooks/lib-tasks-drift.sh" 'last_stop="$(tail -1 "$f" | grep backlog-loop-summary)"  # planted read'
run_fence 1 "$C3" "FIRES: summary-record read planted in lib-tasks-drift.sh (selection)"
C4="$TMP/plant-selection-inflight"; mkfix "$C4" ".claude/hooks/reconcile-inflight-selection.sh" 'grep -q backlog-loop-iteration "$stream" && exit 3  # planted read'
run_fence 1 "$C4" "FIRES: iteration-record read planted in reconcile-inflight-selection.sh (selection)"

# (d) the guard: guard.sh legitimately WRITES the shared telemetry stream, so the
#     fence must still fire when it singles out the run-report records.
D="$TMP/plant-guard"; mkfix "$D" ".claude/hooks/guard.sh" 'n="$(grep -c backlog-loop-iteration "$f")"  # planted read-back'
run_fence 1 "$D" "FIRES: iteration-record read planted in guard.sh (guard)"

# (e) the loop-control skeleton (hooks/backlog-loop.sh, T905): it consumes outcomes
#     from each run's RETURN, never from the report — a read-back there feeds the
#     stop conditions from telemetry, the exact counters-into-control P5 breach.
E="$TMP/plant-loop-read"; mkfix "$E" ".claude/hooks/backlog-loop.sh" 'fails="$(grep -c backlog-loop-iteration "$stream")"  # planted report read-back'
run_fence 1 "$E" "FIRES: report read-back planted in the loop skeleton (backlog-loop.sh)"

# (e2) the SAME read WRAPPED across a shell line-continuation still fires — the
#      skeleton is scanned over LOGICAL lines, so splitting the record token
#      across two physical lines cannot clear the line-scope.
E2="$TMP/plant-loop-wrap"
E2_LINE=$'fails="$(grep -c backlog-loop-\\\niteration "$stream")"  # planted wrapped read-back'
mkfix "$E2" ".claude/hooks/backlog-loop.sh" "$E2_LINE"
run_fence 1 "$E2" "FIRES: report read-back WRAPPED across a line-continuation in the loop skeleton"

# (f) CI itself is a gate surface: a step reading the report to gate a merge fires.
F="$TMP/plant-ci"; mkfix "$F" ".github/workflows/ci.yml" '        run: grep backlog-loop-iteration "$HOME/.claude/triage/creance-telemetry.jsonl"  # gate on it'
run_fence 1 "$F" "FIRES: report read planted in ci.yml (CI gate surface)"

# ── does NOT false-fire on the sanctioned surface ─────────────────────────────────

# (g) the loop skeleton may DRIVE the writer — an append, not a read (line-scoped).
G="$TMP/allow-loop-drive"; mkfix "$G" ".claude/hooks/backlog-loop.sh" 'bash "$HOOKS/backlog-loop-report.sh" iteration "$run_id" "$task_id" pass "$verdict" "$pr"'
run_fence 0 "$G" "no false fire: writer DRIVE in the loop skeleton (append, not read)"
G2="$TMP/allow-loop-summary"; mkfix "$G2" ".claude/hooks/backlog-loop.sh" 'bash "$HOOKS/backlog-loop-report.sh" summary "$run_id" "$stop" "$i" "$n"'
run_fence 0 "$G2" "no false fire: summary DRIVE in the loop skeleton"

# (h) a *.test.sh harness may carry the tokens (tests exercise the report; no authority).
H="$TMP/allow-test"; mkfix "$H" ".claude/hooks/guard.test.sh" 'echo "fixture: backlog-loop-iteration backlog-loop-summary BACKLOG_LOOP_REPORT_FILE"'
run_fence 0 "$H" "no false fire: tokens in a *.test.sh harness"

# (i) ci.yml comments (cannot execute) and bare *.test.sh wiring are benign.
I="$TMP/allow-ci-comment"; mkfix "$I" ".github/workflows/ci.yml" '      # asserts field fidelity of the backlog-loop-iteration records'
run_fence 0 "$I" "no false fire: ci.yml comment naming the report tokens"
J="$TMP/allow-ci-wiring"; mkfix "$J" ".github/workflows/ci.yml" '        run: bash .claude/hooks/backlog-loop-report.test.sh'
run_fence 0 "$J" "no false fire: ci.yml step running the report test harness"

# (k) the T905 probe doc names the report by nature (no control authority).
K="$TMP/allow-probe-doc"; mkfix "$K" ".claude/adapters/claude-code-probes.md" 'P-BL: run the loop; assert one backlog-loop-iteration line per iteration landed.'
run_fence 0 "$K" "no false fire: tokens in the allowlisted probe instantiation"

# ── the NON-VACUITY CONTROL (US1.AC5's paired control) ────────────────────────────

# (l) withhold the WRITER's channel resolution: writer exists but names no
#     record/seam token → the control side FAILs (exit 3), distinct from a violation.
L="$TMP/control-writer-withheld"; mkfix "$L"
addfile "$L" ".claude/hooks/backlog-loop-report.sh" '# a writer that no longer resolves any channel'
run_fence 3 "$L" "CONTROL FAILS: writer no longer resolves the run-report channel"

# (m) a MISSING writer file is the same vacuity — control FAILs.
M="$TMP/control-writer-missing"; mkfix "$M"
rm "$M/.claude/hooks/backlog-loop-report.sh"
git -C "$M" add -A
run_fence 3 "$M" "CONTROL FAILS: writer file absent entirely"

# (n) withhold the READER's resolution: triage no longer surfaces the records.
N="$TMP/control-reader-withheld"; mkfix "$N"
addfile "$N" ".claude/workflow/triage.md" 'a triage doc that no longer surfaces the run report'
run_fence 3 "$N" "CONTROL FAILS: triage reader no longer resolves the records"

# (o) a violation is reported AS a violation even when the control would also fail
#     (violations are checked first — exit 1, not 3).
O="$TMP/violation-before-control"; mkfix "$O" ".claude/hooks/guard.sh" 'grep backlog-loop-summary "$f"  # planted'
addfile "$O" ".claude/hooks/backlog-loop-report.sh" '# writer with no tokens'
run_fence 1 "$O" "ordering: a P5 violation reports exit 1 even with a broken control"

# ── fail-closed: an unscannable root is a LOUD failure, never a silent pass (P2) ──
run_fence 2 "$TMP/does-not-exist" "fail-closed: empty/unscannable root exits loud"

# ── CI wiring (the silent-death backstop, P2): this suite must run in verify —
#    its real-tree case is what enforces the fence on every merge. ─────────────────
if grep -qE '(^|[[:space:]])bash[[:space:]]+[.]claude/hooks/backlog-loop-fence[.]test[.]sh([[:space:]]|$)' "$CI"; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  printf 'FAIL %-68s ci.yml verify must run backlog-loop-fence.test.sh\n' "wiring: fence test runs in CI" >&2
fi

printf 'backlog-loop-fence.test.sh: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
