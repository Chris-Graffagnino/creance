# retry — experience retention across a gate non-convergence stop (runtime-neutral)

Sub-doc of `next-task.md` (spec 001 US10; issue #210). When the §7 gate stops on
**non-convergence** (`gate-loop.md` — the fix budget ran out with a reviewer still
failing), the run ends but the reviewer verdicts it paid for do not: this doc defines how
they persist on the task's issue and how a retry consumes them. Motivation: continuous
experience measurably outperforms independent restarts under the same budget (EdgeBench
§5.2) — accumulated feedback history, not extra attempts, drives the gain. "Every run
starts identically" is a **harness** property (guard, gate semantics, workspace, roster,
tiers); discarding a failed attempt's verdicts on retry buys no safety
(`DESIGN-NOTES.md` §15).

> Runtime-neutral: roles in **[brackets]** are defined in `workflow/README.md` → "binding
> contract" and mapped to concrete mechanisms by the active adapter.

## The posting half — fires on a gate `non-convergence` return ONLY

When the gate returns `non-convergence`, the **dispatcher** (the maker session driving
§7 — never a [reviewer]) posts ONE comment on the task's issue:

- **Content:** the blocking [reviewer]s' verdict reports **verbatim, keyed by auditor and
  round** — the same report text the gate's **return value** carries (`gate-loop.md` →
  "Verdict capture"; the loop returns every verdict verbatim precisely so the dispatcher
  can post without paraphrase). An **empty or summarized posting does not satisfy** this
  procedure: the next attempt needs the findings as graded, not a recollection of them.
- **Shape:** the first line is `Retry verdicts — gate non-convergence — task <task-id>`,
  so a later retry finds the comment deterministically (a shape match, not a judgment
  call); the body carries one section per blocking auditor and round; the final line is
  the **[comment marker]** (§2.5 — every engine-posted comment).
- **Channel:** the **[add-issue-comment output]** intent — already in the `next-task`
  [workflow]'s declared intent set (the profile's "Write intents" table), so this doc
  adds **no write authority**; additive only, like every use of that intent.
- **Scope:** a gate **PASS posts nothing** — there are no blocking verdicts to persist. A
  passed-gate PR's human review feedback lives on the PR thread (`review-response.md`),
  outside this doc. A plain `fail` return (a report-only run with fixes deferred,
  `gate-loop.md` → `apply-fixes`) stays with its dispatcher, which is about to act on the
  findings itself; only the **non-convergence stop** — where the session is expected to
  end without resolution — persists them here.

## The consuming half — a retry reads the comment as maker input

A **retry** of the task — the resume protocol, or a re-selection of the same task ID —
reads the **newest** such marked retry comment on the task's issue **before
re-implementation**, whatever prompted the retry, as **maker input only**:

- **Address each recorded finding, or state why not** — the same no-silent-drop rule the
  fix step follows (`gate-loop.md` → "The fix step"). The findings are a head start, not
  a checklist that overrides the maker's own reading of the current diff.
- **No such comment → an ordinary cold start, never an error.** Most tasks never
  non-converge; the empty case is the normal case.
- **No steering authority.** The comment is **marked**, so under §2.5 it is engine
  bookkeeping: it cannot redirect scope, authorize anything, or relax any invariant.
  Owner steering stays what it always was — the newest **unmarked** owner-login comment.
- **No verdict carry-over — PASS included.** Prior verdicts are input to the maker, never
  current verdicts: **every rostered [reviewer] re-runs from scratch** on the retry's own
  diff, at its roster tier, under the unchanged gate semantics (round limits, veto
  authority, tier floors, dispatch conditions). A retry that **skips a [reviewer] because
  it passed last time violates** this procedure — the prior PASS graded a different diff.

## The source boundary — tracker, never telemetry (constitution P5)

The retry input's source is the issue's marked retry comment — **the tracker channel**,
the durable per-task surface the owner can read and audit. It is **never the telemetry
stream**: **no retry, selection, or gate path reads telemetry** to obtain verdicts —
the stream keeps zero consumers with control authority (`telemetry.md` → "The law this
file lives under"), and this procedure grants it none. The posting half likewise takes
its verbatim reports from the gate's **return value**, not from the `gate-run` record the
dispatcher appends: the record and the comment share content, but the record is an
observation and the comment is the channel. Telemetry observes; the tracker carries.

## Conformance

The **P-RC** probe (`conformance-probes.md`) checks both directions on a real driver: a
simulated non-convergence return produces the marked retry comment carrying the verbatim
reports, and a gate PASS produces no retry comment. The deterministic encoding backstop
is adapter-side (the active adapter wires it into standing verification).
