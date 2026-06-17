#!/usr/bin/env bash
# next-task.md budget backstop (issue #93; analysis follow-up to #91).
#
# .claude/workflow/next-task.md is the largest methodology doc and the hub every
# task touches (the per-/next-task context load): new rules gravitate to it, so it
# is the harness's accretion sink. Unlike AGENTS.md (resident every turn, guarded
# by agents-residency-check.sh), next-task.md loads on-demand — but it still sets
# the per-workflow context floor, and that floor rises monotonically if nothing
# watches it. This is the deterministic budget: a line ceiling whose crossing
# forces a conscious "split a section into a sub-doc, or consciously raise the
# bound in a reviewed PR" decision, instead of silent growth.
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

# The budget. next-task.md is the on-demand hub doc, not a manual: keep sections
# tight and split or pointer-out procedures as it grows (DESIGN-NOTES §11, the L2
# tier). 400 lines when this check landed (#93); 500 leaves ~25% headroom (~9K
# tokens) before it trips. Tune here only.
CEILING=500
FILE=".claude/workflow/next-task.md"

if [ ! -f "$FILE" ]; then
  echo "FAIL: $FILE not found in $(pwd) — run the budget check from the repo root" >&2
  exit 1
fi

lines=$(wc -l < "$FILE" | tr -d '[:space:]')
if [ "$lines" -gt "$CEILING" ]; then
  {
    echo "FAIL: $FILE is $lines lines, over the $CEILING-line budget."
    echo "      next-task.md is the per-/next-task hub doc (DESIGN-NOTES §11): split a"
    echo "      section into a sub-doc behind a pointer, or raise CEILING in a reviewed PR."
  } >&2
  exit 1
fi

echo "next-task.md budget: OK ($lines/$CEILING lines)"
