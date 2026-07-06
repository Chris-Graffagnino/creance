#!/usr/bin/env bash
# Tests for the effective-fix-rate derivation (T634, #209, spec 001 US9). Two layers:
#
#  1. BEHAVIORAL (US9.AC3) — drive the concrete recipe `effective-fix-rate.sh` over a
#     PLANTED telemetry stream and assert its computed numbers EXACTLY, per instance:
#     a FAIL→PASS flip and a FAIL→JUSTIFY flip each count ONCE in the numerator; those
#     two plus a non-convergence run whose FAIL never cleared each contribute their
#     re-dispatches to the denominator; a pass-first-try run contributes NOTHING; and
#     both explicit empty states render — with a genuine 0-of-N kept DISTINCT from the
#     "no fix rounds" state. Exact-field equality on the JSON output (never a prefix or
#     single-match-anywhere check), so a derivation that miscounts goes red.
#
#  2. DOCS-ENCODING (US9.AC1/AC2/AC4) — the neutral docs
#     (`workflow/telemetry.md` § Consumers, `workflow/triage.md` "Gate trends" + the §4
#     template) and the adapter recipe reference (`skills/triage/SKILL.md`) are the
#     definition surface (constitution P3: a rule a deterministic check can enforce must
#     have that check). Pin the metric definition, the numerator/denominator-shown render,
#     the two empty states, the observe-only framing, plus the runtime-neutral boundary
#     over the two neutral docs and this test's own CI wiring (P2: proven live).
#
# Bash + jq only, <2s. Run: bash .claude/hooks/effective-fix-rate.test.sh
set -u

DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib-neutrality-scan.sh
. "$DIR/hooks/lib-neutrality-scan.sh"
RECIPE="$DIR/hooks/effective-fix-rate.sh"
TEL="$DIR/workflow/telemetry.md"
TRI="$DIR/workflow/triage.md"
SK="$DIR/skills/triage/SKILL.md"
CI="$(cd "$DIR/.." && pwd)/.github/workflows/ci.yml"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0
ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); printf 'FAIL %s\n' "$1" >&2; [ -n "${2:-}" ] && printf '     %s\n' "$2" >&2; return 0; }
eq()  { if [ "$2" = "$3" ]; then ok; else bad "$1" "want=[$2] got=[$3]"; fi; }

check() { # check <name> <haystack> <needle (grep -F fixed string)>
  local name="$1" hay="$2" needle="$3"
  if printf '%s' "$hay" | grep -qF -- "$needle"; then ok; else
    fail=$((fail + 1)); printf 'FAIL %s\n     missing: %s\n' "$name" "$needle" >&2
  fi
}

for f in "$RECIPE" "$TEL" "$TRI" "$SK" "$CI"; do
  [ -f "$f" ] || { echo "FAIL: required file missing: $f" >&2; exit 1; }
done
command -v jq >/dev/null 2>&1 || { echo "FAIL: jq required by this test" >&2; exit 1; }

run() { bash "$RECIPE" "$@"; }
# jf <captured-json> <jq-filter> — pull an exact field from the recipe's JSON output.
jf() { printf '%s' "$1" | jq -r "$2"; }

