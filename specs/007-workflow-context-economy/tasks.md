# Tasks — Workflow Context Economy

> Task-line format: `- [ ] T<nnnn> [<tier>] <description> (US<#>)`. The
> `[frontier]`/`[strong]`/`[cheap]` tag is the task's minimum capability tier, resolved
> through `.claude/MODELS.md` at run time. Task IDs use the **T12xx** block (4-digit
> format owner-ratified on #213; this block assignment ratified by the spec-007
> conversion PR) — unique across the repo (spec 001 = T1xx–T6xx, 002 = T7xx,
> 003 = T8xx, 004 = T9xx, 005 = T10xx, 006 = T11xx).

## Phase 1 — The measurement substrate

- [ ] T1201 [strong] Repository token-budget check — per-file and per-bundle counts over
      the named context artifacts/bundles that exist at landing time; documented
      owner-ratified budgets (initial values from #166) with an explicit override path,
      budgets for later-landing surfaces (compact packet, stage cards, task index,
      restructured bundles) registered but gating deferred to the owning task's diff
      per US1.AC1 — this task creates no downstream artifact; wired into `verify` with
      the wiring asserted; two-sided falsification fixtures (planted over-budget fails
      naming artifact + count / within-budget control passes); tokenizer identity kept
      out of `workflow/**`, neutrality scan green (US1)

## Phase 2 — The compact surfaces

- [ ] T1202 [strong] Shrink resident `AGENTS.md` to per-turn rules + pointers within its
      ratified budget; every removed rule re-homed in a named source-of-truth doc behind
      a surviving pointer; guard/workflow/CI references still resolve and the existing
      line-ceiling residency check stays enforced alongside the token budget; blocked by
      T1201 (US2)
- [ ] T1203 [strong] Compact project packet — active routing facts only, within budget;
      two-sided drift check against `.claude/PROJECT.md` (planted drift fails naming the
      field / in-sync control passes) wired into `verify`; entrypoints read the packet by
      default with full-profile escalation explicit; blocked by T1201 (US3)
- [ ] T1204 [strong] Split the per-task procedure into demand-loaded stage cards within
      budget (or documented override); entrypoint loads current card + compact packet
      only; full source stays coherent via generated assembly or index with a
      deterministic completeness/drift check compared against an independently captured
      pre-split obligation inventory (committed as a fixture the cards cannot influence)
      so a dropped obligation fails verification; existing references resolve and
      neutrality-scan coverage includes every card; blocked by T1201, T1203 (US4)
- [ ] T1205 [strong] Generated task index — selection-critical fields only, within
      budget; two-sided staleness CI check (planted stale fails naming the entry /
      regenerated control passes) wired into `verify`; selection reads index-first then
      the selected task's full context with the deterministic selection preconditions
      unchanged; blocked by T1201 (US5)

## Phase 3 — Prose to determinism

- [ ] T1206 [strong] Account for the governance-rule candidate set without duplicating
      existing coverage: merge-not-pre-approved is carried by T623's existing
      `guard.test.sh` regression (cite it, assert it still runs, extend only on a found
      gap — no re-implementation); budget-checks-wired is cited from US1.AC2; any new
      encoded rule ships with two-sided focused tests; non-encodable candidates
      documented with explicit P3 justification, never silently dropped; per encoded
      rule, resident prose reduced to a pointer at the check; all new checks name their
      repair target on failure (US6)

## Criterion ownership (multi-task user stories)

| Criterion | Owning task |
|---|---|
| US1.AC1 | T1201 |
| US1.AC2 | T1201 |
| US1.AC3 | T1201 |
| US1.AC4 | T1201 |
| US1.AC5 | T1201–T1206 (every task, graded on its own PR body) |
| US2.AC1 | T1202 |
| US2.AC2 | T1202 |
| US2.AC3 | T1202 |
| US3.AC1 | T1203 |
| US3.AC2 | T1203 |
| US3.AC3 | T1203 |
| US4.AC1 | T1204 |
| US4.AC2 | T1204 |
| US4.AC3 | T1204 |
| US4.AC4 | T1204 |
| US5.AC1 | T1205 |
| US5.AC2 | T1205 |
| US5.AC3 | T1205 |
| US6.AC1 | T1206 |
| US6.AC2 | T1206 |
| US6.AC3 | T1206 |

## Blocked / owner-only tasks (never auto-start — surface them instead)

- none

> Sequencing note (not a blocker): T1206's carried-coverage audit is independent of the
> measurement substrate and may land alongside T1201. Evidence rule: graded as
> **US1.AC5** — each T120x PR body carries measured before/after token counts for the
> surfaces its diff touches, alongside the standard red→green falsification evidence.
