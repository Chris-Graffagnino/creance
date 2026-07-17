#!/usr/bin/env bash
# maker-eval-emit.sh — the maker-eval record + transcript-packet emitter (T802,
# spec 003 US1.AC2 + US1.AC3). The runtime-neutral docs froze the instrument and
# defined the record/packet/fingerprint SHAPE (`.claude/workflow/maker-eval.md`,
# `.claude/workflow/reviewers/maker-eval-corpus.md`); they defer the concrete
# JSONL/packet/hash mechanism to the adapter — "the emitter and its tests are the
# next task's (US1.AC2)". This is that mechanism. Adapter-side, so it may name
# concrete tools (jq, shasum, git) — it is NOT a `workflow/**` neutral doc.
#
# OBSERVE-ONLY (constitution P5). This script only READS the frozen instrument and
# APPENDS to the eval channel's own fenced path. It references no gate, tier, guard,
# or selection state and returns no value any such path consumes. A failed or partial
# write is silent-to-the-eval: a write failure never blocks, never errors, never
# alters the caller — mirroring the telemetry emitter (`guard.sh` → log_telemetry).
#
# Subcommands:
#   fingerprint
#       Print the TRIPLE FINGERPRINT (US1.AC3) as one compact JSON object with three
#       SEPARATELY-recorded, DISJOINT content-hash components, so a maker change, a
#       judge change, and an instrument change are each detectable as their OWN
#       movement and never conflated:
#         maker_behavior  — the maker model resolution (the maker tier rows of the
#                           model table) PLUS the instruction/runtime surfaces that
#                           shape its output: AGENTS.md (always-resident) + the
#                           methodology docs (workflow/**) + the adapter binding
#                           prompts (skills/**). EXCLUDES the eval machinery
#                           (maker-eval.md + the corpus manifest) so it stays disjoint
#                           from eval_instrument. NOT the model table alone (US1.AC3).
#         judge_identity  — the pinned-judge row of the model table, fixed independently
#                           of the maker tier rows (a maker swap never moves it).
#         eval_instrument — the frozen instrument manifest (corpus tasks + prompts,
#                           per-dimension lifecycle metadata, rubrics, judge prompt/spec,
#                           scoring schema, calibration set + labels + floor) — every
#                           artifact whose change alters interpretation/comparability.
#       Inputs are rooted at MAKER_EVAL_ROOT (default: the repo root) so a test can
#       point the recipe at a fixture tree.
#
#   record --run-id <id> --task <ME-id> --tier <maker-tier> --results <judge.json> \
#          [--prompt <f>] [--artifact <f>] [--judge <f>] [--trajectory <traj.json>]
#       Append EXACTLY ONE append-only JSONL record for one (corpus task × maker tier) to
#       <channel>/records.jsonl and store its transcript review packet under
#       <channel>/packets/<run-id>/<task-id>/<tier>/ (run id and task id must be safe path
#       components — no `/` or `..` — so neither the packet dir nor its in-record link can
#       escape the fenced channel; a violating id is a loud caller error). <maker-tier> is
#       the maker tier the run scored this task at (one of the model table's maker tiers —
#       a non-tier value is a loud caller error), recorded as `maker_tier` so `complete`
#       can verify every tier the maker-behavior fingerprint spans was exercised (PR #164;
#       spec 003 US2.AC1). The record carries the run id, the
#       corpus task id, the maker tier, the triple fingerprint, the per-dimension verdict/score
#       each tagged with its lifecycle (from <judge.json>), the overall verdict, the
#       first-upstream-failure class, a timestamp, and a RELATIVE packet link that
#       resolves only inside the fenced channel. <judge.json> is the judge's per-task
#       output: { dimensions:[{dimension,lifecycle,verdict,evidence}...], overall,
#       first_upstream_failure }. A MALFORMED judge output (no overall, or no rubric
#       dimension carrying dimension/lifecycle/verdict) is a loud caller error (exit 2,
#       nothing written) — never a silently-defaulted record a later `complete` would
#       count. A REQUESTED packet artifact (--prompt/--artifact/--judge) must copy in, or
#       the whole write aborts — a record never claims a packet file it lacks. Any other
#       write failure is silent (exit 0, nothing written).
#       --trajectory <traj.json> (T808, US3.AC3) extends the record with the post-hoc
#       per-interval snapshot scores: { intervals:[{interval,dimensions:[{dimension,
#       lifecycle,verdict,...}...],overall}...] }, landed as
#       trajectory:{instrument_version,intervals} inside the SAME (task × tier) record. The
#       version is the INSTRUMENT-DECLARED trajectory instrument version (the corpus
#       manifest -> "Trajectory grading" — frozen, fingerprinted, P4): a malformed
#       trajectory file, or an instrument declaring no version, is a loud caller error
#       (exit 2, nothing written) — never a silently-defaulted or version-less trajectory
#       the surfacing would difference across schemas.
#
#   grade-snapshots --run-id <id> --task <ME-id> --tier <maker-tier> --out <f> -- <judge-cmd...>
#       Post-hoc grading driver (T808, US3.AC3): enumerate the captured interval snapshots
#       under <channel>/trajectory/<run-id>/<task>/<tier>/ (numeric order; a discarded
#       `.tmp` is not a snapshot) and run <judge-cmd...> ONCE PER SNAPSHOT with that
#       snapshot's dir appended as the final argument, collecting each judge's stdout (one
#       judge output per interval, the `record` results shape) into --out as
#       { intervals:[{interval, dimensions, overall, ...}...] } for a subsequent
#       `record --trajectory` append. The RUN BINDING drives this so it never resolves the
#       channel or reads trajectory storage itself: the channel read happens HERE, inside
#       the fence-trusted writer, and the collected verdicts exist only to be appended to
#       the observe-only record — a write-pipeline read, unlike `complete`'s surfacing read
#       (maker-eval-fence.sh). Zero captured snapshots writes { intervals: [] } (exit 0 —
#       the caller then omits --trajectory). Malformed ids/tier, a missing or unwritable
#       --out (checked BEFORE the loop — a doomed out-path must not spend judge calls), a
#       missing judge command, or an unresolvable channel are loud caller errors (exit 2); a judge command
#       that fails or emits a malformed verdict is loud (exit 1, --out not written — and a
#       PRE-EXISTING --out is removed, so a rerun's failure can never leave a stale previous
#       trajectory for `record --trajectory` to consume) — a partial grading never
#       masquerades as the trajectory.
#
#   agreement --run-id <id> --verdicts <judge-cal.json>
#       Compute and APPEND the judge<->owner AGREEMENT figure for one run (T806, spec 003
#       US1.AC5). The frozen owner-labeled calibration set + its floor live in the corpus
#       manifest (reviewers/maker-eval-corpus.md -> "Judge calibration"); this reads the
#       owner label for each CAL-id and its stated floor from there, reads the judge's verdict
#       for each pair from <judge-cal.json> ({ verdicts:[{pair,verdict}...] }), and computes
#       AGREEMENT = (pairs whose judge verdict == owner label, exactly) / (total pairs). It
#       appends EXACTLY ONE observe-only run-scoped line
#       { record:"maker-eval-agreement", run_id, agreement, floor, matched, total, timestamp }
#       to <channel>/records.jsonl. OBSERVE-ONLY: the figure is calibration, never a gate — it
#       feeds no gate/tier/guard/selection path (the triage reader surfaces JUDGE-MISCALIBRATED
#       when agreement < floor; the P5 fence keeps the channel reader-scoped). A judge-verdicts
#       file that does not cover EVERY calibration pair (or a pair not in the frozen set) is a
#       loud caller error (exit 2, nothing written) — an agreement figure over a partial set
#       would be a silently-wrong calibration. Any other write failure is silent (exit 0).
#
#   complete --run-id <id>
#       Exit 0 + print "complete" iff every corpus task id has a record under <id> AT EVERY
#       maker tier in records.jsonl; else exit 3 + "incomplete (missing: <task>@<tier> ...)".
#       This is what the read-only surfacing uses so an INCOMPLETE run is never a comparable
#       baseline (US1.AC2): requiring the full (task × tier) grid means a single-tier run
#       cannot clear MAKER-EVAL-STALE while a changed cheap/frontier row went un-scored
#       (PR #164; spec 003 US2.AC1). A missing/empty stream is incomplete, never a silent baseline.
#       Only `record:"maker-eval"` lines count — a trajectory-incomplete marking (below) shares
#       the (run,task,tier) keys and must never stand in for a task's scored record.
#
#   snapshot-run --run-id <id> --task <ME-id> --tier <maker-tier> --workspace <dir> -- <cmd...>
#       Run the maker command (T807, spec 003 US3.AC1/AC2), capturing a snapshot of
#       <workspace> once per elapsed interval of the INSTRUMENT-DECLARED cadence — scheduled
#       against fixed boundaries from the run's start, so copy time never stretches the
#       sampling grid (the corpus
#       manifest's "Snapshot cadence" section — a frozen, fingerprinted value, P4) into the
#       channel's own trajectory storage, <channel>/trajectory/<run-id>/<task>/<tier>/
#       interval-<n>/, distinct from packets/ so the US3.AC4 fence extension can scope to it.
#       SILENT-TO-THE-RUN: the maker command's stdout/stderr pass through untouched and its
#       exit code is propagated EXACTLY; a failed or partial capture (and a failed marking
#       write) never blocks, errors, or alters it — each interval copies into a `.tmp` dir
#       and renames only on success, so a partial capture is discarded, never counted. No
#       snapshot-derived value reaches stdout: the subcommand returns only the maker
#       command's own output/exit (grading is post-hoc — US3.AC3, the next task's). A run
#       whose elapsed time spans >= 1 declared interval yet captured ZERO snapshots appends
#       one explicit observe-only `maker-eval-trajectory-incomplete` line (run id, task, tier,
#       cadence, intervals elapsed) to <channel>/records.jsonl — explicitly, never silently —
#       while a genuinely sub-interval run appends nothing (the two-sided marking, US3.AC2).
#       Malformed ids/tier, a missing workspace, or an undeclared/zero cadence are loud
#       caller errors (exit 2, the maker command NOT started); an unresolvable channel is a
#       write-path failure — the maker command still runs, un-snapshotted, exit propagated.
#
# Channel resolution (the fenced eval path), precedence:
#   1. MAKER_EVAL_DIR — test/override seam (mirrors GUARD_TELEMETRY_FILE);
#   2. the profile — .claude/PROJECT.md → "Paths" → "Maker-eval records": a concrete
#      backticked override path that is absolute or ~/-rooted (the channel is out-of-repo).
#      A <placeholder> value, a `*.md` doc pointer, or a bare relative sub-path name
#      (`packets/`, `records.jsonl`) is prose describing the default, not an override;
#   3. the shipped default — <home>/.claude/triage/<repo-basename>-maker-eval.
#
# Run: bash .claude/hooks/maker-eval-emit.sh <subcommand> [args]
# Tests: .claude/hooks/maker-eval-emit.test.sh (wired into CI verify).
set -u

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="${MAKER_EVAL_ROOT:-$(cd "$SELF_DIR/../.." && pwd)}"
CLAUDE_DIR="$ROOT/.claude"
MODELS="$CLAUDE_DIR/MODELS.md"
AGENTS="$ROOT/AGENTS.md"
WORKFLOW_DIR="$CLAUDE_DIR/workflow"
SKILLS_DIR="$CLAUDE_DIR/skills"
CORPUS="$WORKFLOW_DIR/reviewers/maker-eval-corpus.md"
PROFILE="${MAKER_EVAL_PROJECT_FILE:-$CLAUDE_DIR/PROJECT.md}"

