# Tasks — Maker Eval Corpus

> Task-line format: `- [ ] T<nnn> [<tier>] <description> (US<#>)`. The
> `[frontier]`/`[strong]`/`[cheap]` tag is the task's minimum capability tier,
> resolved through `.claude/MODELS.md` at run time. Task IDs use the **T8xx** block
> — unique across the repo (spec 001 = T1xx–T6xx, spec 002 = T7xx).

## Phase 1 — Corpus & run

- [ ] T801 [strong] Runtime-neutral maker-eval workflow doc: a small frozen corpus
      + per-task rubric, the eval run ([headless run] of the maker scored by a
      read-only [reviewer]-style judge), the record shape, the model-table
      fingerprint, the observe-only boundary (P5), and corpus/rubric-via-PR-only
      (P4); add the records-storage row to `PROJECT.template.md` → "Paths"
      ([roles] only) (US1)
- [ ] T802 [strong] Eval-run record emission (append-only JSONL, one per corpus
      task) + model-table fingerprint capture; observe-only, touches no gate/tier
      state; ships a test incl. the write-failure-stays-silent case (US1)

## Phase 2 — Trigger, surface, and the P5 fence

- [ ] T803 [cheap] Triage "Maker eval" section: score regressions vs the last run +
      MAKER-EVAL-STALE on a fingerprint change + explicit "no data yet" empty state,
      read-only over the records (US2)
- [ ] T804 [strong] Deterministic P5 fence: a CI assertion that the eval-record
      path is referenced only by the eval writer and the triage reader — and by no
      gate/tier/guard/selection path — + a `.test.sh` proving it fires on a planted
      cross-reference and passes on the real tree (US2)
- [ ] T805 [cheap] Claude skill binding (reuse [workflow]/[headless run]/[reviewer];
      run on fingerprint change + schedule) + conformance probe (synthetic 1-task
      corpus; record appended with fingerprint, no gate/tier touched) added to the
      neutral checklist, instantiated for the active adapter, run live, results
      recorded (US2)

## Criterion ownership (multi-task user stories)

| Criterion | Owning task |
|---|---|
| US1.AC1 | T801 |
| US1.AC2 | T802 |
| US1.AC3 | T802 |
| US1.AC4 | T801 |
| US2.AC1 | T805 |
| US2.AC2 | T803 |
| US2.AC3 | T804 |
| US2.AC4 | T805 |

## Blocked / owner-only tasks (never auto-start — surface them instead)

- none
