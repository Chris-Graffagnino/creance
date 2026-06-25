#!/usr/bin/env bash
# Encoding tests for T801 (#155 — spec 003 maker-eval corpus, US1.AC1 + US1.AC4). The
# done-when criteria on the issue body are the rubric (the acceptance reviewer grades
# against them exactly as a US#).
#
# Like the other runtime-neutral procedures, the corpus + its wiring ARE the
# implementation: `.claude/workflow/maker-eval.md` (the methodology),
# `.claude/workflow/reviewers/maker-eval-corpus.md` (the frozen instrument), the pinned-judge
# line in the adapter model table, and the Maker-eval-records Paths row. The eval run itself
# is model-driven and report-only (it cannot be a deterministic hard gate — a flaky verdict
# would block honest work, spec 003), so the honesty of a live run is a probe / the §7 gate's
# job, not this test's. This test encodes each done-when criterion against the doc + corpus
# surface so a later edit that drops one fails the `verify` CI job (constitution P3: a rule a
# deterministic check can enforce must have that check).
#
# DW1 in particular is a REAL structural check, not a string grep: it parses the corpus
# manifest and asserts >= 6 frozen tasks, every task carrying a valid lifecycle tag
# (capability/regression/saturated) and a non-empty rubric, with all three lifecycle states
# represented — so deleting a task, dropping a rubric, or collapsing the lifecycle spread
# fails CI.
#
# Run: bash .claude/hooks/maker-eval-docs.test.sh
set -u

DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib-neutrality-scan.sh
. "$DIR/hooks/lib-neutrality-scan.sh"
NEU="$DIR/workflow/maker-eval.md"
CORPUS="$DIR/workflow/reviewers/maker-eval-corpus.md"
README="$DIR/workflow/README.md"
MODELS="$DIR/MODELS.md"
PROJECT="$DIR/PROJECT.md"
TEMPLATE="$DIR/PROJECT.template.md"
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

for f in "$NEU" "$CORPUS" "$README" "$MODELS" "$PROJECT" "$TEMPLATE" "$CI"; do
  if [ ! -f "$f" ]; then
    echo "FAIL: required file missing: $f" >&2
    exit 1
  fi
done

NEU_FLAT="$(flat "$NEU")"
CORPUS_FLAT="$(flat "$CORPUS")"
README_FLAT="$(flat "$README")"
MODELS_FLAT="$(flat "$MODELS")"
PROJECT_FLAT="$(flat "$PROJECT")"
TEMPLATE_FLAT="$(flat "$TEMPLATE")"

# ── DW1 (structural) — >= 6 frozen tasks, each with a valid lifecycle tag + a rubric, ─────
# all three lifecycle states represented. Parse the corpus manifest's task rows (markdown
# table, "| ME-… |"). awk fields on '|': $2=id $3=lifecycle $6=rubric. The trim idiom is the
# same one auditor-liveness-docs.test.sh / evasion-register-docs.test.sh use (BSD+GNU awk
# safe — '|' alternation, never a {n} interval, #97). Plain counters keep this bash-3.2
# portable; no associative arrays.
cap=0; reg=0; sat=0
rows=0; malformed=0
while IFS= read -r row; do
  rows=$((rows + 1))
  id="$(printf '%s' "$row"   | awk -F'|' '{ gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2 }')"
  life="$(printf '%s' "$row" | awk -F'|' '{ gsub(/^[ \t]+|[ \t]+$/, "", $3); print $3 }')"
  rub="$(printf '%s' "$row"  | awk -F'|' '{ gsub(/^[ \t]+|[ \t]+$/, "", $6); print $6 }')"
  case "$life" in
    capability) cap=$((cap + 1)) ;;
    regression) reg=$((reg + 1)) ;;
    saturated) sat=$((sat + 1)) ;;
    *) printf 'FAIL DW1: task %s has invalid lifecycle "%s" (want capability/regression/saturated)\n' "$id" "$life" >&2; malformed=1 ;;
  esac
  # A task with no rubric cannot be scored — the rubric is mandatory. "has an alphanumeric"
  # rejects empty / "—" regardless of UTF-8 byte width.
  if ! printf '%s' "$rub" | grep -qE '[[:alnum:]]'; then
    printf 'FAIL DW1: task %s has no rubric\n' "$id" >&2; malformed=1
  fi