usage() {
  printf 'usage: %s {fingerprint | record --run-id <id> --task <ME-id> --tier <maker-tier> --results <f> [--prompt <f>] [--artifact <f>] [--judge <f>] [--trajectory <f>] | agreement --run-id <id> --verdicts <f> | complete --run-id <id> | snapshot-run --run-id <id> --task <ME-id> --tier <maker-tier> --workspace <dir> -- <cmd...> | grade-snapshots --run-id <id> --task <ME-id> --tier <maker-tier> --out <f> -- <judge-cmd...>}\n' \
    "$(basename "$0")" >&2
}

# ── hashing ───────────────────────────────────────────────────────────────────
# A single content hash over stdin. shasum/sha256sum/git-hash-object all give a
# stable hex digest; only run-to-run stability on one machine matters (the
# fingerprint is only ever differenced against the same machine's prior runs).
hash_stdin() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | cut -d' ' -f1
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum | cut -d' ' -f1
  else
    git hash-object --stdin
  fi
}

# Emit path-tagged contents for each existing file read from stdin (one path per
# line). The path is recorded relative to ROOT so a rename is hash-visible; the
# unit-separator framing keeps two files' contents from blurring together.
emit_files_stdin() {
  local f
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    [ -f "$f" ] || continue
    printf '\037F\037%s\037\n' "${f#"$ROOT"/}"
    cat "$f"
    printf '\n'
  done
}

# The maker-behavior surface files: methodology (workflow/**) + adapter binding
# prompts (skills/**) + the always-resident AGENTS.md — EXCLUDING the eval machinery
# (maker-eval.md and the corpus manifest), which belong to eval_instrument, so the
# two components stay disjoint. Sorted for a deterministic, order-independent hash.
maker_surface_files() {
  {
    find "$WORKFLOW_DIR" -type f -name '*.md' \
      ! -name 'maker-eval.md' \
      ! -path '*/reviewers/maker-eval-corpus.md' 2>/dev/null
    find "$SKILLS_DIR" -type f -name '*.md' 2>/dev/null
    [ -f "$AGENTS" ] && printf '%s\n' "$AGENTS"
  } | LC_ALL=C sort -u
}

