#!/usr/bin/env bash
# Tests for backlog-loop.sh — the [backlog-loop] control skeleton (T902, spec 004
# US1.AC2/AC3; neutral model: .claude/workflow/backlog-loop.md).
#
# Proves the deterministic stop-condition set and the activation gating with stub
# seam commands (the GH-seam idiom from reconcile-inflight-selection.test.sh), each
# case traceable to an acceptance criterion:
#   * max-N:            halts at exactly N with more candidates left (AC3a), and
#                       N=0 is a no-op — zero iterations, the iteration command
#                       NEVER invoked (AC3a);
#   * backlog-drained:  M < N eligible -> completes all M, never stops early while
#                       eligible work and budget remain (AC3b);
#   * first-FAIL-advances / repeated-gate-fail: one FAIL sets a one-selection skip
#                       (consumed whatever comes next); the SAME stable identity
#                       failing twice stops the run — incl. the neutral doc's
#                       worked two-task trace where the skipped identity is
#                       re-selected because no other candidate exists (AC3c);
#   * between-iterations only: a FAILing iteration still runs to its terminal
#                       state and is recorded BEFORE any stop fires (AC3);
#   * activation gating: consulted BEFORE any iteration (recorder-stub ordering),
#                       review -> zero iterations (AC2a); the REAL default
#                       autonomy-mode.sh against the shipped profile resolves to
#                       review and runs nothing (AC2b); a flip to review between
#                       iterations stops fail-closed without starting the next
#                       iteration (AC3d); a missing/broken/lying activation
#                       command resolves to review, never autonomous (AC2);
#   * aborted / refused outcomes: aborted -> fail-closed (AC3d); refused ->
#                       ineligible for the rest of the run, never re-selected;
#   * malformed selector output: anything but exactly one `T`+digits ID (two
#                       ids on one line, multi-line output, a non-ID token)
#                       stops fail-closed — never a concatenated bogus
#                       identity, never misread as backlog-drained;
#   * usage guards:     missing/non-numeric N, missing seams -> loud exit 2;
#   * wiring (P2):      the `verify` job ACTIVELY runs this test, and the neutral
#                       doc still names the closed stop-reason set the skeleton
#                       implements (mechanism <-> model drift backstop).
# Assertions are per-instance: full-transcript string equality on stdout and on
# the stubs' invocation logs — never a prefix-only or single-match-anywhere grep
# (AGENTS.md falsification rule / next-task §5).
# Bash only, <1s. Run: bash .claude/hooks/backlog-loop.test.sh
set -u

HOOKS="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HOOKS/backlog-loop.sh"
REPO="$(cd "$HOOKS/../.." && pwd)"
CI="$REPO/.github/workflows/ci.yml"
MODEL="$REPO/.claude/workflow/backlog-loop.md"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
# Hermetic lock (T906): every run below now takes the single-instance loop lock, so point it at
# our scratch dir. On the real default path the suite would contend with an actual loop on this
# machine — and with a parallel CI job — turning unrelated cases red for the wrong reason.
export BACKLOG_LOOP_LOCK_DIR="$TMP/loop.lock"
pass=0
fail=0
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); printf 'FAIL %s\n' "$1" >&2; }

assert_eq() { # <label> <got> <want> — exact string equality
  if [ "$2" = "$3" ]; then ok; else bad "$1: got '$2' want '$3'"; fi
}

# ── stub seam commands (generic; each case gets its own fixture dir via $FIX) ──
BIN="$TMP/bin"
mkdir -p "$BIN"

# Selector stub: prints the FIRST backlog id that is neither excluded (args) nor
# marked done; logs every consult (args included) so exclusion sets are provable.
cat > "$BIN/select.sh" <<'EOF'
#!/usr/bin/env bash
set -u
printf 'select\n' >> "$FIX/events.log"
printf 'sel:%s\n' "$*" >> "$FIX/sel.log"
while IFS= read -r id; do
  [ -n "$id" ] || continue
  if grep -qxF "$id" "$FIX/done" 2>/dev/null; then continue; fi
  excluded=0
  for x in "$@"; do
    if [ "$x" = "$id" ]; then excluded=1; break; fi
  done
  if [ "$excluded" -eq 1 ]; then continue; fi
  printf '%s\n' "$id"
  exit 0
done < "$FIX/backlog"
exit 0
EOF

# Iteration stub: consumes the first $FIX/plan line matching the id
# (`<id> <outcome...>`; repeated lines give sequential outcomes; no line ->
# default `pass PR-<id>`); logs start AND end markers so "ran to its terminal
# state" is provable; marks pass ids done. The sentinel outcome EXIT1 makes the
# stub exit non-zero (the broken-cycle arm).
cat > "$BIN/iter.sh" <<'EOF'
#!/usr/bin/env bash
set -u
id="$1"
printf 'iteration %s\n' "$id" >> "$FIX/events.log"
printf 'start %s\n' "$id" >> "$FIX/iter.log"
out="pass PR-$id"
if [ -f "$FIX/plan" ]; then
  n=0
  hit=0
  while IFS= read -r l; do
    n=$((n + 1))
    if [ "$hit" -eq 0 ]; then
      case "$l" in
        "$id "*)
          hit=$n
          out="${l#* }"
          ;;
      esac
    fi
  done < "$FIX/plan"
  if [ "$hit" -gt 0 ]; then
    sed "${hit}d" "$FIX/plan" > "$FIX/plan.new" && mv "$FIX/plan.new" "$FIX/plan"
  fi
fi
if [ "$out" = "EXIT1" ]; then
  printf 'end %s outcome exit1\n' "$id" >> "$FIX/iter.log"
  exit 1
fi
printf 'end %s outcome %s\n' "$id" "$out" >> "$FIX/iter.log"
case "$out" in pass*) printf '%s\n' "$id" >> "$FIX/done" ;; esac
printf '%s\n' "$out"
exit 0
EOF

