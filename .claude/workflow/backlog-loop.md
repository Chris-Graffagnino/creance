# backlog-loop — bounded unattended chaining of gated next-task cycles (runtime-neutral)

The spec for the **[backlog-loop]** role: a bounded iteration model that runs several
complete `next-task.md` cycles in one unattended session, so an engaged autonomous run
drains a bounded segment of the backlog into a **queue of ratifiable PRs** instead of one.
The loop is a *wrapper*: it owns iteration sequencing, the deterministic stop conditions,
and the observe-only run report — nothing else. Everything inside an iteration is the
single-task procedure, unchanged.

> Runtime-neutral: roles in **[brackets]** are defined in `workflow/README.md` → "binding
> contract" and mapped to concrete mechanisms by the active adapter. Project facts (paths,
> task-ID format, the blocked-task list) come from `.claude/PROJECT.md`.

## What the loop owns (and what stays with `next-task.md`)

The loop owns exactly three things:

- **iteration sequencing** — resolving the next candidate *between* iterations and
  starting each iteration as a fresh run;
- **the stop conditions** — deterministic, evaluated only *between* iterations (below);
- **the run report** — one observe-only record per iteration (below).

It does NOT own — and must not restate, weaken, or extend:

- **The single-task cycle.** Each iteration is a **complete, unmodified** `next-task.md`
  run: §0 preconditions → the §0.5 **[autonomy activation]** decision → §1 selection with
  **[live-state reconciliation]** → implement in the **[isolated workspace]** → the §7
  gate → §8 **PASS→promote-to-PR / FAIL→discard**. The loop *invokes* that procedure and
  reads its outcome; it never reaches into it, skips a step, or substitutes its own.
- **Gate semantics.** Round limits, veto authority, tier floors, and the reviewer roster
  are `gate-loop.md`'s (the single source of truth) and are **unchanged** by this spec —
  the loop composes existing roles only and adds no reviewer, no condition, no floor.
- **Merge authority.** Promotion inside an iteration is the existing §7-gated PR path;
  **merge stays session-explicit** (`next-task.md` §2.5/§8). N iterations never compound
  into merge authority: the run's terminal state is a queue of open PRs, every one
  awaiting the same human (or session-authorized) merge as a single-task run's PR.

## Reachability — only through [autonomy activation]

The loop is reachable **only** through the existing **[autonomy activation]** check — the
same off-by-default, fail-closed decision that gates a single autonomous task
(`next-task.md` §0.5; `workflow/README.md` → "Isolation and the guard's fail-open
posture"). With neither activation signal, or on any uncertainty, the check resolves to
**review** and the loop does not run — there is no separate loop-level opt-in, no loop
path that skips the check, and no fallback that runs iterations un-isolated.

The check runs at two layers, both mandatory:

- **At loop start** — the wrapper that would begin iterating consults
  **[autonomy activation]** first; anything but an engaged autonomous decision means the
  loop never starts (review mode: a single `next-task.md` run, a human merges).
- **Inside every iteration** — each cycle's own §0.5 decision runs unchanged (the loop
  never passes "already engaged" down as an assumption; explicit-context carries data,
  never authority). A cycle that resolves to review, or whose **[isolated workspace]**
  entry fails loud, aborts per `next-task.md` §0.5 — and the loop stops (condition (d)
  below), never continuing around a failed-closed check.

## Inputs (explicit, per the explicit-context rule)

The wrapper that starts a run passes every value the run must honor in the invocation
itself (`workflow/README.md` → "The explicit-context rule"):

- **iteration budget N** — required; resolved from configuration or the invocation text,
  **never hardcoded in the loop body**. **N = 0 is a valid no-op run**: stop condition (a)
  fires immediately and no iteration is attempted.
- **the repo root and any non-default paths** (e.g. a profile-overridden report location)
  — explicit, never inferred from a working directory or environment hints alone.

Each iteration is started as a fresh **[headless run]** of the `next-task` **[workflow]**
with the resolved task ID passed explicitly in the invocation text — one task, one clean
context (`next-task.md` → "Context discipline"); no iteration continues a prior
iteration's conversation.

## The loop

```text
if [autonomy activation] resolves to anything but an engaged autonomous run:
    stop — review mode; the loop never starts

iterations ← 0
fails      ← empty map        # stable task identity → gate-FAIL count this run
skip       ← none             # identity to pass over once (the advance rule)
ineligible ← empty set        # identities refused by [live-state reconciliation] this run

loop:                          # every condition below is evaluated HERE, between
                               # iterations — never mid-task
    (a) if iterations = N:                   stop max-N        # N=0 stops before any iteration
    (d) if [autonomy activation] no longer
        resolves to an engaged run:          stop fail-closed
    candidate ← next-task §1 selection (lowest-numbered unchecked task whose
                dependencies are met, the profile's blocked list excluded),
                skipping `ineligible`, and passing over `skip` when another
                unblocked candidate exists (no other candidate → `skip` is
                re-selected: it re-surfaces as lowest-unblocked)
    (b) if no candidate:                     stop backlog-drained

    run ONE complete next-task cycle for candidate as a fresh [headless run],
        the task ID explicit in the invocation text
    iterations ← iterations + 1              # every started iteration consumes budget,
                                             # whatever its outcome
    outcome ← the cycle's result, read from the run's own return
              (gate PASS + PR ref | gate FAIL + discard | refused | aborted)
    append one run-report line (observe-only; a write failure is
        silent-to-the-run — see "The run report")

    case outcome:
        gate PASS → PR:   skip ← none
        gate FAIL → discard:
            fails[candidate] ← fails[candidate] + 1
            (c) if fails[candidate] = 2:     stop repeated-gate-fail
            skip ← candidate                 # advance to the next unblocked candidate
        refused ([live-state reconciliation] refused the candidate — its live
                 state shows landed or in-flight work):
            ineligible ← ineligible + candidate   # re-selecting would refuse again;
                                                  # the drift is surfaced, per §1
        aborted (a lifecycle or activation check failed closed mid-cycle):
            (d)                              stop fail-closed
```

