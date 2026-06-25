# Spec — Maker Eval Corpus

> Epic for the Creance repo itself. The acceptance [reviewer] (`spec-auditor`)
> grades each task against the `US#` acceptance criteria below — bullets are
> addressable as `US1.AC1`, `US1.AC2`, … (the nth bullet under that story), so
> they are written as independently checkable statements.

## Overview

Creance proves its *reviewers* stay live (auditor-liveness) but has no equivalent
for the *maker* — the generation path — so a one-line model-table swap can silently
degrade quality with nothing to catch it until production. This spec adds a small,
frozen golden-task corpus — **seeded from real Creance failures and workflows**, each
dimension carrying lifecycle metadata so the set stays frozen for comparability yet
grows and retires only by reviewed PR — that re-scores the maker whenever its
**behavior fingerprint** changes (the model resolution **plus** the instruction/runtime
surfaces that shape its output, not the model table alone), emits append-only
observe-only records (the gate-telemetry form) with a human-reviewable transcript packet
per task, and surfaces regressions in triage. The signal is **differential** — this run
versus the last on the same frozen corpus — so an absolute judge score is never
load-bearing; the judge is nonetheless calibrated against a small owner-labeled set so
the instrument is known-meaningful rather than assumed valid, and the channel is fenced
observe-only by a deterministic CI assertion. Done means: a maker-behavior change
triggers a recorded maker-eval whose regressions surface in triage, and no eval record
can reach a gate, tier, guard, or selection path.