# Activation stubs: always-autonomous, always-review, a per-call sequence (reads
# line min(call#, last) of $FIX/act.plan), and one that PRINTS autonomous but
# exits non-zero (a failing check must never read as engaged).
cat > "$BIN/act-auto.sh" <<'EOF'
#!/usr/bin/env bash
printf 'activation\n' >> "$FIX/events.log"
printf 'autonomous\n'
EOF
cat > "$BIN/act-review.sh" <<'EOF'
#!/usr/bin/env bash
printf 'activation\n' >> "$FIX/events.log"
printf 'review\n'
EOF
cat > "$BIN/act-seq.sh" <<'EOF'
#!/usr/bin/env bash
set -u
printf 'activation\n' >> "$FIX/events.log"
n=0
if [ -f "$FIX/act.count" ]; then n="$(cat "$FIX/act.count")"; fi
n=$((n + 1))
printf '%s\n' "$n" > "$FIX/act.count"
total="$(grep -c . "$FIX/act.plan")"
if [ "$n" -gt "$total" ]; then n="$total"; fi
sed -n "${n}p" "$FIX/act.plan"
EOF
cat > "$BIN/act-lying.sh" <<'EOF'
#!/usr/bin/env bash
printf 'autonomous\n'
exit 1
EOF

# mkfix <name> — fresh fixture dir for one case, exported for the stubs.
mkfix() {
  FIX="$TMP/$1"
  mkdir -p "$FIX"
  : > "$FIX/done"
  : > "$FIX/sel.log"
  : > "$FIX/iter.log"
  : > "$FIX/events.log"
  export FIX
}

# run_loop <N> — run the skeleton with the stub seams ($ACT set per case);
# captures stdout in OUT and the exit code in RC.
run_loop() {
  RC=0
  OUT="$(BACKLOG_LOOP_ACTIVATION_CMD="$ACT" \
    BACKLOG_LOOP_SELECT_CMD="bash $BIN/select.sh" \
    BACKLOG_LOOP_ITERATION_CMD="bash $BIN/iter.sh" \
    bash "$SCRIPT" run "$1" 2>/dev/null)" || RC=$?
}

# ── 1. max-N: 5 eligible candidates, N=3 -> exactly 3 iterations, stop max-N.
#    Cannot exceed N (AC3a). Full-transcript equality: exactly these tasks, in
#    order, and nothing after the stop line.
mkfix c1
printf 'T101\nT102\nT103\nT104\nT105\n' > "$FIX/backlog"
ACT="bash $BIN/act-auto.sh"
run_loop 3
want="$(printf 'iteration 1 task T101 outcome pass PR-T101\niteration 2 task T102 outcome pass PR-T102\niteration 3 task T103 outcome pass PR-T103\nstop: max-N after 3 of 3')"
assert_eq "max-N: exact transcript at N=3 with 5 eligible" "$OUT" "$want"
assert_eq "max-N: exit 0 on a clean stop" "$RC" "0"
want="$(printf 'start T101\nend T101 outcome pass PR-T101\nstart T102\nend T102 outcome pass PR-T102\nstart T103\nend T103 outcome pass PR-T103')"
assert_eq "max-N: iteration command invoked exactly 3 times" "$(cat "$FIX/iter.log")" "$want"

# ── 2. N=0 is a valid no-op run (AC3a): stop (a) fires before any iteration —
#    zero iterations, the iteration AND selection commands never invoked.
mkfix c2
printf 'T101\nT102\n' > "$FIX/backlog"
ACT="bash $BIN/act-auto.sh"
run_loop 0
assert_eq "N=0: no-op transcript, stop max-N" "$OUT" "stop: max-N after 0 of 0"
assert_eq "N=0: iteration command NEVER invoked" "$(cat "$FIX/iter.log")" ""
assert_eq "N=0: selection never consulted" "$(cat "$FIX/sel.log")" ""
assert_eq "N=0: activation still consulted first" "$(cat "$FIX/events.log")" "activation"

# ── 3. M < N eligible (AC3b): completes all M=2 with budget N=5 left, stop
#    backlog-drained — never stops early while eligible work and budget remain.
mkfix c3
printf 'T111\nT112\n' > "$FIX/backlog"
ACT="bash $BIN/act-auto.sh"
run_loop 5
want="$(printf 'iteration 1 task T111 outcome pass PR-T111\niteration 2 task T112 outcome pass PR-T112\nstop: backlog-drained after 2 of 5')"
assert_eq "M<N: all M complete, stop backlog-drained" "$OUT" "$want"

# ── 4. First gate FAIL advances (AC3c): T201 FAILs once -> the next selection
#    passes over T201 while T202 exists; the skip is consumed by that ONE
#    selection, so T201 is re-selected afterwards and completes.
mkfix c4
printf 'T201\nT202\n' > "$FIX/backlog"
printf 'T201 fail-discard\n' > "$FIX/plan"
ACT="bash $BIN/act-auto.sh"
run_loop 5
want="$(printf 'iteration 1 task T201 outcome fail-discard\niteration 2 task T202 outcome pass PR-T202\niteration 3 task T201 outcome pass PR-T201\nstop: backlog-drained after 3 of 5')"
assert_eq "first-FAIL-advances: exact transcript" "$OUT" "$want"
# The selector's own log proves the exclusion sets per consult: the FAILed id is
# excluded on exactly ONE selection (consult 2) and on no later consult.
want="$(printf 'sel:\nsel:T201\nsel:\nsel:')"
assert_eq "first-FAIL-advances: skip excluded on exactly one selection" "$(cat "$FIX/sel.log")" "$want"

# ── 5. Same identity FAILs twice -> stop repeated-gate-fail (AC3c): the neutral
#    doc's worked two-task trace with no other unblocked candidate — the skipped
#    identity is re-selected (via the exclude-only-ineligible re-consult), its
#    fails count intact, and the second FAIL stops the run.
mkfix c5
printf 'T301\n' > "$FIX/backlog"
printf 'T301 fail-discard\nT301 fail-discard\n' > "$FIX/plan"
ACT="bash $BIN/act-auto.sh"
run_loop 5
want="$(printf 'iteration 1 task T301 outcome fail-discard\niteration 2 task T301 outcome fail-discard\nstop: repeated-gate-fail after 2 of 5')"
assert_eq "repeated-gate-fail: exact transcript (worked trace)" "$OUT" "$want"
# Selector log proves the re-selection path: consult 2 excludes the skipped id
# (finds nothing), consult 3 excludes only ineligible (empty) and re-selects it.
want="$(printf 'sel:\nsel:T301\nsel:')"
assert_eq "repeated-gate-fail: skip re-selected when no other candidate" "$(cat "$FIX/sel.log")" "$want"

