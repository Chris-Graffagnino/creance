# Tasks — Maker Eval Corpus

> Task-line format: `- [ ] T<nnn> [<tier>] <description> (US<#>)`. The
> `[frontier]`/`[strong]`/`[cheap]` tag is the task's minimum capability tier,
> resolved through `.claude/MODELS.md` at run time. Task IDs use the **T8xx** block
> — unique across the repo (spec 001 = T1xx–T6xx, spec 002 = T7xx).

## Phase 1 — Corpus & run

- [x] T801 [strong] Runtime-neutral maker-eval workflow doc: a small frozen corpus
      **seeded from real Creance signals** (retrospective escapes, discovered-work
      clusters, owner comments, auditor-liveness fixtures) and adopter/product
      workflows (template cold-start, adapter port), each scored rubric dimension
      carrying **lifecycle metadata** (capability/regression/saturated) so the set stays
      frozen yet grows and retires by PR; + per-task rubric + a **pinned judge** (identity fixed
      independently of the maker model-table change), the eval run ([headless run] of
      the maker scored by that read-only [reviewer]-style judge), the record shape
      (run id + per-task) **incl. a transcript review packet** (prompt, artifact/diff,
      judge report, first-upstream-failure class) **stored in the eval channel's fenced
      path**, the **triple fingerprint** (maker-behavior + judge identity + eval
      instrument = every interpretation-altering instrument artifact, incl. lifecycle
      metadata + calibration set/floor), the observe-only boundary
      (P5), and corpus/rubric/lifecycle-metadata/judge-prompt/scoring-schema/calibration-set-via-PR-only
      (P4); add the
      records-storage row (its own path beside telemetry) to `PROJECT.template.md` →
      "Paths" **and** the active `.claude/PROJECT.md` → "Paths" ([roles] only) (US1)
- [x] T802 [strong] Eval-run record emission (append-only JSONL, one per corpus
      task, sharing a run id; a run is complete only when every corpus task is
      present) **+ a transcript review packet per task** (prompt, artifact/diff, judge
      report, compact first-upstream-failure class) **stored within the eval channel's
      fenced path** (any link resolves inside it) + **triple fingerprint capture**
      (maker-behavior = model resolution + instruction/runtime surfaces; pinned-judge
      identity; eval instrument = corpus/prompts/lifecycle-metadata/rubrics/judge-prompt/
      scoring-schema/calibration-set+labels+floor);
      observe-only, touches no gate/tier state; ships a test incl. the
      write-failure-stays-silent and the partial-run-is-not-a-baseline cases (US1)
- [x] T806 [strong] Judge calibration artifact + agreement reporting: a small
      **owner-labeled calibration set** (maker outputs paired with the owner's
      known-good verdicts) as a frozen, PR-only instrument artifact (P4); each run
      computes & records the **judge↔owner agreement** over it as an observe-only
      figure (P5) and defines the agreement floor triage reads (T803); the set, its
      labels, and the floor are part of the eval-instrument fingerprint (US1.AC3 / T802),
      so a change raises INSTRUMENT-CHANGED. The maker
      judge's analog of the auditor-liveness corpus (T605) — checks the pinned judge
      against human judgment rather than assuming it valid; touches no gate/tier state
      (US1)

## Phase 2 — Trigger, surface, and the P5 fence

- [x] T803 [cheap] Triage "Maker eval" section: score regressions vs the last
      *complete* run under an explicit noise-tolerant threshold (not "any delta"),
      **linking each regression's transcript review packet** + MAKER-EVAL-STALE on a
      **maker-behavior** fingerprint change + JUDGE-CHANGED and INSTRUMENT-CHANGED
      /not-comparable when the judge-identity or eval-instrument fingerprint moved +
      **JUDGE-MISCALIBRATED** when recorded judge↔owner agreement (T806) is below floor
      + explicit "no data yet"/incomplete empty states, read-only over the records (US2)
- [x] T804 [strong] Deterministic P5 fence: a CI assertion that the eval-record
      path **and the transcript-packet storage under it** are referenced only by the
      eval writer and the triage reader — and by no gate/tier/guard/selection path — +
      a `.test.sh` proving it fires on a planted cross-reference to either path and
      passes on the real tree (US2)
