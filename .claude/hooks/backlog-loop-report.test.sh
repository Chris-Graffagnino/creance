#!/usr/bin/env bash
# Behavioral tests for backlog-loop-report.sh — the [backlog-loop]'s observe-only
# run-report emitter (T904, #229, spec 004 US1.AC6). This drives the concrete
# emitter against a temp channel and proves FIELD FIDELITY, not mere
# well-formedness: for a scripted mixed run (pass / fail-discard / refused /
# aborted) it asserts each written line's task ID, verdict, and PR-ref-or-discard
# EXACTLY equal the outcome that was driven — per line, exact-field equality,
# never a prefix or single-match-anywhere check — and that a refused/aborted line
# carries NO verdict and NO pr/discard field (a report line never fabricates a
# gate result). The summary line must record the actual stop condition and
# `iterations of N`, with a partial run (i < N) distinguishable AS partial from
# the line content alone. Plus the mandated posture cases: a WRITE FAILURE IS
# SILENT-TO-THE-RUN (unwritable channel -> exit 0, nothing written, caller
# unaffected), while a malformed drive (a fabricated verdict on an ungated
# outcome, a missing gated field, a non-integer counter) is a LOUD caller error
# (exit 2, nothing written). Bash + jq only, <1s.
#
# Run: bash .claude/hooks/backlog-loop-report.test.sh   (wired into CI verify —
# the wiring assertion below fails if the verify job stops running this file, P2)
set -u

DIR="$(cd "$(dirname "$0")" && pwd)"
EMIT="$DIR/backlog-loop-report.sh"
REPO_ROOT="$(cd "$DIR/../.." && pwd)"
CI="$REPO_ROOT/.github/workflows/ci.yml"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0
ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); printf 'FAIL %s\n' "$1" >&2; [ -n "${2:-}" ] && printf '     %s\n' "$2" >&2; return 0; }
eq()  { if [ "$2" = "$3" ]; then ok; else bad "$1" "want=[$2] got=[$3]"; fi; }

[ -f "$EMIT" ] || { echo "FAIL: emitter missing: $EMIT" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "FAIL: jq required by this test" >&2; exit 1; }

CHAN="$TMP/inbox/telemetry.jsonl"   # parent dir deliberately missing: the emitter creates it

emit() { BACKLOG_LOOP_REPORT_FILE="$CHAN" bash "$EMIT" "$@"; }

# field <lineno> <jq-expr> — evaluate a jq expression against EXACTLY line <lineno>
# of the channel (per-instance: the Nth driven outcome is checked on the Nth line,
# never "some line anywhere matches").
field() { sed -n "${1}p" "$CHAN" | jq -r "$2"; }

# ── the scripted mixed run: every outcome class, driven in order ─────────────────
emit iteration run-A T101 pass PASS 'PR#41'          >/dev/null 2>&1; eq "iteration pass exits 0" 0 "$?"
emit iteration run-A T102 fail-discard FAIL          >/dev/null 2>&1; eq "iteration fail-discard exits 0" 0 "$?"
emit iteration run-A T103 refused                    >/dev/null 2>&1; eq "iteration refused exits 0" 0 "$?"
emit iteration run-A T104 aborted                    >/dev/null 2>&1; eq "iteration aborted exits 0" 0 "$?"
emit summary   run-A fail-closed 4 6                 >/dev/null 2>&1; eq "summary exits 0" 0 "$?"

eq "the run wrote exactly one line per driven call" 5 "$(wc -l < "$CHAN" | tr -d '[:space:]')"

# Line 1 — gate PASS: task ID + gate verdict + PR ref, each EXACTLY the driven value.
eq "line1 record type"                "backlog-loop-iteration" "$(field 1 .record)"
eq "line1 run id"                     "run-A"  "$(field 1 .run_id)"
eq "line1 task id == driven task"     "T101"   "$(field 1 .task_id)"
eq "line1 outcome == driven outcome"  "pass"   "$(field 1 .outcome)"
eq "line1 verdict == driven verdict"  "PASS"   "$(field 1 .verdict)"
eq "line1 pr ref == driven pr ref"    "PR#41"  "$(field 1 .pr)"
eq "line1 pass carries no discard"    "false"  "$(field 1 'has("disposition")')"

# Line 2 — gate FAIL: verdict + the discard, no PR ref.
eq "line2 task id == driven task"     "T102"        "$(field 2 .task_id)"
eq "line2 outcome == driven outcome"  "fail-discard" "$(field 2 .outcome)"
eq "line2 verdict == driven verdict"  "FAIL"        "$(field 2 .verdict)"
eq "line2 discard recorded"           "discard"     "$(field 2 .disposition)"
eq "line2 fail carries no pr ref"     "false"       "$(field 2 'has("pr")')"