fp_maker_behavior() {
  {
    printf '\037MAKER-MODEL-ROWS\037\n'
    grep -E '^\|[[:space:]]*\*\*\[(frontier|strong|cheap) tier\]\*\*' "$MODELS" 2>/dev/null
    maker_surface_files | emit_files_stdin
  } | hash_stdin
}

fp_judge_identity() {
  {
    printf '\037JUDGE-ROW\037\n'
    grep -E 'maker-eval judge' "$MODELS" 2>/dev/null
  } | hash_stdin
}

fp_eval_instrument() {
  {
    printf '\037EVAL-INSTRUMENT\037\n'
    printf '%s\n' "$CORPUS" | emit_files_stdin
  } | hash_stdin
}

fingerprint_json() {
  jq -cn \
    --arg mb "$(fp_maker_behavior)" \
    --arg ji "$(fp_judge_identity)" \
    --arg ei "$(fp_eval_instrument)" \
    '{maker_behavior:$mb, judge_identity:$ji, eval_instrument:$ei}'
}

# ── channel resolution ──────────────────────────────────────────────────────────
repo_basename() {
  local r
  r="$(git -C "$ROOT" rev-parse --show-toplevel 2>/dev/null)" || r="$ROOT"
  printf '%s' "${r##*/}"
}

profile_channel() {
  # The channel is an OUT-OF-REPO directory, so a real override is absolute or ~/-rooted
  # (Windows drive paths too). The Paths row also carries prose that is NOT an override —
  # the doc pointer (`workflow/maker-eval.md`), a `<placeholder>` channel, and bare
  # sub-path names (`packets/`, `records.jsonl`). Take the first backticked, placeholder-
  # free, non-relative path; else empty (channel_dir then uses the shipped default).
  sed -n '/^[-*][[:space:]]*\*\*Maker-eval records:\*\*/,/^[-*#]/p' "$PROFILE" 2>/dev/null \
    | grep -oE '`[^`<]+`' | tr -d '`' | grep -E '^(/|~/|[A-Za-z]:)' | head -1
}

channel_dir() {
  if [ -n "${MAKER_EVAL_DIR:-}" ]; then
    printf '%s' "$MAKER_EVAL_DIR"
    return 0
  fi
  local home="${HOME:-${USERPROFILE:-}}" p
  p="$(profile_channel)"
  if [ -n "$p" ]; then
    case "$p" in
      "~/"*) [ -n "$home" ] || return 1; printf '%s/%s' "$home" "${p#\~/}" ;;
      /*|[a-zA-Z]:*) printf '%s' "$p" ;;
      *) printf '%s/%s' "$ROOT" "$p" ;;
    esac
    return 0
  fi
  [ -n "$home" ] || return 1
  printf '%s/.claude/triage/%s-maker-eval' "$home" "$(repo_basename)"
}

# ── corpus task ids (for completeness) ──────────────────────────────────────────
# The frozen corpus task ids, scoped to the "## The corpus tasks" table only (the
# rubric table references the same ids in another section). Same parse the docs test
# uses; '+' quantifiers only (no awk {n} interval — BSD/GNU portable, #97).
corpus_task_ids() {
  awk '/^## / { insec = (index($0, "The corpus tasks") > 0); next }
       insec && /^\| ME-/ { print }' "$CORPUS" 2>/dev/null \
    | awk -F'|' '{ gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2 }' \
    | grep -E '^ME-[0-9]+$'
}

# ── maker tier names (the second axis of completeness) ───────────────────────────
# The maker tier NAMES, parsed from the SAME model-table rows fp_maker_behavior hashes
# into maker_behavior (the `[frontier|strong|cheap] tier` rows). Kept in lockstep with the
# fingerprint surface so a complete run must cover EVERY tier the maker-behavior fingerprint
# spans: recording the all-tier fingerprint after exercising only one tier would let a default
# run clear MAKER-EVAL-STALE without re-scoring a changed cheap/frontier row (PR #164 Codex P2;
# spec 003 US2.AC1). Same `^|…**[<tier> tier]**` anchor as fp_maker_behavior's grep.
maker_tiers() {
  grep -E '^\|[[:space:]]*\*\*\[(frontier|strong|cheap) tier\]\*\*' "$MODELS" 2>/dev/null \
    | sed -E 's/.*\[(frontier|strong|cheap) tier\].*/\1/'
}

# ── calibration set + floor (for the agreement figure, T806 / US1.AC5) ───────────
# The owner-labeled calibration set is a frozen table under "## Judge calibration" in the
# corpus manifest: `| CAL-id | dimension | owner-label | scenario |`. Parse each pair's id
# and owner label, scoped to that section only (so the contract prose above it — which also
# names `meets`/`fails` — cannot leak a phantom pair). '+' quantifiers only (BSD/GNU portable,
# #97). Emits `CAL-id<TAB>label` lines; the agreement math reads the same file's floor below.
calibration_labels() {
  awk '/^## / { insec = (index($0, "Judge calibration") > 0); next }
       insec && /^\| CAL-/ { print }' "$CORPUS" 2>/dev/null \
    | awk -F'|' '{ id=$2; lab=$4;
                   gsub(/^[ \t]+|[ \t]+$/, "", id); gsub(/^[ \t]+|[ \t]+$/, "", lab);
                   if (id ~ /^CAL-[0-9]+$/) print id "\t" lab }'
}

# The stated agreement floor: the `Agreement floor: \`<n>\`` value under "## Judge calibration".
# A single frozen number in [0,1]; parsed from the section so the emitter and the read-only
# surfacing share one source. Empty if absent (the caller then aborts loudly — no silent floor).
calibration_floor() {
  awk '/^## / { insec = (index($0, "Judge calibration") > 0); next }
       insec' "$CORPUS" 2>/dev/null \
    | grep -oE 'Agreement floor:[[:space:]]*`[0-9]+\.?[0-9]*`' \
    | grep -oE '[0-9]+\.?[0-9]*' | head -1
}

# ── snapshot cadence (the instrument-declared interval, T807 / US3.AC1) ──────────
# The trajectory cadence is a frozen-instrument value: the `Snapshot cadence: \`<n>\``
# seconds under "## Snapshot cadence" in the corpus manifest — same single-source parse
# idiom as calibration_floor, so the mechanism can never sample at a rate the instrument
# (and its eval_instrument fingerprint) did not declare. Whole positive seconds; empty if
# absent (the caller then aborts loudly — never a silently-defaulted cadence).
snapshot_cadence() {
  awk '/^## / { insec = (index($0, "Snapshot cadence") > 0); next }
       insec' "$CORPUS" 2>/dev/null \
    | grep -oE 'Snapshot cadence:[[:space:]]*`[0-9]+`' \
    | grep -oE '[0-9]+' | head -1
}

