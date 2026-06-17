#!/usr/bin/env bash
# Encoding tests for issue #74 (T604 — evasion register). Done-when criteria on
# the issue body are the rubric (Phase 8 maintenance task; the acceptance
# reviewer grades against them exactly as a US#).
#
# Like the other runtime-neutral procedures, the register + its wiring ARE the
# implementation — `.claude/workflow/reviewers/evasion-register.md` (the catalog),
# the three auditor specs' dispatch-time pointers, the retrospective's
# append-an-exhibit step, and the P-EV conformance probe. There is no executable
# code path to unit-test, so this encodes each done-when criterion against the doc
# surface; a later edit that drops one fails the `verify` CI job (constitution P3:
# a rule a deterministic check can enforce must have that check).
#
# Run: bash .claude/hooks/evasion-register-docs.test.sh
set -u

DIR="$(cd "$(dirname "$0")/.." && pwd)"
REG="$DIR/workflow/reviewers/evasion-register.md"
SPEC="$DIR/workflow/reviewers/spec-auditor.md"
CON="$DIR/workflow/reviewers/constitution-auditor.md"
CONTRACT="$DIR/workflow/reviewers/contract-auditor.md"
RET="$DIR/workflow/retrospective.md"
PROBES="$DIR/workflow/conformance-probes.md"
READMEWF="$DIR/workflow/README.md"
PROJECT="$DIR/PROJECT.md"
ADAPTER="$DIR/adapters/claude-code-probes.md"
EXTRACT="$DIR/EXTRACTION.md"

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

for f in "$REG" "$SPEC" "$CON" "$CONTRACT" "$RET" "$PROBES" "$READMEWF" "$PROJECT" "$ADAPTER" "$EXTRACT"; do
  if [ ! -f "$f" ]; then
    echo "FAIL: required file missing: $f" >&2
    exit 1
  fi
done

REG_FLAT="$(flat "$REG")"
SPEC_FLAT="$(flat "$SPEC")"
CON_FLAT="$(flat "$CON")"
CONTRACT_FLAT="$(flat "$CONTRACT")"
RET_FLAT="$(flat "$RET")"
PROBES_FLAT="$(flat "$PROBES")"
README_FLAT="$(flat "$READMEWF")"
PROJECT_FLAT="$(flat "$PROJECT")"
ADAPTER_FLAT="$(flat "$ADAPTER")"
EXTRACT_FLAT="$(flat "$EXTRACT")"

# ── DW1 — the register exists, in observed-evasion → fence form, seeded ───────────
check "DW1: register is in observed-evasion → fence form" "$REG_FLAT" \
  "observed gate evasions"
check "DW1: exhibit format names the fence + file:line + mechanized status" "$REG_FLAT" \
  "the deterministic lint it graduated into, or *judgment-only*"
# Seeded from the test-gaming patterns the issue body names explicitly (skipped /
# assertion-free / wrong-target tests — the spec-auditor hard-FAIL rule).
check "DW1 seed: EV-01 skipped test" "$REG_FLAT" \
  "### EV-01 — Skipped test passed off as encoding"
check "DW1 seed: EV-02 assertion-free test" "$REG_FLAT" \
  "### EV-02 — Assertion-free test"
check "DW1 seed: EV-03 loose assertion" "$REG_FLAT" \
  "### EV-03 — Loose assertion"
check "DW1 seed: EV-06 silently dead guard" "$REG_FLAT" \
  "### EV-06 — Silently dead guard"
check "DW1 seed: points at the spec-auditor hard-FAIL rule as the fence" "$REG_FLAT" \
  'reviewers/spec-auditor.md` → "The hard-FAIL rule"'
# Each exhibit carries a file:line exemplar from a real escape (the issue's format
# requirement) — the probe-fingerprint per-cell fence is the worked one.
check "DW1: real-escape exemplar with file:line" "$REG_FLAT" \
  ".claude/hooks/probe-fingerprint-docs.test.sh:119"
check "DW1: silently-dead-guard exemplar anchored to DESIGN-NOTES" "$REG_FLAT" \
  '.claude/DESIGN-NOTES.md` → "The guard was silently dead"'
# P3 — mechanization tracked (which exhibits graduated into a lint, which are
# judgment-only), mirroring PROJECT.md's invariant → enforcement table.
check "DW1/P3: mechanization-status table mirrors invariant → enforcement" "$REG_FLAT" \
  "## Mechanization status"
check "DW1/P3: EV-06 graduated into guard.test.sh" "$REG_FLAT" \
  "guard.test.sh"
check "DW1/P3: EV-08 graduated into the roster drift test" "$REG_FLAT" \
  "reviewer-roster.test.sh"

# ── DW2 — each auditor spec references the register as a dispatch-time checklist ──
for pair in "spec:$SPEC_FLAT" "constitution:$CON_FLAT" "contract:$CONTRACT_FLAT"; do
  who="${pair%%:*}"; hay="${pair#*:}"
  check "DW2 ($who): points at the register" "$hay" \
    "reviewers/evasion-register.md"
  check "DW2 ($who): consults it as a dispatch-time checklist" "$hay" \
    "Consult the evasion register first."
  check "DW2 ($who): cites the matching EV-NN as the evidence anchor" "$hay" \
    "cite the \`EV-NN\` id as the evidence anchor"
  # "from one source — do not restate it three times": each spec points, the
  # register carries the content.
  check "DW2 ($who): does not restate the register" "$hay" \
    "it is not restated here"
done