# ── 6. Stop conditions fire only BETWEEN iterations (AC3): the case-5 fixture's
#    iteration log shows BOTH FAILing iterations ran to their terminal state
#    (start AND end markers) — the stopping second FAIL was a complete, recorded
#    iteration before the stop line (already last in the exact transcript above).
want="$(printf 'start T301\nend T301 outcome fail-discard\nstart T301\nend T301 outcome fail-discard')"
assert_eq "between-iterations: FAILing iterations run to terminal state before stop" "$(cat "$FIX/iter.log")" "$want"

# ── 7. Activation is consulted BEFORE any iteration (AC2a): the shared recorder
#    log proves the ordering activation -> select -> iteration...
mkfix c7
printf 'T401\n' > "$FIX/backlog"
ACT="bash $BIN/act-auto.sh"
run_loop 1
want="$(printf 'activation\nselect\niteration T401')"
assert_eq "activation ordering: consulted before selection and iteration" "$(cat "$FIX/events.log")" "$want"
want="$(printf 'iteration 1 task T401 outcome pass PR-T401\nstop: max-N after 1 of 1')"
assert_eq "activation ordering: transcript" "$OUT" "$want"
# ...and activation=review means ZERO iterations run: the loop never starts.
mkfix c7b
printf 'T401\n' > "$FIX/backlog"
ACT="bash $BIN/act-review.sh"
run_loop 3
assert_eq "review at start: stop fail-closed, zero iterations" "$OUT" "stop: fail-closed after 0 of 3"
assert_eq "review at start: only the activation consult happened" "$(cat "$FIX/events.log")" "activation"
assert_eq "review at start: iteration command never invoked" "$(cat "$FIX/iter.log")" ""

# ── 8. The REAL default activation (AC2b): BACKLOG_LOOP_ACTIVATION_CMD unset,
#    so the skeleton runs the shipped autonomy-mode.sh against this repo's
#    profile — no opt-in, no session authorization -> review, nothing runs.
mkfix c8
printf 'T410\n' > "$FIX/backlog"
RC=0
OUT="$(cd "$REPO" && FIX="$FIX" \
  BACKLOG_LOOP_SELECT_CMD="bash $BIN/select.sh" \
  BACKLOG_LOOP_ITERATION_CMD="bash $BIN/iter.sh" \
  bash "$SCRIPT" run 2 2>/dev/null)" || RC=$?
assert_eq "real default activation: shipped profile resolves to review" "$OUT" "stop: fail-closed after 0 of 2"
assert_eq "real default activation: exit 0 on the clean fail-closed stop" "$RC" "0"
assert_eq "real default activation: iteration command never invoked" "$(cat "$FIX/iter.log")" ""

# ── 9. Activation flips to review between iterations (AC3d): autonomous once,
#    then review -> iteration 1 completes, the between-iteration re-check stops
#    fail-closed WITHOUT starting iteration 2.
mkfix c9
printf 'T501\nT502\nT503\n' > "$FIX/backlog"
printf 'autonomous\nreview\n' > "$FIX/act.plan"
ACT="bash $BIN/act-seq.sh"
run_loop 5
want="$(printf 'iteration 1 task T501 outcome pass PR-T501\nstop: fail-closed after 1 of 5')"
assert_eq "activation flip: stop fail-closed after the completed iteration" "$OUT" "$want"
# Recorder ordering: the re-check happens BEFORE any second selection/iteration.
want="$(printf 'activation\nselect\niteration T501\nactivation')"
assert_eq "activation flip: re-check precedes any next selection" "$(cat "$FIX/events.log")" "$want"
want="$(printf 'start T501\nend T501 outcome pass PR-T501')"
assert_eq "activation flip: iteration 2 never started" "$(cat "$FIX/iter.log")" "$want"

# ── 10. Aborted iteration -> stop fail-closed (AC3d): the explicit outcome, a
#    non-zero exit, and an unrecognized outcome all read as aborted.
mkfix c10a
printf 'T601\nT699\n' > "$FIX/backlog"
printf 'T601 aborted\n' > "$FIX/plan"
ACT="bash $BIN/act-auto.sh"
run_loop 4
want="$(printf 'iteration 1 task T601 outcome aborted\nstop: fail-closed after 1 of 4')"
assert_eq "aborted outcome: stop fail-closed" "$OUT" "$want"
mkfix c10b
printf 'T602\nT699\n' > "$FIX/backlog"
printf 'T602 EXIT1\n' > "$FIX/plan"
ACT="bash $BIN/act-auto.sh"
run_loop 4
want="$(printf 'iteration 1 task T602 outcome aborted\nstop: fail-closed after 1 of 4')"
assert_eq "non-zero-exit cycle: reads as aborted, stop fail-closed" "$OUT" "$want"
mkfix c10c
printf 'T603\nT699\n' > "$FIX/backlog"
printf 'T603 banana\n' > "$FIX/plan"
ACT="bash $BIN/act-auto.sh"
run_loop 4
want="$(printf 'iteration 1 task T603 outcome aborted\nstop: fail-closed after 1 of 4')"
assert_eq "unrecognized outcome: reads as aborted, stop fail-closed" "$OUT" "$want"

# ── 11. Missing/broken activation command -> review, never autonomous (AC2):
#    a nonexistent command and one that prints `autonomous` but exits non-zero.
mkfix c11a
printf 'T610\n' > "$FIX/backlog"
ACT="/nonexistent/no-such-activation-check"
run_loop 3
assert_eq "missing activation cmd: fail closed to review" "$OUT" "stop: fail-closed after 0 of 3"
assert_eq "missing activation cmd: iteration command never invoked" "$(cat "$FIX/iter.log")" ""
mkfix c11b
printf 'T611\n' > "$FIX/backlog"
ACT="bash $BIN/act-lying.sh"
run_loop 3
assert_eq "failing activation cmd: exit code wins over printed 'autonomous'" "$OUT" "stop: fail-closed after 0 of 3"
assert_eq "failing activation cmd: iteration command never invoked" "$(cat "$FIX/iter.log")" ""