# ── The canonical planted stream (US9.AC3's four required run types + a non-gate-run) ──────
#   T900 FAIL→PASS  (constitution-auditor)  : 1 re-dispatch, 1 flip
#   T901 FAIL→JUSTIFY (constitution-auditor): 1 re-dispatch, 1 flip
#   T902 non-convergence, FAIL never clears (spec-auditor, 3 rounds): 2 re-dispatches, 0 flip
#   T903 pass-first-try (both auditors PASS, 1 round): contributes nothing
#   a `block` record: a non-gate-run line that must be IGNORED
# Expected aggregate: numerator 2, denominator 4 (1+1+2), pct 50.
# Per auditor: constitution-auditor 2/2, spec-auditor 0/2.
CANON="$TMP/canonical.jsonl"
cat > "$CANON" <<'EOF'
{"record":"gate-run","timestamp":"2026-07-05T10:00:00Z","repo":"creance","task_id":"T900","rounds":[[{"auditor":"spec-auditor","tier":"cheap","verdict":"PASS"},{"auditor":"constitution-auditor","tier":"strong","verdict":"FAIL"}],[{"auditor":"constitution-auditor","tier":"strong","verdict":"PASS"}]],"fix_rounds_used":1,"outcome":"pass"}
{"record":"gate-run","timestamp":"2026-07-05T11:00:00Z","repo":"creance","task_id":"T901","rounds":[[{"auditor":"constitution-auditor","tier":"strong","verdict":"FAIL"}],[{"auditor":"constitution-auditor","tier":"strong","verdict":"JUSTIFY"}]],"fix_rounds_used":1,"outcome":"pass"}
{"record":"gate-run","timestamp":"2026-07-05T12:00:00Z","repo":"creance","task_id":"T902","rounds":[[{"auditor":"spec-auditor","tier":"cheap","verdict":"FAIL"}],[{"auditor":"spec-auditor","tier":"cheap","verdict":"FAIL"}],[{"auditor":"spec-auditor","tier":"cheap","verdict":"FAIL"}]],"fix_rounds_used":2,"outcome":"non-convergence"}
{"record":"gate-run","timestamp":"2026-07-05T13:00:00Z","repo":"creance","task_id":"T903","rounds":[[{"auditor":"spec-auditor","tier":"cheap","verdict":"PASS"},{"auditor":"constitution-auditor","tier":"strong","verdict":"PASS"}]],"fix_rounds_used":0,"outcome":"pass"}
{"record":"block","timestamp":"2026-07-05T14:00:00Z","repo":"creance","rule":"bulk-staging","tool":"Bash"}
EOF

C="$(run "$CANON")"
eq "canonical: state is a computed rate"                 "rate" "$(jf "$C" '.state')"
eq "canonical: numerator = 2 flips (FAIL→PASS + FAIL→JUSTIFY, each once)" "2" "$(jf "$C" '.numerator')"
eq "canonical: denominator = 4 re-dispatches (1+1+2)"    "4"    "$(jf "$C" '.denominator')"
eq "canonical: pct = 50"                                 "50"   "$(jf "$C" '.pct')"
eq "canonical: no malformed lines"                       "0"    "$(jf "$C" '.skipped_malformed')"
# Per-auditor breakout (US9.AC1 "broken out per auditor").
eq "canonical: constitution-auditor numerator = 2 (both flips)"   "2" "$(jf "$C" '.by_auditor["constitution-auditor"].numerator')"
eq "canonical: constitution-auditor denominator = 2"              "2" "$(jf "$C" '.by_auditor["constitution-auditor"].denominator')"
eq "canonical: spec-auditor numerator = 0 (never flipped)"        "0" "$(jf "$C" '.by_auditor["spec-auditor"].numerator')"
eq "canonical: spec-auditor denominator = 2 (non-convergence re-dispatches)" "2" "$(jf "$C" '.by_auditor["spec-auditor"].denominator')"
# The non-gate-run `block` line never inflates a count (only 2 auditors are keyed).
eq "canonical: only the two gate auditors are keyed (block ignored)" "2" "$(jf "$C" '.by_auditor | length')"

# ── AC3 "pass-first-try contributes nothing" — dropping T903 leaves EVERY number identical ─
NO903="$TMP/no903.jsonl"
grep -v '"task_id":"T903"' "$CANON" > "$NO903"
N="$(run "$NO903")"
eq "pass-first-try adds nothing: numerator unchanged"   "$(jf "$C" '.numerator')"   "$(jf "$N" '.numerator')"
eq "pass-first-try adds nothing: denominator unchanged" "$(jf "$C" '.denominator')" "$(jf "$N" '.denominator')"
eq "pass-first-try adds nothing: constitution denom unchanged (2, not 3)" \
   "$(jf "$C" '.by_auditor["constitution-auditor"].denominator')" \
   "$(jf "$N" '.by_auditor["constitution-auditor"].denominator')"