done < <(grep -E '^\| ME-' "$CORPUS")

if [ "$rows" -ge 6 ]; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  printf 'FAIL DW1: parsed only %s corpus task rows (expected >= 6 a small frozen set)\n' "$rows" >&2
fi

# All three lifecycle states must be represented — the metadata is what keeps the set frozen
# yet evolvable (capability probes, regression pins a known failure, saturated is the floor).
for who in "capability:$cap" "regression:$reg" "saturated:$sat"; do
  state="${who%%:*}"; n="${who#*:}"
  if [ "$n" -ge 1 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL DW1: no task carries lifecycle "%s" (the frozen set must span all three states)\n' "$state" >&2
  fi
done

if [ "$malformed" -eq 0 ]; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  printf 'FAIL DW1: corpus manifest has malformed task rows (see above)\n' >&2
fi

# DW1 prose: the corpus declares the lifecycle contract + the neutral doc points at it.
check "DW1: corpus declares the capability/regression/saturated lifecycle contract" "$CORPUS_FLAT" \
  "one of \`capability\`, \`regression\`, \`saturated\`"
check "DW1: neutral doc points at the corpus manifest" "$NEU_FLAT" \
  "reviewers/maker-eval-corpus.md"
# Seeded from real signal classes + adopter workflows, not synthetic toys (US1.AC1).
check "DW1: corpus is seeded from real signal classes, not synthetic toys" "$CORPUS_FLAT" \
  "not synthetic toys"
check "DW1 (seed): discovered-work cluster class is represented" "$CORPUS_FLAT" "discovered-work"
check "DW1 (seed): owner-comment steering class is represented" "$CORPUS_FLAT" "owner-comment steering"
check "DW1 (seed): adapter-port / runtime-neutral boundary class is represented" "$CORPUS_FLAT" \
  "the runtime-neutral boundary"
check "DW1 (seed): template cold-start adopter workflow is represented" "$CORPUS_FLAT" "cold-start"

# ── DW2 — the run: a [headless run] of the maker scored by a read-only judge, no fix loop ─
check "DW2: the maker runs as a [headless run]" "$NEU_FLAT" \
  "Execute the task as a [headless run] of the maker"
check "DW2: scored by a read-only [reviewer]-style judge" "$NEU_FLAT" \
  "read-only **[reviewer]**-style scorer"
check "DW2: a single grading pass, no fix loop (measures, does not repair)" "$NEU_FLAT" \
  "no fix loop and no re-dispatch"
check "DW2: composes existing roles only — no new binding-contract row" "$NEU_FLAT" \
  "no new binding-contract row"
# Differential signal — this run vs the last on the same frozen corpus, never an absolute score.
check "DW2: the signal is differential, not an absolute judge score" "$NEU_FLAT" \
  "an absolute judge score is never load-bearing"

# ── DW3 — the pinned judge: identity fixed independently of the maker model-table change ──
check "DW3 (neutral): judge identity pinned independently of the maker model-table change" "$NEU_FLAT" \
  "pinned independently of the maker model-table change"
# Adapter: the model table declares the judge on its own line, decoupled from the maker rows.
check "DW3 (adapter): MODELS.md declares the pinned maker-eval judge" "$MODELS_FLAT" \
  "maker-eval judge"
check "DW3 (adapter): the judge is not re-resolved from a maker tier row" "$MODELS_FLAT" \
  "not** re-resolved from a maker tier row"
check "DW3 (adapter): a maker swap never moves the judge" "$MODELS_FLAT" \
  "a maker model swap edits a tier row and never moves the judge"

# ── DW4 — the triple fingerprint: three separately-recorded components (US1.AC3 shape) ────
check "DW4: component 1 — the maker-behavior fingerprint" "$NEU_FLAT" \
  "Maker-behavior fingerprint"
check "DW4: the maker-behavior fingerprint is NOT the model table alone" "$NEU_FLAT" \
  "not the model table alone"
check "DW4: component 2 — the pinned-judge identity" "$NEU_FLAT" \
  "Pinned-judge identity"
check "DW4: component 3 — the eval-instrument fingerprint" "$NEU_FLAT" \
  "Eval-instrument fingerprint"
check "DW4: the instrument fingerprint covers lifecycle metadata + calibration set + floor" "$NEU_FLAT" \
  "the per-task lifecycle metadata, the rubrics, the judge prompt/spec, the scoring schema, and the owner-labeled calibration set with its labels and agreement floor"
check "DW4: recorded separately so a judge/instrument change is its own movement" "$NEU_FLAT" \
  "three separately-recorded components"

# ── DW5 — the record + transcript review packet stored in the eval channel's fenced path ──
check "DW5: one append-only record per corpus task, sharing a run id" "$NEU_FLAT" \
  "exactly one append-only record per corpus task"
check "DW5: a transcript review packet per task" "$NEU_FLAT" \
  "stores a transcript review packet"
check "DW5: the packet carries the first-upstream-failure classification" "$NEU_FLAT" \
  "first-upstream-failure classification"
check "DW5: the packet link resolves only inside the eval channel's fenced path" "$NEU_FLAT" \
  "resolves **only inside that same fenced path**"
check "DW5: a run is complete only when every corpus task has a record" "$NEU_FLAT" \
  "complete** only when **every** corpus task has a record"
check "DW5: a failed or partial write changes nothing" "$NEU_FLAT" \
  "failed or partial write **changes nothing**"
check "DW5: an incomplete run is never a comparable baseline" "$NEU_FLAT" \
  "incomplete run is never treated as a comparable baseline"
# The corpus declares the fixed first-upstream-failure taxonomy + the scoring schema.
check "DW5 (corpus): the first-upstream-failure taxonomy is fixed" "$CORPUS_FLAT" \
  "First-upstream-failure taxonomy"
check "DW5 (corpus): the scoring schema is part of the frozen instrument" "$CORPUS_FLAT" \
  "The scoring schema"

# ── DW6 — records live at their OWN path beside telemetry, named via the profile ([roles]) ─
check "DW6 (neutral): records named via the profile, not hardcoded in the neutral doc" "$NEU_FLAT" \
  "the eval channel the profile names"
check "DW6 (neutral): its own append-only path beside the telemetry stream" "$NEU_FLAT" \
  "own append-only path beside the telemetry"
check "DW6 (profile): PROJECT.md Paths carries the Maker-eval records row" "$PROJECT_FLAT" \
  "Maker-eval records:"
check "DW6 (profile): the channel is kept distinct so the P5 fence can scope to it" "$PROJECT_FLAT" \
  "kept distinct from the telemetry stream"
check "DW6 (template): PROJECT.template.md Paths carries the Maker-eval records row" "$TEMPLATE_FLAT" \
  "Maker-eval records:"

# ── DW7 — observe-only (P5) + the instrument grows by PR only (P4) — US1.AC4 ──────────────
P5="a model-tier assignment, or any gate semantic"
check "DW7 (neutral): observe-only — never feeds gate/tier/semantics (P5)" "$NEU_FLAT" "$P5"
check "DW7 (neutral): the Observe-only boundary section exists" "$NEU_FLAT" \
  "## Observe-only"
check "DW7 (corpus): restates the observe-only boundary" "$CORPUS_FLAT" "$P5"
check "DW7 (neutral): the frozen instrument changes only by a human-reviewed PR (P4)" "$NEU_FLAT" \
  "changed only by a human-reviewed PR"
check "DW7 (neutral): a run only reads the instrument and appends observe-only records" "$NEU_FLAT" \
  "A run only *reads* the instrument and *appends* observe-only records"

# ── Discoverability — the workflow README files index lists the new docs ──────────────────
check "README: files index names the maker-eval methodology doc" "$README_FLAT" \
  "\`maker-eval.md\`"
check "README: files index names the corpus manifest" "$README_FLAT" \
  "reviewers/maker-eval-corpus.md"

# ── CI wiring — this test is actually run by the required `verify` check ──────────────────
check "CI: verify runs this encoding test" "$(flat "$CI")" \
  "maker-eval-docs.test.sh"

# ── Runtime-neutral boundary (constitution P1) — both new workflow/** docs name no ────────
# runtime-specific mechanism. The same shared scan the telemetry / auditor-liveness docs
# tests run over their neutral docs; covers BOTH new neutral files.
for nf in "$NEU" "$CORPUS"; do
  mech="$(neutral_mechanism_leaks "$nf")"
  if [ -z "$mech" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL neutral boundary: runtime-specific mechanism leaked into %s\n     found: %s\n' "$nf" "$mech" >&2
  fi
done

echo "maker-eval docs encoding tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
