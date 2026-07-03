#!/usr/bin/env bash
# Encoding tests for issue #75 (T605 — auditor-liveness standing corpus). Done-when
# criteria on the issue body are the rubric (Phase 8 maintenance task; the acceptance
# reviewer grades against them exactly as a US#).
#
# Like the other runtime-neutral procedures, the corpus + its wiring ARE the
# implementation: `.claude/workflow/auditor-liveness.md` (the methodology),
# `.claude/workflow/reviewers/auditor-liveness-corpus.md` (the fixtures), the triage
# CORPUS-STALE surfacing, and the `.claude/skills/auditor-liveness/SKILL.md` binding.
# The run itself is model-driven and report-only (it cannot be a deterministic hard
# gate — issue #75), so the honesty of a live run is the probe/§7-gate's job, not this
# test's. This test encodes each done-when criterion against the doc + corpus surface so
# a later edit that drops one fails the `verify` CI job (constitution P3: a rule a
# deterministic check can enforce must have that check).
#
# DW1 in particular is a REAL structural check, not a string grep: it parses the corpus
# manifest and asserts ≥1 expected-FAIL and ≥1 expected-PASS fixture per auditor, with a
# non-empty evidence anchor on every FAIL row — so deleting a fixture or unbalancing the
# corpus fails CI.
#
# Run: bash .claude/hooks/auditor-liveness-docs.test.sh
set -u

DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib-neutrality-scan.sh
. "$DIR/hooks/lib-neutrality-scan.sh"
NEU="$DIR/workflow/auditor-liveness.md"
CORPUS="$DIR/workflow/reviewers/auditor-liveness-corpus.md"
TRIAGE="$DIR/workflow/triage.md"
TRIAGE_ADP="$DIR/skills/triage/SKILL.md"
SKILL="$DIR/skills/auditor-liveness/SKILL.md"
README="$DIR/workflow/README.md"
PROBES="$DIR/workflow/conformance-probes.md"
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

for f in "$NEU" "$CORPUS" "$TRIAGE" "$TRIAGE_ADP" "$SKILL" "$README" "$PROBES" "$CI"; do
  if [ ! -f "$f" ]; then
    echo "FAIL: required file missing: $f" >&2
    exit 1
  fi
done

NEU_FLAT="$(flat "$NEU")"
CORPUS_FLAT="$(flat "$CORPUS")"
TRIAGE_FLAT="$(flat "$TRIAGE")"
TRIAGE_ADP_FLAT="$(flat "$TRIAGE_ADP")"
SKILL_FLAT="$(flat "$SKILL")"
README_FLAT="$(flat "$README")"
PROBES_FLAT="$(flat "$PROBES")"

# ── DW1 (structural) — ≥1 expected-FAIL + ≥1 expected-PASS fixture per auditor ────────
# Parse the corpus manifest's fixture rows (markdown table, "| AL-… |"). awk fields on
# '|': $2=id $3=auditor $4=expected $6=evidence-anchor. The trim idiom is the same one
# evasion-register-docs.test.sh uses (BSD+GNU awk safe). No associative arrays — plain
# counters keep this bash-3.2 portable (issue #97 territory).
acc_f=0; acc_p=0; con_f=0; con_p=0; ctr_f=0; ctr_p=0; sq_f=0; sq_p=0
rows=0; malformed=0
while IFS= read -r row; do
  rows=$((rows + 1))
  id="$(printf '%s' "$row"  | awk -F'|' '{ gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2 }')"
  aud="$(printf '%s' "$row" | awk -F'|' '{ gsub(/^[ \t]+|[ \t]+$/, "", $3); print $3 }')"
  exp="$(printf '%s' "$row" | awk -F'|' '{ gsub(/^[ \t]+|[ \t]+$/, "", $4); print $4 }')"
  anc="$(printf '%s' "$row" | awk -F'|' '{ gsub(/^[ \t]+|[ \t]+$/, "", $6); print $6 }')"
  case "$aud" in
    acceptance|constitution|contract|spec-quality) ;;
    *) printf 'FAIL DW1: fixture %s has unknown auditor "%s"\n' "$id" "$aud" >&2; malformed=1; continue ;;
  esac
  case "$exp" in
    FAIL)
      case "$aud" in
        acceptance) acc_f=$((acc_f + 1)) ;;
        constitution) con_f=$((con_f + 1)) ;;
        contract) ctr_f=$((ctr_f + 1)) ;;
        spec-quality) sq_f=$((sq_f + 1)) ;;
      esac
      # A FAIL fixture without an expected evidence anchor cannot tell "caught it for the
      # right reason" from an unrelated FAIL — the anchor is mandatory (real content, not
      # a placeholder dash). "has an alphanumeric" rejects empty / "—" regardless of UTF-8
      # byte width.
      if ! printf '%s' "$anc" | grep -qE '[[:alnum:]]'; then
        printf 'FAIL DW1: FAIL fixture %s has no evidence anchor\n' "$id" >&2; malformed=1
      fi ;;
    PASS)
      case "$aud" in
        acceptance) acc_p=$((acc_p + 1)) ;;
        constitution) con_p=$((con_p + 1)) ;;
        contract) ctr_p=$((ctr_p + 1)) ;;
        spec-quality) sq_p=$((sq_p + 1)) ;;
      esac ;;
    *) printf 'FAIL DW1: fixture %s has invalid expected verdict "%s"\n' "$id" "$exp" >&2; malformed=1 ;;
  esac