# ── trajectory instrument version (the versioned schema key, T808 / US3.AC3) ─────
# The trajectory extension's comparability key: the `Trajectory instrument version:
# \`<n>\`` value under "## Trajectory grading" in the corpus manifest — the same
# single-source parse idiom as snapshot_cadence, so a record can never carry a version
# the fingerprinted instrument did not declare. Whole positive number; empty if absent
# (the caller then aborts loudly — never a silently-defaulted or version-less trajectory).
trajectory_version() {
  awk '/^## / { insec = (index($0, "Trajectory grading") > 0); next }
       insec' "$CORPUS" 2>/dev/null \
    | grep -oE 'Trajectory instrument version:[[:space:]]*`[0-9]+`' \
    | grep -oE '[0-9]+' | head -1
}

# ── record ──────────────────────────────────────────────────────────────────────
# A packet-path token (run_id/task_id) must be a single non-escaping path component, so
# neither the on-disk packet dir nor the in-record packet link can leave the fenced
# channel (US1.AC2 "packet artifacts never escape"). A `/`- or `..`-bearing id is rejected.
safe_token() { # <token> -> 0 iff a single non-escaping path component
  case "$1" in
    "" | "." )       return 1 ;;
    *"/"* | *".."* ) return 1 ;;
    * )              return 0 ;;
  esac
}