- **"Same task" is a stable task identity** — the task ID in the profile's format, not a
  positional index — so a discard-then-reselect cycle cannot loop unbounded below max-N:
  the second gate FAIL of one identity stops the run (condition (c)), wherever in the run
  the two FAILs fell.
- **First FAIL advances, second stops.** On a first gate FAIL the iteration itself has
  already discarded its workspace (§8 FAIL→discard, unchanged); the loop then passes over
  that identity in favor of the next unblocked candidate, re-selecting it only when it
  re-surfaces as lowest-unblocked. This grinds on nothing: no third attempt exists.
- **The loop consumes outcomes from the run's return, never from the report.** Stop
  conditions and the advance rule read each iteration's result exactly where §8's
  promote/discard step reads the gate outcome — from the invoked run itself. The run
  report is **write-only** for the loop (see below).

## Stop conditions (the closed set)

Deterministic, and evaluated only **between** iterations — a stop condition never
interrupts a task mid-cycle; a started iteration always runs to its own terminal state
(PR, discard, refusal, or abort) before any condition is consulted:

| # | Condition | Stop meaning |
|---|---|---|
| (a) | `iterations = N` (max-N; N from configuration/invocation, never hardcoded; N=0 → immediate no-op) | budget drained — the run cannot exceed N iterations |
| (b) | no unblocked candidate remains (selection finds nothing startable) | backlog drained — the run must not stop early while eligible work and budget remain |
| (c) | the same task identity fails the §7 gate **twice** in one run | non-convergence — a human reads the two discards; the loop never grinds |
| (d) | any lifecycle or **[autonomy activation]** check fails closed (at the between-iteration re-check, or aborting a cycle) | fail-closed — autonomy's posture is preserved, not retried around |

## Safety invariants (what N iterations must never change)

- **No merge, no base-branch write — across the whole run.** Each iteration terminates at
  a PR via the existing promotion path or at a discard; the falsification obligation that
  an un-gated change cannot reach the base branch extends to the multi-iteration case
  (spec 004 US1.AC4 — the multi-iteration extension of the single-run proof).
- **No new gate semantics.** The roster, round limits, veto authority, and tier floors are
  exactly `gate-loop.md`'s; this spec adds none and the loop cannot override a verdict.
- **No widening of what automation may write.** A loop iteration may write exactly what a
  single-task run may write (reviewer specs, guards, invariants, and the constitution stay
  PR-only — constitution P4).
- **No post-PR comment watching.** The loop never reacts to reviewer comments on the PRs
  it opened — out of scope by spec (spec 004 non-goals); the PRs wait for the owner.

## The run report (observe-only)

Between-iteration state becomes durable as a run report under `telemetry.md`'s law:
**telemetry observes; it never decides.**

- **Shape:** one line per iteration — the task ID, the gate verdict, and the resulting PR
  reference or discard, each field matching that iteration's actual outcome — plus one
  terminal run-summary line carrying the stop condition and `iterations of N`, so a
  **partially completed run is a valid outcome, visible *as partial*** — never mistaken
  for a clean drain, never treated as an error baseline.
- **Channel:** the out-of-repo triage-inbox channel per `telemetry.md`'s storage
  convention — the existing default; no new path convention. The triage **[workflow]**
  surfaces the batch in its snapshot.
- **Write failure is silent-to-the-run:** it never aborts an in-flight iteration and never
  blocks a promotion (the same posture as every emitter under `telemetry.md`).
- **Nothing reads it back.** No gate-outcome, model-tier-assignment, or task-selection
  path reads the run report or the iteration counters (constitution P5); the loop's own
  control flow reads outcomes from each run's return, above. The deterministic fence
  proving this — paired with a control proving the reporting path *does* resolve the
  report — is spec 004 US1.AC5's.

## How an adapter degrades gracefully

- **No [backlog-loop] mechanism** → nothing is lost from the single-task flow: run
  `next-task.md` cycles one at a time (each still fully gated); only the unattended
  chaining is absent.
- **The loop mechanism and its conformance probe are the adapter's** to bind — the live
  proof is one real multi-task unattended run recorded with dated fingerprints, including
  the observed stop condition, in the adapter's probe-results table
  (`conformance-probes.md` pattern; spec 004 US1.AC7).

