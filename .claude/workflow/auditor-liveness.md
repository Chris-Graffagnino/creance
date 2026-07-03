# auditor-liveness — keep the judgment auditors proven live (runtime-neutral)

Constitution **P2** ("no silently dead guards") requires enforcement machinery to be
**proven live, not assumed live**. Today that guarantee is delivered **asymmetrically**:

- The deterministic **[guard]** is proven live on **every gate run** — the adapter's
  `guard.test.sh` (with its matcher-wiring assertion) runs in the required check, so a guard
  that stopped firing fails the build that day.
- The judgment **[reviewer]**s are proven live **only once per adapter** — the `P-RV`
  conformance probe (`conformance-probes.md`) dispatches a reviewer against a single planted
  violation and expects a `FAIL` with `file:line` evidence, but it runs only "before first
  relying on an adapter… re-probe only the roles whose mechanism changed".

So when a reviewer **spec** is edited — a retrospective lands a hunt-rule tightening, a
refactor reorganizes a spec — nothing re-confirms the auditor **still catches everything it
caught before**. P2 plainly covers the auditors (they are enforcement machinery); only the
guard gets continuous liveness. This workflow closes that gap: it **promotes `P-RV` from a
one-time, single-violation adoption probe into a standing regression corpus** and re-runs it
on every reviewer-spec change and on a schedule.

> Runtime-neutral: roles in **[brackets]** are defined in `workflow/README.md` → "The
> binding contract". Project specifics — the constitution path, the invariant checklist, the
> reviewer roster — come from `.claude/PROJECT.md`. Below, *the profile* means that file.
> This workflow **composes existing roles only** — the read-only **[reviewer]** fan-out the
> gate already uses, plus observe-only surfacing — and (exactly like the retrospective)
> introduces **no new binding-contract row**.

## Relationship to `P-RV` and the guard's deterministic test (the discipline it generalizes)

| | Proves | Cadence | Shape |
|---|---|---|---|
| `guard.test.sh` (the **[guard]**'s regression test) | the deterministic guard still fires | every gate run (required check) | deterministic — a hard gate |
| `P-RV` (the **[reviewer]** conformance probe) | the reviewer **binding** works on this adapter | once at adoption / on a mechanism swap | model-driven — a one-shot probe |
| **this corpus** | each auditor still **discriminates** known-good from known-bad under its current spec | on every reviewer-spec change **+ ≥ weekly** | model-driven — a standing **report-only** run |

The corpus is the auditor analog of `guard.test.sh`: it generalizes P2's "proven live, not
assumed live" discipline **from the deterministic guard to the model-driven auditors**.
Because the auditors are nondeterministic, the corpus **cannot be a deterministic hard merge
gate** — a flaky verdict would block honest work. So unlike `guard.test.sh` it is a
**report-only** run surfaced to the owner (below), never a gate. `P-RV` is its **origin**:
the corpus is `P-RV` made standing, broadened from one planted violation to a matched
known-bad/known-good pair **per auditor**, and re-run continuously instead of once.

## The corpus (what must exist)

The fixtures live in `reviewers/auditor-liveness-corpus.md`. The contract that file declares,
and that the profile's deterministic backstop enforces:

- **At least one expected-`FAIL` and one expected-`PASS` fixture per auditor.** The FAIL
  fixture proves the auditor still catches its dimension's violation; the PASS fixture proves
  it does not FAIL a clean diff. Only the matched pair proves the auditor *discriminates*
  rather than being stuck on one verdict — the known-good/known-bad calibration the guard's
  regression test already uses.
- **Each fixture declares** its target auditor, its expected verdict, the violation it
  plants, and — for a FAIL — the **evidence anchor** the catch must name, so "caught it for
  the right reason" is distinguishable from an unrelated FAIL.
- **Seeded from known escapes** — the evasion-register exhibits and the retrospective's
  incidents (below) — with one exception: a **newly added reviewer with no logged escape
  yet** may bootstrap its first FAIL fixture from the case its spec mandates, until a real
  escape is logged.

## The run (read-only, report-only — composes existing roles)

For each fixture, **the same dispatch the §7 gate would make**, against the materialized
plant, **read-only**:

1. Materialize the fixture's planted scenario as a throwaway change the auditor can grade
   (the worktree-materialization the retrospective already uses for a historical tree, and
   the planted-violation dispatch `P-RV` / `P-EV` already use) — never a checked-in patch
   that would rot. A run leaves the repo as it found it.
2. Dispatch the fixture's target **[reviewer]** against the plant, **read-only and
   report-only** — a single fan-out, **no fix step and no re-dispatch loop** (unlike the
   gate's converge-to-PASS cycle; the corpus *measures* an auditor, it does not drive a task
   to PASS). The constitution and spec-quality **[reviewers]** are dispatched
   **at-or-above the [strong tier]** floor — the same floor the gate and the **[guard]**
   enforce, never below.
3. Compare the returned verdict to the fixture's expected verdict (and, for a FAIL, that the
   evidence anchor was named). Equal ⇒ the fixture is `PASS` (the auditor is live on it);
   unequal ⇒ `MISMATCH` (the auditor may have gone blind — or over-eager — on that
   dimension), which the report surfaces for the owner to investigate.