# ── 12. refused -> ineligible for the rest of the run (AC3c support): T701 is
#    refused once, excluded from EVERY later consult, and never re-invoked.
mkfix c12
printf 'T701\nT702\n' > "$FIX/backlog"
printf 'T701 refused\n' > "$FIX/plan"
ACT="bash $BIN/act-auto.sh"
run_loop 5
want="$(printf 'iteration 1 task T701 outcome refused\niteration 2 task T702 outcome pass PR-T702\nstop: backlog-drained after 2 of 5')"
assert_eq "refused: exact transcript" "$OUT" "$want"
want="$(printf 'sel:\nsel:T701\nsel:T701')"
assert_eq "refused: identity excluded from every later selection" "$(cat "$FIX/sel.log")" "$want"
want="$(printf 'start T701\nend T701 outcome refused\nstart T702\nend T702 outcome pass PR-T702')"
assert_eq "refused: identity never re-invoked this run" "$(cat "$FIX/iter.log")" "$want"

# ── 13. Broken selector -> stop fail-closed (the header's documented decision:
#    a selector that cannot run is a lifecycle check failing closed, condition
#    (d) — never silently read as an empty backlog / backlog-drained).
mkfix c13
printf 'T710\n' > "$FIX/backlog"
ACT="bash $BIN/act-auto.sh"
RC=0
OUT="$(BACKLOG_LOOP_ACTIVATION_CMD="$ACT" \
  BACKLOG_LOOP_SELECT_CMD="/nonexistent/no-such-selector" \
  BACKLOG_LOOP_ITERATION_CMD="bash $BIN/iter.sh" \
  bash "$SCRIPT" run 3 2>/dev/null)" || RC=$?
assert_eq "broken selector: stop fail-closed, not backlog-drained" "$OUT" "stop: fail-closed after 0 of 3"
assert_eq "broken selector: exit 0 on the clean stop" "$RC" "0"
assert_eq "broken selector: iteration command never invoked" "$(cat "$FIX/iter.log")" ""

# ── 14. Malformed selector output -> stop fail-closed (craft-review finding):
#    the selector contract is EXACTLY one task ID (`T` + digits) or nothing.
#    Two IDs on one line must never become a concatenated bogus identity
#    ("T901T902"); multi-line or garbage output is the selector misbehaving —
#    condition (d), never an accepted candidate, never backlog-drained.
run_malformed() { # <label> <selector-stdout-via-printf-format>
  mkfix "$1"
  RC=0
  OUT="$(BACKLOG_LOOP_ACTIVATION_CMD="bash $BIN/act-auto.sh" \
    BACKLOG_LOOP_SELECT_CMD="printf '$2'" \
    BACKLOG_LOOP_ITERATION_CMD="bash $BIN/iter.sh" \
    bash "$SCRIPT" run 3 2>/dev/null)" || RC=$?
}
run_malformed c14a 'T901 T902\n'
assert_eq "malformed selector (two ids, one line): stop fail-closed" "$OUT" "stop: fail-closed after 0 of 3"
assert_eq "malformed selector (two ids, one line): iteration never invoked" "$(cat "$FIX/iter.log")" ""
run_malformed c14b 'T901\nT902\n'
assert_eq "malformed selector (two ids, two lines): stop fail-closed" "$OUT" "stop: fail-closed after 0 of 3"
assert_eq "malformed selector (two ids, two lines): iteration never invoked" "$(cat "$FIX/iter.log")" ""
run_malformed c14c 'banana\n'
assert_eq "malformed selector (non-task-id token): stop fail-closed" "$OUT" "stop: fail-closed after 0 of 3"
assert_eq "malformed selector (non-task-id token): iteration never invoked" "$(cat "$FIX/iter.log")" ""

# ── Usage guards: missing/non-numeric N, wrong subcommand, and a missing seam
#    are loud exit-2 errors — never a silent default that touches real state.
rc_guard() { # <label> <want-rc> [args...] — seams present unless overridden
  local label="$1" want="$2"
  shift 2
  local got=0
  BACKLOG_LOOP_ACTIVATION_CMD="bash $BIN/act-auto.sh" \
    BACKLOG_LOOP_SELECT_CMD="${GUARD_SELECT-bash $BIN/select.sh}" \
    BACKLOG_LOOP_ITERATION_CMD="${GUARD_ITER-bash $BIN/iter.sh}" \
    bash "$SCRIPT" "$@" > /dev/null 2>&1 || got=$?
  if [ "$got" = "$want" ]; then ok; else bad "$label: got rc=$got want $want"; fi
}
mkfix cguard
printf 'T801\n' > "$FIX/backlog"
rc_guard "usage: no arguments -> exit 2" 2
rc_guard "usage: missing N -> exit 2" 2 run
rc_guard "usage: non-numeric N -> exit 2" 2 run three
rc_guard "usage: negative N -> exit 2" 2 run -1
rc_guard "usage: unknown subcommand -> exit 2" 2 walk 3
GUARD_SELECT="" rc_guard "usage: missing BACKLOG_LOOP_SELECT_CMD -> exit 2" 2 run 1
GUARD_ITER="" rc_guard "usage: missing BACKLOG_LOOP_ITERATION_CMD -> exit 2" 2 run 1
assert_eq "usage errors: iteration command never invoked" "$(cat "$FIX/iter.log")" ""

# ── Report drive (T905): under BACKLOG_LOOP_RUN_ID the loop drives the T904
#    emitter — one iteration record per completed cycle in the outcome's own
#    form plus the terminal summary — write-only and silent-to-the-run; without
#    a run id nothing is driven (the T902 behavior). Field assertions are
#    per-record via jq (the emitter's own test idiom), never a grep-anywhere.
run_loop_report() { # <N> <report-file> <run-id>
  RC=0
  OUT="$(BACKLOG_LOOP_ACTIVATION_CMD="$ACT" \
    BACKLOG_LOOP_SELECT_CMD="bash $BIN/select.sh" \
    BACKLOG_LOOP_ITERATION_CMD="bash $BIN/iter.sh" \
    BACKLOG_LOOP_REPORT_FILE="$2" \
    BACKLOG_LOOP_RUN_ID="$3" \
    bash "$SCRIPT" run "$1" 2>/dev/null)" || RC=$?
}
rfield() { # <report-file> <line#> <jq-expr>
  sed -n "$2p" "$1" | jq -r "$3" 2>/dev/null
}

