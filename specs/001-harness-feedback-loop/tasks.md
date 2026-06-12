# Tasks — Harness Feedback Loop

> Task-line format: `- [ ] T<nnn> [<tier>] <description> (US<#>)`. The
> `[frontier]`/`[strong]`/`[cheap]` tag is the task's minimum capability tier,
> resolved through `.claude/MODELS.md` at run time.

## Phase 1 — Telemetry foundation

- [ ] T101 [strong] Define runtime-neutral telemetry record + storage path
      convention in the workflow layer; add "Telemetry" row to
      `PROJECT.template.md` → "Paths" (US1)
- [ ] T102 [strong] Emit gate-run records from the Claude adapter gate loop;
      telemetry write failures never affect gate outcome (US1)
- [ ] T103 [strong] Guard block-logging + regression tests incl. the
      silent-failure case (US1)

## Phase 2 — Surfacing & review throughput

- [ ] T201 [cheap] Triage "Gate trends" section with explicit no-data state (US2)
- [ ] T202 [cheap] Triage "Discovered-work clusters" section (US2)
- [ ] T203 [strong] Risk-ranked PR digest in the next-task PR body template;
      verbatim verdicts retained below (US4)

## Phase 3 — Retrospective back-test

- [ ] T301 [strong] Retrospective workflow doc: dispatch, classification
      taxonomy, propose-via-PR rule, strong-tier floor (US3)
- [ ] T302 [cheap] Claude Code skill binding for the retrospective (US3)
- [ ] T303 [cheap] Conformance probe for the retrospective role; run on the
      live adapter and record results (US3)

## Phase 4 — Machinery freshness

- [ ] T401 [cheap] Probe-run fingerprint (guard script + hook wiring hash)
      recorded with probe results (US5)
- [ ] T402 [cheap] Triage PROBES-STALE and GUARD-SILENT checks (US5)

## Criterion ownership (multi-task user stories)

| Criterion | Owning task |
|---|---|
| US1.AC1 | T101 |
| US1.AC2 | T102 |
| US1.AC3 | T103 |
| US1.AC4 | T103 |
| US2.AC1 | T201 |
| US2.AC2 | T202 |
| US2.AC3 | T201 |
| US2.AC4 | T201 |
| US3.AC1 | T301 |
| US3.AC2 | T301 |
| US3.AC3 | T301 |
| US3.AC4 | T301 |
| US3.AC5 | T302 (probe: T303) |
| US4.AC1 | T203 |
| US4.AC2 | T203 |
| US4.AC3 | T203 |
| US5.AC1 | T401 |
| US5.AC2 | T402 |
| US5.AC3 | T402 |

## Blocked / owner-only tasks (never auto-start — surface them instead)

- T101 embeds one design default that needs a conscious owner nod before it
  starts: telemetry lives out-of-repo alongside the triage inbox (keeps project
  repos clean, matches the existing triage convention). If the owner prefers
  in-repo, versioned telemetry, say so on issue #18 before T101 begins.