# Lines 3+4 — refused/aborted ran NO gate: the line records the outcome itself and
# carries NO verdict and NO pr/discard field (never a fabricated gate result).
eq "line3 task id"                    "T103"    "$(field 3 .task_id)"
eq "line3 outcome refused"            "refused" "$(field 3 .outcome)"
eq "line3 refused has NO verdict"     "false"   "$(field 3 'has("verdict")')"
eq "line3 refused has NO pr"          "false"   "$(field 3 'has("pr")')"
eq "line3 refused has NO discard"     "false"   "$(field 3 'has("disposition")')"
eq "line4 task id"                    "T104"    "$(field 4 .task_id)"
eq "line4 outcome aborted"            "aborted" "$(field 4 .outcome)"
eq "line4 aborted has NO verdict"     "false"   "$(field 4 'has("verdict")')"
eq "line4 aborted has NO pr"          "false"   "$(field 4 'has("pr")')"
eq "line4 aborted has NO discard"     "false"   "$(field 4 'has("disposition")')"

# Line 5 — the terminal summary: the ACTUAL stop condition + `iterations of N`,
# and a partial run (i < N on a non-max-N stop) is readable AS partial from the
# line content alone — never mistaken for a clean drain.
eq "line5 record type"                "backlog-loop-summary" "$(field 5 .record)"
eq "line5 run id"                     "run-A"       "$(field 5 .run_id)"
eq "line5 stop == actual stop"        "fail-closed" "$(field 5 .stop)"
eq "line5 iterations == actual count" "4"           "$(field 5 .iterations)"
eq "line5 budget == invoked N"        "6"           "$(field 5 .budget)"
eq "line5 partial visible (i < N)"    "true"        "$(field 5 '.iterations < .budget')"

# A clean max-N drain, for contrast: the same fields make it distinguishable
# from the partial line above (i == N, stop == max-N).
emit summary run-B max-N 6 6 >/dev/null 2>&1
eq "clean-drain stop recorded"        "max-N" "$(field 6 .stop)"
eq "clean drain not partial (i = N)"  "false" "$(field 6 '.iterations < .budget')"

# ── loud caller errors: nothing written, exit 2 ──────────────────────────────────
before="$(wc -l < "$CHAN" | tr -d '[:space:]')"
emit iteration run-A T105 refused FABRICATED     >/dev/null 2>&1; eq "refused + a fabricated verdict is a loud caller error" 2 "$?"
emit iteration run-A T105 aborted PASS 'PR#9'    >/dev/null 2>&1; eq "aborted + fabricated gate fields is a loud caller error" 2 "$?"
emit iteration run-A T105 pass PASS              >/dev/null 2>&1; eq "pass missing its pr-ref is a loud caller error" 2 "$?"
emit iteration run-A T105 fail-discard           >/dev/null 2>&1; eq "fail-discard missing its verdict is a loud caller error" 2 "$?"
emit iteration run-A T105 exploded               >/dev/null 2>&1; eq "an unknown outcome is a loud caller error" 2 "$?"
emit iteration run-A                             >/dev/null 2>&1; eq "iteration missing args is a loud caller error" 2 "$?"
emit summary run-A max-N six 6                   >/dev/null 2>&1; eq "a non-integer iteration count is a loud caller error" 2 "$?"
emit summary run-A max-N 6                       >/dev/null 2>&1; eq "summary missing args is a loud caller error" 2 "$?"
emit bogus                                       >/dev/null 2>&1; eq "an unknown subcommand is a loud caller error" 2 "$?"
eq "no caller error wrote a line" "$before" "$(wc -l < "$CHAN" | tr -d '[:space:]')"

# ── write failure is SILENT-TO-THE-RUN (US1.AC6): exit 0, nothing written ────────
# The channel parent "directory" is a regular file, so mkdir -p fails
# deterministically (no chmod, which root ignores). The emitter must exit 0 —
# the caller-side run continues — and must not report a landed record on stdout.
BLOCK="$TMP/blockfile"
: > "$BLOCK"
out="$(BACKLOG_LOOP_REPORT_FILE="$BLOCK/sub/report.jsonl" bash "$EMIT" iteration run-C T201 pass PASS 'PR#7' 2>/dev/null)"
eq "unwritable channel: emitter exits 0 (silent-to-the-run)" 0 "$?"
eq "unwritable channel: no record claimed on stdout" "" "$out"
if [ -e "$BLOCK/sub" ]; then bad "unwritable channel: nothing may be created"; else ok; fi
out="$(BACKLOG_LOOP_REPORT_FILE="$BLOCK/sub/report.jsonl" bash "$EMIT" summary run-C fail-closed 1 6 2>/dev/null)"
eq "unwritable channel: summary write also silent (exit 0)" 0 "$?"
eq "unwritable channel: summary claims no record either" "" "$out"

# ── CI wiring (the silent-death backstop, P2): verify must ACTIVELY run this ─────
if grep -qE '(^|[[:space:]])bash[[:space:]]+[.]claude/hooks/backlog-loop-report[.]test[.]sh([[:space:]]|$)' "$CI"; then
  ok
else
  bad "wiring: ci.yml verify must run backlog-loop-report.test.sh"
fi

printf 'backlog-loop-report.test.sh: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
