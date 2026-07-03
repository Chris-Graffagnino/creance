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
#          [--prompt <f>] [--artifact <f>] [--judge <f>]
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
  printf 'usage: %s {fingerprint | record --run-id <id> --task <ME-id> --tier <maker-tier> --results <f> [--prompt <f>] [--artifact <f>] [--judge <f>] | agreement --run-id <id> --verdicts <f> | complete --run-id <id>}\n' \
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
results_valid() { # <results.json> -> 0 iff structurally a judge output
  jq -e '
    (.overall | type == "string") and (.overall | length > 0)
    and ((.dimensions // []) | type == "array")
    and ((.dimensions // []) | length > 0)
    and ((.dimensions // []) | all(.dimension != null and .lifecycle != null and .verdict != null))
  ' "$1" >/dev/null 2>&1
}

do_record() {
  local run_id="" task_id="" tier="" results="" prompt_f="" artifact_f="" judge_f=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --run-id)   run_id="${2:-}"; shift 2 ;;
      --task)     task_id="${2:-}"; shift 2 ;;
      --tier)     tier="${2:-}"; shift 2 ;;
      --results)  results="${2:-}"; shift 2 ;;
      --prompt)   prompt_f="${2:-}"; shift 2 ;;
      --artifact) artifact_f="${2:-}"; shift 2 ;;
      --judge)    judge_f="${2:-}"; shift 2 ;;
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

  rec="$(jq -c \
    --arg ts "$ts" --arg repo "$repo" --arg run "$run_id" --arg task "$task_id" \
    --arg tier "$tier" --argjson fp "$fp" --arg packet "$packet_rel" \
    '{record:"maker-eval", timestamp:$ts, repo:$repo, run_id:$run, task_id:$task,
      maker_tier:$tier,
      fingerprint:$fp,
      dimensions:(.dimensions // []),
      overall:(.overall // "fail"),
      first_upstream_failure:(.first_upstream_failure // "none"),
      packet:$packet}' \
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
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --run-id)   run_id="${2:-}"; shift 2 ;;
      --verdicts) verdicts="${2:-}"; shift 2 ;;
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
  local channel agreement ts repo rec
  channel="$(channel_dir)" || return 0
  [ -n "$channel" ] || return 0
  # A fixed-scale fraction in [0,1]; awk (not bc) for portability. `matched/total`.
  agreement="$(awk -v m="$matched" -v t="$total" 'BEGIN { printf "%.4f", (t>0 ? m/t : 0) }')" || return 0
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)" || return 0
  repo="$(repo_basename)"
  rec="$(jq -c \
    --arg ts "$ts" --arg repo "$repo" --arg run "$run_id" \
    --argjson agreement "$agreement" --argjson floor "$floor" \
    --argjson matched "$matched" --argjson total "$total" \
    -n '{record:"maker-eval-agreement", timestamp:$ts, repo:$repo, run_id:$run,
         agreement:$agreement, floor:$floor, matched:$matched, total:$total}' \
    2>/dev/null)" || return 0
  [ -n "$rec" ] || return 0

  {
    mkdir -p "$channel" || return 0
    printf '%s\n' "$rec" >> "$channel/records.jsonl" || return 0
  } 2>/dev/null || return 0

  printf '%s\n' "$rec"
}

# ── complete ──────────────────────────────────────────────────────────────────
record_present() { # <records-file> <run-id> <task-id> <tier>
  [ -f "$1" ] || return 1
  local n
  n="$(jq -c --arg r "$2" --arg t "$3" --arg k "$4" \
        'select(.run_id == $r and .task_id == $t and .maker_tier == $k)' "$1" 2>/dev/null | grep -c .)"
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

# ── dispatch ──────────────────────────────────────────────────────────────────
cmd="${1:-}"
[ "$#" -gt 0 ] && shift
case "$cmd" in
  fingerprint) fingerprint_json ;;
  record)      do_record "$@" ;;
  agreement)   do_agreement "$@" ;;
  complete)    do_complete "$@" ;;
  *) usage; exit 2 ;;
esac
