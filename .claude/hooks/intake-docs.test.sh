#!/usr/bin/env bash
# Encoding tests for US6.AC1 / US6.AC3 / US6.AC4 (T501).
#
# The triage and intake procedures are runtime-neutral prose executed by the
# engine — `.claude/workflow/triage.md` and `.claude/workflow/intake.md` ARE the
# implementation; there is no executable code path to unit-test. These tests
# therefore encode each criterion against that surface: the required sections,
# the exact output shape (including the explicit empty state — the criteria's
# negative case), and the write-posture invariants must be present and stated
# as hard bounds, so a later edit that drops any of them fails the `verify` CI
# job. Live-runtime conformance of the same behaviors is covered by the P-IN
# conformance probe (workflow/conformance-probes.md → "P-IN", results recorded
# in adapters/claude-code-probes.md), per US6.AC6.
#
# Run: bash .claude/hooks/intake-docs.test.sh
set -u

DIR="$(cd "$(dirname "$0")/.." && pwd)"
TRIAGE="$DIR/workflow/triage.md"
INTAKE="$DIR/workflow/intake.md"

pass=0
fail=0

# Normalize whitespace so assertions survive prose re-wrapping.
flat() { tr -s '[:space:]' ' ' < "$1"; }
TRIAGE_FLAT="$(flat "$TRIAGE")"
INTAKE_FLAT="$(flat "$INTAKE")"

check() { # check <name> <haystack> <needle (grep -F fixed string)>
  local name="$1" hay="$2" needle="$3"
  if printf '%s' "$hay" | grep -qF -- "$needle"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL %s\n     missing: %s\n' "$name" "$needle" >&2
  fi
}

# ── US6.AC1 — triage detects unmapped tracker work, read-only ──────────────────
# Detection rule: title carries no task ID AND no live tasks-file line references it.
check "AC1 detection: section defined" "$TRIAGE_FLAT" \
  "**Unmapped tracker work.**"
check "AC1 detection: no-task-ID criterion" "$TRIAGE_FLAT" \
  "title carries no task ID"
check "AC1 detection: tasks-file cross-reference criterion" "$TRIAGE_FLAT" \
  "no live tasks-file line references"
check "AC1 detection: one line per issue (number, title, age)" "$TRIAGE_FLAT" \
  "One line per issue: number, title, age."
check "AC1 read-only: triage detects, never converts" "$TRIAGE_FLAT" \
  "**Detection only:**"
check "AC1 read-only: conversion delegated to intake workflow" "$TRIAGE_FLAT" \
  "the intake [workflow]'s job (\`intake.md\`)"
# Snapshot output shape: the section, its explicit empty state (the criterion's
# negative case), and the non-empty pointer to run intake.
check "AC1 output: snapshot section header" "$TRIAGE_FLAT" \
  "## Unmapped tracker work"
check "AC1 output: one-line-per-issue format" "$TRIAGE_FLAT" \
  "- #<n> <title> — opened <age/date>"
check "AC1 output: explicit empty state" "$TRIAGE_FLAT" \
  '(or "none — every open issue is mapped to a task ID")'
check "AC1 output: non-empty state points at intake" "$TRIAGE_FLAT" \
  "run the intake [workflow] (\`intake.md\`) to convert them"

# ── US6.AC3 — conversions land only as PRs; write posture is bounded ───────────
check "AC3 posture: repo written only on an intake branch" "$INTAKE_FLAT" \
  "**The repo is written only on an intake branch.**"
check "AC3 posture: never edit base-branch tasks file/spec" "$INTAKE_FLAT" \
  "Never edit a live tasks file, spec, or any other repo file on the base branch."
check "AC3 posture: standard branch -> gate -> PR flow" "$INTAKE_FLAT" \
  "branch → §7 gate → PR"
check "AC3 posture: conversion PR never closes the source issue" "$INTAKE_FLAT" \
  "**The conversion PR does not close the source issue.**"
check "AC3 posture: no closing keyword in the PR body" "$INTAKE_FLAT" \
  "without a closing keyword"
check "AC3 posture: intake never merges its own PR" "$INTAKE_FLAT" \
  "never merges its own conversion PR"
check "AC3 posture: task IDs append-only, never renumbered" "$INTAKE_FLAT" \
  "**append-only, never renumber**"

# ── US6.AC4 — retitle to convention + marked harness comment ───────────────────
check "AC4: issue retitled to the task-ID title convention" "$INTAKE_FLAT" \
  "retitle the issue to the profile's \`<type>: [<task-id>] <description>\` convention"
check "AC4: cross-link comment is marked (provenance rules)" "$INTAKE_FLAT" \
  "post a marked comment with the assigned task ID"
check "AC4: marked comment carries the drafted acceptance criteria" "$INTAKE_FLAT" \
  "the drafted acceptance criteria, and the PR reference"

# ── Runtime-conformance pointer: P-IN probe must exist and encode (b)(c)(d) ────
PROBES="$DIR/workflow/conformance-probes.md"
PROBES_FLAT="$(flat "$PROBES")"
check "P-IN: probe defined in the neutral checklist" "$PROBES_FLAT" \
  "### P-IN — intake (\`intake.md\`)"
check "P-IN: base branch byte-identical after the run" "$PROBES_FLAT" \
  "the base branch and its tasks files are byte-identical after the run"
check "P-IN: retitle + task ID + drafted ACs verified" "$PROBES_FLAT" \
  "retitled to the task-ID convention and the marked comment carries the assigned task ID and drafted acceptance criteria"
check "P-IN: no closing keyword, no issue closed, no merge" "$PROBES_FLAT" \
  "no closing keyword for the fixture issue appears in any PR the run opens, no issue is closed, and no merge is performed"

printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
