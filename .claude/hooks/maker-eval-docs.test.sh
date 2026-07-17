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
check "DW5: one append-only record per (corpus task × maker tier), sharing a run id" "$NEU_FLAT" \
  "exactly one append-only record per (corpus task × maker tier)"
check "DW5: a transcript review packet per task" "$NEU_FLAT" \
  "stores a transcript review packet"
check "DW5: the packet carries the first-upstream-failure classification" "$NEU_FLAT" \
  "first-upstream-failure classification"
check "DW5: the packet link resolves only inside the eval channel's fenced path" "$NEU_FLAT" \
  "resolves **only inside that same fenced path**"
check "DW5: a run is complete only when every corpus task has a record" "$NEU_FLAT" \
  "complete** only when **every** corpus task has a record"
check "DW5: completeness spans every maker tier (PR #164 tier coverage)" "$NEU_FLAT" \
  "a record under its run id **at every maker tier**"
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

# ── T806 (#218 — spec 003 US1.AC5) — the owner-labeled calibration set + agreement figure ──
# The judge is CALIBRATED against human judgment, not assumed valid. The frozen instrument now
# carries the actual owner-labeled calibration set (a parseable `| CAL-… |` table) + a stated
# agreement floor, and the neutral doc defines HOW a run computes the judge↔owner agreement over
# it. This is a REAL structural check (not a string grep) mirroring DW1: it parses the
# calibration table, asserts every pair is well-formed (CAL-<digits>, unique), carries an owner
# label that is a real scoring-schema verdict, and probes a real corpus rubric dimension — and
# that the labels SPAN the verdict range (a set of all-`meets` or all-`fails` labels could not
# discriminate a stuck judge). A later edit that drops the set, a label, the floor, or collapses
# the label spread fails the `verify` CI job (constitution P3).
# The valid scoring-schema verdicts + the real rubric dimensions, reused from the corpus itself.
valid_verdicts="meets partial fails"
rubric_dims="$(rows_under "$CORPUS" "scored rubric dimensions" | awk -F'|' '{ gsub(/^[ \t]+|[ \t]+$/, "", $3); print $3 }')"

cal_rows="$(awk '/^## / { insec = (index($0, "Judge calibration") > 0); next }
                 insec && /^\| CAL-/ { print }' "$CORPUS")"
cal_ids="$(printf '%s\n' "$cal_rows" | awk -F'|' '{ gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2 }' | grep -E '^CAL-')"
ncal="$(printf '%s\n' "$cal_ids" | grep -c .)"
ncaluniq="$(printf '%s\n' "$cal_ids" | sort -u | grep -c .)"

if [ "$ncal" -ge 2 ]; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  printf 'FAIL T806: parsed only %s calibration pairs (expected >= 2 — a matched-discrimination set)\n' "$ncal" >&2
fi
if [ "$ncal" -eq "$ncaluniq" ]; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  printf 'FAIL T806: calibration pair ids are not unique (%s rows, %s distinct)\n' "$ncal" "$ncaluniq" >&2
fi
if [ "$(printf '%s\n' "$cal_ids" | grep -vcE '^CAL-[0-9]+$')" -eq 0 ]; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  printf 'FAIL T806: a calibration pair id is not of the form CAL-<digits>\n' >&2
fi

# Per-row: owner label is a real scoring-schema verdict; dimension is a real rubric dimension.
n_meets=0; n_fails=0; cal_bad=0
while IFS= read -r crow; do
  [ -n "$crow" ] || continue
  cdim="$(printf  '%s' "$crow" | awk -F'|' '{ gsub(/^[ \t]+|[ \t]+$/, "", $3); print $3 }')"
  clabel="$(printf '%s' "$crow" | awk -F'|' '{ gsub(/^[ \t]+|[ \t]+$/, "", $4); print $4 }')"
  # the owner label must be one of meets/partial/fails
  if ! printf '%s\n' $valid_verdicts | grep -qxF -- "$clabel"; then
    printf 'FAIL T806: calibration owner label "%s" is not a scoring-schema verdict (meets/partial/fails)\n' "$clabel" >&2; cal_bad=1
  fi
  case "$clabel" in meets) n_meets=$((n_meets + 1)) ;; fails) n_fails=$((n_fails + 1)) ;; esac
  # the probed dimension must be a real corpus rubric dimension (referential integrity)
  if ! printf '%s\n' "$rubric_dims" | grep -qxF -- "$cdim"; then
    printf 'FAIL T806: calibration pair probes unknown rubric dimension "%s"\n' "$cdim" >&2; cal_bad=1
  fi
