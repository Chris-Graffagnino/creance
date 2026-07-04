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