# A well-formed judge output (the record-schema contract, US1.AC2): a non-empty overall
# verdict plus at least one rubric dimension, each carrying its dimension/lifecycle/verdict.
# A malformed output (e.g. `{}`, or non-JSON) is rejected loudly so a garbled judge run can
# never default to a record that `complete` then counts as a baseline.
JUDGE_OUTPUT_FILTER='
    (.overall | type == "string") and (.overall | length > 0)
    and ((.dimensions // []) | type == "array")
    and ((.dimensions // []) | length > 0)
    and ((.dimensions // []) | all(.dimension != null and .lifecycle != null and .verdict != null))
'
results_valid() { # <results.json> -> 0 iff structurally a judge output
  jq -e "$JUDGE_OUTPUT_FILTER" "$1" >/dev/null 2>&1
}

# A well-formed trajectory file (the versioned schema extension, US3.AC3): an intervals
# ARRAY (empty is a caller error — a no-snapshot run simply omits --trajectory), each entry
# carrying a numeric interval, at least one rubric dimension with its
# dimension/lifecycle/verdict, and a non-empty overall — the same per-snapshot shape
# results_valid pins for the endpoint. Malformed is rejected loudly so a garbled grading
# can never land a trajectory the surfacing would then difference.
trajectory_valid() { # <traj.json> -> 0 iff EXACTLY ONE JSON document, structurally a per-interval grading output
  # Slurped (-s) and length-checked so the SAME document the record build embeds
  # ($traj[0]) is the one validated: a plain `jq -e` over the raw file grades only the
  # LAST document of a multi-document file while --slurpfile lands the FIRST — a crafted
  # two-document file would slip an invalid trajectory past validation (review of this PR).
  jq -es '
    (length == 1) and (.[0] |
      ((.intervals // null) | type == "array")
      and ((.intervals // []) | length > 0)
      and ((.intervals // []) | all(
        (.interval | type == "number")
        and ((.dimensions // []) | type == "array")
        and ((.dimensions // []) | length > 0)
        and ((.dimensions // []) | all(.dimension != null and .lifecycle != null and .verdict != null))
        and (.overall | type == "string") and (.overall | length > 0)
      )))
  ' "$1" >/dev/null 2>&1
}

do_record() {
  local run_id="" task_id="" tier="" results="" prompt_f="" artifact_f="" judge_f="" traj_f=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --run-id)     run_id="${2:-}"; shift 2 ;;
      --task)       task_id="${2:-}"; shift 2 ;;
      --tier)       tier="${2:-}"; shift 2 ;;
      --results)    results="${2:-}"; shift 2 ;;
      --prompt)     prompt_f="${2:-}"; shift 2 ;;
      --artifact)   artifact_f="${2:-}"; shift 2 ;;
      --judge)      judge_f="${2:-}"; shift 2 ;;
      # Guarded: a dangling --trajectory must be a loud usage error — an unguarded
      # `shift 2` leaves the arg list unchanged and spins the parser forever (the
      # do_agreement bug class; PR #290 review).
      --trajectory) [ "$#" -ge 2 ] || { usage; return 2; }; traj_f="$2"; shift 2 ;;
      *) usage; return 2 ;;
    esac
  done
  # Missing required args are a CALLER error (not a write failure): fail loud.
  if [ -z "$run_id" ] || [ -z "$task_id" ] || [ -z "$tier" ] || [ -z "$results" ]; then
    usage; return 2
  fi
  if ! safe_token "$run_id" || ! safe_token "$task_id"; then
    printf 'maker-eval-emit: run id and task id must be safe path components (no "/" or ".."): run-id=[%s] task=[%s]\n' \
      "$run_id" "$task_id" >&2
    return 2
  fi
  # The maker tier the run scored this task at must be a REAL maker tier (the rows the
  # maker-behavior fingerprint spans), so `complete` can verify every tier was exercised and
  # a typo cannot silently leave a run forever-incomplete. A loud caller error, not a write
  # failure (PR #164; spec 003 US2.AC1).
  if ! maker_tiers | grep -qxF -- "$tier"; then
    printf 'maker-eval-emit: --tier must be a maker tier (%s): got [%s]\n' \
      "$(maker_tiers | tr '\n' ' ')" "$tier" >&2
    return 2
  fi
  if [ ! -f "$results" ]; then
    printf 'maker-eval-emit: results file not found: %s\n' "$results" >&2
    return 2
  fi
  if ! results_valid "$results"; then
    printf 'maker-eval-emit: results file is not a well-formed judge output: %s\n' "$results" >&2
    return 2
  fi
  # A REQUESTED trajectory extension must be well-formed AND versioned by the instrument
  # (US3.AC3): both failures are loud CALLER errors — a version-less or garbled trajectory
  # must never land in a record the surfacing would difference across schemas.
  local traj_version=""
  if [ -n "$traj_f" ]; then
    if [ ! -f "$traj_f" ]; then
      printf 'maker-eval-emit: trajectory file not found: %s\n' "$traj_f" >&2
      return 2
    fi
    if ! trajectory_valid "$traj_f"; then
      printf 'maker-eval-emit: trajectory file is not a well-formed per-interval grading output: %s\n' "$traj_f" >&2
      return 2
    fi
    traj_version="$(trajectory_version)"
    if [ -z "$traj_version" ]; then
      printf 'maker-eval-emit: no trajectory instrument version declared by the instrument (%s -> "Trajectory grading")\n' "$CORPUS" >&2
      return 2
    fi
  fi

  # From here every failure is a WRITE failure: silent-to-the-eval (exit 0, nothing
  # written, caller unaffected). The fingerprint, timestamp, and record are built
  # first; the channel write is wrapped so any failure returns 0 before the success
  # print, so a partial write is never reported as a landed record.
  local channel fp ts repo packet_rel rec failure
  channel="$(channel_dir)" || return 0
  [ -n "$channel" ] || return 0
  fp="$(fingerprint_json)" || return 0
  [ -n "$fp" ] || return 0
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)" || return 0
  repo="$(repo_basename)"
  # Tier-scoped packet dir: a run records one (task × tier) per record, so the packet path
  # carries the tier too — else two tiers' packets for one task collide. `tier` is validated
  # above as a maker-tier name (a safe single component), so the path cannot escape.
  packet_rel="packets/$run_id/$task_id/$tier"
  failure="$(jq -r '.first_upstream_failure // "none"' "$results" 2>/dev/null)" || failure="none"

  # The trajectory extension rides the SAME jq build: slurped from the validated file (an
  # absent --trajectory slurps /dev/null -> [], and the empty $tv keys the omission), so
  # the record lands atomically with or without its trajectory — never a second write.
  rec="$(jq -c \
    --arg ts "$ts" --arg repo "$repo" --arg run "$run_id" --arg task "$task_id" \
    --arg tier "$tier" --argjson fp "$fp" --arg packet "$packet_rel" \
    --arg tv "$traj_version" --slurpfile traj "${traj_f:-/dev/null}" \
    '{record:"maker-eval", timestamp:$ts, repo:$repo, run_id:$run, task_id:$task,
      maker_tier:$tier,
      fingerprint:$fp,
      dimensions:(.dimensions // []),
      overall:(.overall // "fail"),
      first_upstream_failure:(.first_upstream_failure // "none"),
      packet:$packet}
     + (if $tv == "" then {}
        else {trajectory:{instrument_version:($tv|tonumber),
                          intervals:$traj[0].intervals}} end)' \
    "$results" 2>/dev/null)" || return 0
  [ -n "$rec" ] || return 0

  {
    mkdir -p "$channel/$packet_rel" || return 0
    # A REQUESTED packet artifact must land, or the whole write aborts silently — a record
    # never claims a packet file it lacks. cp itself fails on a missing/unreadable source,
    # so the copy (not a prior [ -f ] probe) is the gate.
    [ -z "$prompt_f" ]   || cp "$prompt_f"   "$channel/$packet_rel/prompt.txt"       || return 0
    [ -z "$artifact_f" ] || cp "$artifact_f" "$channel/$packet_rel/artifact.txt"     || return 0
    [ -z "$judge_f" ]    || cp "$judge_f"    "$channel/$packet_rel/judge-report.md"  || return 0
    printf '%s\n' "$failure" > "$channel/$packet_rel/first-upstream-failure.txt" || return 0
    printf '%s\n' "$rec" >> "$channel/records.jsonl" || return 0
  } 2>/dev/null || return 0

  printf '%s\n' "$rec"
}

# ── agreement (the judge<->owner calibration figure, T806 / US1.AC5) ─────────────
do_agreement() {
  local run_id="" verdicts=""
  # A dangling option (a flag with no value) is a loud usage error: an unguarded `shift 2`
  # on a 1-element list leaves the list unchanged and the loop spins forever.
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --run-id)   [ "$#" -ge 2 ] || { usage; return 2; }; run_id="$2"; shift 2 ;;
      --verdicts) [ "$#" -ge 2 ] || { usage; return 2; }; verdicts="$2"; shift 2 ;;
      *) usage; return 2 ;;
    esac
  done
  # Missing required args / a hostile run id are CALLER errors: fail loud (like `record`).
  if [ -z "$run_id" ] || [ -z "$verdicts" ]; then usage; return 2; fi
  if ! safe_token "$run_id"; then
    printf 'maker-eval-emit: run id must be a safe path component (no "/" or ".."): run-id=[%s]\n' "$run_id" >&2
    return 2
  fi
  if [ ! -f "$verdicts" ]; then
    printf 'maker-eval-emit: verdicts file not found: %s\n' "$verdicts" >&2
    return 2
  fi
  # The judge-verdicts file must be a { verdicts:[{pair,verdict}...] } object — a malformed
  # shape is a loud caller error, never a silently-defaulted agreement.
  if ! jq -e '((.verdicts // null) | type == "array")
              and ((.verdicts // []) | all(.pair != null and .verdict != null))' \
        "$verdicts" >/dev/null 2>&1; then
    printf 'maker-eval-emit: verdicts file is not a well-formed { verdicts:[{pair,verdict}...] } object: %s\n' "$verdicts" >&2
    return 2
  fi
  # Every judge verdict must be a scoring-schema value (`meets`/`partial`/`fails` — the corpus
  # manifest's per-dimension verdicts). A non-schema verdict is a loud caller error, never a
  # silently-counted disagreement that would skew the figure.
  if ! jq -e '(.verdicts // []) | all(.verdict | IN("meets","partial","fails"))' \
        "$verdicts" >/dev/null 2>&1; then
    printf 'maker-eval-emit: every judge verdict must be a scoring-schema value (meets|partial|fails): %s\n' "$verdicts" >&2
    return 2
  fi

  # Read the frozen owner labels + floor from the corpus manifest (the single source). A run
  # with no parseable calibration set or no stated floor cannot compute an honest agreement —
  # a loud caller error, not a defaulted figure.
  local labels floor total matched
  labels="$(calibration_labels)"
  floor="$(calibration_floor)"
  if [ -z "$labels" ]; then
    printf 'maker-eval-emit: no owner-labeled calibration pairs parsed from %s\n' "$CORPUS" >&2
    return 2
  fi
  if [ -z "$floor" ]; then
    printf 'maker-eval-emit: no agreement floor parsed from %s\n' "$CORPUS" >&2
    return 2
  fi

  # Agreement = (pairs whose judge verdict == owner label, exactly) / (total frozen pairs).
  # EVERY frozen pair must have exactly one judge verdict, and every judge verdict must name a
  # frozen pair — an agreement over a partial or extraneous set would be a silently-wrong
  # calibration, so either is a loud caller error (nothing written).
  total=0; matched=0
  local cal_id owner_label judge_verdict n_for_pair pair
  # (a) every judge-verdict pair id must be a known calibration id (no extraneous pairs).
  while IFS= read -r pair; do
    [ -n "$pair" ] || continue
    if ! printf '%s\n' "$labels" | cut -f1 | grep -qxF -- "$pair"; then
      printf 'maker-eval-emit: judge verdict names unknown calibration pair: %s\n' "$pair" >&2
      return 2
    fi
  done <<EOF
$(jq -r '.verdicts[].pair' "$verdicts" 2>/dev/null)
EOF
  # (b) every frozen pair must have exactly one judge verdict, matched exactly against the label.
  while IFS="$(printf '\t')" read -r cal_id owner_label; do
    [ -n "$cal_id" ] || continue
    total=$((total + 1))
    n_for_pair="$(jq -r --arg p "$cal_id" '[.verdicts[] | select(.pair == $p)] | length' "$verdicts" 2>/dev/null)"
    if [ "${n_for_pair:-0}" -ne 1 ]; then
      printf 'maker-eval-emit: calibration pair %s must have exactly one judge verdict (got %s)\n' "$cal_id" "${n_for_pair:-0}" >&2
      return 2
    fi
    judge_verdict="$(jq -r --arg p "$cal_id" 'first(.verdicts[] | select(.pair == $p) | .verdict)' "$verdicts" 2>/dev/null)"
    [ "$judge_verdict" = "$owner_label" ] && matched=$((matched + 1))
  done <<EOF
$labels
EOF
  if [ "$total" -eq 0 ]; then
    printf 'maker-eval-emit: no calibration pairs to score\n' >&2
    return 2
  fi

  # From here every failure is a WRITE failure: silent-to-the-eval (exit 0, nothing written),
  # exactly as `record` and the telemetry emitter do — the eval is observe-only.
  local channel ts repo rec
  channel="$(channel_dir)" || return 0
  [ -n "$channel" ] || return 0
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)" || return 0
  repo="$(repo_basename)"
  # jq computes agreement = matched/total itself, so the fraction is a CANONICAL JSON number
  # (8/8 -> 1, 2/4 -> 0.5) with no locale-decimal or trailing-zero variance across jq versions
  # or awk locales (the old `awk "%.4f"` emitted `1.0000`, which some jq builds preserved rather
  # than normalized). `matched`/`total` are plain shell integers; jq divides.
  rec="$(jq -c \
    --arg ts "$ts" --arg repo "$repo" --arg run "$run_id" \
    --argjson floor "$floor" \
    --argjson matched "$matched" --argjson total "$total" \
    -n '{record:"maker-eval-agreement", timestamp:$ts, repo:$repo, run_id:$run,
         agreement:(if $total > 0 then $matched / $total else 0 end),
         floor:$floor, matched:$matched, total:$total}' \
    2>/dev/null)" || return 0
  [ -n "$rec" ] || return 0

  {
    mkdir -p "$channel" || return 0
    printf '%s\n' "$rec" >> "$channel/records.jsonl" || return 0
  } 2>/dev/null || return 0

  printf '%s\n' "$rec"
}

# ── complete ──────────────────────────────────────────────────────────────────
# Only `record:"maker-eval"` lines count: the trajectory-incomplete marking (T807) shares
# the (run_id, task_id, maker_tier) keys, so without the kind filter a marked-but-unscored
# task would satisfy the completeness grid — an incomplete run silently promoted to baseline.
record_present() { # <records-file> <run-id> <task-id> <tier>
  [ -f "$1" ] || return 1
  local n
  n="$(jq -c --arg r "$2" --arg t "$3" --arg k "$4" \
        'select(.record == "maker-eval" and .run_id == $r and .task_id == $t and .maker_tier == $k)' "$1" 2>/dev/null | grep -c .)"
  [ "${n:-0}" -gt 0 ]
}

do_complete() {
  local run_id=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --run-id) run_id="${2:-}"; shift 2 ;;
      *) usage; return 2 ;;
    esac
  done
  [ -n "$run_id" ] || { usage; return 2; }

  # A run is a comparable baseline only when it has re-scored every corpus task at EVERY
  # maker tier — the second completeness axis (PR #164; spec 003 US2.AC1). The all-tier
  # maker_behavior fingerprint a record stamps is honest only if the run that recorded it
  # exercised all tiers, so `complete` requires the full (task × tier) grid; a single-tier
  # (or scoped-task) run never reaches it and is never a silent baseline.
  local channel ids tiers missing="" tid k
  channel="$(channel_dir)" || { printf 'incomplete (channel unresolved)\n'; return 3; }
  ids="$(corpus_task_ids)"
  if [ -z "$ids" ]; then
    printf 'incomplete (no corpus tasks parsed)\n'
    return 3
  fi
  tiers="$(maker_tiers)"
  if [ -z "$tiers" ]; then
    printf 'incomplete (no maker tiers parsed)\n'
    return 3
  fi
  # Task ids (ME-NN) and tier names (frontier/strong/cheap) carry no whitespace or glob
  # metacharacters, so word-splitting the two lists is safe and avoids nested heredocs.
  for tid in $ids; do
    for k in $tiers; do
      record_present "$channel/records.jsonl" "$run_id" "$tid" "$k" || missing="$missing $tid@$k"
    done
  done
  if [ -z "$missing" ]; then
    printf 'complete\n'
    return 0
  fi
  printf 'incomplete (missing:%s)\n' "$missing"
  return 3
}

# ── snapshot-run (interval trajectory capture, T807 / US3.AC1+AC2) ───────────────
# One interval's capture: copy the workspace into a `.tmp` dir and RENAME to
# interval-<n> only when the whole copy landed, so a partial capture (a mid-copy kill
# when the maker command exits, a full disk) is discarded, never counted as a snapshot.
# VCS internals are excluded — the snapshot is the working tree the judge will grade,
# not the repository object store. Silent on every failure (the run is observe-only).
snapshot_capture() { # <traj-dir> <n> <workspace>
  local dest="$1/interval-$2" tmp="$1/interval-$2.tmp"
  {
    [ -e "$dest" ] && return 0
    mkdir -p "$tmp" || return 0
    # The copy runs BACKGROUNDED and reaped via `wait` so the capture loop's TERM trap can
    # fire mid-copy (a trap on a foreground child is deferred until it finishes) and kill
    # the copy rather than orphan it past snapshot-run's return; `tmp_inflight` lets the
    # trap discard the partial tree the killed copy leaves (PR #288 review).
    tmp_inflight="$tmp"
    cp -R "$3/." "$tmp/" & child=$!
    if ! wait "$child"; then child=""; tmp_inflight=""; rm -rf "$tmp"; return 0; fi
    child=""
    rm -rf "$tmp/.git"
    mv "$tmp" "$dest" || rm -rf "$tmp"
    tmp_inflight=""
  } 2>/dev/null
  return 0
}

do_snapshot_run() {
  local run_id="" task_id="" tier="" ws=""
  # Dangling options are loud usage errors (the do_agreement guarded-shift idiom); `--`
  # ends the options and everything after it is the maker command, untouched.
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --run-id)    [ "$#" -ge 2 ] || { usage; return 2; }; run_id="$2"; shift 2 ;;
      --task)      [ "$#" -ge 2 ] || { usage; return 2; }; task_id="$2"; shift 2 ;;
      --tier)      [ "$#" -ge 2 ] || { usage; return 2; }; tier="$2"; shift 2 ;;
      --workspace) [ "$#" -ge 2 ] || { usage; return 2; }; ws="$2"; shift 2 ;;
      --)          shift; break ;;
      *) usage; return 2 ;;
    esac
  done
  # Everything below `usage/return 2` is a CALLER error, checked BEFORE the maker command
  # starts — loud, nothing run, nothing written. From the moment the command starts, every
  # failure is a WRITE failure: silent-to-the-run (US3.AC1).
  if [ -z "$run_id" ] || [ -z "$task_id" ] || [ -z "$tier" ] || [ -z "$ws" ] || [ "$#" -eq 0 ]; then
    usage; return 2
  fi
  if ! safe_token "$run_id" || ! safe_token "$task_id"; then
    printf 'maker-eval-emit: run id and task id must be safe path components (no "/" or ".."): run-id=[%s] task=[%s]\n' \
      "$run_id" "$task_id" >&2
    return 2
  fi
  if ! maker_tiers | grep -qxF -- "$tier"; then
    printf 'maker-eval-emit: --tier must be a maker tier (%s): got [%s]\n' \
      "$(maker_tiers | tr '\n' ' ')" "$tier" >&2
    return 2
  fi
  if [ ! -d "$ws" ]; then
    printf 'maker-eval-emit: workspace is not a directory: %s\n' "$ws" >&2
    return 2
  fi
  # The cadence is INSTRUMENT-DECLARED (US3.AC1): an instrument that declares none (or a
  # zero interval) cannot honestly sample a trajectory — a loud caller error, never a
  # silently-defaulted rate the eval_instrument fingerprint knows nothing about.
  local cadence
  cadence="$(snapshot_cadence)"
  if [ -z "$cadence" ] || [ "$cadence" -eq 0 ]; then
    printf 'maker-eval-emit: no positive snapshot cadence declared by the instrument (%s -> "Snapshot cadence")\n' "$CORPUS" >&2
    return 2
  fi

  # An unresolvable channel is a WRITE-path failure, not a caller error: the maker command
  # still runs (silent-to-the-run), just un-snapshotted, its exit code propagated.
  local channel="" traj="" looppid="" wakes_f=""
  channel="$(channel_dir)" || channel=""
  if [ -n "$channel" ]; then
    traj="$channel/trajectory/$run_id/$task_id/$tier"
    # The loop's wake tally IS the elapsed-interval clock for the marking below: one byte
    # per cadence wake, written by the same sleeps that drive capture, so "the run spanned
    # an interval" and "a capture was due" can never disagree. A second wall clock (whole-
    # second arithmetic) could tick across a sub-interval run's boundary and mark a run
    # that never reached its first capture. Scratch file, never inside the channel (the
    # blocked-channel marking case must still be able to count wakes); if mktemp fails the
    # tally degrades to zero — marking silently never fires, a write-path degradation.
    wakes_f="$(mktemp 2>/dev/null)" || wakes_f=""
    # The capture loop: one snapshot per elapsed cadence interval, in the background so the
    # maker command's own timing is untouched. Killed the moment the command exits.
    #
    # Wakes are scheduled against FIXED cadence boundaries derived from the loop start
    # (t0 + i*cadence), never a fresh full-cadence sleep after each copy — otherwise a copy
    # taking measurable time stretches the sampling grid to cadence+copy_duration and
    # silently drops trajectory samples (PR #288 review). A boundary already past when its
    # turn comes (a copy overran it) sleeps zero and is captured late rather than skipped,
    # so every elapsed boundary is accounted — one wake tick and one capture attempt each.
    # The FIRST wake is a plain full-cadence sleep (t0 is whole-second wall time, so a
    # t0-derived first deadline could fire up to 1s early and tick a wake on a genuinely
    # sub-interval run — the exact false marking the wake tally exists to prevent); from
    # boundary 2 on, <=1s of wall-clock truncation only jitters capture timing, never the
    # tally's sub-interval judgement. The sleep is backgrounded and reaped via `wait` so
    # the TERM trap fires immediately (never after a full pending cadence), kills the
    # active child — the sleep, or via snapshot_capture the in-flight copy — and discards
    # the partial `.tmp`; the parent's kill would otherwise orphan them past return.
    ( child="" tmp_inflight=""
      trap '[ -n "$child" ] && { kill "$child"; wait "$child"; } 2>/dev/null
            [ -z "$tmp_inflight" ] || rm -rf "$tmp_inflight"
            exit 0' TERM
      t0="$(date +%s)"
      i=1
      while :; do
        if [ "$i" -eq 1 ]; then rem="$cadence"
        else
          rem=$(( t0 + i * cadence - $(date +%s) ))
          [ "$rem" -gt 0 ] || rem=0
        fi
        sleep "$rem" & child=$!
        wait "$child" || exit 0
        child=""
        [ -z "$wakes_f" ] || printf '.' >> "$wakes_f"
        snapshot_capture "$traj" "$i" "$ws"
        i=$((i + 1))
      done ) 2>/dev/null &
    looppid=$!
  fi

  local rc
  "$@"
  rc=$?
  if [ -n "$looppid" ]; then
    kill "$looppid" 2>/dev/null
    wait "$looppid" 2>/dev/null
  fi

  # The two-sided trajectory-incomplete marking (US3.AC1/AC2): a run spanning >= 1 declared
  # interval (>= 1 loop wake) with ZERO captured snapshots is recorded explicitly — "no
  # snapshots" must never masquerade as "no intervals elapsed" — while a genuinely
  # sub-interval run (the loop never woke) appends nothing. Counts only RENAMED interval
  # dirs (a discarded .tmp is not a snapshot). The marking itself is an observe-only
  # append: its write failure is silent, and `complete` never counts it as a scored record
  # (record_present filters on record:"maker-eval").
  local intervals=0
  if [ -n "$wakes_f" ]; then
    intervals="$(wc -c < "$wakes_f" 2>/dev/null | tr -d '[:space:]')"
    rm -f "$wakes_f" 2>/dev/null
  fi
  if [ -n "$channel" ] && [ "${intervals:-0}" -ge 1 ]; then
    local captured ts repo marker
    captured="$(find "$traj" -maxdepth 1 -type d -name 'interval-*' ! -name '*.tmp' 2>/dev/null | grep -c .)"
    if [ "${captured:-0}" -eq 0 ]; then
      {
        ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
          && repo="$(repo_basename)" \
          && marker="$(jq -cn \
               --arg ts "$ts" --arg repo "$repo" --arg run "$run_id" --arg task "$task_id" \
               --arg tier "$tier" --argjson cad "$cadence" --argjson iv "$intervals" \
               '{record:"maker-eval-trajectory-incomplete", timestamp:$ts, repo:$repo,
                 run_id:$run, task_id:$task, maker_tier:$tier,
                 cadence_seconds:$cad, intervals_elapsed:$iv, snapshots:0}')" \
          && [ -n "$marker" ] \
          && mkdir -p "$channel" \
          && printf '%s\n' "$marker" >> "$channel/records.jsonl"
      } 2>/dev/null || :
    fi
  fi
  return "$rc"
}