done <<EOF
$cal_rows
EOF

# The labels must SPAN the verdict range — at least one `meets` AND one `fails` — so a judge
# stuck at "always meets" or "always fails" scores below agreement instead of trivially high
# (the matched known-good/known-bad discrimination, mirrored from auditor-liveness).
if [ "$n_meets" -ge 1 ] && [ "$n_fails" -ge 1 ]; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  printf 'FAIL T806: calibration labels do not span the verdict range (meets=%s fails=%s — need >=1 of each)\n' "$n_meets" "$n_fails" >&2
fi
if [ "$cal_bad" -eq 0 ]; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  printf 'FAIL T806: calibration table has malformed or dangling rows (see above)\n' >&2
fi

# The stated agreement floor is a single number in [0,1], parseable from the section.
cal_floor="$(awk '/^## / { insec = (index($0, "Judge calibration") > 0); next } insec' "$CORPUS" \
  | grep -oE 'Agreement floor:[[:space:]]*`[0-9]+\.?[0-9]*`' | grep -oE '[0-9]+\.?[0-9]*' | head -1)"
if [ -n "$cal_floor" ] && awk -v f="$cal_floor" 'BEGIN { exit !(f >= 0 && f <= 1) }'; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  printf 'FAIL T806: no valid agreement floor in [0,1] stated under Judge calibration (got: %s)\n' "${cal_floor:-<none>}" >&2
fi

# Prose: the corpus declares the set is owner-labeled + the floor raises JUDGE-MISCALIBRATED.
check "T806 (corpus): the calibration set is owner-labeled + part of the frozen instrument" "$CORPUS_FLAT" \
  "owner-labeled calibration set"
check "T806 (corpus): the floor raises JUDGE-MISCALIBRATED in the read-only surfacing" "$CORPUS_FLAT" \
  "JUDGE-MISCALIBRATED"
check "T806 (corpus): the set is no longer reserved — it declares the frozen pairs" "$CORPUS_FLAT" \
  "The owner-labeled calibration pairs"

# Neutral doc: defines the agreement COMPUTATION (fraction of pairs matching the owner label)
# and that it is observe-only — never gates/retiers/alters the eval (P5).
check "T806 (neutral): the doc defines the agreement computation section" "$NEU_FLAT" \
  "The agreement computation"
check "T806 (neutral): agreement is the fraction of pairs whose judge verdict equals the owner label" "$NEU_FLAT" \
  "the fraction of pairs whose judge verdict equals the owner's label exactly"
check "T806 (neutral): the agreement figure is observe-only — never gates/retiers/alters the eval" "$NEU_FLAT" \
  "never** gates a run, retiers a model, alters a score"
check "T806 (neutral): below-floor surfaces as JUDGE-MISCALIBRATED, a warning not an action" "$NEU_FLAT" \
  "JUDGE-MISCALIBRATED"
check "T806 (neutral): the set/labels/floor belong to the eval-instrument fingerprint (US1.AC3)" "$NEU_FLAT" \
  "they belong to the eval-instrument fingerprint"

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
# PR #164 (Codex P2): the maker-behavior fingerprint spans all maker tiers, so a default run
# must cover every tier (else clearing MAKER-EVAL-STALE certifies a tier it never scored), and
# each record names the tier it scored (the second completeness axis, enforced by the emitter).
check "US2.AC1: binding's default run covers every maker tier (PR #164)" "$SKILL_FLAT" \
  "targets **every** maker tier"
