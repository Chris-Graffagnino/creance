# gate-loop — the §7 pre-PR gate expressed as code (runtime-neutral)

The pseudocode spec for an **[orchestrated run]** of the `next-task.md` §7 gate. Where the
active adapter provides the **[orchestrated run]** role, the loop below executes as code;
where it does not, §7's prose procedure — unchanged — is the documented degradation path.
The two are equivalent in *what* happens; the code form moves the bookkeeping out of
executor discipline: an orchestrated loop **cannot forget** to re-dispatch a failing
reviewer, **cannot** report the gate passed with a FAIL outstanding, and **cannot** lose a
verdict.

## What the loop owns (and what stays with the dispatcher)

The loop owns §7 steps 2, 4 and 5: the parallel reviewer fan-out, the fix-and-re-dispatch
cycle, the non-convergence stop, and verbatim verdict retention. It does NOT own:

- §7 step 1 (the maker's self-review) — run it before invoking the loop;
- §7 step 3 (the **[code-review pass]** / **[security-review pass]**) — run it alongside;
- §8 (attaching the verdicts to the PR) — the loop *returns* every verdict; posting them
  is the dispatcher's job, exactly as today;
- appending the telemetry record — the loop *builds* the `gate-run` payload
  (`telemetry.md`) and returns it; **the dispatcher appends it** (see "Telemetry" below).

The loop runs against the task branch's **committed** diff versus the base branch — the
reviewers see only commits, so commit before invoking it.

## Inputs (explicit, per the explicit-context rule)

The dispatcher passes every value the run must honor in the invocation itself:

- **task-id** — required; the acceptance reviewer cannot grade without it.
- **strong-model / cheap-model** — the **[strong tier]** and **[cheap tier]** rows,
  resolved by the **dispatcher** through the adapter's model table. The loop itself never
  names a model and never reads the table — the one-line-model-swap property survives
  because resolution happens at dispatch time, outside this spec.
- **dispatch-contract** — true when the diff touches a provider interface, monetization,
  or the data model (§7's contract-reviewer rule); default false.
- **max-fix-rounds** — the non-convergence bound; default 2 (§7's "two fix-and-re-dispatch
  rounds").
- **apply-fixes** — default true; false yields a single report-only fan-out (no fix step),
  for a dispatcher that wants to apply fixes itself between invocations.

A missing required input is a hard error before any dispatch — never guessed, never
inherited from ambient state.

## The loop

```text
reviewers ← [ acceptance(cheap-model, task-id), constitution(strong-model) ]
if dispatch-contract:  reviewers ← reviewers + [ contract(cheap-model) ]

verdicts ← empty map            # reviewer → its LATEST verdict, verbatim
pending  ← reviewers
fix-rounds-used ← 0

loop:
    results ← dispatch every reviewer in pending IN PARALLEL — each one per its spec
              under reviewers/, on its resolved model, returning the structured verdict
              { verdict: PASS | JUSTIFY | FAIL,  report: <its full report, verbatim> }

    record this dispatch round into the telemetry payload (see "Telemetry"):
        one { auditor, tier, verdict } entry per dispatched reviewer — verdict
        NO-RESULT for a reviewer that returned nothing; every FAIL report (and the
        literal string NO-RESULT for a no-result dispatch) kept verbatim in
        fail_reports, keyed by auditor and round

    for each reviewer in pending that returned a result:
        verdicts[reviewer] ← that result          # overwrite: the latest verdict wins

    failing ← every reviewer in pending whose verdict is FAIL,
              plus every reviewer in pending that returned NO result
              # a missing verdict is never a pass — it stays failing

    if failing is empty:
        return { gate: PASS, verdicts, telemetry(outcome: pass),
                 justified: reviewers whose latest verdict is JUSTIFY }
                 # JUSTIFY clears the gate only with the deviation documented in the PR body

    if not apply-fixes, or fix-rounds-used = max-fix-rounds:
        return { gate: FAIL, failing, verdicts,
                 telemetry(outcome: non-convergence when the fix budget ran out,
                           else fail) }
                 # non-convergence: stop and surface the disagreement in the PR body —
                 # the loop never overrides a reviewer (maker is not the checker)

    findings ← the FAIL reports among failing      # no-result reviewers have no findings
    if findings is not empty:
        fix(findings)                              # see "The fix step"

    fix-rounds-used ← fix-rounds-used + 1
    pending ← failing                              # re-dispatch ONLY the failures
```

## The fix step

`fix(findings)` is performed by a **maker-role executor — never a reviewer** (the
maker≠checker split is preserved because the fixer holds no verdict authority and the
reviewers hold no edit capability). It receives the blocking verdict reports verbatim and:

- applies the **minimal scoped change** addressing each blocking finding (§5 discipline —
  nothing speculative), with the relevant tests run;
- **commits** the fix on the task branch, staging specific files — the re-dispatched
  reviewers audit the committed diff, so an uncommitted fix is invisible to them;
- never touches the base branch;
- when it judges a finding wrong or out of scope, it leaves the code unchanged for that
  finding and says why — it must not silently drop a finding, and it must not override
  the reviewer; disagreement surfaces through the non-convergence stop.

In an interactive degradation (no [orchestrated run]), the maker session itself is this
executor, exactly as §7's prose describes.

## Verdict capture

Each dispatch returns a **structured verdict**: the overall `verdict` plus the reviewer's
full report **verbatim** in `report` — the same item-by-item table its spec defines. The
`report` string is what §8 posts to the PR, unchanged. The map keeps every dispatched
reviewer's **latest** verdict, so the gate's outcome and its evidence travel together in
the return value; the outcome can never live only in a conversation.

## Telemetry (one record per gate run — built by the loop, appended by the dispatcher)

Every return path carries a telemetry-ready `gate-run` payload per `telemetry.md`:
`task_id`, the per-round `{ auditor, tier, verdict }` history, `fix_rounds_used`, the
`outcome` (`pass` / `fail` / `non-convergence`), and `fail_reports` verbatim. The payload
names **tiers, never models** — the loop never sees past its dispatch parameters, and the
model values are never copied into the record.

The split is deliberate: the loop **builds**, the **dispatcher appends** — stamping the
envelope (`timestamp`, `repo`), resolving the stream location from the profile
(`telemetry.md` → "Storage convention", parent directory created if missing), and
appending one JSONL line **after the gate's outcome is already returned**. Ordering is
the enforcement of `telemetry.md`'s law: a failed append happens downstream of the
outcome, so it structurally cannot block, fail, or alter the gate — the dispatcher
treats a write failure as silent-to-the-gate (note it, proceed exactly as if it had
succeeded). One record per completed gate invocation, whatever the outcome.

## Constraints inherited (not relaxed by orchestration)

- Every dispatched reviewer still satisfies every **[reviewer]** constraint: separate
  context, no file-mutation capability, adversarial posture per its spec, parallel
  dispatch.
- The constitution reviewer's **[strong tier]** floor applies to its dispatch parameter —
  strong-model is mandatory input precisely so the floor never depends on inherited
  session state.
- The per-stage tier map in `next-task.md` is unchanged: acceptance + contract reviewers
  on the **[cheap tier]**, the fix step at the task's own tier.
- A `gate: FAIL` return is blocking, exactly as §7.4: the dispatcher surfaces it; it never
  re-grades or overrides the verdicts.
