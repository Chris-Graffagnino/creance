#!/usr/bin/env bash
# backlog-loop-fence.sh — the deterministic P5 fence over the [backlog-loop] run
# report (T904, spec 004 US1.AC5). The runtime-neutral doc
# (.claude/workflow/backlog-loop.md → "The run report (observe-only)") states the
# boundary: NOTHING reads the report back — the loop's own control flow reads each
# iteration's outcome from the run's return, never from the report. This is the
# deterministic CI assertion enforcing it (the maker-eval-fence.sh pattern),
# rather than leaving P5 to reviewer judgment. Adapter-side, so it may name
# concrete files — it is NOT a `workflow/**` neutral doc.
#
# WHAT IT PROVES (constitution P5 — telemetry/evaluation observes, never decides):
#   The run-report records (`backlog-loop-iteration` / `backlog-loop-summary`
#   lines on the telemetry stream) and the channel access seam
#   (`BACKLOG_LOOP_REPORT_FILE`) are READ/RESOLVED only by the report WRITER
#   (hooks/backlog-loop-report.sh) and the triage READER surface (workflow/
#   triage.md + skills/triage/SKILL.md), and by NO gate-outcome, model-tier-
#   assignment, task-selection, or guard code path. The loop-control skeleton
#   (hooks/backlog-loop.sh — the T905 wrapper; scanned whenever present) may only
#   DRIVE the writer (`backlog-loop-report iteration|summary` — an append), never
#   read or resolve the channel: it is line-scoped below, not whole-file trusted,
#   the same discipline the maker-eval fence applies to its run binding. A
#   reference anywhere outside the allowlist/line-scope means a control-authority
#   path can read the observe-only run report or its iteration counters — exactly
#   the P5 breach US1.AC5 fences against.
#
# WHY TOKENS, NOT THE ABSOLUTE PATH: the report rides the EXISTING out-of-repo
# telemetry stream (telemetry.md's storage convention — a shared, run-time-
# resolved location that legitimate emitters like guard.sh also append to), so
# fencing the stream path itself would false-fire on every sanctioned telemetry
# writer. Any code that singles out the RUN REPORT — to read a verdict, count
# iterations, or resolve its seam — must name the report's own tokens (the two
# record discriminators or the env seam), so the fence keys on those.
#
# THE NON-VACUITY CONTROL (US1.AC5's "paired with a control"): after the scan the
# fence verifies the reporting path still RESOLVES the channel — the writer
# (hooks/backlog-loop-report.sh) and the reader (workflow/triage.md) must each
# reference the report tokens. If either no longer does, the fence FAILS (exit 3):
# it must never rot into scanning for a token nothing uses.
#
# DETERMINISM + FAIL-CLOSED: a plain `grep` over the tracked tree (NOT ripgrep,
# whose user config can silently skip files — the check-tasks-consistency.sh
# idiom). If the tree cannot be listed at all it exits LOUD (exit 2), not a
# silent pass (the "silently dead machinery" anti-pattern, constitution P2).
#
# Root override: BACKLOG_LOOP_FENCE_ROOT (default: the repo root) so the .test.sh
# can point the scan at a throwaway fixture tree with a planted cross-reference.
#
# Exit codes: 0 clean · 1 P5 violation · 2 unscannable (fail-closed) · 3 control
# failure (writer/reader no longer resolves the channel — the fence is vacuous).
#
# Run:   bash .claude/hooks/backlog-loop-fence.sh
# Tests: .claude/hooks/backlog-loop-fence.test.sh (wired into CI verify).
set -u

ROOT="${BACKLOG_LOOP_FENCE_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"

# The run report's reference surface, split into the two KINDS the fence
# distinguishes (so the loop skeleton can be line-scoped below):
#
#   CHANNEL_READ_TOKENS — reaching INTO the report: the two record discriminators
#   (the only handles that single the report's lines out of the shared telemetry
#   stream) and the env access seam. Naming any of these reads report content or
#   resolves the report channel directly — per spec 004 US1.AC5 only the report
#   writer and the triage reader may.
#
#   WRITER_INVOCATION — DRIVING the writer (`backlog-loop-report`): asking the
#   emitter to append a line. This is the loop wrapper's sanctioned job; it is
#   NOT a read of the report (the emitter is write-only — it has no read
#   subcommand), so the skeleton's line-scope treats a drive as benign while a
#   CHANNEL_READ_TOKENS reference there still fires.
#
# ERE; portable constructs only — no awk-style {n} interval (shell-lint.sh, #97).
CHANNEL_READ_TOKENS='backlog-loop-iteration|backlog-loop-summary|BACKLOG_LOOP_REPORT_FILE'
WRITER_INVOCATION='backlog-loop-report'
CHANNEL_TOKENS="$CHANNEL_READ_TOKENS|$WRITER_INVOCATION"

