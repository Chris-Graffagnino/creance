#!/usr/bin/env bash
# backlog-loop-report.sh — the [backlog-loop]'s observe-only run-report emitter
# (T904, spec 004 US1.AC6). The runtime-neutral docs define the report's SHAPE and
# channel (`.claude/workflow/backlog-loop.md` → "The run report (observe-only)":
# one line per iteration — the task ID plus that iteration's terminal outcome in
# the outcome's OWN form — plus one terminal run-summary line) and the storage
# convention (`.claude/workflow/telemetry.md`: one out-of-repo append-only JSONL
# stream per project, shared by every record type, discriminated by the `record`
# field). This is the concrete adapter mechanism; the live loop composition that
# drives it is T905's. Adapter-side, so it may name concrete tools (jq, git) —
# it is NOT a `workflow/**` neutral doc.
#
# OBSERVE-ONLY (constitution P5; telemetry.md's law: telemetry observes, never
# decides). This script only APPENDS to the run-report channel — it is WRITE-ONLY
# and reads nothing back: no gate, tier, guard, or selection state in, and no
# value any such path consumes out. A write failure is SILENT-TO-THE-RUN: it never
# aborts an in-flight iteration, never blocks a promotion, and never exits
# non-zero after the caller's arguments validated — mirroring the telemetry
# emitter (guard.sh → log_telemetry), which appends to the SAME stream.
#
# Subcommands (driven by the loop wrapper, one call per report line):
#   iteration <run-id> <task-id> <outcome...>
#       Append EXACTLY ONE `backlog-loop-iteration` record for one completed
#       iteration. <outcome...> is that iteration's terminal outcome in the
#       outcome's own form (backlog-loop.md — a report line NEVER fabricates a
#       gate result):
#         pass <verdict> <pr-ref>   — gate PASS: records the gate verdict and the
#                                     resulting PR reference (`pr` field);
#         fail-discard <verdict>    — gate FAIL: records the verdict and the
#                                     discard (`disposition:"discard"` field);
#         refused                   — [live-state reconciliation]'s positive
#                                     refusal: no gate ran, so the record carries
#                                     NO verdict and NO pr/disposition field;
#         aborted                   — a lifecycle/[autonomy activation] check
#                                     failed closed mid-cycle: likewise NO verdict
#                                     and NO pr/disposition field.
#       Extra arguments on a refused/aborted outcome are a LOUD caller error
#       (exit 2, nothing written) — the only way to attach a verdict or artifact
#       to an ungated iteration is a caller bug fabricating a gate result.
#   summary <run-id> <stop-condition> <iterations> <N>
#       Append EXACTLY ONE terminal `backlog-loop-summary` record carrying the
#       stop condition and `iterations of N` (`iterations`/`budget` fields), so a
#       partially completed run is visible AS partial from the line itself —
#       never mistaken for a clean drain, never an error baseline (US1.AC6).
#
# Channel resolution (the run report goes to the EXISTING telemetry stream —
# telemetry.md's storage convention; NO new path convention), precedence:
#   1. BACKLOG_LOOP_REPORT_FILE — test/override seam (mirrors GUARD_TELEMETRY_FILE);
#   2. the profile — .claude/PROJECT.md → "Paths" → Telemetry: the bullet's first
#      backticked `.jsonl` path; a placeholder-bearing value (contains `<...>`)
#      describes the default in prose and is not an override;
#   3. the shipped default — <home>/.claude/triage/<repo-basename>-telemetry.jsonl.
# The parent directory is created if missing; any failure to resolve, create, or
# append is silent (exit 0, nothing written).
#
# Run: bash .claude/hooks/backlog-loop-report.sh <subcommand> [args]
# Tests: .claude/hooks/backlog-loop-report.test.sh (wired into CI verify).
# P5 fence: .claude/hooks/backlog-loop-fence.sh — this writer and the triage
# reader are the only surfaces sanctioned to name the channel's record tokens.
set -u

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
PROFILE="${BACKLOG_LOOP_PROJECT_FILE:-$SELF_DIR/../PROJECT.md}"

usage() {
  printf 'usage: %s {iteration <run-id> <task-id> (pass <verdict> <pr-ref> | fail-discard <verdict> | refused | aborted) | summary <run-id> <stop-condition> <iterations> <N>}\n' \
    "$(basename "$0")" >&2
}

# ── channel resolution (guard.sh → telemetry_file convention) ───────────────────
profile_channel() {
  sed -n '/^[-*][[:space:]]*\*\*Telemetry:\*\*/,/^[-*#]/p' "$PROFILE" 2>/dev/null \
    | grep -oE '`[^`<]+\.jsonl`' | head -1 | tr -d '`'
}

report_file() {
  if [ -n "${BACKLOG_LOOP_REPORT_FILE:-}" ]; then
    printf '%s' "$BACKLOG_LOOP_REPORT_FILE"
    return 0
  fi
  local home="${HOME:-${USERPROFILE:-}}" root p
  p="$(profile_channel)"
  if [ -n "$p" ]; then
    case "$p" in
      "~/"*) [ -n "$home" ] || return 1; printf '%s/%s' "$home" "${p#\~/}" ;;
      /*|[a-zA-Z]:*) printf '%s' "$p" ;;
      *) root="$(git rev-parse --show-toplevel 2>/dev/null)" || return 1
         printf '%s/%s' "$root" "$p" ;;
    esac
    return 0
  fi
  [ -n "$home" ] || return 1
  root="$(git rev-parse --show-toplevel 2>/dev/null)" || return 1
  printf '%s/.claude/triage/%s-telemetry.jsonl' "$home" "${root##*/}"
}

