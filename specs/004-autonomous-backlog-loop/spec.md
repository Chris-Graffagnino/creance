# Spec — Autonomous Backlog Loop

> Converted from owner-filed issue #203 via intake (`workflow/intake.md`). Formalizes a
> bounded, deterministic loop that chains gated `next-task` cycles in one unattended run,
> built on the closed isolation/autonomy foundation (epic #81 · T610–T613). The
> acceptance [reviewer] (`spec-auditor`) grades each task against the `US#` acceptance
> criteria below — bullets are addressable as `US1.AC1`, `US1.AC2`, … Each criterion is
> written as an independently checkable statement.

## Overview

Everything needed to run **one** task unattended already exists — the `[isolated workspace]`
lifecycle, the `[autonomy activation]` check (off by default, fails closed to review),
gate-in-place with PASS→PR / FAIL→discard, and the falsification proof that an un-gated
change cannot reach the base branch (spec 001 US, T610–T613; epic #81). What does not exist
is a way to run **several tasks in sequence** unattended. `next-task.md` §8 ends a run at one
PR by design.

This feature adds a runtime-neutral **`[backlog-loop]`** that wraps the existing single-task
flow: each iteration is a complete, unmodified `next-task` cycle, iterations are bounded by
**deterministic** stop conditions checked only *between* iterations, the run terminates at PRs
(never a merge, never a base-branch write), and its per-iteration state is observe-only
telemetry. "Done" means an operator can start one gated, unattended run that drains a bounded
segment of the backlog into a queue of ratifiable PRs, and every safety invariant the
single-task path guarantees still holds across N iterations — proven by deterministic tests and
one live conformance probe.

## Non-goals

- **No auto-merge.** Merge authorization stays session-explicit (spec 001 autonomy model);
  N iterations must never compound into merge authority. Promotion reuses the existing
  T612 PR path unchanged.
- **No new gate semantics.** The loop composes existing roles only — it adds no round-limit,
  veto-authority, tier-floor, or reviewer-roster change (constitution P5).
- **No control authority for run state.** The run report and iteration counters are
  measurement; they never feed a gate outcome, model-tier assignment, or task selection
  (constitution P5).
- **No post-PR reviewer-comment watching.** Reacting to reviewer comments after a PR opens is
  out of scope for this spec (a separate concern).
- **No change to what automation may write.** A loop iteration must not widen the set of
  files automation may modify (reviewer specs, guards, invariants, constitution stay PR-only;
  constitution P4).

## User stories

### US1 — Bounded, gated unattended backlog draining
As the operator of an opted-in autonomous build, I want a bounded loop that runs several
gated `next-task` cycles in one unattended session, so that I wake to a queue of clean,
ratifiable PRs instead of one — with every safety invariant of the single-task path preserved
across iterations.

**Acceptance Criteria**
- AC1: The loop is specified as a runtime-neutral `[backlog-loop]` in `.claude/workflow/**`
  (capabilities named as bracketed [roles] only — no runtime tool, CLI flag, vendor, or model
  ID; the `workflow/**` neutrality scan stays green), and each iteration is a complete,
  unmodified `next-task` cycle — `[live-state reconciliation]` → implement in the
  `[isolated workspace]` → §7 gate → PASS→PR / FAIL→discard — reusing those roles verbatim; the
  diff introduces no change to gate semantics (round limits, veto authority, tier floors,
  reviewer roster) as shown by the roster/gate-loop sources being unchanged.
- AC2: The loop is reachable **only** through the existing `[autonomy activation]` check: a
  deterministic test proves (a) an entry path that starts iterations without the activation
  check FAILS, and (b) with the profile opt-in absent and no session authorization, the loop
  resolves to review (does not run) — the fail-closed posture is preserved, not relaxed.
- AC3: Stop conditions are **deterministic** and evaluated only *between* iterations, never
  mid-task: (a) a configured **max-N** tasks per run, N resolved from configuration/invocation
  and never hardcoded in the loop body — **N=0 is a valid no-op run that stops immediately for
  condition (a) with no iteration attempted**; (b) no unblocked candidate remains; (c) the same
  task failing the §7 gate **twice** — on the **first** gate FAIL the iteration discards
  (FAIL→discard) and the loop **advances to the next unblocked candidate**, re-selecting the
  same task only if it re-surfaces as lowest-unblocked, where "same task" is tracked by a
  **stable task identity** so a discard-then-reselect cycle cannot loop unbounded below max-N;
  (d) any lifecycle/`[autonomy activation]` check failing closed. A **paired** test proves the
  run halts at N (cannot exceed N iterations) **and** that with M < N eligible unblocked tasks
  the run completes M and stops for condition (b) (it does not stop early while eligible work
  and budget remain), **plus the first-FAIL-advances-to-next-candidate and N=0-no-op behaviors**.
- AC4: The run **never merges and never writes the base branch**: each iteration terminates at a PR
  via the existing T612 promotion path (merge stays session-explicit). A falsification test
  proves that across N iterations no merge and no base-branch write occurs, and that an
  un-gated change from any iteration is unreachable from base (extends the T613 proof to the
  multi-iteration case).
- AC5: Between-iteration state — the run report and any iteration counters — is **observe-only**:
  a deterministic fence proves that no gate-outcome, model-tier-assignment, or task-selection
  code path reads the run report or the counters (constitution P5), **paired** with a control
  proving the writer/reader (reporting) path *does* resolve them, so the fence is not vacuous.
- AC6: The run report is written to the out-of-repo triage-inbox channel (the existing triage
  default; no new path convention invented), one line per iteration recording the task ID, the
  gate verdict, and the resulting PR reference or discard, **each field matching that
  iteration's actual outcome** — a deterministic test asserts the recorded verdict and
  PR-ref/discard equal the iteration's real gate result, not merely that a well-formed line
  exists. A **run-report write failure is silent-to-the-run**: it never aborts an in-flight
  iteration or blocks promotion (consistent with the observe-only posture of the run report),
  and a **partially completed run is a valid outcome, not an error baseline** — still
  observable *as partial* in the report so it is not mistaken for a clean drain. `/triage`
  surfaces the batch in its snapshot.
- AC7: A conformance probe records **one real multi-task unattended run** on the live
  adapter with dated fingerprints (the T303/P-IW pattern), including the observed stop
  condition.
