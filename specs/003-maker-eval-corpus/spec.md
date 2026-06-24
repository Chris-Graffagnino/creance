# Spec — Maker Eval Corpus

> Epic for the Creance repo itself. The acceptance [reviewer] (`spec-auditor`)
> grades each task against the `US#` acceptance criteria below — bullets are
> addressable as `US1.AC1`, `US1.AC2`, … (the nth bullet under that story), so
> they are written as independently checkable statements.

## Overview

Creance proves its *reviewers* stay live (auditor-liveness) but has no equivalent
for the *maker* — the generation path — so a one-line model-table swap can silently
degrade quality with nothing to catch it until production. This spec adds a small,
frozen golden-task corpus that re-scores the maker whenever the model table
changes, emits append-only observe-only records (the gate-telemetry form), and
surfaces regressions in triage. The signal is **differential** — this run versus
the last on the same frozen corpus — so absolute judge calibration is never
load-bearing, and the channel is fenced observe-only by a deterministic CI
assertion. Done means: a model-table change triggers a recorded maker-eval whose
regressions surface in triage, and no eval record can reach a gate, tier, guard,
or selection path.

Motivation and provenance: the "New SDLC with vibe coding" analysis
(https://addyosmani.com/blog/new-sdlc-vibe-coding; the Kaggle whitepaper),
2026-06-23 — "set the bar at the eval, not the demo." Mirrors the auditor-liveness
corpus (T605) for the maker, and spec-001 telemetry + freshness (US1/US5). Issue:
#144 (stacked on spec 002, #142 / PR #143, for the shared `.claude/PROJECT.md`
Paths edit).

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
As a harness operator, I want a frozen golden-task corpus that scores the maker's
output against per-task rubrics and records the result observe-only, so that
generation quality becomes a trend I can inspect rather than an anecdote.

**Acceptance Criteria**
- AC1: A runtime-neutral workflow doc defines a small, frozen set of representative
  tasks, each paired with a known-good rubric; an eval run resolves the current
  model table, executes each task via a **[headless run]** of the maker, and scores
  the output with a read-only **[reviewer]**-style judge against the rubric. It
  names **[roles]** only (constitution P1) and names where records are stored via
  `.claude/PROJECT.md` → "Paths" (beside telemetry, out-of-repo by default).
- AC2: Each run emits exactly one append-only record per corpus task (task ID, the
  model-table resolution used, the per-rubric verdict/score, and a timestamp), in
  the gate-telemetry JSONL form; a failed write changes nothing (it has nothing to
  block — AC4).
- AC3: Each run records a deterministic content-hash fingerprint of the model table
  alongside its results — mirroring the probe-run fingerprint (spec 001 US5.AC1) —
  so a model swap is detectable as a fingerprint change, not inferred from timing.
- AC4: The eval is **observe-only (constitution P5)**: no record, score, or flag
  feeds a gate outcome, a tier assignment, or gate semantics. The corpus and its
  rubrics are reviewer-spec-class artifacts — changed only by a human-reviewed PR,
  never by an automatic rewrite or a side effect of a run (constitution P4).

### US2 — Trigger, surface, and the deterministic P5 fence
As a harness operator, I want the eval re-run on every model-table change and its
regressions surfaced in triage, with the observe-only boundary enforced
deterministically, so a degrading swap is surfaced in days and the eval channel
can never gain control authority.

**Acceptance Criteria**
- AC1: The eval is (re-)run when the model-table fingerprint changes and on a
  schedule (the T605 / [workflow] cadence), exposed by a skill binding reusing
  existing roles — no new binding-contract role is created.
- AC2: Triage gains a read-only "Maker eval" section: score regressions against the
  last recorded run, a **MAKER-EVAL-STALE** flag when the current model-table
  fingerprint differs from the last run's (a swap with no fresh eval, a warning),
  and an explicit "no data yet" empty state — rendered consistently with the other
  snapshot sections, never silently omitted (spec 001 US2/US5 pattern). Triage
  neither runs the eval nor writes records.
- AC3: A **deterministic CI assertion** fences the channel: the eval-record path is
  referenced only by the eval writer and the triage reader, and by no gate, tier,
  guard, or selection code path — so P5 is enforced deterministically, not left to
  judgment (a deliberate strengthening over spec 001's telemetry, whose P5
  enforcement is judgment-only). It ships with a `.test.sh` proving the fence fires
  on a planted cross-reference and passes on the real tree (constitution P2).
- AC4: A conformance probe (a synthetic single-task corpus; verify a record is
  appended with the model-table fingerprint and that no gate/tier state is touched)
  is added to the neutral checklist, instantiated for the active adapter, and passes
  on it with results recorded.