# ── grade-snapshots (post-hoc trajectory grading driver, T808 / US3.AC3) ─────────
# The channel's trajectory read happens HERE, inside the fence-trusted writer, so the run
# binding can drive post-hoc grading without ever resolving the channel or reading the
# trajectory storage itself (maker-eval-fence.sh — a write-pipeline read, unlike
# `complete`'s surfacing read: the collected verdicts exist only to be appended back via
# `record --trajectory`). This is post-run tooling with no maker command to protect, so
# unlike snapshot-run its failures are LOUD: a partial or garbled grading must never
# masquerade as the trajectory.
do_grade_snapshots() {
  local run_id="" task_id="" tier="" out=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --run-id) [ "$#" -ge 2 ] || { usage; return 2; }; run_id="$2"; shift 2 ;;
      --task)   [ "$#" -ge 2 ] || { usage; return 2; }; task_id="$2"; shift 2 ;;
      --tier)   [ "$#" -ge 2 ] || { usage; return 2; }; tier="$2"; shift 2 ;;
      --out)    [ "$#" -ge 2 ] || { usage; return 2; }; out="$2"; shift 2 ;;
      --)       shift; break ;;
      *) usage; return 2 ;;
    esac
  done
  if [ -z "$run_id" ] || [ -z "$task_id" ] || [ -z "$tier" ] || [ -z "$out" ] || [ "$#" -eq 0 ]; then
    usage; return 2
  fi
  if ! safe_token "$run_id" || ! safe_token "$task_id"; then
    printf 'maker-eval-emit: run id and task id must be safe path components (no "/" or ".."): run-id=[%s] task=[%s]\n' \
      "$run_id" "$task_id" >&2
    return 2
  fi
  if ! maker_tiers | grep -qxF -- "$tier"; then
    printf 'maker-eval-emit: --tier must be a maker tier (%s): got [%s]\n' \
      "$(maker_tiers | tr '\n' ' ')" "$tier" >&2
    return 2
  fi
  # Grading reads the channel; an unresolvable channel means there is nothing to grade and
  # no honest way to say so silently — a loud caller error (there is no maker run to protect).
  local channel traj
  channel="$(channel_dir)" || channel=""
  if [ -z "$channel" ]; then
    printf 'maker-eval-emit: cannot resolve the maker-eval channel — nothing to grade\n' >&2
    return 2
  fi
  traj="$channel/trajectory/$run_id/$task_id/$tier"

  # --out must be writable BEFORE the grading loop: each judge invocation is a real
  # [headless run] the caller pays for, so a doomed out-path fails loudly here — never
  # after N judge calls have already been spent (review of this PR).
  local out_dir
  out_dir="$(dirname -- "$out")"
  # The containing dir must be writable even when --out already exists: a failed grading
  # REMOVES the target (below), so the preflight must guarantee that removal can succeed.
  if [ ! -d "$out_dir" ] || [ ! -w "$out_dir" ] \
    || { [ -e "$out" ] && [ ! -w "$out" ]; }; then
    printf 'maker-eval-emit: --out is not writable: %s\n' "$out" >&2
    return 2
  fi

  # Captured snapshots only: RENAMED interval dirs, numeric order (interval-10 after
  # interval-2); a discarded `.tmp` is not a snapshot (US3.AC1). Zero captured snapshots
  # is a legitimate outcome (a sub-interval or trajectory-incomplete run): --out gets
  # { intervals: [] } and the caller omits --trajectory on the record.
  local ns
  ns="$(find "$traj" -maxdepth 1 -type d -name 'interval-*' ! -name '*.tmp' 2>/dev/null \
    | sed -E 's/.*interval-([0-9]+)$/\1/' | grep -E '^[0-9]+$' | LC_ALL=C sort -n)"

  local tmpout n v
  tmpout="$(mktemp)" || {
    printf 'maker-eval-emit: cannot create a scratch file for grading\n' >&2
    return 1
  }
  # A long grading loop (one [headless run] per snapshot) can be interrupted; the scratch
  # file must not outlive the run. EXIT covers every return path; INT/TERM fold into the
  # interrupted judge command's nonzero exit (the loud-failure path below). The path is
  # expanded NOW (double quotes): at script EXIT the function's local is out of scope, so
  # a deferred "$tmpout" would be unbound under set -u.
  # shellcheck disable=SC2064
  trap "rm -f '$tmpout'" EXIT INT TERM
  for n in $ns; do
    # One judge invocation per snapshot, the snapshot dir appended as the final argument.
    # A failing judge, or a verdict that is not a well-formed judge output, aborts the
    # whole grading loudly — a trajectory missing graded intervals is not the trajectory.
    # The verdict is slurped and length-checked (the trajectory_valid discipline): a
    # multi-document judge print must not validate on one document and land another.
    # Every loud-failure path also REMOVES the target: on a rerun over a pre-existing
    # --out, deleting only the scratch file would leave the stale previous trajectory in
    # place for a later `record --trajectory` to consume — "failed grading leaves no
    # trajectory output" means none, not an old one (PR #290 review).
    if ! v="$("$@" "$traj/interval-$n")"; then
      printf 'maker-eval-emit: judge command failed on interval-%s (%s)\n' "$n" "$traj" >&2
      rm -f "$tmpout" -- "$out"; return 1
    fi
    if ! printf '%s' "$v" | jq -es "(length == 1) and (.[0] | $JUDGE_OUTPUT_FILTER)" >/dev/null 2>&1; then
      printf 'maker-eval-emit: judge output for interval-%s is not a well-formed judge output\n' "$n" >&2
      rm -f "$tmpout" -- "$out"; return 1
    fi
    printf '%s' "$v" | jq -cs --argjson n "$n" '.[0] + {interval:$n}' >> "$tmpout" || {
      printf 'maker-eval-emit: cannot collect the interval-%s verdict\n' "$n" >&2
      rm -f "$tmpout" -- "$out"; return 1
    }
  done
  if ! jq -s '{intervals:.}' "$tmpout" > "$out" 2>/dev/null; then
    printf 'maker-eval-emit: cannot write the graded trajectory to %s\n' "$out" >&2
    rm -f "$tmpout" -- "$out"; return 1
  fi
  rm -f "$tmpout"
}

# ── dispatch ──────────────────────────────────────────────────────────────────
cmd="${1:-}"
[ "$#" -gt 0 ] && shift
case "$cmd" in
  fingerprint)  fingerprint_json ;;
  record)       do_record "$@" ;;
  agreement)    do_agreement "$@" ;;
  complete)     do_complete "$@" ;;
  snapshot-run) do_snapshot_run "$@" ;;
  grade-snapshots) do_grade_snapshots "$@" ;;
  *) usage; exit 2 ;;
esac