# The non-vacuity control's two reporting-path surfaces: the writer must name the
# tokens it emits/resolves, and the triage reader must name the records it
# surfaces. Withhold either resolution and the fence FAILS (exit 3).
WRITER_FILE='.claude/hooks/backlog-loop-report.sh'
READER_FILE='.claude/workflow/triage.md'

# Files permitted to carry the report tokens. Tier 1 is the AC's writer/reader
# pair — the only code/prose paths sanctioned to touch the report. Tier 2 is the
# non-executable / non-control surface that names the tokens by nature: the
# profile declaration, the extraction manifest, the probe doc, every test harness
# (tests exercise the report but carry no runtime authority), and the fence
# itself. Two surfaces are deliberately NOT blanket-allowed but line-scoped in
# the loop below: (1) CI (it RUNS the report's tests but is also a gate that
# decides the merge — see CI_BENIGN_LINE), and (2) the loop-control skeleton
# (hooks/backlog-loop.sh — it may DRIVE the writer but never read the report; it
# is where the iteration counters live, so a read-back there is the exact
# counters-feeding-control breach). Anything NOT matched here or line-scoped —
# guard.sh, gate-loop.{js,md}, MODELS.md, the reconcile-*/announce-* selection
# hooks, lib-tasks-drift.sh, next-task.md, and any future code path — is a
# gate/tier/guard/selection path, and a reference there is the P5 violation.
allowed() {
  case "$1" in
    # Tier 1 — the report's writer and its reader surfaces.
    .claude/hooks/backlog-loop-report.sh)   return 0 ;;  # the report WRITER (append-only)
    .claude/workflow/triage.md)             return 0 ;;  # the neutral triage READER spec (surfaces the batch)
    .claude/skills/triage/SKILL.md)         return 0 ;;  # the triage reader's adapter binding
    # Tier 2 — declaration / manifest / probe-doc / tests / the fence itself.
    .claude/PROJECT.md)                     return 0 ;;  # the profile path declaration
    .claude/PROJECT.template.md)            return 0 ;;  # the template's path row
    .claude/EXTRACTION.md)                  return 0 ;;  # the extraction cut-list
    .claude/adapters/claude-code-probes.md) return 0 ;;  # the T905 probe instantiation (names the report by nature)
    .claude/hooks/backlog-loop-fence.sh)    return 0 ;;  # the fence (names the tokens to scan)
    *.test.sh | *.test.js)                  return 0 ;;  # tests exercise the report (no authority)
    *) return 1 ;;
  esac
}

# CI line-scope (the maker-eval fence idiom). CI is allowlisted only for the
# wiring that RUNS the report's tests; as a gate surface it must not hide a step
# that reads the report. Each token-bearing line is a violation UNLESS benign: a
# YAML comment (cannot execute), or a step invoking a *.test.sh harness. The `$`
# anchor keeps the allowance to a bare invocation.
CI_WORKFLOW='.github/workflows/ci.yml'
CI_BENIGN_LINE='^[0-9]+:[[:space:]]*#|^[0-9]+:[[:space:]]*run: bash \.claude/hooks/[a-z0-9-]+\.test\.sh[[:space:]]*$'

# Loop-skeleton line-scope. The T905 loop wrapper (hooks/backlog-loop.sh) holds
# the iteration counters and consumes each run's outcome FROM THE RUN'S RETURN
# (backlog-loop.md — "the loop consumes outcomes from the run's return, never
# from the report"), so it may DRIVE the writer but never read/resolve the
# channel. Scanned over LOGICAL lines (backslash-continuations folded) so a
# `backlog-\<newline>loop-iteration` wrap cannot split a read token across two
# physical lines. Benign = a line whose only report token is the writer
# invocation; any CHANNEL_READ_TOKENS hit survives as a violation.
LOOP_SKELETON='.claude/hooks/backlog-loop.sh'

