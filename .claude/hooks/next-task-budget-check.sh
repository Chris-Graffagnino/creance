#!/usr/bin/env bash
# next-task.md index budget backstop (issue #93; re-scoped by T1204).
#
# T1204 turned .claude/workflow/next-task.md from the monolithic procedure into
# the ordered index for demand-loaded cards. This legacy line gate now prevents
# procedure prose from silently being re-inlined into the index; the active token
# budget in context-budgets.md independently caps every card.
#
# It is a HARD gate with generous headroom, not an exit-0 warning: an always-green
# warning is the silently-dead-machinery anti-pattern this codebase rejects (P2;
# DESIGN-NOTES §"the guard was silently dead"). Catching gross size growth is the
# deterministic part; whether a given addition *should* live here vs. a sub-doc
# stays an authoring judgment.
#
# Bash + wc only; no git, no network. Resolves the file relative to CWD (the same
# CWD contract check-tasks-consistency.sh / agents-residency-check.sh use; CI runs
# it from the repo root). Run: bash .claude/hooks/next-task-budget-check.sh
set -u

# The index needs only ordering, links, and the completeness-check pointer. A
# 100-line ceiling leaves ample navigation headroom while making re-inlining fail.
CEILING=100
FILE=".claude/workflow/next-task.md"

if [ ! -f "$FILE" ]; then
  echo "FAIL: $FILE not found in $(pwd) — run the budget check from the repo root" >&2
  exit 1
fi

lines=$(wc -l < "$FILE" | tr -d '[:space:]')
if [ "$lines" -gt "$CEILING" ]; then
  {
    echo "FAIL: $FILE is $lines lines, over the $CEILING-line budget."
    echo "      next-task.md is the demand-loaded card index: move procedure prose into a"
    echo "      stage card, or raise CEILING in a reviewed PR."
  } >&2
  exit 1
fi

echo "next-task.md budget: OK ($lines/$CEILING lines)"
