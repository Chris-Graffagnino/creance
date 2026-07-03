# Tasks — Adoption Context Preservation

> Task-line format: `- [ ] T<nnnn> [<tier>] <description> (US<#>)`. The
> `[frontier]`/`[strong]`/`[cheap]` tag is the task's minimum capability tier, resolved
> through `.claude/MODELS.md` at run time. Task IDs use the **T11xx** block (4-digit
> format owner-ratified on #213; this block assignment ratified by the spec-006
> conversion PR) — unique across the repo (spec 001 = T1xx–T6xx, 002 = T7xx,
> 003 = T8xx, 004 = T9xx, 005 = T10xx).

## Phase 1 — The documented path and its guard

- [ ] T1101 [strong] Adoption-path doc — "adopting Creance into an existing project"
      beside the greenfield Quickstart (README links both); profile artifacts as
      reconcile inputs never overwrite targets, per-artifact reconcile procedure;
      reverse GENERICIZE/TEMPLATE cut-list mapping with a deterministic coverage check
      (a cut-list profile entry with no adoption mapping fails); onboarding-prompt
      branch condition (pre-existing artifacts → reconcile branch, stated in the
      prompt itself) (US1)
- [ ] T1102 [strong] Pre-adoption preservation guard (deterministic, fail-closed,
      refuses loud with artifacts named; standalone + invoked by the adoption path) +
      post-adoption conformance probe (pre-install fingerprints asserted post-install,
      changes exempt only via an adopter-ratified reconcile record independent of the
      install's own output) — both with falsification tests in the same diff (planted
      clobber refused / greenfield control proceeds / unreadable state refused;
      planted silent overwrite FAILs / overwrite-free control passes / ratified
      reconcile passes where the same unrecorded change FAILs, independently
      readable evidence); blocked by T1101 (US2)

## Phase 2 — Rescue, prevention, and steady state

- [ ] T1103 [strong] Context-promotion procedure — triage (selective: cross-project /
      standing-preference memories stay) → promote → per-fact coverage-check →
      terminal state via the discoverability gate (delete when the repo home is
      self-discoverable, pointer as the exception, finished trackers retired);
      two-sided prune-gate fixtures (one uncovered fact blocks only its own prune /
      fully-covered control prunes clean); provenance kept out of the always-loaded
      index; workflow/**-resident text names the store as a [role] only (neutrality
      scan green); blocked by T1101 (US3)
- [ ] T1104 [strong] Standing prevention rule — `.claude/DESIGN-NOTES.md` rationale entry
      (adapter-aware) + mechanism-neutral operational trigger in the per-task loop,
      cross-referenced both ways; per-task doc line-budget stays green (pointer-style
      or compensating trim, never a budget bump) and neutrality scan green (US4)
- [ ] T1105 [strong] Recurring index-consolidation pass — named cadence hook; four
      actions (merge duplicates, fix stale, discoverability-gate every pointer, retire
      finished trackers) + explicit empty state; deterministic owner-ratified index
      bound in the profile, exceedance surfaced observe-only (never read by a
      gate/tier/guard/selection path); memory-surfaces-only edit scope, deletions
      through the US3 coverage gate; blocked by T1103 (US5)

## Criterion ownership (multi-task user stories)

| Criterion | Owning task |
|---|---|
| US1.AC1 | T1101 |
| US1.AC2 | T1101 |
| US1.AC3 | T1101 |
| US2.AC1 | T1102 |
| US2.AC2 | T1102 |
| US2.AC3 | T1102 |
| US3.AC1 | T1103 |
| US3.AC2 | T1103 |
| US3.AC3 | T1103 |
| US3.AC4 | T1103 |
| US4.AC1 | T1104 |
| US4.AC2 | T1104 |
| US5.AC1 | T1105 |
| US5.AC2 | T1105 |
| US5.AC3 | T1105 |

## Blocked / owner-only tasks (never auto-start — surface them instead)

- none

> Sequencing note (not a blocker): T1104 (the prevention rule) is independent of the
> adoption path and useful to any project, greenfield included — the owner may land it
> first. US5's index bound value (US5.AC2) is an owner fact ratified in the profile at
> T1105 implementation time, not chosen by the pass.
