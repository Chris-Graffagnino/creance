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
- [x] T302 [cheap] Claude Code skill binding for the retrospective;
      dispatches the constitution auditor at-or-above the strong-tier
      floor (US3)
- [x] T303 [cheap] Conformance probe for the retrospective workflow; run on
      the live adapter and record results (US3)

## Phase 4 — Machinery freshness

- [x] T401 [cheap] Probe-run fingerprint (guard script + hook wiring hash)
      recorded with probe results (US5)
- [x] T402 [strong] Triage PROBES-STALE and GUARD-SILENT checks (US5) —
      strong: this machinery guards the guard (see DESIGN-NOTES §4)

## Phase 5 — Issue intake

- [x] T501 [strong] Issue intake: triage "Unmapped tracker work" detection,
      runtime-neutral intake workflow doc + skill binding, README row +
      conformance probe run on the live adapter (US6) — strong: defines how
      owner requests become scope, constitution-screen semantics included

## Phase 6 — PR review

- [x] T601 [strong] Verified PR-review workflow doc (`pr-review.md`) + Claude
      skill binding: ingest the PR diff **and every inline comment** (bot/Codex
      included), ground each finding to current `file:line`, post one
      severity-ranked review; reuse "The review standard" + the `reviewers/`
      specs and change no §7 gate semantics; encoding tests wired into CI
      (#53; new capability scoped in-PR per owner direction — done-when on issue)
      — strong: touches the runtime-neutral workflow boundary (constitution P1)

## Phase 7 — Reviewer roster

- [x] T602 [strong] Collapse the three-place §7 reviewer-set duplication
      (`next-task.md` §7 step 2, `gate-loop.md` "The loop", `gate-loop.js`
      `reviewers` array) into one declarative roster table in `gate-loop.md`,
      repoint `next-task.md` §7 at it, comment the `gate-loop.js` array as
      derived; plus a CI-wired bash drift backstop (`reviewer-roster.test.sh`
      in `verify`) asserting the three sites agree, each reviewer spec exists,
      and each reviewer's agent file excludes edit tools — the test ships in the
      same PR. Representation-only: no gate-semantics change (round limits, veto
      authority, tier floors, parallel fan-out unchanged) (#62; repo-maintenance
      — done-when on issue) — strong: edits the runtime-neutral workflow
      boundary and adds a P2 wiring assertion (constitution P1/P2/P3)
- [x] T603 [cheap] DESIGN-NOTES rationale entry for the reviewer roster + drift
      backstop — a row in the "Things that look like cruft but are not" index —
      so a future maintainer does not collapse it back into three hand-synced
      sites; blocked by T602 (#62; repo-maintenance — done-when on issue)

## Phase 8 — Gate hardening (LFD-delta epics)

> Three out-of-plan epics surfaced by a loss-function-development comparative
> analysis (github.com/elvisun/loss-function-development), intaked from #74/#75/#76.
> Each is engine-maintenance to the review/governance machinery; rubric is the
> done-when criteria carried on its issue (the acceptance reviewer grades against
> those exactly as a `US#`). May be split further at implementation time if a
> done-when exceeds one PR's reasonable scope.

- [x] T604 [strong] Evasion-register: add `reviewers/evasion-register.md`, a
      cumulative, exemplar-based catalog of observed gate evasions
      (`observed evasion → fence`, each with a `file:line` exemplar) that the
      auditors consult at dispatch and the retrospective appends to **via PR**
      (never silently) on HUNT-RULE-GAP / INVARIANT-GAP outcomes; seed it from
      the evasions already implicit in the auditor specs; note the deterministic
      lint each mechanizable exhibit should graduate into (#74; repo-maintenance
      — done-when on issue) — strong: edits the P4-protected reviewer specs and
      the retrospective workflow boundary (constitution P1/P3/P4)
- [x] T605 [strong] Auditor-liveness: promote the one-time `P-RV` reviewer
      conformance probe into a standing planted-violation regression corpus
      (≥1 expected-FAIL and ≥1 expected-PASS fixture per auditor), re-run on
      reviewer-spec change and on a schedule, seeded from retrospective
      incidents; **observe-only** — the liveness signal never feeds gate
      outcomes, tier assignment, or gate semantics (#75; repo-maintenance —
      done-when on issue) — strong: verification machinery guarding the guards,
      with a P5 observe-only boundary (constitution P2/P3/P5)
- [x] T606 [strong] Criteria-gameability: add a gameability screen to
      `intake.md` §4 (for each drafted criterion, name the cheapest way to
      satisfy it without doing the real work; if that path exists the criterion
      is one-sided or trivially satisfiable — tighten it before drafting) and
      mirror it in the acceptance reviewer's intake-conversion check, with an
      encoding test (#76; repo-maintenance — done-when on issue) — strong:
      edits the runtime-neutral intake workflow boundary (constitution P1/P3)

## Phase 9 — Edit-time & execution guardrails (agent-framework-analysis deltas)

> Three deltas surfaced by a comparative analysis of four coding-agent frameworks
> (vercel-labs/coding-agent-template, OpenHands/software-agent-sdk,
> SWE-agent/SWE-agent, SuperClaude_Framework), intaked from #79/#80/#81. Each
> hardens the harness's deterministic-governance surface at the moment work is
> created — edit, selection, execution; rubric is the done-when criteria carried on
> its issue (the acceptance reviewer grades against those exactly as a `US#`). T609
> is an epic and may be split further at implementation time if a done-when exceeds
> one PR's reasonable scope.

- [x] T607 [strong] Edit-time lint/typecheck-and-reject guard: a post-edit
      verification that runs the project's syntax/type check on touched files and
      rejects a change that adds a *new* diagnostic (fix-forward feedback), allowing
      an edit that leaves diagnostics no worse than before; failing open when no
      checker is configured. Ships in the same diff with a **delta-based**
      `guard.test.sh` case (a pre-existing failure + a no-new-diagnostic edit that
      must still be allowed), a matcher-wiring assertion that **enumerates the
      handled edit tools and fails if any is unrouted**, and a new
      invariant-checklist row (#79; repo-maintenance — done-when on issue) —
      strong: changes guard behavior and adds a P2 wiring assertion plus a P3
      determinism backstop (constitution P1/P2/P3)
- [ ] T608 [strong] Live-state reconciliation before task selection: a
      deterministic precondition in `next-task.md` selection that reconciles the
      chosen task's checkbox against live tracker/branch state and refuses stale
      work, reusing (not duplicating) `check-tasks-consistency.sh` and failing open
      when tracker state is unavailable; a **paired** test (one open task selected
      + one drifted task refused in the same harness) encodes both the
      merged-but-unchecked refusal and the no-false-positive path (#80; bug —
      done-when on issue) — strong: replaces a prose cross-check with a
      deterministic selection precondition (constitution P1/P3)
- [ ] T609 [strong] Ephemeral worktree isolation for autonomous mode (epic):
      autonomous work runs in an ephemeral worktree with the §7 gate in place and
      nothing reaches `main` unless the gate passes; autonomous mode is OFF by
      default, engaged only by an explicit in-session request or a config-file
      opt-in (absence = review mode), enforced deterministically; a falsification
      test proves an un-gated change cannot reach `main`; review mode provably
      unchanged (#81; repo-maintenance — done-when on issue) — strong: spans the
      runtime-neutral workflow boundary, adds a P2 falsification test, and keeps
      promotion gated (constitution P1/P2/P3/P4); may split into the (a)–(d)
      sub-tasks named on the issue

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
