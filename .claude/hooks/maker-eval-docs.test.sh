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
# manifest's TWO tables — the task table (>= 6 frozen tasks, each id well-formed ME-<digits>
# and UNIQUE) and the per-dimension rubric table (every scored dimension carrying a valid
# lifecycle tag capability/regression/saturated + a non-empty criterion, with all three
# lifecycle states represented and every dimension bound to a real task and back). Lifecycle
# is per DIMENSION, not per task (spec 003 US1.AC1/AC3/AC4), so a duplicate/malformed task id,
# a dropped criterion, a dangling dimension, or a collapsed lifecycle spread fails CI.
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

# ── DW1 (structural) — the corpus is two parseable markdown tables ("| ME-… |" rows):
#   "## The corpus tasks …"             → | Task | Seed class | Maker task |        ($2 = id)
#   "## The scored rubric dimensions …"  → | Task | Dimension | Lifecycle | Criterion |
#                                           ($2 = task ref, $4 = lifecycle, $5 = criterion)
# Lifecycle is per DIMENSION (spec 003 US1.AC1/AC3/AC4 — a task may mix a saturated floor with a
# regression pin), so it is read from the rubric table, never the task table. rows_under emits
# only the "| ME-…" rows under a given "## " heading, so the two tables parse independently. The
# trim idiom matches auditor-liveness-docs.test.sh (BSD+GNU awk safe — '|' alternation, never a
# {n} interval, #97). Plain counters + sort|uniq keep this bash-3.2 portable; no assoc. arrays.
rows_under() { # <file> <section-heading-substring>: emit '| ME-…' rows under that "## " heading
  awk -v h="$2" '
    /^## / { insec = (index($0, h) > 0); next }
    insec && /^\| ME-/ { print }
  ' "$1"
}

# --- the task table: >= 6 frozen tasks, each id well-formed (ME-<digits>) and UNIQUE ---------
# The run record keys records by corpus task id (maker-eval.md → "The record …"), so a duplicate
# or malformed id would silently collide two tasks onto one baseline join (engineering-craft).
task_ids="$(rows_under "$CORPUS" "The corpus tasks" | awk -F'|' '{ gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2 }' | grep -E '^ME-')"
ntasks="$(printf '%s\n' "$task_ids" | grep -c .)"
nuniq="$(printf  '%s\n' "$task_ids" | sort -u | grep -c .)"
nbadid="$(printf '%s\n' "$task_ids" | grep -vcE '^ME-[0-9]+$')"

if [ "$ntasks" -ge 6 ]; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  printf 'FAIL DW1: parsed only %s corpus tasks (expected >= 6 a small frozen set)\n' "$ntasks" >&2
fi
if [ "$ntasks" -eq "$nuniq" ]; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  printf 'FAIL DW1: corpus task ids are not unique (%s rows, %s distinct)\n' "$ntasks" "$nuniq" >&2
  printf '%s\n' "$task_ids" | sort | uniq -d | sed 's/^/     duplicate id: /' >&2
fi
if [ "$nbadid" -eq 0 ]; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  printf 'FAIL DW1: %s corpus task id(s) are not of the form ME-<digits>\n' "$nbadid" >&2
fi

