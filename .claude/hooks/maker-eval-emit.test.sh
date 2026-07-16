#!/usr/bin/env bash
# Encoding tests for the maker-eval record + packet emitter (T802, #157 — spec 003
# maker-eval corpus, US1.AC2 + US1.AC3). Where maker-eval-docs.test.sh pins the doc/
# corpus SHAPE, this one drives the concrete adapter emitter (maker-eval-emit.sh) and
# proves its observable behavior — the maker analog of guard.test.sh proving the
# telemetry emitter fires. It covers, against fixtures (no network, no real channel):
#
#   AC3 (the triple fingerprint): fingerprint prints three SEPARATE, DISJOINT content
#        hashes; it is deterministic across two identical trees; and each component
#        moves INDEPENDENTLY — a maker-surface or model-resolution edit moves only
#        maker_behavior, a judge-row edit moves only judge_identity, an instrument edit
#        moves only eval_instrument, and an edit to the excluded eval machinery
#        (maker-eval.md) moves none (locking the disjointness that makes a maker change,
#        a judge change, and an instrument change each its own movement).
#   AC2 (the record + packet): record appends EXACTLY ONE JSONL line per corpus task
#        carrying run id, task id, the triple fingerprint, per-dimension verdict+lifecycle,
#        overall, first-upstream-failure, timestamp, and a RELATIVE packet link that
#        resolves only inside the fenced channel; the packet is stored under that path;
#        records are append-only (two tasks -> two lines).
#   AC2 (the two mandated cases): WRITE-FAILURE-STAYS-SILENT (an unwritable channel
#        yields exit 0, empty stderr, nothing written) and PARTIAL-RUN-IS-NOT-A-BASELINE
#        (a run missing any corpus task reports incomplete; all present -> complete).
#   Observe-only: the emitter writes only under the channel (it does not also write a
#        telemetry stream) and invokes no gate/tier/selection control-path script.
#   US3.AC2 (T807, interval snapshot capture): snapshots appear at the INSTRUMENT-DECLARED
#        cadence on a fixture run (and the declared rate is obeyed, not hardcoded); a forced
#        snapshot-write failure leaves the maker run's exit code and workspace artifacts
#        byte-identical; the trajectory-incomplete marking is TWO-SIDED (fires on a planted
#        zero-snapshot multi-interval run, does not fire on a genuinely sub-interval run);
#        a marker line never satisfies run completeness; caller errors are loud and never
#        start the maker command; captures hold FIXED cadence boundaries under slow copies
#        (never cadence+copy_duration drift); and the active capture child is reaped on
#        maker exit (no orphaned copy outlives snapshot-run — PR #288 review).
#
# Run: bash .claude/hooks/maker-eval-emit.test.sh
set -u

DIR="$(cd "$(dirname "$0")" && pwd)"
EMIT="$DIR/maker-eval-emit.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0
ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); printf 'FAIL %s\n' "$1" >&2; [ -n "${2:-}" ] && printf '     %s\n' "$2" >&2; return 0; }
eq()  { if [ "$2" = "$3" ]; then ok; else bad "$1" "want=[$2] got=[$3]"; fi; }
ne()  { if [ "$2" != "$3" ]; then ok; else bad "$1" "unchanged but should differ=[$2]"; fi; }

[ -f "$EMIT" ] || { echo "FAIL: emitter missing: $EMIT" >&2; exit 1; }

# ── fixture tree (relocatable via MAKER_EVAL_ROOT) ───────────────────────────────
# A minimal repo-shaped tree carrying one file per fingerprint component, so a
# mutation to exactly one source proves that component moves and the others do not.
build_tree() { # build_tree <root>
  local r="$1"
  mkdir -p "$r/.claude/workflow/reviewers" "$r/.claude/skills/demo"
  printf 'always-resident instructions\n' > "$r/AGENTS.md"
  cat > "$r/.claude/MODELS.md" <<'EOF'
# Model table
| Tier | Model | Effort |
|---|---|---|
| **[frontier tier]** | `model-frontier` | high |
| **[strong tier]** | `model-strong` | — |
| **[cheap tier]** | `model-cheap` | — |

## The pinned maker-eval judge
| **maker-eval judge** (pinned) | `model-judge` | high |
EOF
  printf 'a methodology doc that shapes maker output\n' > "$r/.claude/workflow/next-task.md"
  # The eval machinery — deliberately EXCLUDED from every component.
  printf 'the maker-eval methodology doc\n' > "$r/.claude/workflow/maker-eval.md"
  # The frozen instrument manifest (eval_instrument) + the corpus task table.
  cat > "$r/.claude/workflow/reviewers/maker-eval-corpus.md" <<'EOF'
# Maker-eval corpus

## The corpus tasks

| Task | Seed class | Maker task |
|---|---|---|
| ME-01 | test-gaming | Implement one criterion and its test. |
| ME-02 | discovered-work | Surface a defect, file it, do not widen. |
| ME-03 | owner-steering | Resume honoring the newest owner steering. |

## Judge calibration

The owner-labeled calibration set + the agreement floor (T806 fixture).

### The owner-labeled calibration pairs

| Pair | Dimension | Owner label | Maker output |
|---|---|---|---|
| CAL-01 | test-live | meets | a live test |
| CAL-02 | test-live | fails | a skipped test |
| CAL-03 | surgical-diff | meets | a scoped diff |
| CAL-04 | surgical-diff | fails | a scope-creep diff |

### The agreement floor

- Agreement floor: `0.75`.

## Snapshot cadence

- Snapshot cadence: `1` seconds (T807 fixture).
EOF
  printf 'an adapter binding prompt\n' > "$r/.claude/skills/demo/SKILL.md"
}

comp() { printf '%s' "$1" | jq -r ".$2"; } # comp <fingerprint-json> <field>

T0="$TMP/tree0"
build_tree "$T0"
BASE="$(MAKER_EVAL_ROOT="$T0" bash "$EMIT" fingerprint)"

# ── AC3: three separate, non-empty, distinct components ──────────────────────────
mb="$(comp "$BASE" maker_behavior)"
ji="$(comp "$BASE" judge_identity)"
ei="$(comp "$BASE" eval_instrument)"
if [ -n "$mb" ] && [ -n "$ji" ] && [ -n "$ei" ]; then ok; else bad "AC3: all three components non-empty" "$BASE"; fi
ne "AC3: maker_behavior != judge_identity" "$mb" "$ji"
ne "AC3: maker_behavior != eval_instrument" "$mb" "$ei"
ne "AC3: judge_identity != eval_instrument" "$ji" "$ei"

