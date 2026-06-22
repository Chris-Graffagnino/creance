#!/usr/bin/env bash
# Encoding tests for issue #85 / US5.AC1 (T401 — the probe-run guard-machinery
# fingerprint). Owns exactly one criterion: US5.AC1.
#
# Like the telemetry/intake/pr-review/retrospective procedures, the conformance-probe
# recording convention is runtime-neutral prose executed by the engine — the neutral
# doc (`.claude/workflow/conformance-probes.md` → "Recording") plus its Claude-adapter
# instantiation (`.claude/adapters/claude-code-probes.md`) ARE the implementation
# surface; there is no executable code path to unit-test. This test encodes US5.AC1
# against that surface so a later edit that drops the fingerprint requirement, the
# wiring-inclusion rationale, the concrete computation, or the recorded fingerprint
# itself fails the `verify` CI job (constitution P3: a rule a deterministic check can
# enforce must have that check).
#
# SCOPE: this is T401 (record a fingerprint alongside results). The currency *comparison*
# — flag PROBES-STALE when the current fingerprint differs from the last recorded probe
# run, and report the age — is US5.AC2 / T402, NOT here; so this test deliberately does
# NOT recompute live machinery hashes (a per-row fingerprint is frozen at probe time —
# what that probe ran against — and must not be auto-bumped to match a later guard
# change). The honesty of the specific recorded hash values is checked once, by the
# spec-auditor recomputing them at the §7 gate (`git hash-object .claude/hooks/guard.sh`
# and the matcher pipeline), exactly the maker/checker split the other *-docs tests use
# (the live counterpart is the probe run itself, conformance-probes.md).
#
# Run: bash .claude/hooks/probe-fingerprint-docs.test.sh
set -u

DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib-neutrality-scan.sh
. "$DIR/hooks/lib-neutrality-scan.sh"
NEU="$DIR/workflow/conformance-probes.md"
ADP="$DIR/adapters/claude-code-probes.md"

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

# ── Neutral convention (conformance-probes.md → "Recording") ─────────────────────────
# US5.AC1: probe runs record a content-hash fingerprint of the [guard] alongside results.
check "neutral: recording requires a content-hash fingerprint of the [guard]" "$NEU_FLAT" \
  "content-hash fingerprint of the [guard]"
# The wiring is in scope on purpose — it has gone silently dead while the logic stayed
# correct, so a script-only hash would miss a wiring regression (DESIGN-NOTES §4 class).
check "neutral: fingerprint covers the wiring that routes events, not just the logic" "$NEU_FLAT" \
  "the wiring that routes events to it"
check "neutral: the wiring-inclusion rationale (silently dead) is stated" "$NEU_FLAT" \
  "has gone silently dead before"
# Reproducibility is what makes a later freshness comparison meaningful.
check "neutral: the fingerprint must be reproducible" "$NEU_FLAT" \
  "the same machinery recomputes to the same fingerprint"
# Scoped so unrelated config edits do not move it (else PROBES-STALE false-fires).
check "neutral: scoped so unrelated config edits do not perturb it" "$NEU_FLAT" \
  "unrelated configuration edits do not perturb it"
# Role-neutral: the concrete hash is the adapter's to define, not named in the neutral doc.
check "neutral: concrete computation is delegated to the adapter" "$NEU_FLAT" \
  "is the adapter's to define"

# ── Adapter instantiation (claude-code-probes.md) ────────────────────────────────────
# Concrete computation for both halves of the fingerprint, reproducible from a checkout.
check "adapter: guard-script hash command is documented" "$ADP_FLAT" \
  "git hash-object .claude/hooks/guard.sh"
check "adapter: hook-wiring hash command is documented" "$ADP_FLAT" \
  "jq -r '.hooks.PreToolUse[].matcher' .claude/settings.json | git hash-object --stdin"
# The wiring hash is over the matcher ONLY — not the whole settings file — so an
# unrelated allowlist edit does not move the fingerprint (matches the neutral scoping).
check "adapter: wiring hash is matcher-only, never the whole settings file" "$ADP_FLAT" \
  "never the whole settings file"
