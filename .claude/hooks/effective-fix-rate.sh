#!/usr/bin/env bash
# effective-fix-rate.sh — the effective-fix-rate derivation over the telemetry
# stream (T634, #209, spec 001 US9). The runtime-neutral docs define the metric
# (`.claude/workflow/telemetry.md` § Consumers) and its triage rendering + explicit
# empty states (`.claude/workflow/triage.md` "Gate trends"); they defer the concrete
# recipe to the adapter (constitution P1). This is that recipe — adapter-side, so it
# may name concrete tools (jq) — it is NOT a `workflow/**` neutral doc.
#
# The metric (US9.AC1). A **flip** is a reviewer whose verdict is FAIL in gate round
# n and PASS or JUSTIFY in round n+1 of the SAME `gate-run` record. Because the gate
# loop re-dispatches only the reviewers that FAILed the prior round (gate-loop.js —
# round n+1 holds only the still-`pending` failures), a reviewer that is FAIL in
# round n and PRESENT in round n+1 is exactly a **FAIL-triggered re-dispatch**. The
# effective-fix rate is:
#     numerator   = flips                        (a FAIL that cleared on re-dispatch)
#     denominator = FAIL-triggered re-dispatches (every FAIL that was re-dispatched)
# aggregated over the window and broken out per auditor. A NON-convergence FAIL that
# never cleared still contributes its re-dispatches to the denominator (it was
# re-dispatched) but nothing to the numerator (it never flipped); a pass-first-try
# run contributes to neither. This introduces NO new record type, NO schema change,
# and NO writer — it reads the `gate-run` records the gate loop already emits.
#
# OBSERVE-ONLY (constitution P5 / US9.AC4). This script only READS the stream and
# prints to stdout. It WRITES NOTHING — not to the stream, not anywhere — and returns
# no value any gate, tier-resolution, guard, or selection path consumes. A missing or
# empty stream is the "no data yet" state, never an error (telemetry.md law: a missing
# file is never an error). Malformed lines are skipped and counted, never repaired.
#
# Usage:
#   effective-fix-rate.sh <stream-path> [--since <ISO-8601-UTC>] [--until <ISO-8601-UTC>]
#
# The optional window bounds filter `gate-run` records by their `timestamp` field.
# ISO-8601 UTC timestamps sort lexicographically, so the comparison is a plain string
# compare — no date arithmetic, portable across BSD/GNU. Both bounds are inclusive;
# omit either for an open end.
#
# Output: ONE compact JSON object on stdout, exit 0 on any readable invocation:
#   {"state":"rate","numerator":N,"denominator":D,"pct":P,
#    "by_auditor":{"<auditor>":{"numerator":n,"denominator":d}, ...},
#    "skipped_malformed":M,"window":{"since":"...","until":"..."}}
# state is one of:
#   "no-data"       — no `gate-run` records in the window (absent/empty file counts)
#   "no-fix-rounds" — `gate-run` records exist but zero FAIL-triggered re-dispatches
#                     (denominator 0) — DISTINCT from a genuine 0-of-N rate, which is
#                     "rate" with numerator 0 and denominator > 0
#   "rate"          — denominator > 0 (numerator may be 0: a real 0-of-N)
# Exit 2 on a usage error (no stream path, unknown option, jq absent).
#
# Run the tests: bash .claude/hooks/effective-fix-rate.test.sh
set -u

usage() {
  echo "usage: effective-fix-rate.sh <stream-path> [--since <ISO>] [--until <ISO>]" >&2
}

stream=""
since=""
until_=""
while [ $# -gt 0 ]; do
  case "$1" in
    --since) since="${2:-}"; shift 2 ;;
    --until) until_="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    --) shift; break ;;
    -*) echo "effective-fix-rate: unknown option: $1" >&2; usage; exit 2 ;;
    *)
      if [ -z "$stream" ]; then
        stream="$1"
      else
        echo "effective-fix-rate: unexpected argument: $1" >&2; usage; exit 2
      fi
      shift
      ;;
  esac
done

if [ -z "$stream" ]; then
  usage
  exit 2
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "effective-fix-rate: jq is required" >&2
  exit 2
fi

# Absent or empty stream is the explicit "no data yet" state, never an error.
if [ ! -s "$stream" ]; then
  printf '{"state":"no-data","numerator":0,"denominator":0,"pct":null,"by_auditor":{},"skipped_malformed":0,"window":{"since":"%s","until":"%s"}}\n' \
    "$since" "$until_"
  exit 0
fi

# Stage 1: classify each non-blank line as a parsed record or a malformed marker so
# malformed lines are counted, not silently dropped. Stage 2: slurp and aggregate.
grep -v '^[[:space:]]*$' "$stream" \
  | jq -R 'try (fromjson) catch {"__bad__":true}' \
  | jq -s -c --arg lo "$since" --arg hi "$until_" '
      def isbad: (type == "object") and has("__bad__");
      (map(select(isbad)) | length) as $bad
      | (map(select(isbad | not))) as $recs
      | ( $recs
          | map(select((type == "object") and (.record == "gate-run")))
          | map(select(($lo == "" or ((.timestamp? // "") >= $lo))
                       and ($hi == "" or ((.timestamp? // "") <= $hi)))) ) as $runs
      | ( $runs
          | map(
              (.rounds // []) as $r
              | [ range(0; ($r | length) - 1) as $i
                  | ( ($r[$i]     // []) | if type == "array" then . else [] end ) as $cur
                  | ( ($r[$i + 1] // []) | if type == "array" then . else [] end ) as $nxt
                  | $cur[]
                  | select((type == "object") and (.verdict == "FAIL") and (.auditor != null))
                  | .auditor as $a
                  | ($nxt | map(select((type == "object") and (.auditor == $a))) | .[0]) as $n
                  | select($n != null)
                  | { auditor: $a, flip: (($n.verdict == "PASS") or ($n.verdict == "JUSTIFY")) }
                ]
            )
          | add // [] ) as $ev
      | ($ev | length) as $den
      | ($ev | map(select(.flip)) | length) as $num
      | ( $ev
          | group_by(.auditor)
          | map({ key: .[0].auditor,
                  value: { numerator: (map(select(.flip)) | length), denominator: length } })
          | from_entries ) as $by
      | (if ($runs | length) == 0 then "no-data"
         elif $den == 0 then "no-fix-rounds"
         else "rate" end) as $state
      | { state: $state,
          numerator: $num,
          denominator: $den,
          pct: (if $den > 0 then ((100 * $num / $den) | round) else null end),
          by_auditor: $by,
          skipped_malformed: $bad,
          window: { since: $lo, until: $hi } }
    '
