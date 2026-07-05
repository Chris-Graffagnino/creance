# Tasks — Fast-Lane Workflow with Deterministic Escalation

> Task-line format: `- [ ] T<nnnn> [<tier>] <description> (US<#>)`. The
> `[frontier]`/`[strong]`/`[cheap]` tag is the task's minimum capability tier, resolved
> through `.claude/MODELS.md` at run time. Task IDs use the **T13xx** block (4-digit
> format owner-ratified on #213; this block assignment ratified by the spec-008
> conversion PR) — unique across the repo (spec 001 = T1xx–T6xx, 002 = T7xx,
> 003 = T8xx, 004 = T9xx, 005 = T10xx, 006 = T11xx, 007 = T12xx).

## Phase 1 — The decision substrate

- [ ] T1301 [strong] Deterministic fast-lane scope checker — explicit inputs (base ref,
      head ref or working-tree path, threshold config), exactly one `eligible`/`escalate`
      verdict with reason lines (tripped triggers named on escalate; evaluated classes
      named on eligible); escalates on protected-path touch, file/line threshold
      overage, missing issue number, and unavailable diff data (fail closed); planted
      fixture per trigger class + in-envelope eligible control (two-sided); wired into
      `verify` with the wiring asserted; protected-path set + thresholds (defaults: ≤3
      files / ≤100 lines) as profile/adapter facts with the owner override path
      documented — the set covering the issue's structural exclusions wherever
      path-expressible (dependency manifests/lockfiles, designated contract/seam/
      data-model/UI surfaces) — neutrality scan green (US1)

## Phase 2 — The lane

- [ ] T1302 [strong] Runtime-neutral fast-lane workflow doc (`workflow/fast-task.md`) —
      roles-only, neutrality-scan covered, composes existing roles with no new gate
      semantics/roster/tier-floor/autonomy/merge change and the full workflow untouched;
      preserved bounds stated unreduced (issue-before-edit, non-base branch, targeted
      verification, required review passes with material findings blocking,
      checker-evidenced constitution screen, PR-stop); streamlining envelope enumerated
      and bounded; deterministic escalation contract with both mandatory checker call
      sites (entry + pre-PR re-screen), escalate → stop, record, continue only via full
      workflow or owner-approved reclassification; in-flight escalation obligations for
      the judgment-shaped trigger classes no diff-time checker computes (ambiguous
      objective/decision, structural introduction past the path screen, unrunnable or
      ambiguous check, acceptance-affecting discovered work, out-of-lane material
      finding) — one-directional and fail-closed; Blocked by T1301 (US2)
- [ ] T1303 [strong] Active-adapter fast-lane binding + PR-body evidence — binding points
      to the neutral doc (no restated procedure), maps its [roles], invokes the checker
      at both call sites, conformance demonstrated by test or recorded probe; PR-body
      evidence requirements (lane statement, verbatim checker output at both call
      sites, untripped-trigger summary, verification + review-pass evidence) defined
      neutrally with the concrete rendering in the binding; Blocked by T1301, T1302
      (US3)

## Criterion ownership (multi-task user stories)

| Criterion | Owning task |
|---|---|
| US1.AC1 | T1301 |
| US1.AC2 | T1301 |
| US1.AC3 | T1301 |
| US1.AC4 | T1301 |
| US2.AC1 | T1302 |
| US2.AC2 | T1302 |
| US2.AC3 | T1302 |
| US2.AC4 | T1302 |
| US2.AC5 | T1302 |
| US3.AC1 | T1303 |
| US3.AC2 | T1303 |

## Blocked / owner-only tasks (never auto-start — surface them instead)

- none

> Sequencing note (not a blocker): spec 007 (workflow context economy, #166) and this
> spec are deliberately independent — if spec 007's compact artifacts land first, T1302's
> lane context-loading consumes them instead of inventing a second summary surface
> (spec.md Overview). The fast lane stays out of the [backlog-loop] until separately
> specified (Non-goals).
