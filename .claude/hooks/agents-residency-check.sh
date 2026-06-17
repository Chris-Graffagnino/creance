#!/usr/bin/env bash
# AGENTS.md residency backstop (issue #91; principle: DESIGN-NOTES §11, #9).
#
# AGENTS.md is imported into EVERY session (CLAUDE.md -> @AGENTS.md), so it is
# the L1 "always resident" tier: every line is a per-turn token tax on every
# task. DESIGN-NOTES §11 (frequency-weighted placement) names the invisible
# regression this guards — an adopter pastes a full procedure manual or style
# guide into AGENTS.md and silently taxes every turn. Constitution P3
# (determinism over model-noticing) wants that rule backstopped by a check, not
# left to a reviewer's eye. This is the blunt, deterministic form: a line
# ceiling. It catches gross size bloat; it does NOT catch a procedure inlined
# under the ceiling — that stays a judgment call for the constitution auditor.
#
# Bash + wc only; no git, no network. Resolves AGENTS.md relative to CWD (the
# same CWD contract check-tasks-consistency.sh uses; CI runs it from the repo
# root). Run: bash .claude/hooks/agents-residency-check.sh
set -u

# The ceiling. AGENTS.md is per-turn rules + pointers, not a manual: keep it
# terse and push procedures into .claude/workflow/** behind pointers
# (DESIGN-NOTES §11). 137 lines when this check landed (#91); 200 leaves ~46%
# headroom for adopter-specific rules before it trips. Tune here only.
CEILING=200
FILE="AGENTS.md"

if [ ! -f "$FILE" ]; then
  echo "FAIL: $FILE not found in $(pwd) — run the residency check from the repo root" >&2
  exit 1
fi

lines=$(wc -l < "$FILE" | tr -d '[:space:]')
if [ "$lines" -gt "$CEILING" ]; then
  {
    echo "FAIL: $FILE is $lines lines, over the $CEILING-line residency ceiling."
    echo "      AGENTS.md is resident in EVERY session (DESIGN-NOTES §11): keep it"
    echo "      per-turn rules + pointers; move procedures into .claude/workflow/**."
  } >&2
  exit 1
fi

echo "AGENTS.md residency: OK ($lines/$CEILING lines)"