# rd1: a mixed run (pass / first-FAIL / re-selection refused) writes one record
# per iteration + one summary, each field equal to that iteration's outcome.
mkfix rd1
printf 'T901\nT902\nT903\n' > "$FIX/backlog"
printf 'T902 fail-discard\nT902 refused\n' > "$FIX/plan"
ACT="bash $BIN/act-auto.sh"
run_loop_report 9 "$FIX/report.jsonl" run-rd1
want="$(printf 'iteration 1 task T901 outcome pass PR-T901\niteration 2 task T902 outcome fail-discard\niteration 3 task T903 outcome pass PR-T903\niteration 4 task T902 outcome refused\nstop: backlog-drained after 4 of 9')"
assert_eq "report drive: stdout transcript unchanged by the drive" "$OUT" "$want"
assert_eq "report drive: exactly 5 records (4 iterations + summary)" "$(grep -c . "$FIX/report.jsonl")" "5"
assert_eq "report drive: rec1 task"        "$(rfield "$FIX/report.jsonl" 1 .task_id)" "T901"
assert_eq "report drive: rec1 outcome"     "$(rfield "$FIX/report.jsonl" 1 .outcome)" "pass"
assert_eq "report drive: rec1 verdict"     "$(rfield "$FIX/report.jsonl" 1 .verdict)" "PASS"
assert_eq "report drive: rec1 pr ref"      "$(rfield "$FIX/report.jsonl" 1 .pr)" "PR-T901"
assert_eq "report drive: rec1 run id"      "$(rfield "$FIX/report.jsonl" 1 .run_id)" "run-rd1"
assert_eq "report drive: rec2 task"        "$(rfield "$FIX/report.jsonl" 2 .task_id)" "T902"
assert_eq "report drive: rec2 outcome"     "$(rfield "$FIX/report.jsonl" 2 .outcome)" "fail-discard"
assert_eq "report drive: rec2 verdict"     "$(rfield "$FIX/report.jsonl" 2 .verdict)" "FAIL"
assert_eq "report drive: rec2 disposition" "$(rfield "$FIX/report.jsonl" 2 .disposition)" "discard"
assert_eq "report drive: rec2 carries no pr" "$(rfield "$FIX/report.jsonl" 2 'has("pr")')" "false"
assert_eq "report drive: rec3 task"        "$(rfield "$FIX/report.jsonl" 3 .task_id)" "T903"
assert_eq "report drive: rec3 outcome"     "$(rfield "$FIX/report.jsonl" 3 .outcome)" "pass"
assert_eq "report drive: rec4 outcome"     "$(rfield "$FIX/report.jsonl" 4 .outcome)" "refused"
assert_eq "report drive: rec4 (ungated) carries no verdict" "$(rfield "$FIX/report.jsonl" 4 'has("verdict")')" "false"
assert_eq "report drive: summary stop"     "$(rfield "$FIX/report.jsonl" 5 .stop)" "backlog-drained"
assert_eq "report drive: summary iterations" "$(rfield "$FIX/report.jsonl" 5 .iterations)" "4"
assert_eq "report drive: summary budget"   "$(rfield "$FIX/report.jsonl" 5 .budget)" "9"

# rd2: no run id -> no drive, no report file (the T902 behavior, unchanged).
mkfix rd2
printf 'T901\n' > "$FIX/backlog"
ACT="bash $BIN/act-auto.sh"
run_loop_report 3 "$FIX/report.jsonl" ""
assert_eq "no run id: loop runs normally" "$OUT" "$(printf 'iteration 1 task T901 outcome pass PR-T901\nstop: backlog-drained after 1 of 3')"
if [ -f "$FIX/report.jsonl" ]; then bad "no run id: report file must not be created"; else ok; fi

# rd3: an unwritable report path is silent-to-the-run — transcript and exit
# code identical to rd2's clean run (the write failure steers nothing).
mkfix rd3
printf 'T901\n' > "$FIX/backlog"
: > "$FIX/blocker" # a FILE where a directory is needed -> mkdir/append both fail
ACT="bash $BIN/act-auto.sh"
run_loop_report 3 "$FIX/blocker/report.jsonl" run-rd3
assert_eq "unwritable report: transcript unchanged" "$OUT" "$(printf 'iteration 1 task T901 outcome pass PR-T901\nstop: backlog-drained after 1 of 3')"
assert_eq "unwritable report: exit 0" "$RC" "0"

# rd4: a fail-closed stop before any iteration still writes the summary record
# (a partial run is visible AS partial — zero of N).
mkfix rd4
printf 'T901\n' > "$FIX/backlog"
ACT="bash $BIN/act-review.sh"
run_loop_report 3 "$FIX/report.jsonl" run-rd4
assert_eq "review mode: loop never starts" "$OUT" "stop: fail-closed after 0 of 3"
assert_eq "review mode: summary is the ONLY record" "$(grep -c . "$FIX/report.jsonl")" "1"
assert_eq "review mode: summary stop" "$(rfield "$FIX/report.jsonl" 1 .stop)" "fail-closed"
assert_eq "review mode: summary iterations" "$(rfield "$FIX/report.jsonl" 1 .iterations)" "0"

# ── Concurrency lock (T906, issue #267 DW1/DW2). Two overlapping invocations —
#    a cron fire crossing a manual run — must not both reach selection. Before
#    this, the ONLY thing preventing a genuine double-start was an incidental
#    `git worktree add -b` branch-name collision, which is not a mutex.

# Blocking iteration stub: announces it is mid-iteration, then waits for a release
# file, so run A provably HOLDS the lock while run B starts. Bounded (~60s worst
# case) so a regression cannot hang CI forever.
cat > "$BIN/iter-block.sh" <<'EOF'
#!/usr/bin/env bash
set -u
printf 'iteration %s\n' "$1" >> "$FIX/events.log"
: > "$FIX/holding"
i=0
while [ ! -e "$FIX/go" ]; do
  i=$((i + 1)); [ "$i" -lt 600 ] || break
  sleep 0.1 2>/dev/null || sleep 1
done
printf 'pass PR-%s\n' "$1"
EOF

# Sweep seam stub: logs the call and its session argument, then is DELIBERATELY
# noisy and non-zero — a broken sweep must not colour the run in any way.
cat > "$BIN/sweep.sh" <<'EOF'
#!/usr/bin/env bash
set -u
printf 'sweep\n' >> "$FIX/events.log"
printf 'session:%s\n' "${1:-}" >> "$FIX/sweep.log"
printf 'sweep noise on stdout\n'
printf 'sweep noise on stderr\n' >&2
exit 1
EOF