# ── AC3: determinism — a second identical tree reproduces the same fingerprint ───
T1="$TMP/tree1"
build_tree "$T1"
DUP="$(MAKER_EVAL_ROOT="$T1" bash "$EMIT" fingerprint)"
eq "AC3: fingerprint deterministic across two identical trees" "$BASE" "$DUP"

# ── AC3: independence — mutate exactly one source, assert only its component moves ─
# Each case builds a fresh identical tree (so its baseline equals BASE), mutates one
# file, recomputes, and compares each component against BASE.
assert_only() { # assert_only <label> <mutated-fp> <moved-field>
  local label="$2" fp="$3" moved="$4"
  local m j e
  m="$(comp "$fp" maker_behavior)"; j="$(comp "$fp" judge_identity)"; e="$(comp "$fp" eval_instrument)"
  case "$moved" in
    maker_behavior)  ne "$label: maker_behavior moves" "$mb" "$m"; eq "$label: judge_identity stable" "$ji" "$j"; eq "$label: eval_instrument stable" "$ei" "$e" ;;
    judge_identity)  eq "$label: maker_behavior stable" "$mb" "$m"; ne "$label: judge_identity moves" "$ji" "$j"; eq "$label: eval_instrument stable" "$ei" "$e" ;;
    eval_instrument) eq "$label: maker_behavior stable" "$mb" "$m"; eq "$label: judge_identity stable" "$ji" "$j"; ne "$label: eval_instrument moves" "$ei" "$e" ;;
    none)            eq "$label: maker_behavior stable" "$mb" "$m"; eq "$label: judge_identity stable" "$ji" "$j"; eq "$label: eval_instrument stable" "$ei" "$e" ;;
  esac
}

mut() { # mut <field-label> <mutator-fn> -> recomputed fingerprint of a fresh+mutated tree
  local d="$TMP/mut-$1"
  build_tree "$d"
  "$2" "$d"
  MAKER_EVAL_ROOT="$d" bash "$EMIT" fingerprint
}

m_surface()   { printf 'edit to an instruction surface\n' >> "$1/.claude/workflow/next-task.md"; }
m_makerrow()  { sed -i.bak 's/`model-strong`/`model-strong-2`/' "$1/.claude/MODELS.md"; rm -f "$1/.claude/MODELS.md.bak"; }
m_judgerow()  { sed -i.bak 's/`model-judge`/`model-judge-2`/' "$1/.claude/MODELS.md"; rm -f "$1/.claude/MODELS.md.bak"; }
m_skill()     { printf 'edit to an adapter binding prompt\n' >> "$1/.claude/skills/demo/SKILL.md"; }
m_instrument(){ printf '| ME-04 | new-seed | a new corpus task |\n' >> "$1/.claude/workflow/reviewers/maker-eval-corpus.md"; }
m_machinery() { printf 'edit to the excluded eval machinery doc\n' >> "$1/.claude/workflow/maker-eval.md"; }

assert_only x "AC3: instruction-surface edit"     "$(mut surface  m_surface)"   maker_behavior
assert_only x "AC3: maker model-resolution edit"  "$(mut makerrow m_makerrow)"  maker_behavior
assert_only x "AC3: adapter-binding-prompt edit"  "$(mut skill    m_skill)"     maker_behavior
assert_only x "AC3: pinned-judge-row edit"        "$(mut judgerow m_judgerow)"  judge_identity
assert_only x "AC3: instrument (corpus) edit"     "$(mut instr    m_instrument)" eval_instrument
assert_only x "AC3: excluded eval-machinery edit moves nothing" "$(mut mach m_machinery)" none

# ── AC2: record shape + packet, against a fixture channel ────────────────────────
CH="$TMP/channel"
cat > "$TMP/judge.json" <<'EOF'
{"dimensions":[{"dimension":"behavior-performed","lifecycle":"saturated","verdict":"meets","evidence":"impl@foo:10"},
{"dimension":"assertion-locus","lifecycle":"regression","verdict":"partial","evidence":"loose@foo.test:5"}],
"overall":"fail","first_upstream_failure":"weak-verification"}
EOF
printf 'the materialized task prompt\n' > "$TMP/prompt.txt"
printf 'diff --git a/x b/x\n+change\n'   > "$TMP/artifact.diff"
printf '# judge report\nassertion-locus only partial\n' > "$TMP/judge-report.md"

LINE="$(MAKER_EVAL_ROOT="$T0" MAKER_EVAL_DIR="$CH" bash "$EMIT" record \
  --run-id run-A --task ME-01 --tier strong --results "$TMP/judge.json" \
  --prompt "$TMP/prompt.txt" --artifact "$TMP/artifact.diff" --judge "$TMP/judge-report.md")"

eq "AC2: exactly one JSONL line written" "1" "$(grep -c . "$CH/records.jsonl" 2>/dev/null)"
eq "AC2: record is valid JSON"        "ok" "$(printf '%s' "$LINE" | jq -e . >/dev/null 2>&1 && echo ok)"
eq "AC2: record carries the run id"   "run-A" "$(printf '%s' "$LINE" | jq -r .run_id)"
eq "AC2: record carries the task id"  "ME-01" "$(printf '%s' "$LINE" | jq -r .task_id)"
eq "AC2: record carries the maker tier (US2.AC1)" "strong" "$(printf '%s' "$LINE" | jq -r .maker_tier)"
eq "AC2: record carries a timestamp (ISO-8601 Z)" "ok" \
  "$(printf '%s' "$LINE" | jq -r .timestamp | grep -qE '^[0-9]+-[0-9][0-9]-[0-9][0-9]T[0-9:]+Z$' && echo ok)"
eq "AC2: record carries the overall verdict" "fail" "$(printf '%s' "$LINE" | jq -r .overall)"
eq "AC2: record carries the first-upstream-failure class" "weak-verification" \
  "$(printf '%s' "$LINE" | jq -r .first_upstream_failure)"
# per-dimension verdict carries its lifecycle (never collapsed to one tag per task)
eq "AC2: per-dimension verdict carries lifecycle" "saturated" \
  "$(printf '%s' "$LINE" | jq -r '.dimensions[0].lifecycle')"
eq "AC2: per-dimension verdict carries the verdict" "partial" \
  "$(printf '%s' "$LINE" | jq -r '.dimensions[1].verdict')"
# the triple fingerprint is embedded with all three components
eq "AC2: record embeds the triple fingerprint (3 keys)" "3" \
  "$(printf '%s' "$LINE" | jq -r '.fingerprint | keys | length')"

