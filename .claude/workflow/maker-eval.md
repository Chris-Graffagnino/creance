# maker-eval — keep the maker (the generation path) proven non-degrading (runtime-neutral)

The harness proves its **[reviewer]s** stay live (`auditor-liveness.md`) but has no
equivalent for the **maker** — the generation path that writes the code. So a one-line
model-table swap, or an edit to an instruction surface that shapes the maker's output, can
**silently degrade generation quality** with nothing to catch it until the degradation
reaches production. This workflow closes that gap with the maker analog of the
auditor-liveness corpus: a small **frozen golden-task corpus** that re-scores the maker
whenever its **behavior fingerprint** changes, emits **observe-only** records with a
human-reviewable transcript packet per task, and surfaces regressions through the read-only
heartbeat.

> Runtime-neutral: roles in **[brackets]** are defined in `workflow/README.md` → "The
> binding contract". Project specifics — the constitution path, the records location, the
> model tiers — come from `.claude/PROJECT.md` and the adapter's model table. Below, *the
> profile* means that file. This workflow **composes existing roles only** — a
> **[headless run]** of the maker, a read-only **[reviewer]**-style judge, and observe-only
> surfacing — and (exactly like the retrospective and auditor-liveness) introduces
> **no new binding-contract row**.

## Relationship to auditor-liveness and the guard's deterministic test (the discipline it mirrors)

