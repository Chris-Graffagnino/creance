---
name: maker-eval
description: Run the standing maker-eval corpus (project specifics from .claude/PROJECT.md). Re-scores the MAKER — the generation path that writes the code — against the frozen golden-task corpus + per-task rubrics with the pinned judge, after a maker-behavior fingerprint change (the maker model resolution OR an instruction/runtime surface that shapes its output, not the model table alone) or on the weekly schedule. The maker analog of auditor-liveness for the reviewers. Executes each corpus task as a [headless run] of the maker, scores the output with a read-only [reviewer]-style judge, and APPENDS an observe-only record + transcript packet per task to the fenced eval channel — which never feeds a gate outcome, tier assignment, or gate semantics (P5). Use when the user says "maker eval", "run the maker corpus", "eval the maker", "re-score the maker", when triage flags MAKER-EVAL-STALE, or on the weekly schedule. Read-and-append only — never edits the frozen instrument, never gates, never merges.
---

# /maker-eval — Claude Code binding

The workflow logic is runtime-neutral and lives in **`.claude/workflow/maker-eval.md`** —
**read that file now and execute it.** The frozen instrument it runs is
`.claude/workflow/reviewers/maker-eval-corpus.md` (the corpus tasks, the per-dimension
lifecycle-tagged rubric, the pinned-judge prompt/spec, the scoring schema, the
first-upstream-failure taxonomy). It **composes existing roles only** — a **[headless run]**
of the maker, a read-only **[reviewer]**-style judge, and observe-only record emission — and
introduces **no new binding-contract row** (constitution P1; spec 003 US2.AC1). The mapping of
its abstract **[roles]**:

| Neutral role | Claude Code mechanism |
|---|---|
| **[workflow]** (this one) | this skill; a run takes no required argument — it runs the whole corpus and records one append-only result **per corpus task** under one shared **run id**. An optional `ME-id` (e.g. `ME-03`) in the invocation text scopes the run to one task (the explicit-context rule) — a diagnostic whose **partial run is never a comparable baseline** (a subset run has not re-scored every task — `workflow/maker-eval.md` → "The record …"; the completeness oracle below is what the read-only surfacing keys on, so a scoped run simply never reaches `complete`) |
| **the maker** (the subject under test) — its model resolution | the maker tier rows (`[frontier]`/`[strong]`/`[cheap]`) of `.claude/MODELS.md`, resolved to the row the run targets (default: the **[strong tier]** row — the maker as a real strong-tagged task would run; an `ME-id`/tier note in the invocation text may target another row). Passed as the `--model` flag on the maker [headless run] below |
| **[headless run]** (executing each task as the maker would) | `claude -p "<the task's materialized prompt>" --model <maker row>` — for each corpus task, reconstruct the prompt from `reviewers/maker-eval-corpus.md` → "Task detail" (the corpus declares the *task*; the runner materializes the *prompt*, `maker-eval.md` → "The run"), run it non-interactively, and capture the generated artifact/diff. Exactly as a real task would run — no fix loop here either |
| **[reviewer]** (the pinned judge — read-only, **report-only**) | a subagent dispatched via the Agent tool against the maker's captured output, in its own context, **with no edit tools**, scoring it against that task's lifecycle-tagged rubric dimensions and emitting the scoring-schema verdict (per-dimension `meets`/`partial`/`fails` + evidence, an `overall`, and a first-upstream-failure class on any non-pass). A **single grading pass: no fix step, no re-dispatch loop** (unlike the §7 gate's converge-to-PASS loop — the corpus *measures* the maker, it does not drive a diff to PASS, `maker-eval.md` → "The run"). The judge has no authority over the maker, the tiers, or the gate |
| **pinned-judge identity** (fixed independently of the maker model-table change) | the **`maker-eval judge`** row of `.claude/MODELS.md` — its **own line**, **not** re-resolved from a maker tier row a maker swap moves — passed as the Agent tool's `model` parameter on **every** judge dispatch (never inherited from the session, so a maker swap never moves the judge and the differential stays an independent measurement — constitution P1). If that row's model is unavailable, round **up** (never down) and say so loudly in the run summary |
| **record + transcript-packet emission** (the observe-only write) | `bash .claude/hooks/maker-eval-emit.sh record --run-id <id> --task <ME-id> --results <judge.json> [--prompt <f>] [--artifact <f>] [--judge <f>]` — the T802 emitter (US1.AC2/AC3). It appends **exactly one** append-only JSONL record for the task to the fenced eval channel and stores its transcript review packet (prompt, artifact/diff, judge report, first-upstream-failure class) **inside** that channel, stamping the **triple fingerprint** itself. `<judge.json>` is the judge's per-task output `{ dimensions:[{dimension,lifecycle,verdict,evidence}...], overall, first_upstream_failure }`. The run id is a single safe path component (no `/` or `..`), shared across the run's tasks — e.g. `run-$(date -u +%Y%m%dT%H%M%SZ)`. A malformed judge output or a missing requested packet file is a **loud** caller error (nothing written); any other write failure is **silent-to-the-eval** (the run is observe-only — a failed write blocks nothing) |
| **the triple fingerprint** (the run's `maker_behavior` / `judge_identity` / `eval_instrument` hashes) | computed **by the emitter** on each `record`; recompute it directly with `bash .claude/hooks/maker-eval-emit.sh fingerprint` (the **single-source recipe** — never re-derive what the maker-behavior surface covers; see "The maker-behavior fingerprint trigger" below). Reused, not re-derived, so what the surface covers stays a one-place edit |
| **completeness oracle** (a run is comparable only when whole) | `bash .claude/hooks/maker-eval-emit.sh complete --run-id <id>` (exit 0 = every corpus task has a record under `<id>`; exit 3 = incomplete). The read-only surfacing (`triage.md`) keys on this so an **incomplete run is never a silent baseline** — a scoped `ME-id` diagnostic never reaches `complete` |
| **observe-only results channel** | the out-of-repo eval channel the profile names — `.claude/PROJECT.md` → "Paths" → **Maker-eval records** — written **only** through the emitter above (never an in-repo table — the channel is fenced out-of-repo by `maker-eval-fence.sh`, T804). Append-only; **never** read by any gate, tier resolver, guard, selection step, or gate-semantic. The triage **"Maker eval"** section (T803) is the read-only surfacing |
| **[headless run] + the ≥ weekly schedule** (the two triggers) | **schedule:** `claude -p "/maker-eval"` on the same scheduler substrate the read-only triage heartbeat uses (the launcher contract, `workflow/triage.md` §6) — the named minimum cadence is **weekly**. **On maker-behavior change:** the deterministic **MAKER-EVAL-STALE** flag the daily heartbeat surfaces (`triage.md`; the detector is below) is the signal to invoke this skill on demand |
| **[bulk-read offload]** | the `Explore` subagent (spawn on the **[cheap tier]** per `.claude/MODELS.md`) for a large materialized artifact the judge must read |
| **[comment marker]** | the footer line defined in `.claude/skills/next-task/SKILL.md` → "The [comment marker] concrete form" — on any `gh issue comment` / `gh pr comment` body a run posts (e.g. when proposing an instrument change via PR; a run never edits the instrument in place — constitution P4) |
| **[environment block]** | `.claude/skills/next-task/SKILL.md` → "This environment's concrete forms" (the single copy — `gh` PATH fallback, UTF-8 temp-file bodies) |

## The maker-behavior fingerprint trigger (the deterministic on-change detector)

`maker-eval.md` → "Re-run policy" defers the concrete recipe to the adapter. It is **not**
re-derived here — it is the `maker_behavior` component the emitter computes, the
**single source**:

```
bash .claude/hooks/maker-eval-emit.sh fingerprint    # → {maker_behavior, judge_identity, eval_instrument}
```

The `.maker_behavior` field is a content hash over the **maker model resolution** (the maker
tier rows of `.claude/MODELS.md`) **plus the instruction/runtime surfaces that shape the
maker's output** — `AGENTS.md`, the methodology docs (`workflow/**`), and the adapter binding
prompts (`skills/**`) — **excluding** the eval machinery itself (so it stays disjoint from
`eval_instrument`). It is therefore **not the model table alone** (spec 003 US1.AC3): an
instruction-surface edit with no model swap still moves it.

Triage recomputes this same recipe (it reuses it, never re-derives it) and flags
**MAKER-EVAL-STALE** when the current `.maker_behavior` differs from the **last complete run's**
recorded `fingerprint.maker_behavior` — a swap or an instruction-surface edit happened with no
fresh eval. That flag is the on-change trigger to invoke this skill; the weekly schedule is the
second trigger (a maker can pass once yet drift as the model behind it changes). Both are
`maker-eval.md` → "Re-run policy"; this binding only supplies *how* each is launched.

## Observe-only — the hard boundary (constitution P5)

Every record, score, per-dimension verdict, agreement figure, and fingerprint movement is an
**evaluation record**: append-only observation. It **never** feeds a gate outcome, a model-tier
assignment, or any gate semantic (round limits, veto authority, tier floors). A regression
**surfaces** for a human to act on through the ordinary task flow — it never auto-reverts a
swap, never re-tiers, never re-dispatches the gate, never edits the frozen instrument. This run
only **reads** the instrument and **appends** to the fenced channel; it proposes an instrument
change (a new task, a promoted dimension) the way the retrospective proposes a hunt-rule
tightening — as a reviewed PR, never in place (constitution P4). This is the same fence the
profile's telemetry/evaluation invariant draws (`.claude/PROJECT.md` → "Invariant checklist")
and the deterministic `maker-eval-fence.sh` enforces (T804): a change that lets an eval record
reach a gate/tier/guard/selection path is a FAIL.

## Relationship to auditor-liveness (the discipline this mirrors)

`auditor-liveness` proves each judgment **[reviewer]** still discriminates known-good from
known-bad; this corpus proves the **maker** still meets the known-good rubric on a frozen task
set. Both generalize constitution **P2**'s "proven live, not assumed live" discipline from the
deterministic `guard.test.sh` to a model-driven path, so both run **report-only on a schedule +
on a fingerprint change** rather than as a hard gate (a flaky verdict would block honest work).
The signal is **differential** — this run versus the last complete run on the *same frozen
corpus* — so an absolute judge score is never load-bearing (`maker-eval.md`). The neutral doc
carries the full relationship table.