# the packet link resolves ONLY inside the fenced channel (relative, no escape)
PKT="$(printf '%s' "$LINE" | jq -r .packet)"
case "$PKT" in
  /*) bad "AC2: packet link is relative (not absolute)" "got=[$PKT]" ;;
  *)  ok ;;
esac
case "$PKT" in
  *..*) bad "AC2: packet link cannot escape via .." "got=[$PKT]" ;;
  *)    ok ;;
esac
if [ -d "$CH/$PKT" ]; then ok; else bad "AC2: packet dir exists inside the channel" "missing: $CH/$PKT"; fi
for part in prompt.txt artifact.txt judge-report.md first-upstream-failure.txt; do
  if [ -f "$CH/$PKT/$part" ]; then ok; else bad "AC2: packet stores $part"; fi
done
eq "AC2: packet records the first-upstream-failure class" "weak-verification" \
  "$(cat "$CH/$PKT/first-upstream-failure.txt" 2>/dev/null)"

# append-only: a second record appends a second line (does not overwrite)
MAKER_EVAL_ROOT="$T0" MAKER_EVAL_DIR="$CH" bash "$EMIT" record \
  --run-id run-A --task ME-02 --tier strong --results "$TMP/judge.json" >/dev/null
eq "AC2: records are append-only (2 records -> 2 lines)" "2" "$(grep -c . "$CH/records.jsonl")"

# ── T806 (US1.AC5): the judge<->owner AGREEMENT figure — computed + recorded observe-only ──
# The fixture corpus (build_tree) carries a 4-pair owner-labeled calibration set (CAL-01..04:
# meets/fails/meets/fails) + a stated floor of 0.75. The `agreement` subcommand reads those
# frozen labels + floor, reads the judge's verdict per pair, and appends ONE observe-only
# run-scoped record with agreement = matched/total. These cases prove the MATH (perfect, a
# below-floor miss), the recorded shape (floor carried, matched/total carried), the loud
# caller errors (partial or extraneous verdict set), and observe-only (write-failure silent).
AGCH="$TMP/agreement-channel"
# (i) perfect agreement — every judge verdict equals the owner label -> 1.0, matched==total.
cat > "$TMP/v-perfect.json" <<'EOF'
{"verdicts":[{"pair":"CAL-01","verdict":"meets"},{"pair":"CAL-02","verdict":"fails"},
{"pair":"CAL-03","verdict":"meets"},{"pair":"CAL-04","verdict":"fails"}]}
EOF
AGLINE="$(MAKER_EVAL_ROOT="$T0" MAKER_EVAL_DIR="$AGCH" bash "$EMIT" agreement \
  --run-id run-AG --verdicts "$TMP/v-perfect.json")"
eq "T806: agreement record is valid JSON" "ok" "$(printf '%s' "$AGLINE" | jq -e . >/dev/null 2>&1 && echo ok)"
eq "T806: record kind is maker-eval-agreement" "maker-eval-agreement" "$(printf '%s' "$AGLINE" | jq -r .record)"
eq "T806: record carries the run id" "run-AG" "$(printf '%s' "$AGLINE" | jq -r .run_id)"
eq "T806: perfect agreement is 1" "1" "$(printf '%s' "$AGLINE" | jq -r .agreement)"
eq "T806: matched equals total on perfect agreement" "ok" \
  "$(printf '%s' "$AGLINE" | jq -e '.matched == .total and .total == 4' >/dev/null 2>&1 && echo ok)"
eq "T806: the stated floor (0.75) is recorded from the frozen instrument" "0.75" \
  "$(printf '%s' "$AGLINE" | jq -r .floor)"
eq "T806: agreement is one appended line (observe-only stream)" "1" "$(grep -c . "$AGCH/records.jsonl")"
# (ii) a below-floor run — 2 of 4 pairs disagree -> 0.5, still RECORDED (never a gate).
AGCH2="$TMP/agreement-channel-below"
cat > "$TMP/v-below.json" <<'EOF'
{"verdicts":[{"pair":"CAL-01","verdict":"fails"},{"pair":"CAL-02","verdict":"meets"},
{"pair":"CAL-03","verdict":"meets"},{"pair":"CAL-04","verdict":"fails"}]}
EOF
AGLINE2="$(MAKER_EVAL_ROOT="$T0" MAKER_EVAL_DIR="$AGCH2" bash "$EMIT" agreement \
  --run-id run-AG2 --verdicts "$TMP/v-below.json")"
eq "T806: 2-of-4 agreement is 0.5" "0.5" "$(printf '%s' "$AGLINE2" | jq -r .agreement)"
eq "T806: matched=2 on a 2-of-4 run" "2" "$(printf '%s' "$AGLINE2" | jq -r .matched)"
eq "T806: a below-floor agreement is still recorded (never gated away)" "1" \
  "$(grep -c . "$AGCH2/records.jsonl")"
eq "T806: agreement 0.5 is below the recorded floor 0.75 (the JUDGE-MISCALIBRATED condition)" "ok" \
  "$(printf '%s' "$AGLINE2" | jq -e '.agreement < .floor' >/dev/null 2>&1 && echo ok)"
# (iii) a verdict set that misses a frozen pair is a LOUD caller error (nothing written) —
# an agreement over a partial set would be a silently-wrong calibration.
AGCH3="$TMP/agreement-channel-partial"
cat > "$TMP/v-partial.json" <<'EOF'
{"verdicts":[{"pair":"CAL-01","verdict":"meets"},{"pair":"CAL-02","verdict":"fails"}]}
EOF
MAKER_EVAL_ROOT="$T0" MAKER_EVAL_DIR="$AGCH3" bash "$EMIT" agreement \
  --run-id run-AG3 --verdicts "$TMP/v-partial.json" >/dev/null 2>&1; rc=$?
eq "T806: a partial verdict set is a loud caller error (exit 2)" "2" "$rc"
eq "T806: a partial verdict set lands no record" "0" "$(grep -c . "$AGCH3/records.jsonl" 2>/dev/null || echo 0)"
# (iv) a verdict naming a pair NOT in the frozen set is likewise a loud caller error.
AGCH4="$TMP/agreement-channel-extra"
cat > "$TMP/v-extra.json" <<'EOF'
{"verdicts":[{"pair":"CAL-01","verdict":"meets"},{"pair":"CAL-02","verdict":"fails"},
{"pair":"CAL-03","verdict":"meets"},{"pair":"CAL-04","verdict":"fails"},
{"pair":"CAL-99","verdict":"meets"}]}
EOF
MAKER_EVAL_ROOT="$T0" MAKER_EVAL_DIR="$AGCH4" bash "$EMIT" agreement \
  --run-id run-AG4 --verdicts "$TMP/v-extra.json" >/dev/null 2>&1; rc=$?
eq "T806: an extraneous (unknown) pair is a loud caller error (exit 2)" "2" "$rc"
eq "T806: an extraneous pair lands no record" "0" "$(grep -c . "$AGCH4/records.jsonl" 2>/dev/null || echo 0)"
# (v) a malformed verdicts file is a loud caller error, never a defaulted agreement.
AGCH5="$TMP/agreement-channel-malformed"; printf '%s\n' '{}' > "$TMP/v-empty.json"
MAKER_EVAL_ROOT="$T0" MAKER_EVAL_DIR="$AGCH5" bash "$EMIT" agreement \
  --run-id run-AG5 --verdicts "$TMP/v-empty.json" >/dev/null 2>&1; rc=$?
eq "T806: a malformed verdicts file is a loud caller error (exit 2)" "2" "$rc"
# (vi) WRITE-FAILURE-STAYS-SILENT — an unwritable channel (parent is a regular file, so
# mkdir -p must fail) yields exit 0, empty stderr, nothing written.
printf 'i am a file, not a dir\n' > "$TMP/agfile"
agerr="$(MAKER_EVAL_ROOT="$T0" MAKER_EVAL_DIR="$TMP/agfile/agsub" bash "$EMIT" agreement \
  --run-id run-AG6 --verdicts "$TMP/v-perfect.json" 2>&1 1>/dev/null)"; rc=$?
eq "T806: agreement write failure exits 0 (silent-to-the-eval)" "0" "$rc"
eq "T806: agreement write failure emits nothing to stderr" "" "$agerr"
if [ -e "$TMP/agfile/agsub" ]; then bad "T806: agreement write failure wrote nothing" "created $TMP/agfile/agsub"; else ok; fi
# (vii) a verdict OUTSIDE the scoring schema (meets|partial|fails) is a loud caller error —
# silently counting a non-schema verdict as a disagreement would skew the figure.
AGCH7="$TMP/agreement-channel-bogus"
cat > "$TMP/v-bogus.json" <<'EOF'
{"verdicts":[{"pair":"CAL-01","verdict":"bogus"},{"pair":"CAL-02","verdict":"fails"},
{"pair":"CAL-03","verdict":"meets"},{"pair":"CAL-04","verdict":"fails"}]}
EOF
MAKER_EVAL_ROOT="$T0" MAKER_EVAL_DIR="$AGCH7" bash "$EMIT" agreement \
  --run-id run-AG7 --verdicts "$TMP/v-bogus.json" >/dev/null 2>&1; rc=$?
eq "T806: a non-schema judge verdict is a loud caller error (exit 2)" "2" "$rc"
eq "T806: a non-schema judge verdict lands no record" "0" "$(grep -c . "$AGCH7/records.jsonl" 2>/dev/null || echo 0)"
# (viii) a dangling option (--run-id with no value) is a loud usage error (exit 2, nothing
# written) — the unguarded parser left the arg list unchanged after `shift 2` and spun
# forever. perl's alarm caps the run (macOS ships no GNU timeout): a regression dies on
# SIGALRM (rc 142) instead of hanging the suite.
AGCH8="$TMP/agreement-channel-dangling"
MAKER_EVAL_ROOT="$T0" MAKER_EVAL_DIR="$AGCH8" perl -e 'alarm 5; exec @ARGV' \
  bash "$EMIT" agreement --run-id >/dev/null 2>&1; rc=$?
eq "T806: agreement --run-id with no value is a loud usage error (exit 2, no hang)" "2" "$rc"
if [ -e "$AGCH8" ]; then bad "T806: a dangling option writes nothing" "created $AGCH8"; else ok; fi

# ── T806 (US1.AC5 / AC3): a CALIBRATION-SET edit moves ONLY eval_instrument ────────────────
# The calibration set + labels + floor are part of the frozen instrument, so editing an owner
# label must move the eval_instrument fingerprint component and NOTHING else (a maker/judge
# change must stay distinguishable from an instrument change — the disjointness AC3 requires).
m_calibration() { sed -i.bak 's/| CAL-01 | test-live | meets |/| CAL-01 | test-live | fails |/' \
  "$1/.claude/workflow/reviewers/maker-eval-corpus.md"; rm -f "$1/.claude/workflow/reviewers/maker-eval-corpus.md.bak"; }
assert_only x "AC3: owner-label (calibration) edit moves only eval_instrument" \
  "$(mut calib m_calibration)" eval_instrument

# ── US2.AC1: --tier is required and must be a real maker tier ─────────────────────────
# A typo'd or absent tier is a loud caller error, never a silently tier-less record that
# would leave `complete` forever-incomplete or let a bad tier evade the (task × tier) grid.
VCH="$TMP/tier-validation"
MAKER_EVAL_ROOT="$T0" MAKER_EVAL_DIR="$VCH" bash "$EMIT" record \
  --run-id run-V --task ME-01 --results "$TMP/judge.json" >/dev/null 2>&1; rc=$?
eq "US2.AC1: a record with no --tier is a loud caller error (exit 2)" "2" "$rc"
MAKER_EVAL_ROOT="$T0" MAKER_EVAL_DIR="$VCH" bash "$EMIT" record \
  --run-id run-V --task ME-01 --tier bogus --results "$TMP/judge.json" >/dev/null 2>&1; rc=$?
eq "US2.AC1: a non-maker-tier --tier is a loud caller error (exit 2)" "2" "$rc"
eq "US2.AC1: a rejected tier lands no record" "0" "$(grep -c . "$VCH/records.jsonl" 2>/dev/null || echo 0)"

# ── AC2 / US2.AC1: PARTIAL-RUN-IS-NOT-A-BASELINE — completeness spans (task × tier) ──
# A run is comparable only when every corpus task is scored at EVERY maker tier, so a run
# that scored ALL tasks at ONE tier (the old default) is NOT a baseline — the Finding-1 fix:
# it cannot clear MAKER-EVAL-STALE while a changed cheap/frontier row went un-scored.
TCH="$TMP/tier-channel"
# (i) all three corpus tasks at strong only -> still incomplete (frontier/cheap missing).
for t in ME-01 ME-02 ME-03; do
  MAKER_EVAL_ROOT="$T0" MAKER_EVAL_DIR="$TCH" bash "$EMIT" record \
    --run-id run-T --task "$t" --tier strong --results "$TMP/judge.json" >/dev/null
done
out="$(MAKER_EVAL_ROOT="$T0" MAKER_EVAL_DIR="$TCH" bash "$EMIT" complete --run-id run-T)"; rc=$?
ne "US2.AC1: a single-tier run (all tasks, one tier) is NOT complete" "0" "$rc"
eq "US2.AC1: single-tier run renders incomplete" "ok" "$(printf '%s' "$out" | grep -q '^incomplete' && echo ok)"
eq "US2.AC1: incomplete names a missing (task@tier) pair" "ok" \
  "$(printf '%s' "$out" | grep -qE 'ME-0[0-9]@(frontier|cheap)' && echo ok)"
# (ii) fill in the remaining tiers (frontier + cheap) for every task -> complete.
for t in ME-01 ME-02 ME-03; do
  for k in frontier cheap; do
    MAKER_EVAL_ROOT="$T0" MAKER_EVAL_DIR="$TCH" bash "$EMIT" record \
      --run-id run-T --task "$t" --tier "$k" --results "$TMP/judge.json" >/dev/null
  done
done
out="$(MAKER_EVAL_ROOT="$T0" MAKER_EVAL_DIR="$TCH" bash "$EMIT" complete --run-id run-T)"; rc=$?
eq "US2.AC1: an all-tier run exits 0" "0" "$rc"
eq "US2.AC1: an all-tier run renders as complete" "complete" "$out"
# an empty/absent stream is incomplete, never a silent baseline
out="$(MAKER_EVAL_ROOT="$T0" MAKER_EVAL_DIR="$TMP/empty-ch" bash "$EMIT" complete --run-id run-Z)"; rc=$?
ne "AC2: an absent stream is incomplete (no silent baseline)" "0" "$rc"

# ── AC2: WRITE-FAILURE-STAYS-SILENT ──────────────────────────────────────────────
# Channel parent is a regular file, so mkdir -p must fail. The emitter must exit 0,
# print nothing to stderr, and write no record (the gate-telemetry silent-write law).
printf 'i am a file, not a dir\n' > "$TMP/afile"
err="$(MAKER_EVAL_ROOT="$T0" MAKER_EVAL_DIR="$TMP/afile/sub" bash "$EMIT" record \
  --run-id run-B --task ME-01 --tier strong --results "$TMP/judge.json" 2>&1 1>/dev/null)"; rc=$?
eq "AC2: write failure exits 0 (silent-to-the-eval)" "0" "$rc"
eq "AC2: write failure emits nothing to stderr" "" "$err"
if [ -e "$TMP/afile/sub" ]; then bad "AC2: write failure wrote nothing" "created $TMP/afile/sub"; else ok; fi

# ── Observe-only: writes only under the channel; invokes no control-path script ──
# Behavioral: a record run created the channel but no telemetry stream anywhere in TMP.
if find "$TMP" -name '*-telemetry.jsonl' 2>/dev/null | grep -q .; then
  bad "observe-only: emitter wrote a telemetry stream (must touch only its own channel)"
else ok; fi
# Source: the emitter calls no gate/tier/selection control-path machinery.
if grep -nE '(gate-loop|reconcile-(task|inflight)|autonomy-mode|announce-task)' "$EMIT" >/dev/null 2>&1; then
  bad "observe-only: emitter references a gate/tier/selection control-path script"
else ok; fi

# ── B (channel resolution, #158): the Maker-eval Paths row carries a doc pointer
# (`workflow/maker-eval.md`) and bare sub-path prose (`packets/`, `records.jsonl`) beside
# a <placeholder> channel — none is an override, so resolution must fall through to the
# OUT-OF-REPO shipped default and never write inside the repo tree. ──────────────────────
BPROF="$TMP/profile-docptr.md"
cat > "$BPROF" <<'EOF'
## Paths
- **Maker-eval records:** default per `workflow/maker-eval.md` — out-of-repo beside the
  triage inbox: `<triage inbox dir>/creance-maker-eval/`, holding `records.jsonl` and a
  `packets/` subtree.
- **Next:** x
EOF
BRT="$TMP/btree"; build_tree "$BRT"
BHOME="$TMP/bhome"
( unset MAKER_EVAL_DIR
  HOME="$BHOME" MAKER_EVAL_ROOT="$BRT" MAKER_EVAL_PROJECT_FILE="$BPROF" \
    bash "$EMIT" record --run-id run-B2 --task ME-01 --tier strong --results "$TMP/judge.json" >/dev/null )
if find "$BRT" -name records.jsonl 2>/dev/null | grep -q .; then
  bad "B: doc-pointer/prose is not the channel (no repo-internal record)" "records.jsonl under $BRT"
else ok; fi
if [ -n "$(find "$BHOME/.claude/triage" -name records.jsonl 2>/dev/null)" ]; then ok
else bad "B: record lands in the out-of-repo default channel" "no records.jsonl under $BHOME/.claude/triage"; fi
# a concrete, out-of-repo (absolute) profile path IS honored as an override
BPROF2="$TMP/profile-real.md"
printf '## Paths\n- **Maker-eval records:** `%s/realchan`\n' "$TMP" > "$BPROF2"
( unset MAKER_EVAL_DIR
  HOME="$BHOME" MAKER_EVAL_ROOT="$BRT" MAKER_EVAL_PROJECT_FILE="$BPROF2" \
    bash "$EMIT" record --run-id run-B3 --task ME-01 --tier strong --results "$TMP/judge.json" >/dev/null )
if [ -f "$TMP/realchan/records.jsonl" ]; then ok
else bad "B: a concrete out-of-repo profile path is used as the channel" "missing $TMP/realchan/records.jsonl"; fi

# ── D (atomic record+packet, #158): a REQUESTED packet artifact whose copy fails aborts
# the whole write silently — a record never lands without its requested packet files. ──
DCH="$TMP/dchannel"; mkdir -p "$TMP/adir"
out="$(MAKER_EVAL_ROOT="$T0" MAKER_EVAL_DIR="$DCH" bash "$EMIT" record \
  --run-id run-D --task ME-01 --tier strong --results "$TMP/judge.json" --prompt "$TMP/adir" 2>/dev/null)"; rc=$?
eq "D: a failing packet copy exits 0 (silent-to-the-eval)" "0" "$rc"
eq "D: a failing packet copy prints no record" "" "$out"
eq "D: a failing packet copy lands no record line" "0" "$(grep -c . "$DCH/records.jsonl" 2>/dev/null || echo 0)"
# a requested-but-missing packet file likewise aborts (cp fails on a missing source)
MAKER_EVAL_ROOT="$T0" MAKER_EVAL_DIR="$TMP/dchannel2" bash "$EMIT" record \
  --run-id run-D2 --task ME-01 --tier strong --results "$TMP/judge.json" --prompt "$TMP/no-such-file" >/dev/null 2>&1; rc=$?
eq "D: a requested-but-missing packet exits 0" "0" "$rc"
eq "D: a requested-but-missing packet lands no record" "0" "$(grep -c . "$TMP/dchannel2/records.jsonl" 2>/dev/null || echo 0)"

# ── E (judge-output schema, #158): a malformed judge output is a loud caller error and
# never a counted record, so a garbled run can never render `complete`. ────────────────
ECH="$TMP/echannel"; printf '%s\n' '{}' > "$TMP/empty.json"
MAKER_EVAL_ROOT="$T0" MAKER_EVAL_DIR="$ECH" bash "$EMIT" record \
  --run-id run-E --task ME-01 --tier strong --results "$TMP/empty.json" >/dev/null 2>&1; rc=$?
eq "E: malformed judge output is rejected (exit 2)" "2" "$rc"
eq "E: malformed judge output lands no record" "0" "$(grep -c . "$ECH/records.jsonl" 2>/dev/null || echo 0)"
# end-to-end: a full set of malformed outputs never renders the run complete
for t in ME-01 ME-02 ME-03; do
  MAKER_EVAL_ROOT="$T0" MAKER_EVAL_DIR="$ECH" bash "$EMIT" record \
    --run-id run-Emt --task "$t" --tier strong --results "$TMP/empty.json" >/dev/null 2>&1
done
out="$(MAKER_EVAL_ROOT="$T0" MAKER_EVAL_DIR="$ECH" bash "$EMIT" complete --run-id run-Emt)"; rc=$?
ne "E: a run of malformed outputs never renders complete" "0" "$rc"
eq "E: that run renders incomplete" "ok" "$(printf '%s' "$out" | grep -q '^incomplete' && echo ok)"
# a well-formed judge output is still accepted (no over-rejection)
eq "E: a well-formed judge output is still recorded" "ME-01" \
  "$(MAKER_EVAL_ROOT="$T0" MAKER_EVAL_DIR="$TMP/echannel-ok" bash "$EMIT" record \
      --run-id run-Eok --task ME-01 --tier strong --results "$TMP/judge.json" | jq -r .task_id)"

# ── C (packet-path fence, #158 / AC2 "packet artifacts never escape"): a run_id or
# task_id carrying `/` or `..` is a loud caller error — nothing is written and no packet
# dir or in-record link escapes the channel. (The `:176/:179` link checks above only
# exercise a benign id; these feed genuinely hostile tokens.) ──────────────────────────
CCH="$TMP/cchannel"; mkdir -p "$CCH"
for hostile in '../../escape' 'a/b' '..'; do
  MAKER_EVAL_ROOT="$T0" MAKER_EVAL_DIR="$CCH" bash "$EMIT" record \
    --run-id "$hostile" --task ME-01 --tier strong --results "$TMP/judge.json" >/dev/null 2>&1; rc=$?
  eq "C: hostile run-id [$hostile] is a loud caller error (exit 2)" "2" "$rc"
done
# the same guard applies to the task id
MAKER_EVAL_ROOT="$T0" MAKER_EVAL_DIR="$CCH" bash "$EMIT" record \
  --run-id run-C --task '../../escape' --tier strong --results "$TMP/judge.json" >/dev/null 2>&1; rc=$?
eq "C: hostile task-id is a loud caller error (exit 2)" "2" "$rc"
# the `..`-traversal target ($CCH/packets/../../escape -> $TMP/escape) was never created,
# and no record landed for any rejected id
if [ -e "$TMP/escape" ]; then bad "C: no packet artifact escaped the fenced channel" "created $TMP/escape"; else ok; fi
eq "C: a rejected hostile id lands no record" "0" "$(grep -c . "$CCH/records.jsonl" 2>/dev/null || echo 0)"
# a realistic, safe id still records (no over-rejection)
eq "C: a safe id still records" "ME-01" \
  "$(MAKER_EVAL_ROOT="$T0" MAKER_EVAL_DIR="$TMP/cchannel-ok" bash "$EMIT" record \
      --run-id 2026-06-25T13-18-42Z --task ME-01 --tier strong --results "$TMP/judge.json" | jq -r .task_id)"

# ── T807 (US3.AC1/AC2): interval snapshot capture — cadence, silence, two-sided marking ──
# The fixture instrument (build_tree) declares a 1-second cadence, so a short real run
# exercises the declared-rate contract without a slow suite.

# (i) CADENCE FIXTURE — a ~2.5s maker run at cadence 1 captures interval-1 AND interval-2,
# each snapshot carrying the workspace's bytes; the maker's exit propagates; no marker lands.
SWS="$TMP/snap-ws"; mkdir -p "$SWS"
printf 'workspace payload\n' > "$SWS/payload.txt"
SCH="$TMP/snap-channel"
MAKER_EVAL_ROOT="$T0" MAKER_EVAL_DIR="$SCH" bash "$EMIT" snapshot-run \
  --run-id run-S --task ME-01 --tier strong --workspace "$SWS" -- sleep 2.5; rc=$?
eq "US3.AC2: snapshot-run propagates the maker exit code (0)" "0" "$rc"
STRAJ="$SCH/trajectory/run-S/ME-01/strong"
for n in 1 2; do
  if [ -d "$STRAJ/interval-$n" ]; then ok; else bad "US3.AC2: cadence-1 2.5s run captured interval-$n"; fi
done
eq "US3.AC2: a snapshot carries the workspace bytes" "workspace payload" \
  "$(cat "$STRAJ/interval-1/payload.txt" 2>/dev/null)"
eq "US3.AC2: a snapshotted multi-interval run lands NO trajectory-incomplete marker" "0" \
  "$(grep -c 'trajectory-incomplete' "$SCH/records.jsonl" 2>/dev/null || echo 0)"

# (ii) THE DECLARED RATE IS OBEYED — at cadence 2 the same ~2.6s run captures EXACTLY ONE
# snapshot, not one-per-second: capture follows the instrument's declaration, never a
# hardcoded or as-fast-as-possible rate (US3.AC1 "fixed, instrument-declared cadence").
T2="$TMP/tree-cadence2"; build_tree "$T2"
sed -i.bak 's/Snapshot cadence: `1`/Snapshot cadence: `2`/' \
  "$T2/.claude/workflow/reviewers/maker-eval-corpus.md"
rm -f "$T2/.claude/workflow/reviewers/maker-eval-corpus.md.bak"
SCH2="$TMP/snap-channel-c2"
MAKER_EVAL_ROOT="$T2" MAKER_EVAL_DIR="$SCH2" bash "$EMIT" snapshot-run \
  --run-id run-S2 --task ME-01 --tier strong --workspace "$SWS" -- sleep 2.6 >/dev/null
eq "US3.AC2: cadence 2 over a 2.6s run captures exactly one snapshot" "1" \
  "$(find "$SCH2/trajectory/run-S2/ME-01/strong" -maxdepth 1 -type d -name 'interval-*' 2>/dev/null | grep -c .)"

# (iii) BYTE-IDENTICAL ON WRITE FAILURE — the same artifact-writing maker command runs once
# against a working channel and once against an unwritable one (parent is a regular file):
# equal exit codes, empty wrapper stderr, and the two workspaces diff -r identical — a
# forced snapshot-write failure never blocks, fails, or alters the maker's run (US3.AC1).
WSA="$TMP/snap-ws-ok"; WSB="$TMP/snap-ws-fail"
for w in "$WSA" "$WSB"; do mkdir -p "$w"; printf 'seed\n' > "$w/seed.txt"; done
MAKER_EVAL_ROOT="$T0" MAKER_EVAL_DIR="$TMP/snap-ok-ch" bash "$EMIT" snapshot-run \
  --run-id run-F --task ME-01 --tier strong --workspace "$WSA" -- \
  sh -c 'printf made\\n >> "$1/artifact.txt"; sleep 1.3; exit 7' _ "$WSA"; rca=$?
printf 'i am a file, not a dir\n' > "$TMP/snap-afile"
snap_err="$(MAKER_EVAL_ROOT="$T0" MAKER_EVAL_DIR="$TMP/snap-afile/sub" bash "$EMIT" snapshot-run \
  --run-id run-F --task ME-01 --tier strong --workspace "$WSB" -- \
  sh -c 'printf made\\n >> "$1/artifact.txt"; sleep 1.3; exit 7' _ "$WSB" 2>&1 1>/dev/null)"; rcb=$?
eq "US3.AC2: maker exit code propagated with a working capture path" "7" "$rca"
eq "US3.AC2: maker exit code propagated under a forced snapshot-write failure" "7" "$rcb"
eq "US3.AC2: a forced snapshot-write failure emits nothing to stderr" "" "$snap_err"
if diff -r "$WSA" "$WSB" >/dev/null 2>&1; then ok
else bad "US3.AC2: workspaces byte-identical with and without a working capture path" "$(diff -r "$WSA" "$WSB" 2>&1 | head -3)"; fi
if [ -e "$TMP/snap-afile/sub" ]; then bad "US3.AC2: a failed capture wrote nothing" "created $TMP/snap-afile/sub"; else ok; fi
# the working-channel control run did capture (the silence above is not vacuous no-capture)
eq "US3.AC2: the control run captured a snapshot" "ok" \
  "$(find "$TMP/snap-ok-ch/trajectory/run-F/ME-01/strong" -maxdepth 1 -type d -name 'interval-*' 2>/dev/null | grep -q . && echo ok)"

# (iv) TWO-SIDED TRAJECTORY-INCOMPLETE MARKING (US3.AC1/AC2). Firing side: a PLANTED
# zero-snapshot multi-interval run — trajectory storage blocked (a regular file) while the
# records stream stays writable — appends exactly ONE explicit marker line carrying the
# (run, task, tier) and the elapsed-interval evidence.
MCH="$TMP/snap-channel-marked"; mkdir -p "$MCH"
printf 'blocker\n' > "$MCH/trajectory"
MAKER_EVAL_ROOT="$T0" MAKER_EVAL_DIR="$MCH" bash "$EMIT" snapshot-run \
  --run-id run-M --task ME-01 --tier strong --workspace "$SWS" -- sleep 2.2; rc=$?
eq "US3.AC2: the marked run still propagates the maker exit code" "0" "$rc"
eq "US3.AC2: a zero-snapshot multi-interval run lands exactly one marker line" "1" \
  "$(grep -c . "$MCH/records.jsonl" 2>/dev/null || echo 0)"
MLINE="$(head -1 "$MCH/records.jsonl" 2>/dev/null)"
eq "US3.AC2: the marker is the explicit trajectory-incomplete record kind" \
  "maker-eval-trajectory-incomplete" "$(printf '%s' "$MLINE" | jq -r .record)"
eq "US3.AC2: the marker names the run id"    "run-M"  "$(printf '%s' "$MLINE" | jq -r .run_id)"
eq "US3.AC2: the marker names the task"      "ME-01"  "$(printf '%s' "$MLINE" | jq -r .task_id)"
eq "US3.AC2: the marker names the maker tier" "strong" "$(printf '%s' "$MLINE" | jq -r .maker_tier)"
eq "US3.AC2: the marker records zero snapshots over >=1 elapsed interval" "ok" \
  "$(printf '%s' "$MLINE" | jq -e '.snapshots == 0 and .intervals_elapsed >= 1' >/dev/null 2>&1 && echo ok)"
# Non-firing side: a genuinely sub-interval run (shorter than one declared interval) with the
# SAME zero snapshots appends nothing — a marking test that exercises only the firing
# direction does not satisfy US3.AC2.
UCH="$TMP/snap-channel-under"
MAKER_EVAL_ROOT="$T0" MAKER_EVAL_DIR="$UCH" bash "$EMIT" snapshot-run \
  --run-id run-U --task ME-01 --tier strong --workspace "$SWS" -- true >/dev/null
eq "US3.AC2: a genuinely sub-interval run is NOT marked trajectory-incomplete" "0" \
  "$(grep -c . "$UCH/records.jsonl" 2>/dev/null || echo 0)"

# (v) THE MARKER NEVER COUNTS AS A SCORED RECORD — completeness stays honest: score every
# (task × tier) EXCEPT ME-01@strong, land a marker for exactly that slot, and `complete`
# must still report it missing (a marked-but-unscored task is not a baseline row — the
# record-kind filter in record_present; US1.AC2/US2.AC1 unchanged by T807).
KCH="$TMP/snap-channel-complete"; mkdir -p "$KCH"
for t in ME-01 ME-02 ME-03; do
  for k in frontier strong cheap; do
    [ "$t@$k" = "ME-01@strong" ] && continue
    MAKER_EVAL_ROOT="$T0" MAKER_EVAL_DIR="$KCH" bash "$EMIT" record \
      --run-id run-K --task "$t" --tier "$k" --results "$TMP/judge.json" >/dev/null
  done
done
printf 'blocker\n' > "$KCH/trajectory"
MAKER_EVAL_ROOT="$T0" MAKER_EVAL_DIR="$KCH" bash "$EMIT" snapshot-run \
  --run-id run-K --task ME-01 --tier strong --workspace "$SWS" -- sleep 1.2 >/dev/null
out="$(MAKER_EVAL_ROOT="$T0" MAKER_EVAL_DIR="$KCH" bash "$EMIT" complete --run-id run-K)"; rc=$?
ne "US3.AC2: a trajectory-incomplete marker never satisfies completeness" "0" "$rc"
eq "US3.AC2: the marked-but-unscored slot is still reported missing" "ok" \
  "$(printf '%s' "$out" | grep -qF 'ME-01@strong' && echo ok)"

# (vi) CALLER ERRORS ARE LOUD AND THE MAKER COMMAND IS NEVER STARTED — a bad tier, a
# hostile id, and an instrument declaring no cadence each exit 2 BEFORE the run (the maker
# command below would create a sentinel file; none may exist).
SENT="$TMP/snap-sentinel"
MAKER_EVAL_ROOT="$T0" MAKER_EVAL_DIR="$TMP/snap-chX" bash "$EMIT" snapshot-run \
  --run-id run-X --task ME-01 --tier bogus --workspace "$SWS" -- touch "$SENT" >/dev/null 2>&1; rc=$?
eq "US3.AC2: a non-maker-tier --tier is a loud caller error (exit 2)" "2" "$rc"
MAKER_EVAL_ROOT="$T0" MAKER_EVAL_DIR="$TMP/snap-chX" bash "$EMIT" snapshot-run \
  --run-id '../escape' --task ME-01 --tier strong --workspace "$SWS" -- touch "$SENT" >/dev/null 2>&1; rc=$?
eq "US3.AC2: a hostile run id is a loud caller error (exit 2)" "2" "$rc"
T3="$TMP/tree-no-cadence"; build_tree "$T3"
sed -i.bak '/^## Snapshot cadence/,$d' "$T3/.claude/workflow/reviewers/maker-eval-corpus.md"
rm -f "$T3/.claude/workflow/reviewers/maker-eval-corpus.md.bak"
MAKER_EVAL_ROOT="$T3" MAKER_EVAL_DIR="$TMP/snap-chX" bash "$EMIT" snapshot-run \
  --run-id run-X --task ME-01 --tier strong --workspace "$SWS" -- touch "$SENT" >/dev/null 2>&1; rc=$?
eq "US3.AC2: an instrument declaring no cadence is a loud caller error (exit 2)" "2" "$rc"
if [ -e "$SENT" ]; then bad "US3.AC2: a rejected snapshot-run never starts the maker command" "created $SENT"; else ok; fi

# (vii) FIXED CADENCE BOUNDARIES (PR #288 owner P1) — captures are scheduled against
# deadlines derived from the LOOP START (t0 + n*cadence), so copy time never stretches the
# sampling grid to cadence+copy_duration. A `cp` shim adds ~1s per copy; at cadence 1 a
# ~4.7s run must still land interval-3 (a full-sleep-after-copy loop drifts to wakes at
# ~1.0/3.05/5.1s and never reaches it).
CPSHIM="$TMP/cp-shim"; mkdir -p "$CPSHIM"
REALCP="$(command -v cp)"
cat > "$CPSHIM/cp" <<EOF
#!/bin/sh
sleep 1
exec "$REALCP" "\$@"
EOF
chmod +x "$CPSHIM/cp"
BCH="$TMP/snap-channel-boundaries"
MAKER_EVAL_ROOT="$T0" MAKER_EVAL_DIR="$BCH" PATH="$CPSHIM:$PATH" bash "$EMIT" snapshot-run \
  --run-id run-B --task ME-01 --tier strong --workspace "$SWS" -- sleep 4.7; rc=$?
eq "US3.AC2: the boundary-scheduled run propagates the maker exit code" "0" "$rc"
BTRAJ="$BCH/trajectory/run-B/ME-01/strong"
for n in 1 2 3; do
  if [ -d "$BTRAJ/interval-$n" ]; then ok
  else bad "US3.AC2: slow copies do not drift capture off the fixed cadence boundary (interval-$n)"; fi
done

# (viii) THE ACTIVE CAPTURE CHILD IS REAPED (PR #288 Codex P2) — when the maker command
# exits mid-copy, the in-flight copy is killed and its partial `.tmp` discarded; no
# orphaned child keeps writing into the trajectory dir after snapshot-run has returned.
# A 2s `cp` shim guarantees the copy straddles the ~1.5s maker exit.
CPSHIM2="$TMP/cp-shim-slow"; mkdir -p "$CPSHIM2"
cat > "$CPSHIM2/cp" <<EOF
#!/bin/sh
sleep 2
exec "$REALCP" "\$@"
EOF
chmod +x "$CPSHIM2/cp"
RCH="$TMP/snap-channel-reap"
MAKER_EVAL_ROOT="$T0" MAKER_EVAL_DIR="$RCH" PATH="$CPSHIM2:$PATH" bash "$EMIT" snapshot-run \
  --run-id run-R --task ME-01 --tier strong --workspace "$SWS" -- sleep 1.5; rc=$?
eq "US3.AC2: the reaped run propagates the maker exit code" "0" "$rc"
RTRAJ="$RCH/trajectory/run-R/ME-01/strong"
eq "US3.AC2: no in-flight .tmp capture survives the maker command's exit" "0" \
  "$(find "$RTRAJ" -maxdepth 1 -name '*.tmp' 2>/dev/null | grep -c .)"
# an orphaned copy would finish ~0.5s from now and resurrect the .tmp tree — prove the
# child was killed, not merely its droppings swept once
sleep 1.2
eq "US3.AC2: no orphaned copy keeps writing after snapshot-run returns" "0" \
  "$(find "$RTRAJ" -maxdepth 1 \( -name '*.tmp' -o -name 'interval-*' \) 2>/dev/null | grep -c .)"

echo "maker-eval emit tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