# The results table carries the fingerprint alongside each run (US5.AC1, literally).
check "adapter: results table has a Fingerprint column" "$ADP_FLAT" \
  "| Probe | Result | Fingerprint | Observed |"
# EVERY non-placeholder row in the "## Probe results" table must carry a well-formed
# guard=<sha7> wiring=<sha7> fingerprint in its dedicated Fingerprint column — not merely
# somewhere in the row, and not merely one row in the file. US5.AC1 and the Recording
# convention require the fingerprint alongside EACH run, and T402's PROBES-STALE reads the
# LATEST row's Fingerprint cell, so a future result appended without one must FAIL here.
# Scope to the Probe results section (the Probe instantiation table carries no fingerprints
# by design); skip the header, the separator, and the `_(append …)_` template row.
# (Codex P2 on PR #86: a single file-wide match passed an unfingerprinted row; owner-relayed
# Codex P2: a whole-row grep passes an empty cell when the Observed narrative holds
# fingerprint-shaped text — so validate the Fingerprint CELL specifically, not the row.)
results_section="$(awk '
  /^## / { insec = ($0 ~ /^## Probe results/) ? 1 : 0 }
  insec { print }
' "$ADP")"
res_rows=0
res_bad=0
while IFS= read -r row; do
  [ "${row#|}" != "$row" ] || continue                        # table rows only (start with |)
  printf '%s' "$row" | grep -qE '^\| *Probe +\|' && continue  # header
  printf '%s' "$row" | grep -qE '^\|[ |:-]*\|$' && continue   # separator
  printf '%s' "$row" | grep -qF '_(append' && continue        # template/placeholder row
  res_rows=$((res_rows + 1))
  # Validate the FINGERPRINT CELL specifically — the 3rd column, i.e. field 4 when the row
  # is split on '|' (field 1 is the empty span before the leading pipe; the Probe/Result
  # cells before it never contain a pipe). Grepping the whole row would let an empty
  # Fingerprint cell pass whenever the Observed narrative holds a fingerprint-shaped string,
  # and T402 parses THIS column for staleness. Anchored so the cell holds the fingerprint
  # and nothing else. (Field 4 is unaffected by any pipe in the later Observed cell.)
  fp_cell="$(printf '%s\n' "$row" | awk -F'|' '{ print $4 }')"
  printf '%s' "$fp_cell" | grep -qE '^ *guard=[0-9a-f]{7} wiring=[0-9a-f]{7} *$' && continue
  res_bad=$((res_bad + 1))
  printf 'FAIL adapter: Fingerprint cell is not a well-formed guard=<sha7> wiring=<sha7>:\n     %s…\n' \
    "$(printf '%s' "$row" | cut -c1-72)" >&2
done <<RESULTS_EOF
$results_section
RESULTS_EOF
if [ "$res_rows" -ge 1 ] && [ "$res_bad" -eq 0 ]; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  [ "$res_rows" -ge 1 ] || printf 'FAIL adapter: no non-placeholder probe-result rows found to check\n' >&2
fi
# Scope boundary is stated in the doc itself: T401 records, T402 compares (no scope creep).
check "adapter: ties recording to US5.AC1 and defers currency to T402" "$ADP_FLAT" \
  "US5.AC2 / T402"

# ── Runtime-neutral boundary (constitution P1) ───────────────────────────────────────
# The fingerprint text added to the neutral doc must name no runtime-specific mechanism
# (the GitHub CLI, model IDs, Claude-Code-only tokens). `git` is the harness's universal
# VCS substrate and is exempt; strip the `.claude/` profile pointer first so the
# `\bclaude\b` word match never false-fires on it (same shape as telemetry-docs.test.sh).
mech="$(neutral_mechanism_leaks "$NEU")"
if [ -z "$mech" ]; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  printf 'FAIL neutral boundary: runtime-specific mechanism leaked into %s\n     found: %s\n' "$NEU" "$mech" >&2
fi

echo "probe-fingerprint docs encoding tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