# Tracked-tree listing, repo-relative. git ls-files when ROOT is a work tree;
# else a find fallback so a non-git fixture still scans.
list_files() {
  if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "$ROOT" ls-files
  else
    ( cd "$ROOT" && find . -type f -not -path './.git/*' | sed 's#^\./##' )
  fi
}

# Fold shell line-continuations into ONE logical line, emitted as `grep -n`-style
# "<start-lineno>:<text>" (the maker-eval fence's fold, same POSIX awk).
fold_continuations() {
  awk '
    { buf = buf $0 }
    start == 0 { start = NR }
    /\\$/ { sub(/\\$/, "", buf); next }
    { print start ":" buf; buf = ""; start = 0 }
    END { if (start != 0) print start ":" buf }
  ' "$1"
}

files="$(list_files | LC_ALL=C sort)"
if [ -z "$files" ]; then
  printf 'backlog-loop-fence: no files to scan under %s — cannot enforce the P5 fence (failing closed).\n' "$ROOT" >&2
  exit 2
fi

violations=0
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  allowed "$rel" && continue
  if [ "$rel" = "$LOOP_SKELETON" ]; then
    hits="$(fold_continuations "$ROOT/$rel" | grep -E "$CHANNEL_TOKENS")"
  else
    hits="$(grep -I -nE "$CHANNEL_TOKENS" "$ROOT/$rel" 2>/dev/null)"
  fi
  [ -n "$hits" ] || continue
  # CI: drop the benign lines (comment / sanctioned *.test.sh wiring); what
  # survives is a violation.
  if [ "$rel" = "$CI_WORKFLOW" ]; then
    hits="$(printf '%s\n' "$hits" | grep -vE "$CI_BENIGN_LINE")"
    [ -n "$hits" ] || continue
  fi
  # The loop skeleton: keep only the channel-READ/seam hits as violations — a
  # bare writer DRIVE is its sanctioned job and drops out.
  if [ "$rel" = "$LOOP_SKELETON" ]; then
    hits="$(printf '%s\n' "$hits" | grep -E "$CHANNEL_READ_TOKENS")"
    [ -n "$hits" ] || continue
  fi
  violations=$((violations + 1))
  printf 'P5 FENCE VIOLATION: %s references the observe-only backlog-loop run report (record discriminators / channel seam) — only the report writer and the triage reader may, never a gate/tier/guard/selection path or the loop control flow (constitution P5; spec 004 US1.AC5):\n' "$rel" >&2
  printf '%s\n' "$hits" | sed 's/^/    /' >&2
done <<EOF
$files
EOF

if [ "$violations" -gt 0 ]; then
  printf 'backlog-loop-fence: %d file(s) outside the writer/reader allowlist reference the run report — P5 (observe-only) breached.\n' "$violations" >&2
  exit 1
fi

# ── the non-vacuity control (US1.AC5) ─────────────────────────────────────────────
# The fence is only meaningful while the reporting path still resolves the channel
# it scans for. If the writer or the reader stops referencing the report tokens,
# the fence is scanning for a token nothing uses — FAIL LOUD, never a silent pass.
if ! grep -qE "$CHANNEL_READ_TOKENS" "$ROOT/$WRITER_FILE" 2>/dev/null; then
  printf 'backlog-loop-fence: CONTROL FAILURE — the report writer (%s) no longer resolves the run-report channel (no record/seam token found); the fence would be vacuous.\n' "$WRITER_FILE" >&2
  exit 3
fi
if ! grep -qE "$CHANNEL_READ_TOKENS" "$ROOT/$READER_FILE" 2>/dev/null; then
  printf 'backlog-loop-fence: CONTROL FAILURE — the triage reader (%s) no longer resolves the run-report records (no record token found); the fence would be vacuous.\n' "$READER_FILE" >&2
  exit 3
fi

printf 'backlog-loop-fence: OK — the run report (backlog-loop-iteration/-summary records + the channel seam) is referenced only by the report writer and the triage reader, and both still resolve it.\n'
exit 0