# wait_file <path> — bounded wait for a file to appear; non-zero if it never does.
wait_file() {
  local i=0
  while [ ! -e "$1" ]; do
    i=$((i + 1)); [ "$i" -lt 600 ] || return 1
    sleep 0.1 2>/dev/null || sleep 1
  done
  return 0
}

# dead_pid — a pid that is certainly NOT running: spawn a trivial child and reap it.
dead_pid() { ( exit 0 ) & local p=$!; wait "$p" 2>/dev/null; printf '%s\n' "$p"; }

# ── L1. TWO CONCURRENT STARTS -> exactly one proceeds (DW2's first direction).
#    Real processes, not a simulated lock file: A is held mid-iteration while B
#    starts for real.
mkfix lock-concurrent
printf 'T101\nT102\n' > "$FIX/backlog"
ACT="bash $BIN/act-auto.sh"
LOCK_A="$FIX/loop.lock"
( BACKLOG_LOOP_ACTIVATION_CMD="$ACT" \
  BACKLOG_LOOP_SELECT_CMD="bash $BIN/select.sh" \
  BACKLOG_LOOP_ITERATION_CMD="bash $BIN/iter-block.sh" \
  BACKLOG_LOOP_LOCK_DIR="$LOCK_A" \
  bash "$SCRIPT" run 1 > "$FIX/a.out" 2>/dev/null ) &
apid=$!
if wait_file "$FIX/holding"; then
  ok                                   # setup gate: the concurrency window is genuinely open
  BRC=0
  BOUT="$(BACKLOG_LOOP_ACTIVATION_CMD="$ACT" \
    BACKLOG_LOOP_SELECT_CMD="bash $BIN/select.sh" \
    BACKLOG_LOOP_ITERATION_CMD="bash $BIN/iter.sh" \
    BACKLOG_LOOP_LOCK_DIR="$LOCK_A" \
    bash "$SCRIPT" run 1 2>"$FIX/b.err")" || BRC=$?
  assert_eq "lock: the second concurrent start declines" "$BOUT" "stop: fail-closed after 0 of 1"
  assert_eq "lock: a declined start is still a clean stop" "$BRC" "0"
  # deterministic, not silent: the decline names the lock it could not take.
  if grep -qF "$LOCK_A" "$FIX/b.err"; then ok; else bad "lock: the declining run printed no diagnostic naming the lock"; fi
  : > "$FIX/go"
  wait "$apid"
  # THE criterion — "does not start a second selection/iteration". Counted across
  # BOTH runs, so a B that declined only AFTER consulting the selector would fail.
  assert_eq "lock: exactly one selection across two concurrent starts" "$(grep -c '^select$' "$FIX/events.log")" "1"
  assert_eq "lock: exactly one iteration across two concurrent starts" "$(grep -c '^iteration ' "$FIX/events.log")" "1"
  awant="$(printf 'iteration 1 task T101 outcome pass PR-T101\nstop: max-N after 1 of 1')"
  assert_eq "lock: the holder completed its own run normally" "$(cat "$FIX/a.out")" "$awant"
  # DW2's second direction: a normal run RELEASES, so the next run is not deadlocked.
  if [ ! -d "$LOCK_A" ]; then ok; else bad "lock: the holder did not release the lock on exit"; fi
  # (the blocking stub never marks its task done, so the fresh run re-selects T101 —
  # what matters here is that it PROCEEDS at all rather than declining on a stale lock.)
  run_loop 1
  assert_eq "lock: a later run proceeds after the lock was released" "$OUT" "$(printf 'iteration 1 task T101 outcome pass PR-T101\nstop: max-N after 1 of 1')"
else
  bad "lock setup: run A never reached its iteration — the concurrency window never opened"
  kill "$apid" 2>/dev/null
fi

# ── L2. A LIVE holder is respected (the same decision, deterministically, with no
#    fork): the lock records THIS test process, which is certainly running.
mkfix lock-live
printf 'T101\n' > "$FIX/backlog"
ACT="bash $BIN/act-auto.sh"
LOCK_L="$FIX/live.lock"
mkdir -p "$LOCK_L"
printf 'pid=%s\nsession=someone-else\n' "$$" > "$LOCK_L/owner"
LRC=0
: > "$FIX/sweep.log"
LOUT="$(BACKLOG_LOOP_ACTIVATION_CMD="$ACT" \
  BACKLOG_LOOP_SELECT_CMD="bash $BIN/select.sh" \
  BACKLOG_LOOP_ITERATION_CMD="bash $BIN/iter.sh" \
  BACKLOG_LOOP_SWEEP_CMD="bash $BIN/sweep.sh" \
  BACKLOG_LOOP_LOCK_DIR="$LOCK_L" \
  bash "$SCRIPT" run 1 2>/dev/null)" || LRC=$?
assert_eq "lock: a live holder makes the run decline" "$LOUT" "stop: fail-closed after 0 of 1"
assert_eq "lock: nothing was selected while declining" "$(grep -c '^select$' "$FIX/events.log")" "0"
# The most dangerous ordering for the new DESTRUCTIVE path: a run turned away by a live
# holder must not sweep — its sweep would see the LIVE holder's workspaces as orphans.
assert_eq "lock: a run declined by a live holder takes no sweep action" "$(grep -c '^sweep$' "$FIX/events.log")" "0"
# and the live holder's lock is left exactly as it was — never released by the decliner.
if [ -d "$LOCK_L" ] && grep -qxF "pid=$$" "$LOCK_L/owner"; then ok; else bad "lock: a declining run removed or rewrote the LIVE holder's lock"; fi

# ── L3. A STALE lock is reclaimed (the crash case): one SIGKILL must not wedge
#    every future run. The recorded holder is a reaped pid, so it cannot be alive.
mkfix lock-stale
printf 'T101\n' > "$FIX/backlog"
ACT="bash $BIN/act-auto.sh"
LOCK_S="$FIX/stale.lock"
mkdir -p "$LOCK_S"
printf 'pid=%s\nsession=crashed-run\n' "$(dead_pid)" > "$LOCK_S/owner"
SRC=0
SOUT="$(BACKLOG_LOOP_ACTIVATION_CMD="$ACT" \
  BACKLOG_LOOP_SELECT_CMD="bash $BIN/select.sh" \
  BACKLOG_LOOP_ITERATION_CMD="bash $BIN/iter.sh" \
  BACKLOG_LOOP_LOCK_DIR="$LOCK_S" \
  bash "$SCRIPT" run 1 2>/dev/null)" || SRC=$?