# ── AC2/AC3 empty state 1: "no data yet" — absent, empty, and no-gate-run-records streams ──
eq "no-data: absent file"                "no-data" "$(jf "$(run "$TMP/nope.jsonl")" '.state')"
: > "$TMP/empty.jsonl"
eq "no-data: empty file"                 "no-data" "$(jf "$(run "$TMP/empty.jsonl")" '.state')"
printf '{"record":"block","timestamp":"2026-07-05T14:00:00Z","rule":"x","tool":"Bash"}\n' > "$TMP/blockonly.jsonl"
eq "no-data: stream with no gate-run records" "no-data" "$(jf "$(run "$TMP/blockonly.jsonl")" '.state')"

# ── AC2/AC3 empty state 2: "no fix rounds in window" — gate-runs but denominator 0 ─────────
printf '{"record":"gate-run","timestamp":"2026-07-05T10:00:00Z","task_id":"T1","rounds":[[{"auditor":"spec-auditor","tier":"cheap","verdict":"PASS"}]],"fix_rounds_used":0,"outcome":"pass"}\n' > "$TMP/nofix.jsonl"
NF="$(run "$TMP/nofix.jsonl")"
eq "no-fix-rounds: state"       "no-fix-rounds" "$(jf "$NF" '.state')"
eq "no-fix-rounds: denominator" "0"             "$(jf "$NF" '.denominator')"

# ── AC2 the DISTINCTION: a genuine 0-of-N is a rate (denominator > 0), NOT "no fix rounds" ──
printf '{"record":"gate-run","timestamp":"2026-07-05T12:00:00Z","task_id":"T902","rounds":[[{"auditor":"spec-auditor","tier":"cheap","verdict":"FAIL"}],[{"auditor":"spec-auditor","tier":"cheap","verdict":"FAIL"}]],"fix_rounds_used":1,"outcome":"non-convergence"}\n' > "$TMP/zeroofn.jsonl"
Z="$(run "$TMP/zeroofn.jsonl")"
eq "0-of-N: state is a rate, not an empty state" "rate" "$(jf "$Z" '.state')"
eq "0-of-N: numerator 0"                         "0"    "$(jf "$Z" '.numerator')"
eq "0-of-N: denominator > 0 (reviewers were re-dispatched)" "1" "$(jf "$Z" '.denominator')"

# ── Malformed lines are skipped and COUNTED, the rate still computed over the valid lines ──
{ cat "$CANON"; printf 'not json at all\n'; printf '{"record":"gate-run", truncated\n'; } > "$TMP/malformed.jsonl"
M="$(run "$TMP/malformed.jsonl")"
eq "malformed: two bad lines counted" "2" "$(jf "$M" '.skipped_malformed')"
eq "malformed: valid rate still computed" "2" "$(jf "$M" '.numerator')"

# ── The snapshot WINDOW filters by timestamp (triage derives over a window) ────────────────
# --since excludes T900 (10:00) and T901 (11:00), keeps T902 (12:00) and T903 (13:00) → 0/2.
W="$(run "$CANON" --since 2026-07-05T11:30:00Z)"
eq "window --since: numerator 0 (both flips excluded)"    "0" "$(jf "$W" '.numerator')"
eq "window --since: denominator 2 (only T902 remains)"    "2" "$(jf "$W" '.denominator')"
# --until symmetrically keeps only T900 (10:00) → 1/1.
W2="$(run "$CANON" --until 2026-07-05T10:30:00Z)"
eq "window --until: numerator 1 (only T900's flip)"       "1" "$(jf "$W2" '.numerator')"
eq "window --until: denominator 1"                        "1" "$(jf "$W2" '.denominator')"

# ── OBSERVE-ONLY (US9.AC4): the recipe WRITES NOTHING to the stream ────────────────────────
before="$(shasum "$CANON" | cut -d' ' -f1)"
run "$CANON" >/dev/null
run "$CANON" --since 2026-07-05T11:00:00Z >/dev/null
after="$(shasum "$CANON" | cut -d' ' -f1)"
eq "observe-only: the stream is byte-identical after derivation (writes nothing)" "$before" "$after"
# A usage error (no stream path) exits non-zero and writes nothing to stdout.
run >/dev/null 2>&1; eq "usage: no stream path exits 2" "2" "$?"

