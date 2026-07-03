#!/usr/bin/env bash
# Encoding tests for US6.AC1 / US6.AC2 / US6.AC3 / US6.AC4 / US6.AC5 (T501) and
# US7.AC1 / US7.AC2 / US7.AC3 / US7.AC4 (T204 — triage "Unacknowledged owner
# comments"), plus T606 (#76; repo-maintenance — done-when on issue): the §4
# gameability screen, its mirror as a named step in the acceptance reviewer's
# intake-conversion mode (so a prose-only addition does not satisfy the gate),
# and the spec-auditor left-shift note. T705 (#219; US2.AC4) de-forks the
# gameability rule: its single canonical home is the shared spec-quality reviewer
# (`reviewers/spec-quality-auditor.md` hunt (d)) and intake §4 delegates to it — a
# re-fork (re-inlining the worked-example prose into intake) FAILs CI here.
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
# shellcheck source=lib-neutrality-scan.sh
. "$DIR/hooks/lib-neutrality-scan.sh"
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

check_absent() { # check_absent <name> <haystack> <needle> — FAIL if the needle IS present
  local name="$1" hay="$2" needle="$3"
  if printf '%s' "$hay" | grep -qF -- "$needle"; then
    fail=$((fail + 1))
    printf 'FAIL %s\n     unexpectedly present: %s\n' "$name" "$needle" >&2
  else
    pass=$((pass + 1))
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

# ── US6.AC2 — five-bucket classification, constitution screen, never guess ─────
check "AC2 taxonomy: exactly one bucket per issue" "$INTAKE_FLAT" \
  "## 2. Classify (exactly one bucket per issue)"
check "AC2 taxonomy: bucket 1 spec work" "$INTAKE_FLAT" \
  "1. **Spec work**"
check "AC2 taxonomy: bucket 2 repo-maintenance" "$INTAKE_FLAT" \
  "2. **Repo-maintenance**"
check "AC2 taxonomy: bucket 3 bug against the base branch" "$INTAKE_FLAT" \
  "3. **Bug against the base branch**"
check "AC2 taxonomy: bucket 4 duplicate" "$INTAKE_FLAT" \
  "4. **Duplicate**"
check "AC2 taxonomy: bucket 5 underspecified" "$INTAKE_FLAT" \
  "5. **Underspecified**"
check "AC2 screen: constitution screened before any drafting" "$INTAKE_FLAT" \
  "## 3. Constitution screen (before any drafting)"
check "AC2 screen: conflicts surfaced, never silently converted" "$INTAKE_FLAT" \
  "**surfaced on the issue — never silently converted**"
check "AC2 underspecified: decision-ready ask shape" "$INTAKE_FLAT" \
  "\`Decision needed:\` / \`Recommendation:\` pair"
check "AC2 underspecified: owner intent never guessed" "$INTAKE_FLAT" \
  "**Never guess owner intent into acceptance criteria.**"

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

# ── US6.AC5 — skill binding exists; no new binding-contract role ───────────────
SKILL="$DIR/skills/intake/SKILL.md"
if [ -r "$SKILL" ]; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  printf 'FAIL AC5: skill binding file present\n     missing: %s\n' "$SKILL" >&2
fi
SKILL_FLAT="$(flat "$SKILL")"
check "AC5: binding executes the runtime-neutral workflow doc" "$SKILL_FLAT" \
  "\`.claude/workflow/intake.md\`"
check "AC5: workflow composes existing roles only" "$INTAKE_FLAT" \
  "Intake composes existing roles only"
# Negative case: the binding-contract table in workflow/README.md must NOT gain
# an intake role row (intake composes existing roles; it appears only in the
# Files list).
README_FLAT="$(flat "$DIR/workflow/README.md")"
if printf '%s' "$README_FLAT" | grep -qF -- "| **[intake]**"; then
  fail=$((fail + 1))
  printf 'FAIL AC5: no [intake] role row in the binding-contract table\n' >&2
else
  pass=$((pass + 1))
fi

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

# ── US7.AC1 — triage surfaces unacknowledged owner comments, read-only ─────────
# Detection: unmarked owner-login comments newer than the last harness-marked
# activity, for each open issue and PR.
check "US7.AC1 detection: section defined" "$TRIAGE_FLAT" \
  "**Unacknowledged owner comments.**"
check "US7.AC1 detection: per open issue and PR" "$TRIAGE_FLAT" \
  "For each open issue and PR, the unmarked owner-login comments"
check "US7.AC1 detection: newer than last harness-marked activity" "$TRIAGE_FLAT" \
  "newer than the **last harness-marked activity** on that thread"
# Read phase (§1) must fetch the comment/timeline evidence the derivation needs,
# else a headless run renders the section empty/stale (Codex P2, PR #39).
check "US7.AC1 read phase: fetch comment threads + timeline events" "$TRIAGE_FLAT" \
  "**For each open issue and PR, fetch its comment thread and cross-referenced timeline events**"
check "US7.AC1 output: one line per comment shape" "$TRIAGE_FLAT" \
  "One line per comment: item number, comment date, the comment's first line."
# Snapshot output shape: the section, its one-line format, and the explicit
# empty state (the criterion's negative case).
check "US7.AC1 output: snapshot section header" "$TRIAGE_FLAT" \
  "## Unacknowledged owner comments"
check "US7.AC1 output: one-line-per-comment format" "$TRIAGE_FLAT" \
  '- #<n> (<issue|PR>) <comment-date> — "<comment'"'"'s first line>"'
check "US7.AC1 output: explicit empty state" "$TRIAGE_FLAT" \
  '(or "none — no unmarked owner comment is newer than the last harness-marked activity")'

# ── US7.AC2 — "last harness-marked activity" is defined ────────────────────────
check "US7.AC2: marked comment OR cross-referenced harness event" "$TRIAGE_FLAT" \
  "the newest **[comment marker]**-marked comment on the thread, or the newest cross-referenced harness commit/PR event"
check "US7.AC2: no-marked-activity fallback to last harness action" "$TRIAGE_FLAT" \
  "when the thread carries no marked activity, any owner comment newer than the item's last cross-referenced harness action counts"

# ── US7.AC3 — detection is read-only; acting on it is next-task's job ───────────
check "US7.AC3: detection only, triage stays read-only" "$TRIAGE_FLAT" \
  "**Detection only:** triage names the unacknowledged comment and stays"
check "US7.AC3: acting on it is next-task's job" "$TRIAGE_FLAT" \
  "acting on it is the next-task [workflow]'s job"
check "US7.AC3: posts nothing, marks nothing, mutates nothing" "$TRIAGE_FLAT" \
  "triage posts nothing, marks nothing, and mutates no thread state"

# ── US7.AC4 — references the [comment marker] role only, no concrete string ─────
check "US7.AC4: references the [comment marker] role" "$TRIAGE_FLAT" \
  "The **[comment marker]** separates"
# Negative case: triage.md must NOT inline the adapter's concrete marker string
# (the literal lives only adapter-side; workflow/** references the role). The
# marker's recognizable substring "engine-authored, not owner steering" must be
# absent from the neutral triage doc.
if printf '%s' "$TRIAGE_FLAT" | grep -qF -- "engine-authored, not owner steering"; then
  fail=$((fail + 1))
  printf 'FAIL US7.AC4: triage.md must not inline the concrete marker string\n' >&2
else
  pass=$((pass + 1))
fi

# ── T606 — gameability screen at intake (#76; repo-maintenance — done-when) ────
SPEC_AUDITOR="$DIR/workflow/reviewers/spec-auditor.md"
SPEC_AUDITOR_FLAT="$(flat "$SPEC_AUDITOR")"
# T705 (US2.AC4): the gameability rule is de-forked. Its single canonical home is the
# shared spec-quality reviewer; intake §4 delegates to it instead of carrying a forked
# copy. So the worked-example prose (the `if x: return y` shape and the one-sided shape)
# now lives in spec-quality-auditor.md, and intake §4 points there.
SPEC_QUALITY_AUDITOR="$DIR/workflow/reviewers/spec-quality-auditor.md"
# Extract ONLY the '- **(d) Gameability**' bullet (through its indented continuation,
# stopping at the next top-level bullet or heading): the invariant is that the canonical
# phrase and BOTH worked shapes live INSIDE hunt (d), not merely somewhere in the file —
# a whole-file check would keep passing if the worked examples drifted out of the hunt.
hunt_d_block() {
  awk '
    d && (/^- \*\*\(/ || /^#/) { exit }
    /^- \*\*\(d\) Gameability\*\*/ { d = 1 }
    d { print }
  ' "$1"
}
SPEC_QUALITY_HUNT_D="$(hunt_d_block "$SPEC_QUALITY_AUDITOR" | tr -s '[:space:]' ' ')"

# DW1 — intake.md §4 still runs the gameability screen at draft time, but now DELEGATES
# to the shared reviewer's check rather than restating the rule.
check "T606 DW1: §4 gameability-screen heading" "$INTAKE_FLAT" \
  "Screen each drafted criterion for gameability"
check "T606 DW1: the screen names the cheapest satisfy-without-the-work path" "$INTAKE_FLAT" \
  "cheapest way to satisfy the criterion without doing the real work"

# T705 (US2.AC4): the canonical rule lives in the shared spec-quality reviewer's hunt (d),
# carrying BOTH worked shapes — the single definition intake delegates to. Each assertion
# runs against the extracted hunt-(d) block, so moving the canonical phrase or a worked
# shape elsewhere in the file (outside hunt (d)) FAILs.
check "T705 canonical: hunt (d) block extracted (non-empty)" "$SPEC_QUALITY_HUNT_D" \
  "(d) Gameability"
check "T705 canonical: hunt (d) is the single gameability definition" "$SPEC_QUALITY_HUNT_D" \
  "single canonical definition of the gameability screen"
check "T705 canonical: hunt (d) carries the trivially-satisfiable worked example (if x: return y)" "$SPEC_QUALITY_HUNT_D" \
  "if x: return y"
check "T705 canonical: hunt (d) carries the one-sided (recall without precision) worked example" "$SPEC_QUALITY_HUNT_D" \
  "One-sided (recall without precision)"

# T705 (US2.AC4): intake §4 DELEGATES to that single definition (points at the reviewer's
# hunt (d)) and names the one-definition/two-consumers de-fork.
check "T705 delegate: intake §4 delegates to the shared reviewer's gameability check" "$INTAKE_FLAT" \
  "spec-quality [reviewer]'s gameability check"
check "T705 delegate: intake §4 points at reviewers/spec-quality-auditor.md hunt (d)" "$INTAKE_FLAT" \
  "\`reviewers/spec-quality-auditor.md\` → hunt **(d)**"
check "T705 delegate: intake §4 names the one-definition/two-consumers de-fork" "$INTAKE_FLAT" \
  "one definition, two consumers (the spec gate and intake)"

# T705 (US2.AC4): the acceptance reviewer's intake-conversion mode is the third consumer —
# its gameability bullet must also point at the canonical home (reviewers/
# spec-quality-auditor.md hunt (d)), not at worked examples intake §4 no longer carries.
check "T705 delegate: spec-auditor intake mode points at reviewers/spec-quality-auditor.md hunt (d)" "$SPEC_AUDITOR_FLAT" \
  "\`reviewers/spec-quality-auditor.md\` → hunt **(d)**"
check "T705 delegate: spec-auditor intake mode cites hunt (d)'s worked examples" "$SPEC_AUDITOR_FLAT" \
  "per hunt **(d)**'s worked examples"

# T705 (US2.AC4) re-fork guard: a later edit that re-inlines the rule prose into intake
# (the fork this task removed) FAILs CI. The two worked-example strings are the fork's
# fingerprint — they belong in the canonical reviewer home ONLY, never restated in intake.
check_absent "T705 re-fork guard: intake §4 does not re-inline the if-x-return-y worked example" "$INTAKE_FLAT" \
  "if x: return y"
check_absent "T705 re-fork guard: intake §4 does not re-inline the one-sided worked example" "$INTAKE_FLAT" \
  "One-sided (recall without precision)"

# DW2 — the gate verifies drafted criteria via a NAMED artifact: an explicit step in
# the acceptance reviewer's intake-mode checklist, not prose alone. Assert the named
# section in spec-auditor.md AND that intake §5.1 wires the screen into the gate.
check "T606 DW2: acceptance reviewer carries a named intake-conversion mode" "$SPEC_AUDITOR_FLAT" \
  "## Intake-conversion mode"
check "T606 DW2: the named step screens drafted criteria for gameability" "$SPEC_AUDITOR_FLAT" \
  "Not trivially gameable"
check "T606 DW2: a checkable-but-gameable drafted criterion is a FAIL" "$SPEC_AUDITOR_FLAT" \
  "checkable but gameable is a"
check "T606 DW2: §5.1 wires the gameability screen into the acceptance check" "$INTAKE_FLAT" \
  "pass the §4 gameability screen"
# Post-open review fix (#101, Codex/owner P2): intake mode must say the design
# screen REPLACES the impl/encoding-test hunt + hard-FAIL rule for the drafted
# (future-work) criteria, else a valid intake PR is wrongly FAILed for missing tests.
check "T606 DW2: intake mode replaces impl/test hunt for drafted (future) criteria" "$SPEC_AUDITOR_FLAT" \
  "replaces the implementation/encoding-test hunt and the hard-FAIL rule"

# DW3 — a short note ties the screen to the spec-auditor: it left-shifts a fence the
# reviewer otherwise applies only post-implementation.
check "T606 DW3: left-shift note present" "$INTAKE_FLAT" \
  "left-shifts"
check "T606 DW3: note references the spec-auditor reviewer spec" "$INTAKE_FLAT" \
  "\`reviewers/spec-auditor.md\` → \"The"
check "T606 DW3: note frames the reviewer as the post-implementation backstop" "$INTAKE_FLAT" \
  "post-implementation"

# ── #170 — maintenance rubric carried by the marked §5 intake cross-link ───────
# The acceptance reviewer grades a `done-when on issue` task against the marked
# §5 intake cross-link comment for the task ID (the additive-write posture), NOT
# any later marked bookkeeping that restates criteria (a §4.5 plan, §5 blockage,
# §8 verdict — the maker-shadows-the-rubric hazard) and NOT an edit to the
# owner-authored body; the rubric-less case stays a hard FAIL. A later edit that
# broadens the selector, reverts either doc to "body", or drops the FAIL control
# branch fails these.
check "#170: spec-auditor grades from the marked intake cross-link for this task ID" "$SPEC_AUDITOR_FLAT" \
  "the marked intake cross-link comment for this task ID"
check "#170: spec-auditor excludes a later marked plan from shadowing the rubric" "$SPEC_AUDITOR_FLAT" \
  "let a later maker-authored plan shadow the owner-ratified intake rubric"
check "#170: spec-auditor ties resolve to the newest intake cross-link, not any marked comment" "$SPEC_AUDITOR_FLAT" \
  "newest such cross-link"
check "#170: spec-auditor keeps the rubric-less case a hard FAIL (control branch)" "$SPEC_AUDITOR_FLAT" \
  "no rubric, and that gap is itself the blocking finding: verdict **FAIL**"
check "#170: spec-auditor keeps the body only as a pre-convention fallback" "$SPEC_AUDITOR_FLAT" \
  "placed the criteria in the issue body instead is graded against that body"
check "#170: intake §4 never edits the owner-authored body for the rubric" "$INTAKE_FLAT" \
  "never an edit to the owner-authored body"
check "#170: intake §4 grades against the marked comment" "$INTAKE_FLAT" \
  "grades against that marked comment"
check "#170: intake §4 ties the rubric to the §5 cross-link, not a later comment" "$INTAKE_FLAT" \
  "the newest such cross-link governs"

# ── Runtime-neutral boundary (constitution P1) ─────────────────────────────────
# Intake is a neutral workflow doc, so it uses the same shared banned-token set as
# the other workflow-doc encoding tests (#122).
mech="$(neutral_mechanism_leaks "$INTAKE")"
if [ -z "$mech" ]; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  printf 'FAIL neutral boundary: runtime-specific mechanism leaked into %s\n     found: %s\n' "$INTAKE" "$mech" >&2
fi

printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