check "US2.AC1: binding records the maker tier on each result (--tier)" "$SKILL_FLAT" \
  "--tier <maker-tier>"
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

# ── US3.AC1 (T807) — the trajectory-measurement contract in the neutral doc, and the ──────
# cadence declared by the frozen instrument. The behavioral mechanism tests live in
# maker-eval-emit.test.sh (US3.AC2); these pin the DOC obligations so a later edit that
# drops one — the silent-to-the-run law, the no-maker-visible-score boundary, the explicit
# two-sided trajectory-incomplete marking, the instrument-declared cadence — fails verify.
check "US3.AC1: the neutral doc defines trajectory measurement" "$NEU_FLAT" \
  "## Trajectory measurement"
check "US3.AC1: snapshots follow the instrument-declared cadence" "$NEU_FLAT" \
  "the cadence the frozen instrument declares"
check "US3.AC1: capture is silent-to-the-run" "$NEU_FLAT" \
  "never blocks, fails, or alters the maker's run"
check "US3.AC1: no snapshot-derived score reaches a maker-visible surface" "$NEU_FLAT" \
  "No snapshot-derived score reaches any maker-visible surface"
check "US3.AC1: trajectory-incomplete is marked explicitly, never silently" "$NEU_FLAT" \
  "Trajectory-incomplete is marked explicitly, never silently"
check "US3.AC1: the marking is two-sided (a sub-interval run is not marked)" "$NEU_FLAT" \
  "a genuinely sub-interval run (shorter than one declared interval) is **not** marked"
check "US3.AC1: trajectory storage is distinct from packet storage (the fence can scope to it)" "$NEU_FLAT" \
  "trajectory storage distinct from the packet storage"
check "US3.AC1: the corpus manifest declares the snapshot cadence as frozen instrument" "$CORPUS_FLAT" \
  "## Snapshot cadence (trajectory capture — part of the frozen instrument)"
# Structural: the cadence parses to a positive whole number under the "## Snapshot cadence"
# section — the same single-source parse the mechanism uses (a prose-only declaration the
# parser cannot read would leave every run a loud cadence error).
cadence_val="$(awk '/^## / { insec = (index($0, "Snapshot cadence") > 0); next } insec' "$CORPUS" \
  | grep -oE 'Snapshot cadence:[[:space:]]*`[0-9]+`' | grep -oE '[0-9]+' | head -1)"
if [ -n "$cadence_val" ] && [ "$cadence_val" -gt 0 ]; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  printf 'FAIL US3.AC1: no positive parseable snapshot cadence in the corpus manifest (got: %s)\n' \
    "${cadence_val:-<none>}" >&2
fi

# ── US3.AC3/AC4 (T808) — post-hoc grading + the versioned trajectory extension. The ───────
# mechanism tests live in maker-eval-emit.test.sh (grade-snapshots, record --trajectory) and
# maker-eval-fence.test.sh (the trajectory-storage fence extension); these pin the DOC
# obligations — the same-rubric post-hoc grading, the explicit instrument version, the
# version-keyed INSTRUMENT-CHANGED comparability in the surfacing — so a later edit that
# drops one fails verify.
check "US3.AC3: the pinned judge grades each snapshot against the same per-task rubric" "$NEU_FLAT" \
  "pinned judge grades each captured snapshot against the same per-task rubric"
check "US3.AC3: per-interval scores extend the (task × tier) record" "$NEU_FLAT" \
  "per-(corpus task × maker tier) record"
check "US3.AC3: the extension carries an explicit trajectory instrument version" "$NEU_FLAT" \
  "explicit trajectory instrument version"
check "US3.AC3: a version/schema change moves the eval-instrument fingerprint (P4)" "$NEU_FLAT" \
  "moves the eval-instrument fingerprint"
