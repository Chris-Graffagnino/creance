# Tasks — Held-Out Acceptance Checks

> Task-line format: `- [ ] T<nnnn> [<tier>] <description> (US<#>)`. The
> `[frontier]`/`[strong]`/`[cheap]` tag is the task's minimum capability tier, resolved
> through `.claude/MODELS.md` at run time. Task IDs use the **T10xx** block (4-digit,
> owner-ratified on #213) — unique across the repo (spec 001 = T1xx–T6xx, 002 = T7xx,
> 003 = T8xx, 004 = T9xx).

## Phase 1 — Channel, fence, and grading

- [ ] T1001 [strong] Held-out channel workflow doc (per-spec owner-curated set,
      out-of-repo profile-named path distinct from telemetry/maker-eval, US#-mapped
      independently verifiable entries, [roles] only, P1) + in-repo content-hash
      manifest with reviewed-PR update trail (P4) + triage HELD-OUT-DRIFT observe-only
      warning with no-channel/no-manifest empty states (P5); adds the channel row to
      `.claude/PROJECT.md` → "Paths" (US1)
- [ ] T1002 [strong] Deterministic maker-phase denial of held-out channel reads +
      two-sided falsification test (fires on a planted maker-phase read; passes the
      acceptance-reviewer-dispatch control; wiring assertion; test cases in the same
      diff, P2/P3); blocked by T1001 (US1)
- [ ] T1003 [strong] Acceptance-reviewer held-out grading step (reviewer verifies
      read-only result artifacts — entry execution, where needed, routes through the
      US1.AC1 deterministic dispatcher-side step, never a reviewer shell grant (#188);
      blocking FAIL naming only the failed entry — no set enumeration, passed entries
      stay unrevealed; loud absence degradation, visible rubric unchanged) + two-sided
      live conformance probe
      (planted-fail fixture FAILs a visible-rubric-passing diff, clean control passes,
      independently readable evidence recorded); blocked by T1001+T1002 (US2)

## Criterion ownership (multi-task user stories)

| Criterion | Owning task |
|---|---|
| US1.AC1 | T1001 |
| US1.AC2 | T1001 |
| US1.AC3 | T1002 |
| US2.AC1 | T1003 |
| US2.AC2 | T1003 |
| US2.AC3 | T1003 |

## Blocked / owner-only tasks (never auto-start — surface them instead)

- none

> Sequencing note (not a blocker): the spec overview recommends starting this epic
> after spec 003's trajectory tasks (T807/T808, #211) land — their records show whether
> makers actually overfit to visible checks. The owner may start T1001 earlier; this
> note records the recommendation, not a constraint.