# ── DW3 — the retrospective specifies the append-an-exhibit step (PR-proposal output) ─
check "DW3: HUNT-RULE-GAP appends a new exhibit to the register" "$RET_FLAT" \
  "append a new exhibit to the evasion register"
check "DW3: INVARIANT-GAP appends the matching exhibit to the register" "$RET_FLAT" \
  "appends the matching exhibit to the evasion register"
# P4 — the register is rule-shaped; the append travels the propose-via-PR flow,
# never a silent write. It joins the protected reviewer-spec set.
check "DW3/P4: register is in the propose-via-PR protected set" "$RET_FLAT" \
  "the evasion register"
check "DW3/P4: register named in the write-posture protected files" "$RET_FLAT" \
  "Reviewer specs (the evasion register included)"

# ── DW4 — a conformance probe demonstrates the citation, not merely that it ran ──
check "DW4: P-EV probe defined in the neutral checklist" "$PROBES_FLAT" \
  "### P-EV — evasion register"
check "DW4: P-EV requires citing the matching EV-NN as the evidence anchor" "$PROBES_FLAT" \
  "cites the matching register exhibit's \`EV-NN\` id as the evidence anchor"
check "DW4: P-EV tightened bar — not merely that a reviewer ran" "$PROBES_FLAT" \
  "not merely that a reviewer ran"
check "DW4: P-EV in the coverage map" "$PROBES_FLAT" \
  "| evasion register (\`reviewers/evasion-register.md\`) | P-EV |"
# Adapter half — instantiation row + a recorded live PASS (mirrors P-RT/P-IN: the
# neutral probe spec is half; the live-adapter run is the other half). The result
# check is CELL-SCOPED per the PR #89 Codex/owner review: a bare `| P-EV (` row-prefix
# needle is itself an EV-03 loose assertion — flipping the results row to FAIL/DEGRADED
# or dropping the EV-06 citation would still pass CI, so it would NOT enforce the
# done-when (a live probe demonstrated the auditor citing the exhibit). Assert the
# P-EV *results* row's result cell is PASS AND that the row cites EV-06.
check "DW4: P-EV instantiated in the adapter probe table" "$ADAPTER_FLAT" \
  "| P-EV |"
# The results row begins `| P-EV (` (the dated run), distinct from the `| P-EV |`
# instantiation row. awk field 3 is the result cell (the date cell carries no pipe).
pev_row="$(grep -E '^\| P-EV \(' "$ADAPTER" | head -1)"
pev_cell="$(printf '%s\n' "$pev_row" | awk -F'|' '{ gsub(/^[ \t]+|[ \t]+$/, "", $3); print $3 }')"
if [ "$pev_cell" = "PASS" ]; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  printf 'FAIL DW4: P-EV results-row result cell is not PASS (got: %s)\n' "${pev_cell:-<no \`| P-EV (…)\` row>}" >&2
fi
if printf '%s' "$pev_row" | grep -qF 'EV-06'; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  printf 'FAIL DW4: P-EV results row does not cite EV-06 as the evidence anchor\n' >&2
fi

# ── README — the Files index lists the register (a complete, navigable index) ────
check "README: Files list names the register" "$README_FLAT" \
  "reviewers/evasion-register.md\` — the cumulative cheat museum"

# ── P4 — PROJECT.md invariant names the register as protected ────────────────────
check "P4: PROJECT.md invariant names the evasion register as protected" "$PROJECT_FLAT" \
  "the auditor specs **and the evasion register**"

# ── Extraction hygiene (template/instance split) — the register carries this repo's
#    real-escape exemplars (project facts) in an otherwise-portable engine file, so the
#    template/instance split must be handled, not silent: (a) PROJECT.md documents the
#    register as the one engine-file exception, (b) EXTRACTION.md carries its GENERICIZE
#    disposition so an adopter doesn't inherit dangling Creance SHAs/paths, (c) the register
#    self-documents the reset. Guarding these means "a new engine file added with instance
#    facts but no extraction rule" fails CI instead of silently shipping to adopters.
check "extraction: PROJECT.md documents the register as the one engine-file exception" "$PROJECT_FLAT" \
  "One documented exception:"
check "extraction: EXTRACTION.md carries a disposition for the register (GENERICIZE)" "$EXTRACT_FLAT" \
  "\`workflow/reviewers/evasion-register.md\` | GENERICIZE"
check "extraction: EXTRACTION.md carries a disposition for the register's test" "$EXTRACT_FLAT" \
  "\`hooks/evasion-register-docs.test.sh\` | GENERICIZE"
check "extraction: register self-documents the reset-to-seeds on extraction" "$REG_FLAT" \
  "on extraction they reset to seeds"

# ── Runtime-neutral boundary (constitution P1) — the register lives in workflow/** ─
# so it must name capabilities as [roles] and file:line only. Strip the allowed
# `.claude/` profile pointer first (so it never false-matches \bclaude\b), then ban
# the runtime-specific mechanism set — same scan the telemetry/pr-review docs tests
# run over their neutral docs.
mech="$(sed 's#\.claude/#PROFILEPTR/#g' "$REG" \
  | grep -oiE '\bgh\b|\bclaude\b|\bopus\b|\bsonnet\b|\bfable\b|\bhaiku\b|--model|--json|PreToolUse|settings\.json' \
  | sort -u | tr '\n' ' ')"
if [ -z "$mech" ]; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  printf 'FAIL neutral boundary: runtime-specific mechanism leaked into the register\n     found: %s\n' "$mech" >&2
fi

echo "evasion-register docs encoding tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