done < <(grep -E '^\| AL-' "$CORPUS")

# Guard against the table format silently changing so no rows parse (counters would all
# read 0 and the per-auditor checks below would fail anyway, but this names the cause).
if [ "$rows" -ge 8 ]; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  printf 'FAIL DW1: parsed only %s fixture rows (expected ≥8: a FAIL+PASS pair per auditor)\n' "$rows" >&2
fi

for who in "acceptance:$acc_f:$acc_p" "constitution:$con_f:$con_p" "contract:$ctr_f:$ctr_p" "spec-quality:$sq_f:$sq_p"; do
  a="${who%%:*}"; rest="${who#*:}"; nf="${rest%%:*}"; np="${rest#*:}"
  if [ "$nf" -ge 1 ] && [ "$np" -ge 1 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL DW1: auditor "%s" lacks the matched pair (expected-FAIL=%s expected-PASS=%s; need ≥1 each)\n' "$a" "$nf" "$np" >&2
  fi
done

if [ "$malformed" -eq 0 ]; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  printf 'FAIL DW1: corpus manifest has malformed fixture rows (see above)\n' >&2
fi

# DW1 prose: the corpus declares the per-auditor matched-pair contract.
check "DW1: corpus states the per-auditor FAIL+PASS contract" "$CORPUS_FLAT" \
  "fixture per auditor"
check "DW1: neutral doc points at the corpus fixtures" "$NEU_FLAT" \
  "reviewers/auditor-liveness-corpus.md"

# ── DW2 — re-run on every reviewer-spec change + on a named (≥ weekly) schedule ───────
check "DW2: re-run on every reviewer-spec change" "$NEU_FLAT" \
  "On every reviewer-spec change"
check "DW2: the named minimum cadence is weekly" "$NEU_FLAT" \
  "minimum cadence is weekly"
# The on-change trigger is DETERMINISTIC (P3), not a remembered intention — a fingerprint.
check "DW2/P3: deterministic reviewer-spec fingerprint detector" "$NEU_FLAT" \
  "reviewer-spec fingerprint"
check "DW2/P3: the staleness flag is definite, not a heuristic" "$NEU_FLAT" \
  "definite flag, not a heuristic"
# Surfaced read-only through triage as CORPUS-STALE (the on-change detector's channel).
check "DW2: triage carries the CORPUS-STALE check" "$TRIAGE_FLAT" "CORPUS-STALE"
check "DW2: triage §4 template has the no-baseline state" "$TRIAGE_FLAT" \
  "no corpus run recorded yet"
# Adapter supplies the concrete fingerprint recipe + reuses it from one place (DRY).
check "DW2 (adapter): the reviewer-spec fingerprint recipe is concrete" "$SKILL_FLAT" \
  "git hash-object"
check "DW2 (adapter): the fingerprint renders as specs=<sha7>" "$SKILL_FLAT" \
  "specs=<sha7>"
check "DW2 (triage adapter): reuses the single-source recipe, never re-derives it" "$TRIAGE_ADP_FLAT" \
  "never re-derive it here"
check "DW2 (triage adapter): reads the Corpus-run results baseline" "$TRIAGE_ADP_FLAT" \
  "Corpus-run results"

# ── Post-open review (PR #100 — Codex P2 + owner §2.5 steering): scoped runs must not ─
# refresh the CORPUS-STALE baseline. The binding allows a `/auditor-liveness <fixture-id>`
# diagnostic that exercises ONE fixture; letting its row stand as the freshness baseline
# would report the auditors "current" though only one was re-run. Fix: a Scope column
# (full / partial:<fixture-id>); only `full` rows are baselines.
check "scoped-fix (neutral): a partial run does not refresh the baseline / clear staleness" "$NEU_FLAT" \
  "does not refresh the baseline or clear staleness"
check "scoped-fix (neutral): the baseline is the last full-corpus run" "$NEU_FLAT" \
  "last recorded full-corpus run"
check "scoped-fix (adapter): the results table carries a Scope column" "$SKILL_FLAT" \
  "| Date | Scope |"
check "scoped-fix (adapter): partial rows are labelled partial:<fixture-id>" "$SKILL_FLAT" \
  "partial:<fixture-id>"
check "scoped-fix (adapter): a scoped run never serves as the CORPUS-STALE baseline" "$SKILL_FLAT" \
  "never serves as the CORPUS-STALE baseline"
check "scoped-fix (triage adapter): baseline skips partial rows (full-scope only)" "$TRIAGE_ADP_FLAT" \
  "never serves as the freshness baseline"

# ── DW3 — observe-only channel; never feeds gate outcomes / tier / semantics (P5) ────
P5="a model-tier assignment, or any gate semantic"
check "DW3 (neutral): observe-only — never feeds gate/tier/semantics" "$NEU_FLAT" "$P5"
check "DW3 (neutral): the Observe-only boundary section exists" "$NEU_FLAT" \
  "## Observe-only"
check "DW3 (corpus): restates the observe-only boundary" "$CORPUS_FLAT" "$P5"
check "DW3 (adapter): the binding restates the observe-only boundary" "$SKILL_FLAT" "$P5"
# The run is report-only (no fix loop) — it measures auditors, never repairs a diff.
check "DW3 (neutral): the run is read-only AND report-only" "$NEU_FLAT" \
  "read-only, report-only"
# Composes existing roles only — no new binding-contract row (like the retrospective).
check "DW3 (neutral): composes existing roles, no new binding-contract row" "$NEU_FLAT" \
  "no new binding-contract row"

# ── DW4 — the relationship to P-RV and guard.test.sh is documented ───────────────────
check "DW4 (neutral): a section relates the corpus to P-RV + the guard's test" "$NEU_FLAT" \
  "Relationship to \`P-RV\` and the guard's deterministic test"
check "DW4 (neutral): names P-RV as the origin" "$NEU_FLAT" "P-RV"
check "DW4 (neutral): names guard.test.sh as the deterministic analog" "$NEU_FLAT" \
  "guard.test.sh"
check "DW4 (neutral): generalizes P2's proven-live discipline" "$NEU_FLAT" \
  "proven live, not assumed live"
check "DW4 (neutral): ties the generalization to P2" "$NEU_FLAT" "generalizes P2"
# Adapter half — the binding names the concrete guard.test.sh relationship too.
check "DW4 (adapter): binding relates the corpus to guard.test.sh" "$SKILL_FLAT" \
  "guard.test.sh"
# P-RV back-reference lives in the neutral probe checklist (the standing variant).
check "DW4 (probes): P-RV documents its standing variant" "$PROBES_FLAT" \
  "Standing variant"
check "DW4 (probes): the standing variant points at auditor-liveness.md" "$PROBES_FLAT" \
  "auditor-liveness.md"

# ── Discoverability — the workflow README files index lists the new docs ──────────────
check "README: files index names the auditor-liveness doc" "$README_FLAT" \
  "auditor-liveness.md"
check "README: files index names the corpus manifest" "$README_FLAT" \
  "reviewers/auditor-liveness-corpus.md"

# ── Seeding & growth — fixtures land via PR, never silently (P4) ──────────────────────
check "P4: new fixtures travel the propose-via-PR flow, never a silent write" "$NEU_FLAT" \
  "never an automatic or silent write"
check "seed: corpus is seeded from the evasion register / retrospective incidents" "$NEU_FLAT" \
  "Seeded from known escapes"
# Seeding contract admits the bootstrap exception for a brand-new reviewer with no logged
# escape yet (PR #181 craft review: the top-level contract — not just the fixture detail —
# must say so, so it stays consistent with the bootstrap-seeded AL-SQ-FAIL-01).
check "seed: corpus contract documents the brand-new-reviewer bootstrap exception" "$CORPUS_FLAT" \
  "explicit bootstrap seed for a brand-new reviewer"
# The declared-ahead-of-binding marker was retired once T707 wired the runner to dispatch
# spec-quality (PR #181 had staged it; this test now asserts it is GONE, not present — a
# stale reintroduction of the marker would mean the runner regressed to not covering
# spec-quality, so this is a real structural pin, not a string flip).
if printf '%s' "$CORPUS_FLAT" | grep -qF "declared-but-not-yet-dispatched"; then
  fail=$((fail + 1))
  printf 'FAIL lifecycle: corpus still carries the retired declared-but-not-yet-dispatched marker (T707 wired the runner — spec-quality is bound now)\n' >&2
else
  pass=$((pass + 1))
fi

# ── T707 — the auditor-liveness runner dispatches spec-quality-auditor (mechanize — P3) ─
# DW1/DW2 done-when: the dispatch binding + fingerprint recipe must both name
# spec-quality-auditor, so a full corpus run actually exercises the AL-SQ-* fixtures and
# editing the spec-quality reviewer spec raises CORPUS-STALE, exactly as for the other
# three auditors.
check "T707: reviewer dispatch row names spec-quality-auditor" "$SKILL_FLAT" \
  "spec-quality-auditor"
check "T707: corpus contract states all four auditors are bound (none deferred)" "$CORPUS_FLAT" \
  "all four are bound to the runner"
# The fingerprint recipe (git hash-object argv) must include the spec-quality spec file —
# assert the exact path appears inside the fenced recipe block, not merely anywhere in the
# skill doc (a stray prose mention elsewhere would false-pass a substring-only check).
# Assumes the fingerprint recipe is the FIRST fenced ``` block in SKILL.md (true today) —
# if a future edit adds an earlier code block, retarget this to the block that follows the
# "## The reviewer-spec fingerprint" heading instead of counting from the top.
fp_block="$(awk '/^```$/{n++; if (n==1) {p=1; next} else {p=0}} p' "$SKILL")"
if printf '%s' "$fp_block" | grep -qF "reviewers/spec-quality-auditor.md"; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  printf 'FAIL T707: fingerprint recipe (git hash-object block) omits reviewers/spec-quality-auditor.md\n' >&2
fi

# ── CI wiring — this test is actually run by the required `verify` check ──────────────
check "CI: verify runs this encoding test" "$(flat "$CI")" \
  "auditor-liveness-docs.test.sh"

# ── Runtime-neutral boundary (constitution P1) — the new workflow/** docs name no ─────
# runtime-specific mechanism. Strip the allowed `.claude/` profile pointer first (so it
# never false-matches \bclaude\b), then ban the runtime-specific mechanism set — the same
# scan the telemetry / evasion-register docs tests run over their neutral docs. Covers
# BOTH new neutral files (the methodology doc and the fixture manifest).
for nf in "$NEU" "$CORPUS"; do
  mech="$(neutral_mechanism_leaks "$nf")"
  if [ -z "$mech" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL neutral boundary: runtime-specific mechanism leaked into %s\n     found: %s\n' "$nf" "$mech" >&2
  fi
done

echo "auditor-liveness docs encoding tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
