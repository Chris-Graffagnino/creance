# Spec — Fast-Lane Workflow with Deterministic Escalation

> Epic for the Creance repo itself. The acceptance [reviewer] (`spec-auditor`) grades
> each task against the `US#` acceptance criteria below — bullets are addressable as
> `US1.AC1`, `US1.AC2`, … (the nth bullet under that story), so they are written as
> independently checkable statements.

## Overview

Creance is intentionally rigorous, but routine low-risk work currently pays the same
ceremony cost as gate-sensitive workflow, guard, or spec changes — which makes the
harness feel heavier than necessary and invites humans or agents to route small work
*around* the harness instead of through it. This spec adds a deliberately small
**fast lane** for in-envelope changes, with **deterministic escalation** back to the
full per-task workflow whenever the change leaves the safe envelope. It is not a
replacement for the full gate, and it must not weaken the required issue/branch/PR
lifecycle, the constitution screen, or the required pre-PR review.

The capability lands in three stories: a deterministic scope checker that decides
eligibility/escalation from the actual diff, never model confidence (US1 — the
substrate the lane's every decision resolves through); the runtime-neutral fast-lane
workflow composing existing roles (US2); and the active-adapter binding with PR-body
evidence requirements (US3).

Motivation and provenance: intake of issue #231 (filed 2026-07-03; no thread comments —
the body is the sole owner steering). The issue's eligibility conditions, escalation
triggers, threshold defaults, and acceptance criteria are adopted as the basis of the
stories below. Two translations applied per constitution P1 (the spec-007 precedent):
the issue names a concrete vendor review command (`codex review --base main`, drafted
against a different adapter) — this spec renders it as the required pre-PR review
**[roles]** (the profile's review-pass set and the gate the active adapter binds); and
the issue's escalation-trigger path list is a **project fact** — the neutral workflow
names the *role* (the profile's protected-path set) while the concrete globs and
thresholds live in the profile/adapter surface, never a neutral doc. Classification
note: the issue body calls itself repo-maintenance work, but the request adds a new
invokable capability with multi-task acceptance criteria, so intake converts it as
spec work — the owner ratifies that call by merging this conversion PR. The task-ID
block is **T13xx** (block assignment ratified by merging this spec's conversion PR).

Sequencing note (issue step 6): #166 / spec 007 covers context/token reduction broadly;
this spec is only the reduced-ceremony lane and its escalation contract. If spec 007's
compact artifacts (project packet, stage cards, task index) land first, the fast lane
consumes those artifacts rather than inventing a second summary surface; neither spec
blocks the other.

## Non-goals

- **No bypass of the required pre-PR review.** The fast lane never creates a path to a
  PR that skips the profile's required review passes or lets their material findings
  stop blocking.
- **The model never overrides the checker.** A diff the deterministic checker marks
  `escalate` cannot be argued back into the fast lane by model judgment — eligibility
  is the checker's verdict alone (constitution P3).
- **Not the default for autonomous work.** The fast lane is not used by the
  [backlog-loop] or any unattended path until that composition is separately specified
  and gated.
- **No weakening of `AGENTS.md` or constitution requirements** to reduce ceremony: the
  issue-before-edit, non-base-branch, verification, constitution-screen, and stop-at-PR
  obligations are unchanged in *what* they require.
- **No parallel governance system.** The fast lane composes existing roles — it defines
  no new gate semantics, reviewer roster, tier floors, autonomy behavior, or merge
  rules, and the full workflow's own path is byte-for-byte unaffected for work outside
  the lane.
- **The neutral/adapter split holds (P1):** protected-path globs, numeric thresholds,
  and checker invocation mechanics are project/adapter facts and never enter a neutral
  doc.

## User stories

### US1 — Deterministic fast-lane scope checker

As the fast-lane entrypoint, I want a deterministic eligibility/escalation decision
computed from the actual change, so that lane selection never rests on model confidence
and leaving the safe envelope always fails closed into the full workflow.

**Acceptance Criteria**
- AC1: A deterministic scope checker exists taking the base ref, the head ref or
  working-tree path, and the threshold configuration as explicit inputs, and emitting
  exactly one machine-readable verdict — `eligible` or `escalate` — plus reason lines:
  an `escalate` names every tripped trigger, and an `eligible` names the trigger
  classes evaluated. A verdict with no reasons, both verdicts at once, or a checker
  that infers its inputs from ambient state instead of taking them explicitly does not
  satisfy this.
- AC2: The checker escalates on each trigger class from the source issue — (a) the
  diff touches the project's protected-path set (constitution, `workflow/**` including
  reviewer specs, hooks/guards, adapters, model table, the profile's
  invariants/review-pass/autonomy sections, live `specs/*/{spec.md,tasks.md}`, plus the
  issue's structural exclusions wherever they are path-expressible — dependency
  manifests/lockfiles and any project surfaces the profile designates as public
  contract, provider seam, data model, or UI; the concrete globs stay profile facts
  per AC4). Structural exclusions with no path expression in this project are not the
  checker's job — US2.AC5 assigns them to the lane as in-flight escalation
  obligations, so no exclusion class from the source issue is silently unenforced;
  (b) the diff exceeds the configured file-count or changed-line thresholds;
  (c) no concrete issue number is supplied for the work; (d) required diff data is
  unavailable or unreadable — class (d) failing **closed** to `escalate`, never a
  silent `eligible`. Proven two-sided in the same diff: a planted fixture per trigger
  class fails as `escalate` naming that trigger, AND an in-envelope control change
  (small, safe, non-protected paths, issue number supplied) passes as `eligible` — a
  checker that only ever escalates, or is proven in only one direction, does not
  satisfy this.
- AC3: The checker's tests are wired into standing verification (`verify`) with the
  wiring asserted by the tests themselves — a checker that exists but is never
  exercised by CI is the silently-dead-guard class (constitution P2).
- AC4: The protected-path set and the numeric thresholds are project facts resolved
  from the profile or adapter surface — never hardcoded prose inside a `workflow/**`
  neutral doc — and the neutrality scan stays green over every neutral doc the change
  touches (constitution P1). The initial thresholds are the source issue's (at most 3
  tracked files and at most 100 changed lines, excluding generated evidence artifacts)
  with the owner-ratified override path documented beside the configuration; a
  threshold the checker widens itself violates this criterion.

### US2 — Runtime-neutral fast-lane workflow

As a harness operator, I want a reduced-ceremony workflow for in-envelope changes that
composes the existing roles and fails closed into the full per-task workflow, so that
the common low-risk case gets cheaper without any governance bound getting weaker.

**Acceptance Criteria**
- AC1: A runtime-neutral fast-lane workflow doc exists under `workflow/`, expressed in
  bracketed [roles] with no runtime-specific mechanism, covered by the runtime-neutrality
  scan like every neutral doc, and composing existing roles only — it introduces no new
  gate semantics, reviewer roster change, tier-floor change, autonomy behavior, or merge
  rule, and the full per-task workflow's own text and gate path are unchanged by the
  lane's existence.
- AC2: The fast lane preserves, explicitly and unreduced: an issue before the first
  edit; a non-base branch; targeted verification appropriate to the diff; the required
  pre-PR review — the profile's required review passes with material findings
  blocking; the constitution-sensitivity screen — satisfied deterministically by the
  US1 checker's `eligible` verdict proving the diff touches no protected surface, so
  the "outside constitution-sensitive surfaces" claim is checker evidence, never prose
  assertion; and PR-stop semantics (a PR referencing its issue with a closing keyword,
  no merge). A lane run reaching a PR with any of these absent is a defect of the
  workflow, not an allowed streamlining.
- AC3: What the lane may streamline is enumerated and bounded in the doc itself — full
  spec/task discovery when the issue is explicitly repo-maintenance, breadth of default
  context loading, and reviewer fan-out — with the bound stated per item that material
  findings from every required review pass remain blocking, and that any reduction
  applies only inside the lane (the full workflow's ceremony for out-of-lane work is
  untouched). A streamlining not on the enumerated list is out of contract.
- AC4: The escalation contract is stated and deterministic: the US1 checker gates
  entry, and re-screens the actual diff before PR creation — both call sites mandatory
  — and any `escalate` at any point stops fast-lane execution, records the tripped
  trigger and its evidence, and continues only through the full per-task workflow or an
  owner-approved reclassification. The decision input is the checker's verdict alone —
  a lane that proceeds past an `escalate`, skips the pre-PR re-screen, or substitutes
  model judgment for the verdict violates this criterion (constitution P3).
- AC5: The lane doc obligates escalation on the source issue's remaining trigger
  classes — the ones no diff-time checker can compute: the work turns out to lack a
  clear single objective or to require an ambiguous product/architecture decision; the
  change would introduce a new dependency, public contract, provider seam, data model,
  or UI surface not already caught by the checker's protected-path screen (US1.AC2);
  a targeted verification check cannot be run or gives ambiguous results; discovered
  work affects acceptance criteria; or a required review pass finds a material issue
  that cannot be fixed within lane scope. Each carries the same escalate semantics as
  AC4 — stop, record the trigger and its evidence, continue only through the full
  workflow or owner-approved reclassification. These obligations are one-directional
  and fail closed: they may only add escalations on top of the checker's verdict,
  never argue an `escalate` back to `eligible` (constitution P3), and uncertainty
  about whether one applies resolves to escalate. A lane doc that omits any of these
  classes, or a lane run that proceeds past one, does not satisfy this criterion.

### US3 — Active-adapter binding and PR-body evidence

As an operator invoking the fast lane, I want an adapter binding and evidence-bearing
PR bodies, so that the lane is actually usable and every fast-lane PR shows its
eligibility was earned, not asserted.

**Acceptance Criteria**
- AC1: The active adapter exposes an invokable fast-lane binding that points to the
  neutral workflow doc rather than restating the procedure (the standard binding
  posture), maps the [roles] the doc names to this adapter's mechanisms, and invokes
  the US1 checker at both mandated call sites; the binding's conformance is
  demonstrated by test or recorded probe in the adapter's probe conventions — an
  unexercised binding does not satisfy this.
- AC2: Every fast-lane PR body carries: an explicit statement that the fast lane was
  used; the checker's verbatim eligibility output at both call sites (entry and pre-PR
  re-screen) — verbatim evidence, not a paraphrase; the trigger classes evaluated and
  not tripped; the verification evidence for the targeted checks run; and the required
  review-pass evidence per the profile. A fast-lane PR body missing any element does
  not satisfy this criterion, and the requirement itself lives in the neutral doc with
  the concrete rendering in the binding.