repo_basename() {
  local r
  r="$(git rev-parse --show-toplevel 2>/dev/null)" || r="$PWD"
  printf '%s' "${r##*/}"
}

# ── the write (silent-to-the-run) ────────────────────────────────────────────────
# Everything past argument validation is a WRITE path: any failure exits 0 with
# nothing written and nothing on stdout (an optional stderr warning only), so the
# run the report observes proceeds exactly as if the write had succeeded. The
# record is echoed on stdout ONLY after the append landed — a partial write is
# never reported as a landed line.
append_record() { # <record-json>
  local f
  {
    f="$(report_file)" || return 0
    [ -n "$f" ] || return 0
    mkdir -p "$(dirname "$f")" || return 0
    printf '%s\n' "$1" >> "$f" || return 0
  } 2>/dev/null || return 0
  printf '%s\n' "$1"
}

do_iteration() {
  local run_id="${1:-}" task_id="${2:-}" outcome="${3:-}"
  [ "$#" -ge 3 ] && shift 3 || { usage; return 2; }
  if [ -z "$run_id" ] || [ -z "$task_id" ] || [ -z "$outcome" ]; then
    usage; return 2
  fi

  # The outcome's own form (backlog-loop.md): a GATED outcome carries the gate
  # verdict + PR-or-discard; refused/aborted carry NEITHER. Arity is exact — a
  # missing field on a gated outcome, or an extra one on an ungated outcome
  # (a fabricated gate result), is a LOUD caller error, never a defaulted line.
  local verdict="" pr=""
  case "$outcome" in
    pass)
      if [ "$#" -ne 2 ] || [ -z "$1" ] || [ -z "$2" ]; then
        printf 'backlog-loop-report: iteration pass needs exactly <verdict> <pr-ref>\n' >&2
        return 2
      fi
      verdict="$1"; pr="$2" ;;
    fail-discard)
      if [ "$#" -ne 1 ] || [ -z "$1" ]; then
        printf 'backlog-loop-report: iteration fail-discard needs exactly <verdict>\n' >&2
        return 2
      fi
      verdict="$1" ;;
    refused | aborted)
      if [ "$#" -ne 0 ]; then
        printf 'backlog-loop-report: a %s iteration ran no gate — it takes no verdict or PR/discard field (a report line never fabricates a gate result)\n' "$outcome" >&2
        return 2
      fi ;;
    *)
      printf 'backlog-loop-report: unknown iteration outcome [%s] (pass | fail-discard | refused | aborted)\n' "$outcome" >&2
      return 2 ;;
  esac

  # From here every failure is a WRITE failure: silent-to-the-run (exit 0).
  local ts repo rec
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)" || return 0
  repo="$(repo_basename)"
  rec="$(jq -cn \
    --arg ts "$ts" --arg repo "$repo" --arg run "$run_id" --arg task "$task_id" \
    --arg outcome "$outcome" --arg verdict "$verdict" --arg pr "$pr" \
    '{record:"backlog-loop-iteration", timestamp:$ts, repo:$repo, run_id:$run,
      task_id:$task, outcome:$outcome}
     + (if $outcome == "pass"         then {verdict:$verdict, pr:$pr}
        elif $outcome == "fail-discard" then {verdict:$verdict, disposition:"discard"}
        else {} end)' 2>/dev/null)" || return 0
  [ -n "$rec" ] || return 0
  append_record "$rec"
}

do_summary() {
  local run_id="${1:-}" stop="${2:-}" iterations="${3:-}" budget="${4:-}"
  if [ "$#" -ne 4 ] || [ -z "$run_id" ] || [ -z "$stop" ] || [ -z "$iterations" ] || [ -z "$budget" ]; then
    usage; return 2
  fi
  # `iterations of N` must be two honest counters — a non-integer is a LOUD
  # caller error (never a defaulted or truncated figure).
  case "$iterations" in *[!0-9]* | "") usage; return 2 ;; esac
  case "$budget"     in *[!0-9]* | "") usage; return 2 ;; esac

  # From here every failure is a WRITE failure: silent-to-the-run (exit 0).
  local ts repo rec
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)" || return 0
  repo="$(repo_basename)"
  rec="$(jq -cn \
    --arg ts "$ts" --arg repo "$repo" --arg run "$run_id" --arg stop "$stop" \
    --argjson i "$iterations" --argjson n "$budget" \
    '{record:"backlog-loop-summary", timestamp:$ts, repo:$repo, run_id:$run,
      stop:$stop, iterations:$i, budget:$n}' 2>/dev/null)" || return 0
  [ -n "$rec" ] || return 0
  append_record "$rec"
}

cmd="${1:-}"
[ "$#" -gt 0 ] && shift
case "$cmd" in
  iteration) do_iteration "$@" ;;
  summary)   do_summary "$@" ;;
  *) usage; exit 2 ;;
esac