assert_eq "lock: a stale lock is reclaimed, not deadlocked around" "$SOUT" "$(printf 'iteration 1 task T101 outcome pass PR-T101\nstop: max-N after 1 of 1')"
if [ ! -d "$LOCK_S" ]; then ok; else bad "lock: the reclaimed lock was not released at exit"; fi

# ── L4. A lock dir with NO owner file (killed between mkdir and the owner write)
#    is also stale — otherwise that one-instruction window wedges the loop forever.
mkfix lock-noowner
printf 'T101\n' > "$FIX/backlog"
ACT="bash $BIN/act-auto.sh"
LOCK_N="$FIX/noowner.lock"
mkdir -p "$LOCK_N"
NOUT="$(BACKLOG_LOOP_ACTIVATION_CMD="$ACT" \
  BACKLOG_LOOP_SELECT_CMD="bash $BIN/select.sh" \
  BACKLOG_LOOP_ITERATION_CMD="bash $BIN/iter.sh" \
  BACKLOG_LOOP_LOCK_DIR="$LOCK_N" \
  bash "$SCRIPT" run 1 2>/dev/null)" || :
assert_eq "lock: an owner-less lock dir is reclaimed" "$NOUT" "$(printf 'iteration 1 task T101 outcome pass PR-T101\nstop: max-N after 1 of 1')"

# ── L5. The reclaim can NEVER destroy real content. Point the lock at a populated
#    directory that is not ours: the reclaim must fail (rmdir refuses a non-empty
#    dir — there is no rm -rf on this path) and the run must decline, with the
#    directory and its contents intact.
mkfix lock-populated
printf 'T101\n' > "$FIX/backlog"
ACT="bash $BIN/act-auto.sh"
LOCK_P="$FIX/not-a-lock"
mkdir -p "$LOCK_P"
echo precious > "$LOCK_P/important.txt"
POUT="$(BACKLOG_LOOP_ACTIVATION_CMD="$ACT" \
  BACKLOG_LOOP_SELECT_CMD="bash $BIN/select.sh" \
  BACKLOG_LOOP_ITERATION_CMD="bash $BIN/iter.sh" \
  BACKLOG_LOOP_LOCK_DIR="$LOCK_P" \
  bash "$SCRIPT" run 1 2>/dev/null)" || :
assert_eq "lock: an unreclaimable lock path declines rather than forcing" "$POUT" "stop: fail-closed after 0 of 1"
if [ -f "$LOCK_P/important.txt" ] && [ "$(cat "$LOCK_P/important.txt")" = "precious" ]; then ok; else bad "lock: the stale-lock reclaim destroyed unrelated directory content"; fi

# ── L6. A SIGNALLED run releases the lock AND stops. A release-only handler is a
#    trap: bash resumes the interrupted flow when the handler returns, so the loop
#    would carry on iterating while holding no lock. With N=5 and 3 eligible tasks,
#    a resuming loop drains the backlog (3 iterations); a correctly-exiting one
#    stops after the iteration that was in flight when the signal landed (1).
mkfix lock-signal
printf 'T101\nT102\nT103\n' > "$FIX/backlog"
ACT="bash $BIN/act-auto.sh"
LOCK_G="$FIX/signal.lock"
BACKLOG_LOOP_ACTIVATION_CMD="$ACT" \
  BACKLOG_LOOP_SELECT_CMD="bash $BIN/select.sh" \
  BACKLOG_LOOP_ITERATION_CMD="bash $BIN/iter-block.sh" \
  BACKLOG_LOOP_LOCK_DIR="$LOCK_G" \
  bash "$SCRIPT" run 5 >/dev/null 2>&1 &
gpid=$!
if wait_file "$FIX/holding"; then
  ok
  # bash defers a trap until the foreground command returns, so signal THEN release the
  # blocked iteration: the handler runs at the next opportunity, exactly as in production.
  kill -TERM "$gpid" 2>/dev/null
  : > "$FIX/go"
  grc=0; wait "$gpid" 2>/dev/null || grc=$?
  assert_eq "lock: a signalled run stops instead of resuming unlocked" "$(grep -c '^iteration ' "$FIX/events.log")" "1"
  if [ ! -d "$LOCK_G" ]; then ok; else bad "lock: a signalled run did not release its lock"; fi
  # 128+SIGTERM — a killed run must not masquerade as a clean stop.
  assert_eq "lock: a signalled run exits 128+signo, not 0" "$grc" "143"
else
  bad "lock signal setup: the run never reached its iteration — no signal window opened"
  kill "$gpid" 2>/dev/null; : > "$FIX/go"
fi

# ── L7. The lock is scoped to the REPOSITORY, not to the checkout path. Two linked
#    worktrees of one repo hold different script paths but SHARE one worktree
#    registry — the blast radius of the crash-recovery sweep. Keyed on the script's
#    own directory they would take different locks, both proceed, and the second
#    run's sweep would reap the first's LIVE workspaces.
mkfix lock-repo-scope
printf 'T101\n' > "$FIX/backlog"
ACT="bash $BIN/act-auto.sh"
RS="$FIX/repo"; RS2="$FIX/repo2"
for r in "$RS" "$RS2"; do
  git init -q -b main "$r" >/dev/null 2>&1
  git -C "$r" config user.email t@example.com
  git -C "$r" config user.name test
  mkdir -p "$r/.claude/hooks"
  cp "$SCRIPT" "$r/.claude/hooks/backlog-loop.sh"
  git -C "$r" add .claude/hooks/backlog-loop.sh >/dev/null 2>&1
  git -C "$r" commit -q -m seed >/dev/null 2>&1
