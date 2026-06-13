# Tasks — Harness Feedback Loop

> Task-line format: `- [ ] T<nnn> [<tier>] <description> (US<#>)`. The
> `[frontier]`/`[strong]`/`[cheap]` tag is the task's minimum capability tier,
> resolved through `.claude/MODELS.md` at run time.

## Phase 1 — Telemetry foundation

- [x] T101 [strong] Define runtime-neutral telemetry record + storage path
      convention in the workflow layer; add "Telemetry" row to
      `PROJECT.template.md` → "Paths" (US1)
- [x] T102 [strong] Emit gate-run records from the Claude adapter gate loop;
      telemetry write failures never affect gate outcome (US1)
- [x] T103 [strong] Guard block-logging plus a per-gate-run evaluation record
      (liveness signal) + regression tests incl. the silent-failure case (US1)
- [x] T104 [strong] Carry the introducing-change ref (audited head commit) on
      the `gate-run` record — dispatcher-stamped, observe-only — so the
      retrospective's Fact B attribution is deterministic; doc encoding test +
      P-NT probe extension (US1)

## Phase 2 — Surfacing & review throughput

- [x] T201 [cheap] Triage "Gate trends" section with explicit no-data state (US2)
- [x] T202 [cheap] Triage "Discovered-work clusters" section (US2)
- [x] T203 [strong] Risk-ranked PR digest leading the next-task PR body;
      verbatim per-reviewer verdict comments retained unmodified (US4)
- [x] T204 [cheap] Triage "Unacknowledged owner comments" section: unmarked
      owner-login comments newer than the last harness-marked activity, read-only,
      referencing the [comment marker] role (US7)

## Phase 3 — Retrospective back-test

- [x] T301 [strong] Retrospective workflow doc: dispatch, classification
      taxonomy, propose-via-PR rule, strong-tier floor (US3)
- [ ] T302 [cheap] Claude Code skill binding for the retrospective;
      dispatches the constitution auditor at-or-above the strong-tier
      floor (US3)
- [ ] T303 [cheap] Conformance probe for the retrospective workflow; run on
      the live adapter and record results (US3)

## Phase 4 — Machinery freshness

- [ ] T401 [cheap] Probe-run fingerprint (guard script + hook wiring hash)
      recorded with probe results (US5)
- [ ] T402 [strong] Triage PROBES-STALE and GUARD-SILENT checks (US5) —
      strong: this machinery guards the guard (see DESIGN-NOTES §4)

## Phase 5 — Issue intake

- [x] T501 [strong] Issue intake: triage "Unmapped tracker work" detection,
      runtime-neutral intake workflow doc + skill binding, README row +
      conformance probe run on the live adapter (US6) — strong: defines how
      owner requests become scope, constitution-screen semantics included

## Phase 6 — PR review

- [ ] T601 [strong] Verified PR-review workflow doc (`pr-review.md`) + Claude
      skill binding: ingest the PR diff **and every inline comment** (bot/Codex
      included), ground each finding to current `file:line`, post one
      severity-ranked review; reuse "The review standard" + the `reviewers/`
      specs and change no §7 gate semantics; encoding tests wired into CI
      (#53; new capability scoped in-PR per owner direction — done-when on issue)
      — strong: touches the runtime-neutral workflow boundary (constitution P1)

## Criterion ownership (multi-task user stories)

| Criterion | Owning task |
|---|---|
| US1.AC1 | T101 |
| US1.AC2 | T102 |
| US1.AC3 | T103 |
| US1.AC4 | T103 |
| US1.AC5 | T104 |
| US2.AC1 | T201 |
| US2.AC2 | T202 |
| US2.AC3 | T201 |
| US2.AC4 | T202 |
| US3.AC1 | T301 |
| US3.AC2 | T301 |
| US3.AC3 | T301 |
| US3.AC4 | T301 |
| US3.AC5 | T302 |
| US3.AC6 | T303 |
| US4.AC1 | T203 |
| US4.AC2 | T203 |
| US4.AC3 | T203 |
| US5.AC1 | T401 |
| US5.AC2 | T402 |
| US5.AC3 | T402 |
| US6.AC1 | T501 |
| US6.AC2 | T501 |
| US6.AC3 | T501 |
| US6.AC4 | T501 |
| US6.AC5 | T501 |
| US6.AC6 | T501 |
| US7.AC1 | T204 |
| US7.AC2 | T204 |
| US7.AC3 | T204 |
| US7.AC4 | T204 |

## Blocked / owner-only tasks (never auto-start — surface them instead)

- none

> Note (not a blocker): T101 carries one design default — telemetry lives
> out-of-repo alongside the triage inbox (keeps project repos clean, matches
> the existing triage convention). The owner may override to in-repo on issue
> #18 any time before T101 starts; silence keeps the default.
