# Tasks — Spec-Quality Gate

> Task-line format: `- [ ] T<nnn> [<tier>] <description> (US<#>)`. The
> `[frontier]`/`[strong]`/`[cheap]` tag is the task's minimum capability tier,
> resolved through `.claude/MODELS.md` at run time. Task IDs use the **T7xx** block
> — unique across the repo (spec 001 occupies T1xx–T6xx).

## Phase 1 — The reviewer

- [x] T701 [strong] Spec-quality reviewer spec (`reviewers/`): the five hunts
      (untestability, internal contradiction read against the full current spec,
      unstated edge/negative cases, gameability, undocumented architecture call),
      read-only / reports-only, `US#.AC#` evidence, evasion-register consult —
      runtime-neutral, [roles] only; AND its strong-tier floor by generalizing guard
      rule 5 (today constitution-auditor-specific, `.claude/hooks/guard.sh`) to the
      spec-quality reviewer's dispatch, shipping with a matching `guard.test.sh` case
      (guard-behavior change ships with its test — P2) (US1)
- [x] T702 [cheap] Auditor-liveness fixture pair for the spec-quality reviewer in
      `reviewers/auditor-liveness-corpus.md` (≥1 expected-FAIL including an added AC
      that contradicts an unchanged AC elsewhere in the same spec — proving the
      reviewer reads the full spec, not just the diff; ≥1 expected-PASS); liveness
      stays observe-only (US1)

## Phase 2 — Dispatch, the mechanizable backstop, and dedup

- [x] T703 [strong] Add the reviewer to the gate roster (`gate-loop.md`) under a
      deterministic dispatch condition — a `specs/*/spec.md` added/edited/renamed
      (git `A`/`M`/`R`, the statuses that leave spec content to grade; pure deletion
      `D` documented as non-firing); update both derived mirrors (`next-task.md` §7
      prose, `gate-loop.js` array) and `reviewer-roster.test.sh` in the same diff;
      no-dispatch on non-spec diffs proven (US2)
- [x] T704 [strong] Deterministic spec-lint over `specs/*/spec.md` (empty AC, a
      `US#` with zero ACs, a verbatim-duplicate AC) + a `.test.sh` proving it fires
      on planted smells and does not false-fire on a clean spec; wire into CI
      `verify` (US2)
- [x] T705 [strong] Intake §4 gameability screen delegates to the shared reviewer
      check (de-fork) + a test so a re-fork FAILs CI (US2)
- [x] T706 [cheap] Claude skill/agent binding (reuse the [reviewer] role) +
      conformance probe for the spec-touch dispatch added to the neutral checklist,
      instantiated for the active adapter, run live, results recorded (US2)

## Phase 3 — Liveness coupling (follow-on)

- [x] T707 [cheap] Auditor-liveness runner coupling for the spec-quality auditor
      (**blocked by T706** — needs the `spec-quality-auditor` agent; the dispatch row
      can't point at an agent that does not exist): wire the auditor-liveness `[reviewer]`
      dispatch row + frontmatter (`.claude/skills/auditor-liveness/SKILL.md`) to dispatch
      spec-quality against the materialized `AL-SQ-*` plants **at or above the [strong
      tier]** (guard rule 5 vetoes a below-strong `spec-quality-auditor` dispatch, same as
      constitution), add `reviewers/spec-quality-auditor.md` to the reviewer-spec
      fingerprint recipe so editing it raises CORPUS-STALE, extend
      `auditor-liveness-docs.test.sh` to assert both (mechanize — P3), and retire the
      corpus's declared-ahead-of-binding Lifecycle marker once a full run exercises
      spec-quality. Follow-on to T702 (the US1.AC4 owner), which shipped the liveness
      fixtures observe-only: T707 wires the runner but owns no criterion — US1.AC4
      ownership stays with T702, and T707 is graded against the issue's done-when
      criteria (the T605 maintenance pattern), not a new AC. Discovered while
      working #180 → #182. (US1)

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