done
git -C "$RS" worktree add -q "$FIX/linked" -b linked >/dev/null 2>&1
# SETUP GATE: without a real linked worktree carrying its own copy of the script, the
# different-path/same-repo condition never exists and the case proves nothing.
if [ -f "$FIX/linked/.claude/hooks/backlog-loop.sh" ]; then
  ok
  ( cd "$RS" && TMPDIR="$FIX" BACKLOG_LOOP_LOCK_DIR= BACKLOG_LOOP_ACTIVATION_CMD="$ACT" \
    BACKLOG_LOOP_SELECT_CMD="bash $BIN/select.sh" \
    BACKLOG_LOOP_ITERATION_CMD="bash $BIN/iter-block.sh" \
    bash .claude/hooks/backlog-loop.sh run 1 >/dev/null 2>&1 ) &
  rpid=$!
  if wait_file "$FIX/holding"; then
    ok
    # Same repository, DIFFERENT script path -> must share the lock and decline.
    BOUT2="$( cd "$FIX/linked" && TMPDIR="$FIX" BACKLOG_LOOP_LOCK_DIR= BACKLOG_LOOP_ACTIVATION_CMD="$ACT" \
      BACKLOG_LOOP_SELECT_CMD="bash $BIN/select.sh" \
      BACKLOG_LOOP_ITERATION_CMD="bash $BIN/iter.sh" \
      bash .claude/hooks/backlog-loop.sh run 1 2>/dev/null )"
    assert_eq "lock: a linked worktree of the SAME repo shares the lock" "$BOUT2" "stop: fail-closed after 0 of 1"
    # ...and an UNRELATED repo must still run: the key is repo-scoped, not a global constant
    # (a lock keyed on nothing at all would also pass the assertion above).
    COUT="$( cd "$RS2" && TMPDIR="$FIX" BACKLOG_LOOP_LOCK_DIR= BACKLOG_LOOP_ACTIVATION_CMD="$ACT" \
      BACKLOG_LOOP_SELECT_CMD="bash $BIN/select.sh" \
      BACKLOG_LOOP_ITERATION_CMD="bash $BIN/iter.sh" \
      bash .claude/hooks/backlog-loop.sh run 1 2>/dev/null )"
    assert_eq "lock: an unrelated repo is not blocked (repo-scoped, not global)" "$COUT" "$(printf 'iteration 1 task T101 outcome pass PR-T101\nstop: max-N after 1 of 1')"
  else
    bad "lock repo-scope setup: the holder never reached its iteration"
  fi
  : > "$FIX/go"
  wait "$rpid" 2>/dev/null || :
else
  bad "lock repo-scope setup: the linked worktree was not created — the same-repo/different-path condition never existed"
fi

# ── Crash-recovery sweep seam (T906, DW3): DRIVEN once at startup, before the
#    first selection, with the run's session id — and silent-to-the-run.
mkfix sweep-seam
printf 'T101\nT102\n' > "$FIX/backlog"
ACT="bash $BIN/act-auto.sh"
: > "$FIX/sweep.log"
SWOUT="$(BACKLOG_LOOP_ACTIVATION_CMD="$ACT" \
  BACKLOG_LOOP_SELECT_CMD="bash $BIN/select.sh" \
  BACKLOG_LOOP_ITERATION_CMD="bash $BIN/iter.sh" \
  BACKLOG_LOOP_SWEEP_CMD="bash $BIN/sweep.sh" \
  BACKLOG_LOOP_SESSION_ID="sess-fixed" \
  bash "$SCRIPT" run 2 2>/dev/null)" || :
# the failing, noisy sweep changes NOTHING about the run's transcript (P5-shaped
# posture: driven write-only, its output and status discarded).
assert_eq "sweep: a failing, noisy sweep leaves the run's transcript untouched" "$SWOUT" "$(printf 'iteration 1 task T101 outcome pass PR-T101\niteration 2 task T102 outcome pass PR-T102\nstop: max-N after 2 of 2')"
assert_eq "sweep: driven exactly once per run, not once per iteration" "$(grep -c '^sweep$' "$FIX/events.log")" "1"
assert_eq "sweep: receives the run's session id as its argument" "$(cat "$FIX/sweep.log")" "session:sess-fixed"
# ordering: the sweep must precede the FIRST selection, so a run cannot inherit a
# previous run's leaked workspaces.
assert_eq "sweep: runs before the first selection" "$(grep -E '^(sweep|select)$' "$FIX/events.log" | head -1)" "sweep"

# ── Sweep is gated on an ENGAGED run: review mode never starts the loop, so it
#    must never take the sweep's destructive action either.
mkfix sweep-review
printf 'T101\n' > "$FIX/backlog"
: > "$FIX/sweep.log"
RVOUT="$(BACKLOG_LOOP_ACTIVATION_CMD="bash $BIN/act-review.sh" \
  BACKLOG_LOOP_SELECT_CMD="bash $BIN/select.sh" \
  BACKLOG_LOOP_ITERATION_CMD="bash $BIN/iter.sh" \
  BACKLOG_LOOP_SWEEP_CMD="bash $BIN/sweep.sh" \
  bash "$SCRIPT" run 1 2>/dev/null)" || :
assert_eq "sweep: review mode still never starts the loop" "$RVOUT" "stop: fail-closed after 0 of 1"
assert_eq "sweep: review mode takes no destructive sweep action" "$(grep -c '^sweep$' "$FIX/events.log")" "0"

# ── Wiring (P2): the `verify` job ACTIVELY runs this test (an active `run:`
#    step scoped to the verify job body, not a comment mention) — same
#    discipline as autonomy-mode.test.sh.
verify_steps() { awk '/^  [A-Za-z]/ { inblk = ($0 ~ /^  verify:/) } inblk { print }' "$CI"; }
runs_in_verify() { verify_steps | grep -qE "^[[:space:]]*run:[[:space:]]+bash[[:space:]]+$1([[:space:]]|\$)"; }
if runs_in_verify '\.claude/hooks/backlog-loop\.test\.sh'; then ok; else bad "verify must RUN backlog-loop.test.sh (active run: step)"; fi

# ── Mechanism <-> model drift backstop: the neutral doc the skeleton implements
#    must exist and still name the closed stop-reason set.
if [ -f "$MODEL" ]; then ok; else bad "missing neutral model .claude/workflow/backlog-loop.md"; fi
for reason in max-N backlog-drained repeated-gate-fail fail-closed; do
  if grep -qF "$reason" "$MODEL" 2>/dev/null; then ok; else bad "backlog-loop.md no longer names stop reason '$reason'"; fi
done

printf 'backlog-loop.test.sh: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
