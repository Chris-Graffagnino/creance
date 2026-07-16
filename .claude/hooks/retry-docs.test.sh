#!/usr/bin/env bash
# Encoding tests for issue #210 / spec 001 US10 (T635 — retry consumes prior gate
# verdicts: experience retention across a gate non-convergence stop).
#
# Like the telemetry, intake, and PR-review procedures, the retry channel is
# runtime-neutral prose executed by the engine — workflow/retry.md IS the
# implementation surface. These tests encode US10.AC1–AC5 against that surface so
# a later edit that drops the non-convergence-only trigger, the verbatim
# per-auditor/round posting, the maker-input-only consumption, the
# tracker-not-telemetry boundary, the DESIGN-NOTES tension entry, or either side
# of the two-sided P-RC conformance probe fails the `verify` CI job
# (constitution P3: a rule a deterministic check can enforce must have that
# check). The live counterpart is the P-RC probe itself
# (workflow/conformance-probes.md), which checks the channel on a real driver.
#
# Run: bash .claude/hooks/retry-docs.test.sh
set -u

DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib-neutrality-scan.sh
. "$DIR/hooks/lib-neutrality-scan.sh"
RETRY="$DIR/workflow/retry.md"
NT="$DIR/workflow/next-task.md"
GATECARD="$DIR/workflow/next-task/07-pre-pr-gate.md"
CTXCARD="$DIR/workflow/next-task/03-read-context.md"
DN="$DIR/DESIGN-NOTES.md"
PROBES="$DIR/workflow/conformance-probes.md"
ADAPTER="$DIR/adapters/claude-code-probes.md"

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

for f in "$RETRY" "$NT" "$GATECARD" "$CTXCARD" "$DN" "$PROBES" "$ADAPTER"; do
  if [ ! -f "$f" ]; then
    echo "FAIL: required file missing: $f" >&2
    exit 1
  fi
done

RETRY_FLAT="$(flat "$RETRY")"
NT_FLAT="$(flat "$NT")"
GATECARD_FLAT="$(flat "$GATECARD")"
CTXCARD_FLAT="$(flat "$CTXCARD")"
DN_FLAT="$(flat "$DN")"
PROBES_FLAT="$(flat "$PROBES")"
ADAPTER_FLAT="$(flat "$ADAPTER")"

# ── AC1: the sub-doc + the pointer + the posting half ────────────────────────────────
check "AC1: next-task.md carries a pointer to the retry sub-doc" "$NT_FLAT" \
  "retry.md"
check "AC1: gate card hooks the posting half at the non-convergence stop" "$GATECARD_FLAT" \
  "workflow/retry.md"
check "AC1: posting fires on non-convergence only" "$RETRY_FLAT" \
  "fires on a gate \`non-convergence\` return ONLY"
check "AC1: reports posted verbatim, keyed by auditor and round" "$RETRY_FLAT" \
  "verbatim, keyed by auditor and round"
check "AC1: posted through the [add-issue-comment output] intent" "$RETRY_FLAT" \
  "[add-issue-comment output]"
check "AC1: the comment carries the [comment marker]" "$RETRY_FLAT" \
  "[comment marker]"
check "AC1: an empty or summarized posting does not satisfy" "$RETRY_FLAT" \
  "empty or summarized posting does not satisfy"
check "AC1: the retry comment is deterministically recognizable" "$RETRY_FLAT" \
  "Retry verdicts"

# ── AC2: the consuming half — maker input only, nothing relaxed ──────────────────────
check "AC2: context card hooks the consuming half into the thread read" "$CTXCARD_FLAT" \
  "workflow/retry.md"
check "AC2: retry reads the newest marked retry comment" "$RETRY_FLAT" \
  "newest"
check "AC2: consumed as maker input before re-implementation" "$RETRY_FLAT" \
  "maker input"
check "AC2: no comment means an ordinary cold start, never an error" "$RETRY_FLAT" \
  "never an error"
check "AC2: each recorded finding addressed or declined with a reason" "$RETRY_FLAT" \
  "Address each recorded finding, or state why not"
check "AC2: marked, so it carries no steering authority" "$RETRY_FLAT" \
  "No steering authority"
check "AC2: every reviewer re-runs from scratch on the retry's own diff" "$RETRY_FLAT" \
  "every rostered [reviewer] re-runs from scratch"
check "AC2: no prior verdict — PASS included — carries forward" "$RETRY_FLAT" \
  "PASS included"
check "AC2: skipping a passed reviewer violates the procedure" "$RETRY_FLAT" \
  "skips a [reviewer] because it passed last time violates"

# ── AC3: the source boundary — tracker, never telemetry (P5) ─────────────────────────
check "AC3: the retry input's source is the tracker channel" "$RETRY_FLAT" \
  "the tracker channel"
check "AC3: never the telemetry stream" "$RETRY_FLAT" \
  "never the telemetry stream"
check "AC3: no retry, selection, or gate path reads telemetry for verdicts" "$RETRY_FLAT" \
  "no retry, selection, or gate path reads telemetry"
check "AC3: the posting half reads the gate's return value, not the stream" "$RETRY_FLAT" \
  "return value"

# ── AC4: the DESIGN-NOTES tension entry ──────────────────────────────────────────────
check "AC4: DESIGN-NOTES names the identical-starts vs experience-retention tension" "$DN_FLAT" \
  "Identical starts vs experience retention"
check "AC4: DESIGN-NOTES cites the EdgeBench experience ablation" "$DN_FLAT" \
  "EdgeBench"
check "AC4: resolution — starts stay identical for the harness machinery" "$DN_FLAT" \
  "starts stay identical"
check "AC4: resolution — feedback history persists on the tracker" "$DN_FLAT" \
  "persists on the tracker"

# ── AC5: the two-sided P-RC conformance probe ────────────────────────────────────────
check "AC5: neutral probe P-RC exists" "$PROBES_FLAT" \
  "P-RC"
check "AC5: probe positive side — non-convergence produces the marked retry comment" "$PROBES_FLAT" \
  "produces the marked retry comment"
check "AC5: probe negative side — a gate PASS produces no retry comment" "$PROBES_FLAT" \
  "no retry comment"
check "AC5: posting-only probes do not satisfy (two-sided by definition)" "$PROBES_FLAT" \
  "exercising only the posting path does not satisfy"
check "AC5: the coverage map routes the retry channel to P-RC" "$PROBES_FLAT" \
  "retry channel"
check "AC5: the adapter instantiates P-RC" "$ADAPTER_FLAT" \
  "P-RC"

# ── Runtime-neutral boundary (constitution P1) — the new sub-doc must carry no
#    runtime-specific mechanism; concrete forms live adapter-side only. The global
#    neutrality-scan-coverage test also sweeps every tracked workflow doc; this local
#    scan keeps the failure adjacent to the surface it grades (the *-docs pattern). ──
mech="$(neutral_mechanism_leaks "$RETRY")"
if [ -z "$mech" ]; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  printf 'FAIL neutral boundary: runtime-specific mechanism leaked into %s\n     found: %s\n' "$RETRY" "$mech" >&2
fi

echo "retry docs encoding tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
