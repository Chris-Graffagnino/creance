#!/usr/bin/env bash
# Encoding tests for T803 (#159 — spec 003 maker-eval corpus, US2.AC2): the triage
# read-only "Maker eval" section. Owns exactly one criterion: US2.AC2.
#
# Like the telemetry/intake/pr-review/retrospective/freshness procedures, triage is
# runtime-neutral prose executed by the engine — the neutral doc
# (`.claude/workflow/triage.md`) plus its Claude-adapter instantiation
# (`.claude/skills/triage/SKILL.md`) ARE the implementation surface; there is no executable
# code path to unit-test. This test encodes US2.AC2 against that surface so a later edit that
# drops the section, a flag, the noise threshold, or an explicit state fails the `verify` CI
# job (constitution P3: a rule a deterministic check can enforce must have that check).
#
# SCOPE: T803 is the triage READER — it differences the observe-only maker-eval records the
# T802 emitter writes; it neither runs the eval nor writes records. The record/packet/
# fingerprint SHAPE is T801/T802's, covered by maker-eval-docs.test.sh + maker-eval-emit.test.sh
# — NOT re-asserted here. The deterministic P5 path-fence is T804's. The honesty of the live
# differential (recomputing the maker-behavior fingerprint, joining runs) is exercised by the
# §7 spec-auditor and a future probe — this test deliberately does NOT run a live differential.
#
# Run: bash .claude/hooks/triage-maker-eval-docs.test.sh
set -u

DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib-neutrality-scan.sh
. "$DIR/hooks/lib-neutrality-scan.sh"
NEU="$DIR/workflow/triage.md"
ADP="$DIR/skills/triage/SKILL.md"
CI="$(cd "$DIR/.." && pwd)/.github/workflows/ci.yml"

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

for f in "$NEU" "$ADP" "$CI"; do
  if [ ! -f "$f" ]; then
    echo "FAIL: required file missing: $f" >&2
    exit 1
  fi
done

NEU_FLAT="$(flat "$NEU")"
ADP_FLAT="$(flat "$ADP")"
CI_FLAT="$(flat "$CI")"

# ── §1.8 reads the records read-only + recomputes the current maker-behavior fingerprint ──
check "neutral: §1.8 reads the maker-eval records (read-only source)" "$NEU_FLAT" \
  "The **maker-eval records**"
check "neutral: §1.8 finds the last complete + prior complete run to difference" "$NEU_FLAT" \
  "the **prior complete run**"
check "neutral: §1.8 recomputes the current maker-behavior fingerprint (read-only)" "$NEU_FLAT" \
  "The current maker-behavior fingerprint"
check "neutral: §1.8 defers the channel + recipe to the adapter (P1)" "$NEU_FLAT" \
  "the concrete fingerprint recipe are the adapter's to supply"

# ── §2 derivation: the Maker eval section exists and is the read-only differential ─────────
check "neutral: §2 names the Maker eval derivation" "$NEU_FLAT" \
  "Maker eval (from the maker-eval records)"
check "neutral: §2 — triage neither runs the eval nor writes records (read-only)" "$NEU_FLAT" \
  "Triage neither runs the eval nor writes records"

# ── US2.AC2: regressions under an EXPLICIT NOISE-tolerant threshold (NOT "any delta") ──────
check "AC2: regressions are noise-tolerant, not 'any delta'" "$NEU_FLAT" \
  "not \"any delta\""
check "AC2: differences the frozen ordinal verdict scale, never an absolute score" "$NEU_FLAT" \
  "ordinal scale \`meets\` > \`partial\` > \`fails\`"
# The threshold has two explicit branches; pin BOTH against the actual rule, not nearby prose
# (PR #160 craft review, P3/C13 — assert the invariant, not adjacent text). Branch (a) is
# lifecycle-gated: a `regression`-lifecycle dimension worsening by even one step is signal. The
# needle ties "-lifecycle" to "worsens by", so dropping the lifecycle gate — or the whole branch
# — fails here, instead of passing on branch (b)'s untouched phrase as the old single check did.
check "AC2: branch (a) — a regression-lifecycle dimension worsening one step is signal" "$NEU_FLAT" \
  "-lifecycle dimension worsens by"
check "AC2: branch (a) — those pins are known past failures, so a backslide is signal" "$NEU_FLAT" \
  "these pin known past failures"
# Branch (b): the noise-tolerant aggregate — total worsening across all dimensions ≥ 2 steps.
check "AC2: branch (b) — total worsening across all dimensions clears the threshold" "$NEU_FLAT" \
  "total worsening across all dimensions is"
check "AC2: a lone single-dimension flicker is within noise, not flagged" "$NEU_FLAT" \
  "within noise"

# ── US2.AC2: each flagged regression links its transcript review packet ────────────────────
check "AC2: each regression links its transcript review packet" "$NEU_FLAT" \
  "links its transcript review packet"
check "AC2: the packet is the record's fenced packet path (US1.AC2)" "$NEU_FLAT" \
  "fenced \`packet\` path"

# ── US2.AC2: only COMPLETE runs are differenced; an incomplete run is never a baseline ─────
check "AC2: an incomplete latest run is never a silent baseline" "$NEU_FLAT" \
  "silent baseline"
check "AC2: fewer than two complete runs ⇒ explicit no-data state" "$NEU_FLAT" \
  "fewer than two complete runs"