- [x] T805 [cheap] Claude skill binding (reuse [workflow]/[headless run]/[reviewer];
      run on **maker-behavior** fingerprint change + schedule) + conformance probe
      (synthetic 1-task corpus; record appended with fingerprint, no gate/tier touched)
      added to the neutral checklist, instantiated for the active adapter, run live,
      results recorded (US2)

## Phase 3 — Trajectory & swap protocol (EdgeBench intake, #211/#212)

- [x] T807 [strong] Interval snapshot capture for corpus runs: fixed instrument-declared
      cadence, snapshots into the fenced eval path (US1.AC1), silent-to-the-run on
      write failure, no maker-visible scores, explicit trajectory-incomplete marking;
      tests per US3.AC2 (cadence fixture, byte-identical-on-write-failure, two-sided
      incomplete marking) (#211) (US3)
- [x] T808 [strong] Post-hoc pinned-judge grading of snapshots + versioned schema
      extension: per-interval scores in the (task × tier) record under an explicit
      instrument version (reviewed-PR eval-instrument fingerprint movement, P4); triage
      renders cross-version deltas INSTRUMENT-CHANGED/not-comparable; extend the US2.AC3
      CI fence to the trajectory storage + planted trajectory-path cross-reference test
      case (P2/P5); blocked by T807 (#211) (US3)
- [x] T809 [cheap] Learning-speed swap protocol doc (matched-start selection with stated
      tolerance, fixed budget, gain definition, informs-never-retiers statement) +
      `.claude/MODELS.md` context-window attribute per row with long-horizon guidance +
      the three EdgeBench §5.4 maker behaviors in implementation-loop guidance
      (`next-task.md` budget check stays green); blocked by T807+T808 (#212) (US4)

## Phase 4 — Parser robustness (issue #293; bug)

> One correctness gap in the eval writer hook's option parsers, a follow-on to #290
> (which guarded only `--trajectory`). Surfaced by triage as unmapped tracker work and
> converted via intake (`workflow/intake.md`). It is a bug — no new `US#`; the acceptance
> reviewer grades it against the done-when criteria carried in issue #293's intake
> cross-link comment, exactly as it would a `US#`.

- [ ] T810 [strong] Guard the remaining **dangling-flag infinite loop** in
      the eval writer hook (under `.claude/hooks/`, `#293`): under `set -u` with no `set -e`, a
      trailing flag with no value makes `shift 2` fail without consuming `$1`, so the
      `while [ "$#" -gt 0 ]` parser re-processes the same flag forever (reproduced: a
      dangling `record --task` spins until killed). `do_record`
      (`--run-id`/`--task`/`--tier`/`--results`/`--prompt`/`--artifact`/`--judge`) and
      `do_complete` (`--run-id`) still use the unguarded `val="${2:-}"; shift 2`; only
      `--trajectory` was fixed in #290. Apply the established
      `[ "$#" -ge 2 ] || { usage; return 2; }` idiom (already used by `--trajectory` and by
      `agreement`/`snapshot-run`/`grade-snapshots`) to every remaining flag in both
      parsers, so a dangling flag is a loud usage error (exit 2, nothing written) while a
      well-formed invocation parses unchanged. Ships per-subcommand perl-`alarm`-capped
      dangling-flag regressions in the eval writer's test harness (mirroring the T806 case-(viii)
      and #290 `--trajectory` tests) — each dangling flag exits 2 within the cap, and
      reverting a guard makes its test hang red; robustness only, so the maker-eval
      instrument fence and docs checks stay green (`maker-eval-fence.sh`,
      `maker-eval-docs.test.sh` — no P4/P5 instrument-semantics change) (#293; bug —
      done-when on issue) — strong: closes a hang in observe-only eval tooling and adds the
      P2 regression coverage (constitution P2/P3)

## Criterion ownership (multi-task user stories)

| Criterion | Owning task |
|---|---|
| US1.AC1 | T801 |
| US1.AC2 | T802 |
| US1.AC3 | T802 |
| US1.AC4 | T801 |
| US1.AC5 | T806 |
| US2.AC1 | T805 |
| US2.AC2 | T803 |
| US2.AC3 | T804 |
| US2.AC4 | T805 |
| US3.AC1 | T807 |
| US3.AC2 | T807 |
| US3.AC3 | T808 |
| US3.AC4 | T808 |
| US4.AC1 | T809 |
| US4.AC2 | T809 |
| US4.AC3 | T809 |

## Blocked / owner-only tasks (never auto-start — surface them instead)

- none
