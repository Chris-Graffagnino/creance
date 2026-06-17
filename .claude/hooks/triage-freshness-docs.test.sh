#!/usr/bin/env bash
# Encoding tests for issue #87 / US5.AC2 + US5.AC3 (T402 — the triage
# verification-machinery freshness checks: PROBES-STALE and GUARD-SILENT).
# Owns exactly two criteria: US5.AC2 and US5.AC3.
#
# Like the telemetry/intake/pr-review/retrospective/probe-fingerprint procedures, triage is
# runtime-neutral prose executed by the engine — the neutral doc
# (`.claude/workflow/triage.md`) plus its Claude-adapter instantiation
# (`.claude/skills/triage/SKILL.md`) ARE the implementation surface; there is no executable
# code path to unit-test. This test encodes US5.AC2/AC3 against that surface so a later edit
# that drops a check, its semantics, or its explicit states fails the `verify` CI job
# (constitution P3: a rule a deterministic check can enforce must have that check).
#
# SCOPE: this is T402 (triage *consumes* the fingerprint T401 records — flag PROBES-STALE on
# a fingerprint mismatch + report the last probe run's age; flag GUARD-SILENT, heuristically,
# when gate runs occurred in the window but produced zero guard `evaluation` records). The
# fingerprint *recording* convention is T401's, covered by probe-fingerprint-docs.test.sh —
# NOT re-asserted here. The honesty of the live comparison (recomputing the current machinery
# hash and matching it against the recorded baseline) is exercised by the probe run itself
# (conformance-probes.md) and by the spec-auditor at the §7 gate — the same maker/checker
# split the other *-docs tests use; this test deliberately does NOT recompute live hashes.
#
# Run: bash .claude/hooks/triage-freshness-docs.test.sh
set -u

DIR="$(cd "$(dirname "$0")/.." && pwd)"
NEU="$DIR/workflow/triage.md"
ADP="$DIR/skills/triage/SKILL.md"

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

for f in "$NEU" "$ADP"; do
  if [ ! -f "$f" ]; then
    echo "FAIL: required file missing: $f" >&2
    exit 1
  fi
done

NEU_FLAT="$(flat "$NEU")"
ADP_FLAT="$(flat "$ADP")"

# ── Neutral doc: §1.7 reads the baseline + recomputes the current fingerprint ─────────
check "neutral: §1.7 reads the recorded baseline + age source" "$NEU_FLAT" \
  "the comparison baseline and the age source"
# Recomputing the current fingerprint must be read-only (triage's hard constraint).
check "neutral: recomputing the current fingerprint is read-only (reads, never edits)" "$NEU_FLAT" \
  "Recomputing a content hash"
# The concrete recipe + record location are deferred to the adapter (constitution P1).
check "neutral: concrete recipe/record location are the adapter's to supply" "$NEU_FLAT" \
  "are the adapter's to supply"

# ── Neutral doc: PROBES-STALE (US5.AC2) ──────────────────────────────────────────────
check "neutral: PROBES-STALE check is named" "$NEU_FLAT" "PROBES-STALE"
# AC2 core: flag when the current fingerprint differs from the last recorded probe run.
check "neutral: AC2 — flag on current-vs-last-probe fingerprint mismatch" "$NEU_FLAT" \
  "current fingerprint differs from the last probe run"
# AC2 core: report the age of the last probe run.
check "neutral: AC2 — reports the age of the last probe run" "$NEU_FLAT" \
  "age of the last probe run"
# Explicit no-baseline state (triage's never-silently-omitted discipline).
check "neutral: explicit 'no probe run recorded yet' state" "$NEU_FLAT" \
  "no probe run recorded yet"
# PROBES-STALE is a deterministic flag, not a heuristic (unlike GUARD-SILENT).
check "neutral: PROBES-STALE is a definite flag, not a heuristic" "$NEU_FLAT" \
  "definite flag, not a heuristic"
# Ties to the rationale: the silently-dead-machinery failure class (DESIGN-NOTES §4).
check "neutral: ties to the silently-dead-machinery failure class" "$NEU_FLAT" \
  "silently dead machinery"

# ── Neutral doc: GUARD-SILENT (US5.AC3) ──────────────────────────────────────────────
check "neutral: GUARD-SILENT check is named" "$NEU_FLAT" "GUARD-SILENT"
# AC3 core: zero guard evaluation records over a window in which gate runs occurred.
check "neutral: AC3 — gate-runs present but zero guard evaluation records in window" "$NEU_FLAT" \
  "gate-run record(s) but zero guard evaluation records"
# AC3 explicit: reported as a warning, not an error.
check "neutral: AC3 — reported as a warning, not an error" "$NEU_FLAT" \
  "warning, not an error"
# The heuristic guard: a quiet window (no gate runs) is NOT a dead guard — no warning.
check "neutral: AC3 heuristic — no gate runs in window ⇒ no GUARD-SILENT warning" "$NEU_FLAT" \
  "no gate runs occurred in the window"
check "neutral: explicit 'no gate activity in window' state" "$NEU_FLAT" \
  "no gate activity in window"

# ── Neutral doc: both checks observe-only (telemetry law / read-only contract) ───────
check "neutral: both checks observe and report only (no mutation)" "$NEU_FLAT" \
  "observe and report only"
check "neutral: telemetry observes, never decides (no gate/tier/guard influence)" "$NEU_FLAT" \
  "telemetry observes, never decides"

# ── Neutral doc: §4 inbox template carries the section ────────────────────────────────
check "neutral: §4 inbox template has a Verification-machinery freshness section" "$NEU_FLAT" \
  "## Verification-machinery freshness"

# ── Adapter instantiation (triage SKILL.md) ──────────────────────────────────────────
# The PROBES-STALE check needs the concrete recompute recipe + the recorded-runs location;
# the binding references the single-source recipe rather than re-deriving it (DRY — one-place
# edit if what the fingerprint covers ever changes).
check "adapter: references the recorded probe-results table (recorded-runs location)" "$ADP_FLAT" \
  "Probe results"
check "adapter: renders the fingerprint form for the comparison" "$ADP_FLAT" \
  "guard=<sha7> wiring=<sha7>"
check "adapter: reuses the single-source recipe, never re-derives it" "$ADP_FLAT" \
  "never re-derive it here"
check "adapter: instantiates the no-baseline state" "$ADP_FLAT" \
  "no probe run recorded yet"
check "adapter: GUARD-SILENT is addressed in the binding" "$ADP_FLAT" \
  "GUARD-SILENT"

# ── Runtime-neutral boundary (constitution P1) ───────────────────────────────────────
# The triage workflow doc must name no runtime-specific mechanism (the GitHub CLI, model IDs,
# Claude-Code-only tokens). `git` is the harness's universal VCS substrate and is exempt; the
# fingerprint recipe (guard.sh hash + the settings matcher) is the adapter's, not the neutral
# doc's. Strip the `.claude/` profile pointer first so the `\bclaude\b` word match never
# false-fires on it (same shape as probe-fingerprint-docs.test.sh / telemetry-docs.test.sh).
mech="$(sed 's#\.claude/#PROFILEPTR/#g' "$NEU" \
  | grep -oiE '\bgh\b|\bclaude\b|\bopus\b|\bsonnet\b|\bfable\b|\bhaiku\b|--model|--json|PreToolUse|settings\.json' \
  | sort -u | tr '\n' ' ')"
if [ -z "$mech" ]; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  printf 'FAIL neutral boundary: runtime-specific mechanism leaked into %s\n     found: %s\n' "$NEU" "$mech" >&2
fi

echo "triage-freshness docs encoding tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
