#!/usr/bin/env bash
# backlog-loop-iterate.sh — the [backlog-loop]'s real iteration binding (T905,
# spec 004 US1.AC7; neutral model: .claude/workflow/backlog-loop.md → "Inputs").
#
# The concrete BACKLOG_LOOP_ITERATION_CMD for backlog-loop.sh: runs ONE complete
# next-task cycle for the given task ID as a fresh [headless run] and prints the
# cycle's terminal outcome on stdout in the loop's grammar —
#     pass <pr-ref> | fail-discard | refused | aborted
# Adapter-side, so it may name concrete mechanisms — it is NOT a `workflow/**`
# neutral doc.
#
# Explicit context (workflow/README.md → "The explicit-context rule"): the task
# ID is embedded in the composed prompt text itself — every iteration names its
# task explicitly, so selection inside the cycle is an explicit pick and the
# interactive confirm pause is structurally unreachable (backlog-loop.md).
#
# Outcome transport — read from the run's OWN return, never from a report file
# (constitution P5): the composed prompt instructs the cycle to end its final
# message with exactly one marker line
#     BACKLOG-LOOP-OUTCOME: <pass <pr-ref> | fail-discard | refused | aborted>
# and this wrapper takes the LAST such line of the run's stdout. FAIL CLOSED:
# a missing marker, an unrecognized outcome, or a non-zero run exit prints
# `aborted` (the skeleton stops on condition (d)) — an unreadable cycle is
# never guessed into a pass.
#
# Required seam (NO default on purpose — the launcher owns the machine-specific
# invocation: binary path, model flag resolved from .claude/MODELS.md, auth,
# permission mode):
#   BACKLOG_LOOP_HEADLESS_CMD  a command string, run via `bash -c` with the
#       composed prompt appended as its single argument, that executes one
#       headless next-task cycle and emits the run's final message on stdout
#       (e.g. `claude -p` composed by docs/launchers/backlog-loop.sh).
#
# Usage: backlog-loop-iterate.sh <task-id>
# Exit: 0 with the outcome on stdout (aborted included); 2 on a usage error
# (missing/malformed task id or missing seam — the skeleton reads a non-zero
# exit as `aborted`, so even a misconfigured binding fails closed).
# Tests: .claude/hooks/backlog-loop-iterate.test.sh (wired into CI verify).
set -u

HEADLESS_CMD="${BACKLOG_LOOP_HEADLESS_CMD:-}"

usage() {
  echo "usage: backlog-loop-iterate.sh <task-id>   (requires BACKLOG_LOOP_HEADLESS_CMD)" >&2
  exit 2
}

[ "$#" -eq 1 ] || usage
task_id="$1"
case "$task_id" in T*) ;; *) usage ;; esac
case "${task_id#T}" in '' | *[!0-9]*) usage ;; esac
if [ -z "$HEADLESS_CMD" ]; then
  echo "backlog-loop-iterate: BACKLOG_LOOP_HEADLESS_CMD is required (the launcher composes the machine-specific headless invocation — no silent default)" >&2
  usage
fi

# The composed prompt: one complete, unmodified next-task cycle, the task ID
# explicit in the invocation text, plus the outcome-marker contract. The cycle
# itself decides pass/fail/refused/aborted — this wrapper only transports it.
# The four contract examples are INDENTED on purpose: the outcome grep below is
# anchored to column 0, so a cycle that quotes this contract back verbatim can
# never have a quoted example win the last-marker-wins parse — only the run's
# own unindented terminal line matches.
prompt="/next-task $task_id

Unattended [backlog-loop] iteration (one complete next-task cycle for $task_id — run it exactly per the workflow; never merge). When the cycle reaches its terminal state, end your final message with exactly ONE line, at the start of the line, in this form and nothing after it:
  BACKLOG-LOOP-OUTCOME: pass <pr-ref>     (the §7 gate passed and promotion opened <pr-ref>)
  BACKLOG-LOOP-OUTCOME: fail-discard      (the §7 gate failed; the workspace was discarded)
  BACKLOG-LOOP-OUTCOME: refused           ([live-state reconciliation] refused $task_id — landed or in-flight work exists)
  BACKLOG-LOOP-OUTCOME: aborted           (a lifecycle or [autonomy activation] check failed closed)"

out="$(bash -c "$HEADLESS_CMD \"\$@\"" backlog-loop-headless "$prompt" 2>/dev/null)" || { echo aborted; exit 0; }

marker="$(printf '%s\n' "$out" | grep -E '^BACKLOG-LOOP-OUTCOME:' | tail -1)"
outcome="${marker#BACKLOG-LOOP-OUTCOME:}"
# Trim surrounding whitespace without touching interior spacing (pass <pr-ref>).
outcome="$(printf '%s\n' "$outcome" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"

case "$outcome" in
  pass\ ?*)
    # A ref carrying angle brackets is the contract's own placeholder shape
    # (`pass <pr-ref>`), never a real PR reference — a quoted-contract echo,
    # not a promotion. FAIL CLOSED rather than report a fabricated pass.
    case "$outcome" in
      *"<"* | *">"*) echo aborted ;;
      *) printf '%s\n' "$outcome" ;;
    esac ;;
  fail-discard | refused | aborted) printf '%s\n' "$outcome" ;;
  *) echo aborted ;; # missing/unrecognized marker fails closed
esac
exit 0