# ── DOCS-ENCODING: telemetry.md § Consumers defines the metric (US9.AC1) ───────────────────
flat() { tr -s '[:space:]' ' ' < "$1"; }
TEL_FLAT="$(flat "$TEL")"; TRI_FLAT="$(flat "$TRI")"; SK_FLAT="$(flat "$SK")"
check "AC1: telemetry.md defines the effective-fix rate" "$TEL_FLAT" "**effective-fix rate**"
check "AC1: a flip is FAIL round n → PASS/JUSTIFY round n+1" "$TEL_FLAT" \
  "FAIL in round *n* and PASS or JUSTIFY in round *n+1*"
check "AC1: rate = flips over FAIL-triggered re-dispatches" "$TEL_FLAT" \
  "flips over FAIL-triggered re-dispatches"
check "AC1: aggregated per window and broken out per auditor" "$TEL_FLAT" \
  "aggregated per snapshot window and broken out per auditor"
check "AC1: no new record type / schema / writer" "$TEL_FLAT" \
  "no new record type, no schema change, and no writer change"
check "AC1: non-convergence FAIL counts in denominator, not numerator" "$TEL_FLAT" \
  "still contributes its re-dispatches to the denominator but nothing to the numerator"
check "AC4: observe-only — no gate/tier/guard/selection path reads it" "$TEL_FLAT" \
  "tier resolution, guard, or selection path reads it"
check "AC1/P3: the concrete recipe is the adapter's (never model estimation)" "$TEL_FLAT" \
  "adapter's to supply (never model estimation)"

# ── DOCS-ENCODING: triage.md renders it with numerator+denominator + both empty states (AC2) ─
check "AC2: triage.md renders the Effective-fix rate in Gate trends" "$TRI_FLAT" \
  "Effective-fix rate (submission efficiency)"
check "AC2: numerator and denominator shown, never a bare percentage" "$TRI_FLAT" \
  "with its numerator and denominator shown — never a bare percentage"
check "AC2: deterministic recipe a non-scorer can re-run (P3)" "$TRI_FLAT" \
  "deterministic recipe a non-scorer can re-run"
check "AC2: 'no fix rounds in window' empty state" "$TRI_FLAT" \
  "**\"no fix rounds in window\"**"
check "AC2: distinguished from a genuine 0-of-N rate" "$TRI_FLAT" \
  "distinguished from a genuine 0-of-N rate"
check "AC2: the existing 'no data yet' state also applies" "$TRI_FLAT" \
  "the existing **\"no data yet\"** state"
check "AC2: §4 template carries the Effective-fix rate line" "$TRI_FLAT" \
  "Effective-fix rate: <flips>/<re-dispatches>"
check "AC2: §4 template carries the no-fix-rounds empty state" "$TRI_FLAT" \
  "no fix rounds in window"
check "AC2: §4 no-data note now covers the four gate-trends lines" "$TRI_FLAT" \
  "replaces the four lines above"

# ── DOCS-ENCODING: the adapter names the concrete deterministic recipe ─────────────────────
check "adapter: names the effective-fix-rate.sh recipe" "$SK_FLAT" \
  "effective-fix-rate.sh <telemetry-stream>"
check "adapter: renders numerator/denominator, never a bare percentage" "$SK_FLAT" \
  "never a bare percentage"
check "adapter: maps .state to the two empty states" "$SK_FLAT" "\"no-fix-rounds\""
check "adapter: observe-only — writes nothing, feeds no gate/tier/guard/selection" "$SK_FLAT" \
  "feeds no gate, tier, guard, or selection path, and writes nothing"

# ── Runtime-neutral boundary (constitution P1): the two NEUTRAL docs name no mechanism ─────
for doc in "$TEL" "$TRI"; do
  mech="$(neutral_mechanism_leaks "$doc")"
  if [ -z "$mech" ]; then ok; else
    fail=$((fail + 1))
    printf 'FAIL neutral boundary: runtime mechanism leaked into %s\n     found: %s\n' "$doc" "$mech" >&2
  fi
done

# ── CI wiring (constitution P2: the check is proven live in `verify`) ──────────────────────
check "CI: verify runs this test" "$(flat "$CI")" "effective-fix-rate.test.sh"

echo "effective-fix-rate tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