| | Proves | Cadence | Shape |
|---|---|---|---|
| `guard.test.sh` (the **[guard]**'s regression test) | the deterministic guard still fires | every gate run (required check) | deterministic — a hard gate |
| **auditor-liveness** (`auditor-liveness.md`) | each judgment **[reviewer]** still discriminates known-good from known-bad | on every reviewer-spec change **+ ≥ weekly** | model-driven — a standing **report-only** run |
| **this corpus** (maker-eval) | the **maker** still meets the known-good rubric on a frozen task set | on every **maker-behavior** fingerprint change **+ ≥ weekly** | model-driven — a standing **observe-only** run |

auditor-liveness measures the *checkers*; this corpus measures the *maker*. Both generalize
constitution **P2**'s "proven live, not assumed live" discipline from the deterministic guard
to a model-driven path. Because the maker is nondeterministic, the corpus **cannot be a
deterministic hard gate** — a flaky verdict would block honest work — so like auditor-liveness
it is a **report-only** run whose records are **observe-only** (below), never a gate. The
signal is **differential**: this run versus the last on the *same frozen corpus*, so an
absolute judge score is never load-bearing (the judge is separately calibrated against an
owner-labeled set — `reviewers/maker-eval-corpus.md` → "Judge calibration" — so the
instrument is known-meaningful rather than assumed valid).

## The corpus (what must exist)

The frozen instrument lives in `reviewers/maker-eval-corpus.md`. The contract that file
declares, and that the profile's deterministic backstop enforces:

- **A small, frozen set of representative tasks** — kept frozen so two runs are comparable.
  The set stays frozen for comparability **yet grows and retires only by reviewed PR**
  (constitution P4, below), via the per-dimension **lifecycle metadata** each scored rubric
  dimension carries: `capability` (a forward dimension probing whether the maker *can* do
  something), `regression` (a dimension pinned to a known past failure — a guard against
  backsliding), or `saturated` (a dimension the maker reliably passes, kept as a calibration
  floor). Lifecycle lives on the **dimension, not the task**, so one task can pin a regression
  on one dimension while probing a capability on another (`reviewers/maker-eval-corpus.md`).
- **Each task is paired with a known-good rubric** — the small set of **lifecycle-tagged
  dimensions** the judge scores it against, with the known-good answer stated, so "passed" is
  checkable rather than vibes.
- **Seeded from real signals, not synthetic toys.** Each task is drawn from a real failure
  or workflow *class* the harness has actually seen — retrospective escapes (the
  evasion-register exhibits), discovered-work clusters, owner-comment steering, and
  auditor-liveness fixtures — and from **adopter/product workflows** (cold-starting a fresh
  project from the template, porting an adapter to a new runtime). The corpus is **portable
  engine machinery** like the auditor-liveness corpus: it names the *class* of each real
  signal, never an instance fact, so it ships verbatim and needs no extraction reset.

## The pinned judge (identity fixed independently of the maker model-table change)

The judge is a read-only **[reviewer]**-style scorer: it reads the maker's output and grades
it against the task's rubric, in its own context, with no edit authority — exactly the
adversarial, report-only posture the gate's auditors use, pointed at the maker instead of a
diff. It is part of the **frozen instrument**, so its identity is **pinned independently of
the maker model-table change**: the adapter's model table declares it on its own line,
**not** re-resolved from a tier row a maker swap moves (the concrete pin is the adapter's —
`.claude/MODELS.md`). Between two runs, only the maker varies and the differential stays an
**independent measurement** (constitution P1). A change to the judge's identity, or to its
prompt/spec, is an **instrument change** (it moves the judge-identity or eval-instrument
fingerprint below), never a silent re-grade.

## The run (read-only judge, headless maker — composes existing roles)

A run, for each corpus task:

1. **Resolve the current model table** to the maker's identity (the tier the run targets).
2. **Execute the task as a [headless run] of the maker** — the maker generates the artifact
   or diff the task asks for, non-interactively, exactly as a real task would.
3. **Score the output with the pinned read-only [reviewer]-style judge** against the task's
   rubric — a single grading pass, **no fix loop and no re-dispatch**: the corpus *measures*
   the maker, it does not drive a task to PASS (unlike the §7 gate's converge-to-PASS cycle).

The run **only reads** the frozen instrument and **appends** observe-only records (below); it
never edits the corpus, the rubrics, the judge, or any gate state.

## The record and the transcript review packet (the shape the emitter writes)

Each run emits **exactly one append-only record per corpus task**, all sharing one **run id**,
to the eval channel the profile names — `.claude/PROJECT.md` → "Paths" → **Maker-eval
records**, its **own append-only path beside the telemetry stream**, kept distinct so the
deterministic P5 fence can scope to it. Each record carries: the run id, the corpus task id,
the **triple fingerprint** (below), the per-dimension verdict/score **each tagged with its
lifecycle** (`capability`/`regression`/`saturated`, carried on the dimension — not one tag per
task), and a timestamp — in the same append-only JSONL form the telemetry stream uses
(`telemetry.md`).

Alongside each record the run **stores a transcript review packet** for that task **within
the eval channel's own fenced path** — the task prompt, the generated artifact/diff, the
judge's report, and a compact **first-upstream-failure classification** (the earliest step
that broke, not only the surface symptom — drawn from a fixed taxonomy in
`reviewers/maker-eval-corpus.md` → "First-upstream-failure taxonomy"). Any in-record link to a
packet resolves **only inside that same fenced path**, so packet artifacts never escape the
observe-only backstop and a regression stays human-reviewable rather than a bare dropped
number.

A run is **complete** only when **every** corpus task has a record under its run id. A failed
or partial write **changes nothing** — it has nothing to block (the eval is observe-only) — and
an **incomplete run is never treated as a comparable baseline** by the regression surfacing
(`triage.md`). The concrete JSONL/packet mechanism is the adapter's to supply; the emitter and
its tests are the next task's (US1.AC2).

## The triple fingerprint (three separately-recorded components)

Each run records a deterministic content-hash fingerprint alongside its results — mirroring the
probe-run fingerprint (`auditor-liveness.md`; spec 001 US5) — composed of **three
separately-recorded components**, so a maker change, a judge change, and an instrument change
are each detectable as **their own** fingerprint movement, never inferred from timing and never
conflated:

1. **Maker-behavior fingerprint** — the maker's model resolution **plus the
   instruction/runtime surfaces that shape its output**: the relevant methodology docs, the
   adapter binding prompts, and the always-resident instructions — **not the model table
   alone**. (An instruction-surface edit with no model swap still changes how the maker
   behaves, so it must move this component.)
2. **Pinned-judge identity** — the judge's own model resolution, fixed independently of the
   maker swap (above), so a judge change is visible as its own movement.
3. **Eval-instrument fingerprint** — **every frozen-instrument artifact whose change alters
   interpretation or comparability**: the corpus tasks and their prompts, the per-dimension
   lifecycle metadata, the rubrics, the judge prompt/spec, the scoring schema, and the
   owner-labeled calibration set with its labels and agreement floor. A reviewed-PR change to
   any of these — including promoting or retiring a single dimension's lifecycle — moves this
   component.

Recording them separately lets the read-only surfacing tell an **expected maker delta** from a
**confounded comparison**: a moved maker-behavior fingerprint with a stale eval is a staleness
warning; a moved judge-identity or eval-instrument fingerprint between two runs being
differenced makes the comparison **not-comparable** (the regression call is suppressed rather
than reported as a confounded delta — `triage.md`). The concrete hash recipe is the adapter's
to supply.

## Re-run policy (on maker-behavior change + on a named schedule)

The corpus re-runs on **both** triggers (the same two-trigger discipline as auditor-liveness):

- **On every maker-behavior fingerprint change** — detected **deterministically**
  (constitution **P3**: prefer a deterministic check to a remembered intention). When the
  **current** maker-behavior fingerprint differs from the **last complete run's**, an eval is
  due — a swap or an instruction-surface edit happened with no fresh eval. This is a
  **definite flag, not a heuristic**, surfaced through the heartbeat (`triage.md`).
- **On a schedule — at least weekly.** A maker can pass once yet drift as the model behind it
  changes; only a time-based re-run catches that. The run is invoked non-interactively (a
  **[headless run]**) on the same scheduler substrate the heartbeat uses.

The concrete trigger wiring and schedule are the adapter's (US2.AC1); this doc defines *when*
a re-run is due, not *how* it is launched.

## Observe-only (constitution P5 — the hard boundary)

A record, a score, a regression flag, and a fingerprint movement are **evaluation records**:
append-only observations. They **surface to the owner read-only and never feed a gate outcome,
a model-tier assignment, or any gate semantic** (round limits, veto authority, tier floors).
The corpus measures the maker; being measured grants it **no authority** over the maker, the
tiers, or the gate. A regression never auto-reverts a swap, never re-tiers, never re-dispatches
a gate — it is a signal a human acts on through the ordinary task flow. This is the
constitution's **telemetry-observes-never-decides** principle (P5) applied to the maker, and the
same fence the profile's telemetry/evaluation invariant already draws: a measurement channel
that gains control authority has violated P5, whatever the convenience. A **deterministic CI
assertion** enforces this boundary (the eval-record path and its transcript packets are
referenced only by the eval writer and the read-only surfacing — never a gate/tier/guard/
selection path), enforced deterministically so P5 here is mechanical rather than judgment-only (US2.AC3).

## Seeding & growth (the instrument changes only by PR — never silently)

The corpus, the rubrics, the per-dimension lifecycle metadata, the judge prompt/spec, the scoring
schema, and the owner-labeled calibration set are **reviewer-spec-class artifacts**: they are part of the
frozen instrument, so they are **changed only by a human-reviewed PR — never by an automatic
rewrite or a side effect of a run** (constitution **P4**). A run only *reads* the instrument and
*appends* observe-only records; it proposes an instrument change the way the retrospective
proposes a hunt-rule tightening — as a reviewed PR, never in place. Adding a task or a scored
dimension, promoting a `capability` dimension to `regression`, retiring one to `saturated`, or
re-labeling the calibration set all travel the standard issue → branch → §7 gate → PR flow, and
the owner merges to apply.
