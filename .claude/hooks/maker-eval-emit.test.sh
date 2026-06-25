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
  --run-id run-A --task ME-01 --results "$TMP/judge.json" \
  --prompt "$TMP/prompt.txt" --artifact "$TMP/artifact.diff" --judge "$TMP/judge-report.md")"

eq "AC2: exactly one JSONL line written" "1" "$(grep -c . "$CH/records.jsonl" 2>/dev/null)"
eq "AC2: record is valid JSON"        "ok" "$(printf '%s' "$LINE" | jq -e . >/dev/null 2>&1 && echo ok)"
eq "AC2: record carries the run id"   "run-A" "$(printf '%s' "$LINE" | jq -r .run_id)"
eq "AC2: record carries the task id"  "ME-01" "$(printf '%s' "$LINE" | jq -r .task_id)"
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

# append-only: a second task appends a second line (does not overwrite)
MAKER_EVAL_ROOT="$T0" MAKER_EVAL_DIR="$CH" bash "$EMIT" record \
  --run-id run-A --task ME-02 --results "$TMP/judge.json" >/dev/null
eq "AC2: records are append-only (2 tasks -> 2 lines)" "2" "$(grep -c . "$CH/records.jsonl")"

# ── AC2: PARTIAL-RUN-IS-NOT-A-BASELINE ───────────────────────────────────────────
# Two of three corpus tasks recorded under run-A -> incomplete (non-zero).
out="$(MAKER_EVAL_ROOT="$T0" MAKER_EVAL_DIR="$CH" bash "$EMIT" complete --run-id run-A)"; rc=$?
ne "AC2: partial run exits non-zero (not a baseline)" "0" "$rc"
eq "AC2: partial run renders as incomplete" "ok" "$(printf '%s' "$out" | grep -q '^incomplete' && echo ok)"
eq "AC2: incomplete names the missing task" "ok" "$(printf '%s' "$out" | grep -q 'ME-03' && echo ok)"
# complete the run -> exit 0, "complete"
MAKER_EVAL_ROOT="$T0" MAKER_EVAL_DIR="$CH" bash "$EMIT" record \
  --run-id run-A --task ME-03 --results "$TMP/judge.json" >/dev/null
out="$(MAKER_EVAL_ROOT="$T0" MAKER_EVAL_DIR="$CH" bash "$EMIT" complete --run-id run-A)"; rc=$?
eq "AC2: a full run exits 0" "0" "$rc"
eq "AC2: a full run renders as complete" "complete" "$out"
# an empty/absent stream is incomplete, never a silent baseline
out="$(MAKER_EVAL_ROOT="$T0" MAKER_EVAL_DIR="$TMP/empty-ch" bash "$EMIT" complete --run-id run-Z)"; rc=$?
ne "AC2: an absent stream is incomplete (no silent baseline)" "0" "$rc"

# ── AC2: WRITE-FAILURE-STAYS-SILENT ──────────────────────────────────────────────
# Channel parent is a regular file, so mkdir -p must fail. The emitter must exit 0,
# print nothing to stderr, and write no record (the gate-telemetry silent-write law).
printf 'i am a file, not a dir\n' > "$TMP/afile"
err="$(MAKER_EVAL_ROOT="$T0" MAKER_EVAL_DIR="$TMP/afile/sub" bash "$EMIT" record \
  --run-id run-B --task ME-01 --results "$TMP/judge.json" 2>&1 1>/dev/null)"; rc=$?
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

echo "maker-eval emit tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
