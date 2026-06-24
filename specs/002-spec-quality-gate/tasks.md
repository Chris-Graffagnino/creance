# Tasks — Spec-Quality Gate

> Task-line format: `- [ ] T<nnn> [<tier>] <description> (US<#>)`. The
> `[frontier]`/`[strong]`/`[cheap]` tag is the task's minimum capability tier,
> resolved through `.claude/MODELS.md` at run time. Task IDs use the **T7xx** block
> — unique across the repo (spec 001 occupies T1xx–T6xx).

## Phase 1 — The reviewer

- [ ] T701 [strong] Spec-quality reviewer spec (`reviewers/`): the five hunts
      (untestability, internal contradiction, unstated edge/negative cases,
      gameability, undocumented architecture call), read-only / reports-only,
      `US#.AC#` evidence, evasion-register consult, strong-tier floor via guard
      rule 5 reuse — runtime-neutral, [roles] only (US1)
- [ ] T702 [cheap] Auditor-liveness fixture pair for the spec-quality reviewer in
      `reviewers/auditor-liveness-corpus.md` (≥1 expected-FAIL e.g. a contradictory
      AC pair, ≥1 expected-PASS); liveness stays observe-only (US1)

## Phase 2 — Dispatch, the mechanizable backstop, and dedup

- [ ] T703 [strong] Add the reviewer to the gate roster (`gate-loop.md`) under a
      deterministic spec-touch dispatch condition; update both derived mirrors
      (`next-task.md` §7 prose, `gate-loop.js` array) and `reviewer-roster.test.sh`
      in the same diff; no-dispatch on non-spec diffs proven (US2)
- [ ] T704 [strong] Deterministic spec-lint over `specs/*/spec.md` (empty AC, a
      `US#` with zero ACs, a verbatim-duplicate AC) + a `.test.sh` proving it fires
      on planted smells and does not false-fire on a clean spec; wire into CI
      `verify` (US2)
- [ ] T705 [strong] Intake §4 gameability screen delegates to the shared reviewer
      check (de-fork) + a test so a re-fork FAILs CI (US2)
- [ ] T706 [cheap] Claude skill/agent binding (reuse the [reviewer] role) +
      conformance probe for the spec-touch dispatch added to the neutral checklist,
      instantiated for the active adapter, run live, results recorded (US2)

## Criterion ownership (multi-task user stories)

| Criterion | Owning task |
|---|---|
| US1.AC1 | T701 |
| US1.AC2 | T701 |
| US1.AC3 | T701 |
| US1.AC4 | T702 |
| US2.AC1 | T703 |
| US2.AC2 | T703 |
| US2.AC3 | T704 |
| US2.AC4 | T705 |
| US2.AC5 | T706 |

## Blocked / owner-only tasks (never auto-start — surface them instead)

- none