The run records its outcome — a dated record carrying the **reviewer-spec fingerprint** in
effect (below) and each fixture's `PASS`/`MISMATCH` — to an **observe-only** channel (the
adapter supplies the concrete record location and the fingerprint recipe). That record is the
baseline the re-run policy and the owner-facing freshness surfacing read.

## Re-run policy (on reviewer-spec change + on a named schedule)

The corpus re-runs on **both** triggers:

- **On every reviewer-spec change** — detected **deterministically** (constitution **P3**:
  prefer a deterministic check to a remembered intention). A **reviewer-spec fingerprint** —
  a content hash over the auditor specs (`reviewers/*` — the specs the auditors load and the
  evasion register they consult) — is recorded with each corpus run. The baseline is the last
  run that exercised the **whole corpus**: when the **current** fingerprint differs from the
  **last recorded full-corpus run's**, the corpus is **stale** — a reviewer spec changed since
  every auditor was last confirmed live, so a re-run is due. This mismatch is a
  **definite flag, not a heuristic** — the same machinery the guard-fingerprint
  staleness check (`triage.md` → PROBES-STALE) uses, pointed at the reviewer specs. A
  **partial run** that exercises only a subset of fixtures (e.g. re-checking a single auditor)
  is reported but **does not refresh the baseline or clear staleness** — a subset run has not
  re-confirmed every auditor, so letting it stand in for a full re-confirmation would falsely
  report the corpus current. The concrete hash recipe, the record location, and how a partial
  run is distinguished from a full one are the adapter's to supply.
- **On a schedule — at least weekly.** A reviewer spec can pass review yet drift in
  behaviour as the model behind it changes; only a time-based re-run catches that. The
  **minimum cadence is weekly** — named so "on a schedule" cannot be satisfied by a one-off
  run. The run is invoked non-interactively (a **[headless run]**) on the same scheduler
  substrate the read-only heartbeat uses; the schedule is a documented mechanism, not an
  optional suggestion.

The deterministic staleness flag surfaces through the read-only heartbeat (`triage.md`), so
a stale corpus is visible in days, alongside the guard's own freshness checks — never
discovered only at the next adapter port.

## Observe-only (constitution P5 — the hard boundary)

A fixture outcome (`PASS` / `MISMATCH`) and the staleness flag are **evaluation records**:
append-only observations. They **surface to the owner read-only and never feed a gate
outcome, a model-tier assignment, or any gate semantic** (round limits, veto authority, tier
floors). The corpus measures the auditors; being measured grants it no authority over them.
A `MISMATCH` never auto-edits a spec, never re-dispatches the gate, never downgrades or
escalates a tier — it is a signal a human acts on through the ordinary task flow. This is the
constitution's **telemetry-observes-never-decides** principle (P5) applied to auditor
liveness, and it is the same fence the profile's existing telemetry/evaluation invariant
already draws: a measurement channel that gains control authority has violated P5, whatever
the convenience.

## Seeding & growth (new fixtures land via PR — never silently)

The corpus is **seeded** from violations an auditor has already been shown to own: the
evasion-register exhibits (`reviewers/evasion-register.md`) and the retrospective's own
incidents. A **newly added reviewer is the one exception**: with no logged escape yet, its
first FAIL fixture is bootstrap-seeded from the case its spec mandates, and is superseded by a
real exhibit once the first such escape reaches the register through the retrospective. Every
**WOULD-HAVE-CAUGHT** and **INCONSISTENT-CATCH** escape the retrospective classifies
(`retrospective.md` → §4) is, by construction, a violation that *should* be a standing
fixture — a known-bad the auditor must keep catching.

Adding or changing a fixture is a change to verification machinery, so it travels the
**standard issue → branch → §7 gate → PR flow** like any rule change, and the owner merges
to apply — never an automatic or silent write (constitution **P4**: the harness never
modifies its own verification machinery silently). The corpus run itself only *reads* the
fixtures and *appends* an observe-only outcome record; it proposes fixture changes the way
the retrospective proposes a hunt-rule tightening — as a reviewed PR, never in place.