# --- the rubric-dimension table: per-dimension lifecycle + a criterion, bound to a real task --
cap=0; reg=0; sat=0; ndims=0; dim_bad=0
while IFS= read -r row; do
  [ -n "$row" ] || continue
  ndims=$((ndims + 1))
  ref="$(printf  '%s' "$row" | awk -F'|' '{ gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2 }')"
  life="$(printf '%s' "$row" | awk -F'|' '{ gsub(/^[ \t]+|[ \t]+$/, "", $4); print $4 }')"
  crit="$(printf '%s' "$row" | awk -F'|' '{ gsub(/^[ \t]+|[ \t]+$/, "", $5); print $5 }')"
  case "$life" in
    capability) cap=$((cap + 1)) ;;
    regression) reg=$((reg + 1)) ;;
    saturated)  sat=$((sat + 1)) ;;
    *) printf 'FAIL DW1: a dimension under %s has invalid lifecycle "%s" (want capability/regression/saturated)\n' "$ref" "$life" >&2; dim_bad=1 ;;
  esac
  # A dimension with no criterion cannot be scored. "has an alphanumeric" rejects empty / "—".
  if ! printf '%s' "$crit" | grep -qE '[[:alnum:]]'; then
    printf 'FAIL DW1: a dimension under %s has no criterion\n' "$ref" >&2; dim_bad=1
  fi
  # Referential integrity (forward): every dimension binds to a real corpus task id — a swapped
  # row identity (engineering-craft) fails here rather than scoring a phantom task.
  if ! printf '%s\n' "$task_ids" | grep -qxF -- "$ref"; then
    printf 'FAIL DW1: rubric dimension references unknown task "%s"\n' "$ref" >&2; dim_bad=1
  fi
done < <(rows_under "$CORPUS" "scored rubric dimensions")

if [ "$ndims" -ge 6 ]; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  printf 'FAIL DW1: parsed only %s scored rubric dimensions (expected >= 1 per task, >= 6)\n' "$ndims" >&2
fi