check "US3.AC3: cross-version trajectories render INSTRUMENT-CHANGED / not-comparable" "$NEU_FLAT" \
  "INSTRUMENT-CHANGED / not-comparable"
check "US3.AC3: the violation clause is stated (differenced bump / fingerprint-less schema change)" "$NEU_FLAT" \
  "A version bump that still gets differenced, or a trajectory-schema change that moves no fingerprint, each violates this"
check "US3.AC3: the corpus manifest declares trajectory grading as frozen instrument" "$CORPUS_FLAT" \
  "## Trajectory grading (post-hoc snapshot scoring — part of the frozen instrument)"
# Structural: the trajectory instrument version parses to a positive whole number under the
# "## Trajectory grading" section — the same single-source parse the emitter uses (a
# prose-only declaration would leave every --trajectory record a loud version error).
traj_ver="$(awk '/^## / { insec = (index($0, "Trajectory grading") > 0); next } insec' "$CORPUS" \
  | grep -oE 'Trajectory instrument version:[[:space:]]*`[0-9]+`' | grep -oE '[0-9]+' | head -1)"
if [ -n "$traj_ver" ] && [ "$traj_ver" -gt 0 ]; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  printf 'FAIL US3.AC3: no positive parseable trajectory instrument version in the corpus manifest (got: %s)\n' \
    "${traj_ver:-<none>}" >&2
fi
# The read-only surfacing (triage) is version-keyed: per-interval scores are differenced
# only under matching recorded versions, and a mismatch suppresses the differential.
TRIAGE_DOC="$DIR/workflow/triage.md"
TRIAGE_FLAT="$(flat "$TRIAGE_DOC")"
check "US3.AC3: triage differences trajectories only under matching versions" "$TRIAGE_FLAT" \
  "a trajectory and their recorded versions match exactly"
check "US3.AC3: triage renders the version mismatch as INSTRUMENT-CHANGED (suppressed)" "$TRIAGE_FLAT" \
  "trajectory instrument versions differ"
# ...and the version is NOT the gate on its own (PR #290 review): the trajectory
# differential additionally requires the fingerprint-comparable pair — a cadence-only or
# judge change moves a fingerprint component without bumping the trajectory version, and
# such a pair's trajectory differential must be suppressed like the regression call.
check "US3.AC3: triage's trajectory differential requires the fingerprint-comparable pair" "$TRIAGE_FLAT" \
  "comparable under the JUDGE-CHANGED / INSTRUMENT-CHANGED rule above — matching judge-identity and eval-instrument fingerprint components"
check "US3.AC3: triage names the cadence-only confound the version cannot catch" "$TRIAGE_FLAT" \
  "cadence-only instrument change moves eval-instrument while the trajectory version stays put"
check "US3.AC3: the template carries the fingerprint-suppressed trajectory state" "$TRIAGE_FLAT" \
  "judge or eval-instrument fingerprint moved between the two runs; trajectory differential suppressed"
check "US3.AC3: the neutral doc requires fingerprint comparability for the trajectory differential" "$NEU_FLAT" \
  "matching judge-identity and eval-instrument components — and their recorded trajectory instrument versions match"
check "US3.AC3: the neutral doc's violation clause covers the fingerprint-moved pair" "$NEU_FLAT" \
  "as does a trajectory differential reported on a pair whose judge or eval-instrument fingerprint moved"
check "US3.AC3: the corpus manifest states the fingerprint condition beside the version" "$CORPUS_FLAT" \
  "only when the pair's judge-identity and eval-instrument fingerprint components are unmoved"
TRIAGE_SKILL="$DIR/skills/triage/SKILL.md"
TRIAGE_SKILL_FLAT="$(flat "$TRIAGE_SKILL")"
check "US3.AC3: the triage binding gates the trajectory differential on the fingerprint pair" "$TRIAGE_SKILL_FLAT" \
  "matching \`fingerprint.judge_identity\` and \`fingerprint.eval_instrument\`"

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