Motivation and provenance: the "New SDLC with vibe coding" analysis
(https://addyosmani.com/blog/new-sdlc-vibe-coding; the Kaggle whitepaper),
2026-06-23 — "set the bar at the eval, not the demo." Mirrors the auditor-liveness
corpus (T605) for the maker, and spec-001 telemetry + freshness (US1/US5). Issue:
#144 (stacked on spec 002, #142 / PR #143, for the shared `.claude/PROJECT.md`
Paths edit). Amended 2026-06-24 (issue #146) after an eval-research pass —
full eval-instrument fingerprinting, a maker-behavior (not model-table-only)
fingerprint, a human judge-calibration artifact, transcript review packets,
per-dimension lifecycle metadata, and real-signal corpus seeding — drawing on
hamel.dev evals-faq, eugeneyan.com eval-process, huyenchip.com ai-engineering
pitfalls (2025-01-16), the O'Reilly "evals are not all you need", Anthropic's
"demystifying evals for AI agents", and arXiv:2404.12272.

## Non-goals

- No eval record, score, or regression flag ever feeds a gate outcome, tier
  assignment, or gate semantics (round limits, veto authority, tier floors) —
  observe-and-report only (constitution P5).
- No auto-revert, auto-retier, or prompt/rubric auto-rewrite (constitution P4;
  spec 001 non-goals).
- No new binding-contract **[role]** — reuses [workflow] / [headless run] /
  [reviewer] (constitution P1).
- Not a latency or cost benchmark — it scores output *quality* against rubrics.
- No cross-project corpus aggregation; each project's corpus and rubrics are its
  own.

## User stories

### US1 — The corpus, the run, and the observe-only record
As a harness operator, I want a frozen golden-task corpus — seeded from real failures
and workflows — that scores the maker's output against per-task rubrics with a judge I've
calibrated against my own labels, and records the result observe-only, so that generation
quality becomes a trend I can inspect rather than an anecdote.

**Acceptance Criteria**
- AC1: A runtime-neutral workflow doc defines a small, frozen set of representative
  tasks — **seeded from real Creance signals** (retrospective escapes, discovered-work
  clusters, owner comments, auditor-liveness fixtures) and from **adopter/product
  workflows** (cold-starting from the template, porting an adapter), not synthetic
  toys — each paired with a known-good rubric and **per-dimension lifecycle metadata**
  (`capability` / `regression` / `saturated`) so the set stays frozen for run-to-run
  comparability while dimensions are added, promoted, or retired only by reviewed PR
  (AC4, constitution P4); an eval run resolves the current
  model table, executes each task via a **[headless run]** of the maker, and scores
  the output with a read-only **[reviewer]**-style judge against the rubric. The
  judge is part of the frozen instrument — its identity is **pinned independently of
  the maker model-table change** (declared in the profile / `.claude/MODELS.md`, not
  re-resolved from the row a maker swap moves), so between two runs only the maker
  varies and the differential stays an independent measurement (constitution P1). It
  names **[roles]** only (constitution P1) and names where records are stored via
  `.claude/PROJECT.md` → "Paths" — its **own append-only path beside the telemetry
  stream** (out-of-repo by default), kept distinct so the US2.AC3 fence can scope to
  it.
- AC2: Each run emits exactly one append-only record per corpus task (a shared **run
  id**, the corpus task ID, the maker-behavior fingerprint used (AC3), the per-rubric
  verdict/score, and a timestamp), in the gate-telemetry JSONL form, and **preserves or
  links a transcript review packet** per task — the task prompt, the generated
  artifact/diff, the judge's report, and a compact **first-upstream-failure
  classification** (the earliest step that broke, not only the surface symptom) — so a
  regression is human-reviewable rather than a bare dropped number. A run is **complete**
  only when every corpus task has a record under that run id; a failed or partial write
  changes nothing (it has nothing to block — AC4), and an incomplete run is never treated
  as a comparable baseline (US2.AC2).
- AC3: Each run records a deterministic content-hash fingerprint alongside its
  results — mirroring the probe-run fingerprint (spec 001 US5.AC1) — composed of **three
  separately-recorded components**: (1) the **maker-behavior fingerprint** — the maker
  model resolution **plus** the instruction/runtime surfaces that shape its output (the
  relevant workflow docs, the adapter binding prompts, and the always-resident
  instructions), not the model table alone; (2) the **pinned-judge identity** — the
  judge's own model resolution, fixed independently of the maker swap (AC1); and (3) the
  **eval-instrument fingerprint** — the corpus tasks and their prompts, the rubrics, the
  judge prompt/spec, and the scoring schema. Recording them separately makes a maker
  change, a judge change, and an instrument change each detectable as its own fingerprint
  movement — not inferred from timing and not conflated with one another — so triage can
  tell an expected maker delta from a confounded comparison (US2.AC2).
- AC4: The eval is **observe-only (constitution P5)**: no record, score, or flag
  feeds a gate outcome, a tier assignment, or gate semantics. The frozen instrument —
  the corpus, its rubrics, the judge prompt/spec, and the owner-labeled calibration set
  (AC5) — comprises reviewer-spec-class artifacts, changed only by a human-reviewed PR,
  never by an automatic rewrite or a side effect of a run (constitution P4).
- AC5: The pinned judge is **calibrated against human judgment, not assumed valid**: a
  small **owner-labeled calibration set** (maker outputs paired with the owner's
  known-good verdicts) is part of the frozen instrument (AC4), and each eval run reports
  the **judge↔owner agreement** over that set as an observe-only figure alongside its
  results (constitution P5). The agreement figure never gates, retiers, or alters the
  eval — it tells the operator only whether the instrument's judge still tracks human
  judgment (surfaced in triage, US2.AC2). This is the maker judge's analog of the
  auditor-liveness corpus (T605) for the reviewers — the judge's known-good calibration.

### US2 — Trigger, surface, and the deterministic P5 fence
As a harness operator, I want the eval re-run on every maker-behavior change and its
regressions surfaced in triage, with the observe-only boundary enforced
deterministically, so a degrading swap is surfaced in days and the eval channel
can never gain control authority.

**Acceptance Criteria**
- AC1: The eval is (re-)run when the **maker-behavior fingerprint** changes (US1.AC3 —
  the maker model resolution or any of the instruction/runtime surfaces that shape its
  output, not the model table alone) and on a schedule (the T605 / [workflow] cadence),
  exposed by a skill binding reusing existing roles — no new binding-contract role is
  created.
- AC2: Triage gains a read-only "Maker eval" section: score regressions against the
  last **complete** recorded run (an incomplete run — not every corpus task present
  under its run id, US1.AC2 — renders as incomplete, never a silent baseline) under an
  **explicit regression threshold that tolerates the judge's run-to-run noise** (not
  "any delta", so the observe-only channel does not become alert noise), **linking each
  flagged regression's transcript review packet** (US1.AC2) so it is reviewable in one
  hop; a **MAKER-EVAL-STALE** flag when the current **maker-behavior fingerprint**
  (US1.AC3) differs from the last run's (a swap or an instruction-surface edit with no
  fresh eval, a warning); a **JUDGE-CHANGED / not-comparable** annotation when the
  judge-identity component (US1.AC3) differs between the two runs being differenced, and
  an **INSTRUMENT-CHANGED / not-comparable** annotation when the eval-instrument
  component (US1.AC3) differs — each suppressing the regression call rather than
  reporting a confounded delta; a **JUDGE-MISCALIBRATED** warning when the recorded
  judge↔owner agreement (US1.AC5) falls below its stated floor; and an explicit "no data
  yet" empty state — all rendered consistently with the other snapshot sections, never
  silently omitted (spec 001 US2/US5 pattern). Triage neither runs the eval nor writes
  records.
- AC3: A **deterministic CI assertion** fences the channel: the eval-record path is
  referenced only by the eval writer and the triage reader, and by no gate, tier,
  guard, or selection code path — so P5 is enforced deterministically, not left to
  judgment (a deliberate strengthening over spec 001's telemetry, whose P5
  enforcement is judgment-only). It ships with a `.test.sh` proving the fence fires
  on a planted cross-reference and passes on the real tree (constitution P2).
- AC4: A conformance probe (a synthetic single-task corpus; verify a record is
  appended with the maker-behavior fingerprint and that no gate/tier state is touched)
  is added to the neutral checklist, instantiated for the active adapter, and passes
  on it with results recorded.