# All three lifecycle states must be represented ACROSS the dimensions — the metadata is what
# keeps the set frozen yet evolvable (capability probes, regression pins a known failure,
# saturated is the floor). Counted per dimension now, not per task (spec 003 US1.AC1).
for who in "capability:$cap" "regression:$reg" "saturated:$sat"; do
  state="${who%%:*}"; n="${who#*:}"
  if [ "$n" -ge 1 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL DW1: no dimension carries lifecycle "%s" (the set must span all three states)\n' "$state" >&2
  fi
done

# Referential integrity (reverse): every task has >= 1 scored dimension — a task with no
# dimension cannot be graded. Heredoc (not a pipe) so the counter survives in this shell.
dim_refs="$(rows_under "$CORPUS" "scored rubric dimensions" | awk -F'|' '{ gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2 }')"
uncovered=0
while IFS= read -r tid; do
  [ -n "$tid" ] || continue
  printf '%s\n' "$dim_refs" | grep -qxF -- "$tid" || { printf 'FAIL DW1: task %s has no scored rubric dimension\n' "$tid" >&2; uncovered=1; }
done <<EOF
$task_ids
EOF

if [ "$dim_bad" -eq 0 ] && [ "$uncovered" -eq 0 ]; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  printf 'FAIL DW1: rubric-dimension table has malformed or dangling rows (see above)\n' >&2
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
  "the per-dimension lifecycle metadata, the rubrics, the judge prompt/spec, the scoring schema, and the owner-labeled calibration set with its labels and agreement floor"
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

# ── T805 (#163 — spec 003 US2.AC1) — the skill binding reuses [workflow]/[headless run]/ ──
# [reviewer], runs on a maker-behavior fingerprint change AND a schedule, and adds no new
# binding-contract role. The encoding test for T805's criteria lives here (alongside T801's)
# rather than in a second file, mirroring intake-docs.test.sh (skill `[ -r ]` + workflow-doc
# reference) and evasion-register-docs.test.sh (probe in the neutral checklist + the adapter
# table + a cell-scoped PASS). A later edit that drops the binding, a trigger, or the
# observe-only claim fails the `verify` CI job, so the criterion is anchored, not assumed.
SKILL="$DIR/skills/maker-eval/SKILL.md"
if [ -r "$SKILL" ]; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  printf 'FAIL US2.AC1: skill binding file present\n     missing: %s\n' "$SKILL" >&2
fi
SKILL_FLAT="$(flat "$SKILL")"
check "US2.AC1: binding executes the runtime-neutral workflow doc" "$SKILL_FLAT" \
  "\`.claude/workflow/maker-eval.md\`"
check "US2.AC1: binding declares the maker-behavior fingerprint-change trigger (MAKER-EVAL-STALE)" "$SKILL_FLAT" \
  "MAKER-EVAL-STALE"
check "US2.AC1: binding declares the weekly schedule trigger" "$SKILL_FLAT" \
  "named minimum cadence is **weekly**"
check "US2.AC1: binding composes existing roles only — no new binding-contract row" "$SKILL_FLAT" \
  "no new binding-contract row"
# Negative case: the binding-contract table in workflow/README.md must NOT gain a
# [maker-eval] role row (the skill composes existing roles; it appears only in the Files
# list) — mirrors intake-docs.test.sh's AC5 negative check.
if printf '%s' "$README_FLAT" | grep -qF -- "| **[maker-eval]**"; then
  fail=$((fail + 1))
  printf 'FAIL US2.AC1: no [maker-eval] role row in the binding-contract table\n' >&2
else
  pass=$((pass + 1))
fi

# ── T805 (#163 — spec 003 US2.AC4) — the P-ME conformance probe ────────────────────────────
# The probe must exist in the neutral checklist, be instantiated in the adapter table, and
# carry a recorded live PASS. The result check is CELL-SCOPED (mirrors evasion-register's P-EV
# guidance, PR #89): a bare `| P-ME (` row-prefix needle would let a flip to FAIL/DEGRADED
# still pass CI, so it would NOT enforce the done-when (a live probe recorded a PASS). Assert
# the P-ME *results* row's result cell is PASS.
PROBES="$DIR/workflow/conformance-probes.md"
PROBES_FLAT="$(flat "$PROBES")"
ADAPTER="$DIR/adapters/claude-code-probes.md"
for f in "$PROBES" "$ADAPTER"; do
  if [ ! -f "$f" ]; then
    echo "FAIL US2.AC4: required file missing: $f" >&2
    exit 1
  fi
done
ADAPTER_FLAT="$(flat "$ADAPTER")"
check "US2.AC4: P-ME probe defined in the neutral checklist" "$PROBES_FLAT" \
  "### P-ME — maker-eval (\`maker-eval.md\`)"
check "US2.AC4: P-ME records carry the maker-behavior fingerprint" "$PROBES_FLAT" \
  "carrying that **maker-behavior fingerprint**"
check "US2.AC4: P-ME touches no gate/tier/guard/selection state" "$PROBES_FLAT" \
  "touches no gate, tier, guard, or selection state"
check "US2.AC4: P-ME edits no instrument artifact" "$PROBES_FLAT" \
  "edits no instrument artifact"
# The probe is scoped to the deterministic record/fingerprint/boundary conformance; the
# model-driven maker run + judge are deferred to live use / the gate (PR #164 — the probe must
# not over-claim that the whole binding "fires", since it drives only the record emission).
check "US2.AC4: P-ME scopes to emitter conformance; the model-driven run is deferred to live use" "$PROBES_FLAT" \
  "the pinned-**[reviewer]** judging are exercised by live use"
check "US2.AC4: P-ME in the coverage map" "$PROBES_FLAT" \
  "| maker-eval procedure (\`maker-eval.md\`) | P-ME |"
check "US2.AC4: P-ME instantiated in the adapter probe table" "$ADAPTER_FLAT" \
  "| P-ME |"
# The results row begins `| P-ME (` (the dated run), distinct from the `| P-ME |`
# instantiation row. awk field 3 is the result cell (the date cell carries no pipe) —
# the same field layout as the P-EV row in evasion-register-docs.test.sh.
pme_row="$(grep -E '^\| P-ME \(' "$ADAPTER" | head -1)"
pme_cell="$(printf '%s\n' "$pme_row" | awk -F'|' '{ gsub(/^[ \t]+|[ \t]+$/, "", $3); print $3 }')"
if [ "$pme_cell" = "PASS" ]; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  printf 'FAIL US2.AC4: P-ME results-row result cell is not PASS (got: %s)\n' "${pme_cell:-<no \`| P-ME (…)\` row>}" >&2
fi

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