# ── US2.AC2 (bootstrap edge): ONE complete run still renders the SINGLE-run flags ───────────
# Regression guard (PR #160 review): the no-data fallback must NOT blank MAKER-EVAL-STALE /
# JUDGE-MISCALIBRATED. Both difference the current state against the LAST complete run alone
# (spec.md US2.AC2 — "the last run's" fingerprint / agreement), so they fire from a single run;
# only Regressions + Comparability need a prior run. Collapsing all four to "no data yet" in the
# common one-run bootstrap would hide the very stale/miscalibrated signal US2.AC2 asks triage to
# surface. These checks pin the split so a future edit cannot silently re-suppress it.
check "AC2: §2 opener scopes the two-run differential, not every signal" "$NEU_FLAT" \
  "regression differential compares the"
check "AC2: §2 names the single-run flags as deriving from the last complete run alone" "$NEU_FLAT" \
  "derive from the last complete run alone"
check "AC2: §2 — one complete run still renders the single-run flags" "$NEU_FLAT" \
  "still render from one complete run"
check "AC2: §2 — the pair-dependent lines show 'not enough to difference', not a blanket no-data" "$NEU_FLAT" \
  "not enough to difference"
check "AC2: §4 — one complete run still renders MAKER-EVAL-STALE / JUDGE-MISCALIBRATED" "$NEU_FLAT" \
  "still render against that run"
check "AC2: §4 — the channel-absent collapse fires only with no complete run at all" "$NEU_FLAT" \
  "only when there is no complete run at all"

# ── US2.AC2: MAKER-EVAL-STALE on a maker-behavior fingerprint change (a warning) ───────────
check "AC2: MAKER-EVAL-STALE flag is named" "$NEU_FLAT" "MAKER-EVAL-STALE"
check "AC2: MAKER-EVAL-STALE fires on current-vs-last maker-behavior fingerprint drift" "$NEU_FLAT" \
  "current** maker-behavior fingerprint"
check "AC2: MAKER-EVAL-STALE is a definite flag, not a heuristic" "$NEU_FLAT" \
  "definite flag, not a heuristic"

# ── US2.AC2: JUDGE-CHANGED / INSTRUMENT-CHANGED suppress a confounded comparison ───────────
check "AC2: JUDGE-CHANGED / not-comparable annotation" "$NEU_FLAT" \
  "JUDGE-CHANGED / not-comparable"
check "AC2: INSTRUMENT-CHANGED / not-comparable annotation" "$NEU_FLAT" \
  "INSTRUMENT-CHANGED / not-comparable"
check "AC2: a moved judge/instrument suppresses the regression call" "$NEU_FLAT" \
  "suppresses the regression call"

# ── US2.AC2: JUDGE-MISCALIBRATED when recorded judge↔owner agreement is below floor ────────
check "AC2: JUDGE-MISCALIBRATED flag is named" "$NEU_FLAT" "JUDGE-MISCALIBRATED"
check "AC2: JUDGE-MISCALIBRATED fires below the stated agreement floor (US1.AC5)" "$NEU_FLAT" \
  "below its stated floor"
check "AC2: explicit empty state when no agreement is recorded yet" "$NEU_FLAT" \
  "no agreement recorded yet"

# ── US2.AC2: explicit empty states, rendered consistently, never silently omitted ─────────
check "AC2: explicit 'no data yet' empty state" "$NEU_FLAT" "no data yet"
check "AC2: states render consistently and are never silently omitted" "$NEU_FLAT" \
  "never silently omitted"
check "neutral: §4 inbox template carries the Maker eval section" "$NEU_FLAT" \
  "## Maker eval (last complete run:"

# ── US2.AC2: observe-only (P5) — the section feeds no gate/tier/guard/selection path ───────
check "AC2: the derivation is read-only over the records" "$NEU_FLAT" \
  "read-only over the records"
check "AC2: feeds no gate/tier/guard/selection path (observe-only, P5)" "$NEU_FLAT" \
  "gate, tier, guard, or selection path"

# ── Adapter instantiation (triage SKILL.md) — the deferred concrete facts ──────────────────
check "adapter: a Maker-eval surfacing instantiation exists" "$ADP_FLAT" \
  "Maker-eval surfacing"
check "adapter: reads the records.jsonl stream (the channel the emitter resolves)" "$ADP_FLAT" \
  "records.jsonl"
check "adapter: the read-only completeness oracle for the two-run join" "$ADP_FLAT" \
  "maker-eval-emit.sh complete --run-id"
check "adapter: the single-source maker-behavior fingerprint recompute recipe" "$ADP_FLAT" \
  "maker-eval-emit.sh fingerprint"
check "adapter: reuses the single-source recipe, never re-derives it" "$ADP_FLAT" \
  "never re-derive it here"
check "adapter: JUDGE-MISCALIBRATED reads the recorded agreement/floor (US1.AC5/T806)" "$ADP_FLAT" \
  "no agreement recorded yet"

# ── Runtime-neutral boundary (constitution P1) — triage.md names no runtime mechanism ─────
# The shared scanner's token contract (incl. line-wrapped prose mechanism names) is pinned by
# lib-neutrality-scan.test.sh; here it guards the T803 additions to the neutral doc.
mech="$(neutral_mechanism_leaks "$NEU")"
if [ -z "$mech" ]; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  printf 'FAIL neutral boundary: runtime-specific mechanism leaked into %s\n     found: %s\n' "$NEU" "$mech" >&2
fi

# ── CI wiring — this test is actually run by the required `verify` check (P2: proven live) ─
check "CI: verify runs this encoding test" "$CI_FLAT" \
  "triage-maker-eval-docs.test.sh"

echo "triage maker-eval docs encoding tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
