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
- §7 step 3 (the **[code-review pass]** / **[security-review pass]**, and the advisory
  **[craft-review pass]** where the adapter provides one) — run them alongside;
- §8 (attaching the verdicts to the PR) — the loop *returns* every verdict; posting them
  is the dispatcher's job, exactly as today;
- appending the telemetry record — the loop *builds* the `gate-run` payload
  (`telemetry.md`) and returns it; **the dispatcher appends it** (see "Telemetry" below);
- **restoring the shared-tree task branch after the run** — in a binding where the reviewer holds
  a (sandboxed) shell for inspection, it is read-only only as to *file mutation*: it can still run
  `git`, so a stray `git checkout`/`git switch` in an auditor step can relocate the maker's HEAD off
  the task branch in the **shared** working tree (review mode runs the auditors there, not in an
  isolated worktree). (A binding that instead grants the reviewer **no shell** and **provides** it the
  committed diff has no such reviewer-drift vector — read-only by construction — but a shell-holding
  fixer or diff helper remains in the loop, so the restore is retained regardless.) The dispatcher
  snapshots the task branch it cut and **restores it after the run, on every outcome** — a
  deterministic backstop, run *before* it reads the introducing-commit for telemetry so a drifted HEAD
  can neither strand the maker nor poison the record. The **loop itself** closes the same gap *within*
  the run — it restores the shared tree onto the task branch **before each fix-and-re-dispatch step**
  (review mode; see "The loop"), so a fix round can neither commit onto nor re-audit a HEAD a shell
  step drifted. That in-loop restore is the loop's, the after-run restore is the dispatcher's, and
  together they cover every path. (Under an engaged isolated autonomous run the work lives in
  the ephemeral **[isolated workspace]** governed by the lifecycle, so this shared-tree restore
  is review-mode only.)

The loop runs against the task branch's **committed** diff versus the base branch — the
reviewers see only commits, so commit before invoking it. Under an engaged isolated autonomous
run (`next-task.md` §0.5), that committed diff is read from the **[isolated workspace]** named
by the *workspace location* input below; the loop is location-agnostic — it audits whatever
committed diff that input points at and never infers the location.

## Inputs (explicit, per the explicit-context rule)

The dispatcher passes every value the run must honor in the invocation itself:

- **task-id** — required; the acceptance reviewer cannot grade without it.
- **strong-model / cheap-model** — the **[strong tier]** and **[cheap tier]** rows,
  resolved by the **dispatcher** through the adapter's model table. The loop itself never
  names a model and never reads the table — the one-line-model-swap property survives
  because resolution happens at dispatch time, outside this spec.
- **dispatch-contract** — true when the diff touches a provider interface, monetization,
  or the data model (§7's contract-reviewer rule); default false.
- **dispatch-spec** — true when the diff adds, edits, or renames a `specs/*/spec.md` (git
  status `A`/`M`/`R` — the closed set that leaves spec content to grade; a pure deletion `D`
  has no spec to review and does not fire); default false.
- **max-fix-rounds** — the non-convergence bound; default 2 (§7's "two fix-and-re-dispatch
  rounds").
- **apply-fixes** — default true; false yields a single report-only fan-out (no fix step),
  for a dispatcher that wants to apply fixes itself between invocations.
- **audited ref** — **required**: the explicit ref the run audits, never an inferred working
  directory. A dispatch that read an inferred HEAD could grade a tree a concurrent session
  relocated between dispatch and fan-out — the wrong-diff / vacuity class this gate exists to
  prevent — so exactly one of these two, keyed to the mode, is always given:
  - **workspace location** — under an engaged isolated autonomous run, the location of the
    **[isolated workspace]** whose committed diff the reviewers (and the fix step) audit. It is
    immune to a shared-tree switch by construction (a dedicated checkout).
  - **task-branch** — in review mode, the branch the dispatcher cut. It is the explicit ref the
    diff-obtaining step **verifies the shared tree's HEAD against before every dispatch** (see
    "The loop") — a concurrent session's branch switch fails the round loud instead of grading
    the wrong diff — AND the branch the **fix step** restores the shared tree onto before applying
    a fix or re-dispatching (a parallel shell-holding step in that shared tree can leave HEAD
    relocated off it; see "The fix step").
  Both are passed **explicitly** per the explicit-context rule, never inferred from a working
  directory or env; a run that supplies **neither** is a hard error before any dispatch.

A missing required input is a hard error before any dispatch — never guessed, never
inherited from ambient state.

**Dispatch context — the reviewer [roles] must resolve.** Beyond the values above, the
**[orchestrated run]** must be invoked in a context where each rostered reviewer **[role]** it
will dispatch can actually be resolved. A dispatch that **cannot resolve** a reviewer **[role]**
**fails fast** — aborting **before any reviewer dispatch**, consuming **zero fix rounds**, with a
diagnostic naming the unresolvable **[role]**(s) — rather than fanning out to no-result and
burning the whole `max-fix-rounds` budget grading nothing. (A no-result fan-out still refuses to
pass — a missing verdict is never a pass — but it wastes the entire budget to reach the same
FAIL; a run that can resolve none of its graders should say so once, loudly, not three times,
silently.) **How** a **[role]** resolves and **what** breaks resolution is **binding-specific**
(the active adapter's concern, named in its layer); the neutral contract is only that an
unresolvable **[role]** is a fast, loud, zero-round failure — never a vacuous run.

## The reviewer roster (single source of truth)

The gate's reviewer set — **membership, tier, and dispatch-condition** — is declared once,
here. Each consumer derives the projection it needs from this table: the loop below iterates
it; `next-task.md` §7 names reviewer paths and conditions while delegating tiers here; the
**[orchestrated run]** adapter encodes membership, tiers, and conditional guards; and an
adapter's manual-fallback binding may enumerate membership only. CI-wired structural checks
pin those declared projections to an independent canonical set, while executable adapter
tests assert the exact runtime dispatch set under each condition. Adding or removing a
reviewer therefore requires an intentional roster change plus its affected derived
consumers and tests, rather than an unchecked hand-sync.

| Reviewer spec | Tier | Dispatch condition |
|---|---|---|
| `reviewers/spec-auditor.md` (acceptance) | cheap | `always` |
| `reviewers/constitution-auditor.md` | strong | `always` |
| `reviewers/contract-auditor.md` | cheap | `dispatch-contract` |
| `reviewers/spec-quality-auditor.md` | strong | `dispatch-spec` |

- **Tier** is a capability **[tier]**, resolved to a concrete model by the adapter's table at
  dispatch time — this table never names a model. The constitution reviewer's `strong` and the
  spec-quality reviewer's `strong` are **[strong tier]** floors and never downgrade — the spec
  is the cheapest place to lose a project, so the one check that grades spec content is pinned
  at-or-above strong exactly as the constitution check is.
- **Dispatch condition** is exactly one of three **deterministic** values: `always`,
  `dispatch-contract` (true when the diff touches a provider interface, monetization, or the
  data model — §7's contract-reviewer rule), or `dispatch-spec` (true when the diff adds, edits,
  or renames a `specs/*/spec.md` — git status `A`/`M`/`R`; a pure deletion `D` does not fire).
  No model-judgment condition (e.g. "touches behavioral code") may be added: that would put
  model judgment on the load-bearing path.

## The loop

```text
reviewers ← every roster row whose dispatch-condition holds for this run
            (an `always` row unconditionally; a `dispatch-contract` row iff dispatch-contract
            is true; a `dispatch-spec` row iff dispatch-spec is true), each dispatched on its
            tier's resolved model — the acceptance row also receives task-id

verdicts ← empty map            # reviewer → its LATEST verdict, verbatim
pending  ← reviewers
fix-rounds-used ← 0

loop:
    obtain the committed diff for THIS round from the audited ref. In REVIEW mode this FIRST
        verifies the shared tree's HEAD still matches the task-branch ref — atomically, as part of
        producing the diff — and on MISMATCH ABORTS the round loud: gate FAIL, no reviewer
        dispatched, the mismatch recorded in the telemetry fail_reports keyed to the diff-obtaining
        step (a concurrent session relocated the shared checkout between dispatch and fan-out;
        grading its diff would be wrong/vacuous). This verification runs at dispatch AND at each
        re-dispatch. (Autonomous mode reads the isolated workspace, immune by construction — no
        HEAD check applies; the fail-closed diff contract still holds. See "Constraints inherited".)

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

    if review mode and task-branch is given:       # past the PASS/stop returns: a fix and/or
        restore the shared tree onto task-branch   #   re-dispatch is coming. A parallel auditor
                                                   #   may have drifted HEAD; restore it FIRST so
                                                   #   neither the fix (its commit would miss the
                                                   #   branch) nor the re-dispatch (it would audit
                                                   #   the wrong HEAD) runs against a drifted tree.
                                                   #   Same deterministic, fail-loud restore the
                                                   #   dispatcher runs after the run — a no-op when
                                                   #   nothing drifted. (Isolated run → the work is
                                                   #   in the workspace; no shared tree, so skip.)

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
  reviewers audit the committed diff, so an uncommitted fix is invisible to them (under an
  isolated run this commit lands inside the **[isolated workspace]** the reviewers read, so
  the fix and its re-audit stay in the same place; in review mode the loop restored the shared
  tree onto the task branch first — see "The loop" — so the commit lands on the task branch even
  if a parallel auditor had drifted HEAD);
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
envelope (`timestamp`, `repo`) and the introducing-`commit` ref (the head of the audited
diff; `telemetry.md` → "The `gate-run` record"), all of which need a clock or filesystem
the loop's runtime lacks. The dispatcher reads the `commit` **after the run returns**, not
before invoking the loop: the fix step commits onto the task branch, so the head at append
time is the head of the diff the gate's final round actually audited. It resolves the
stream location from the profile (`telemetry.md` → "Storage convention", parent directory
created if missing), and appends one JSONL line **after the gate's outcome is already
returned**. Ordering is the enforcement of `telemetry.md`'s law: a failed append happens
downstream of the
outcome, so it structurally cannot block, fail, or alter the gate — the dispatcher
treats a write failure as silent-to-the-gate (note it, proceed exactly as if it had
succeeded). One record per completed gate invocation, whatever the outcome.

## Constraints inherited (not relaxed by orchestration)

- Every dispatched reviewer still satisfies every **[reviewer]** constraint: separate
  context, no file-mutation capability, adversarial posture per its spec, parallel
  dispatch.
- How a reviewer obtains the committed diff it audits is **binding-specific**. A binding may grant
  the reviewer a **read-only shell** — then it reads base state by **non-switching** means only
  (`git diff main..HEAD`, `git show main:<path>`, or a throwaway `git worktree`, **each scoped to the
  tree it audits**: under an isolated run the **[isolated workspace]** via an explicit
  `git -C <workspace>`, in review mode the shared tree) and never a `git checkout`/`git switch` of
  that tree, since in review mode it is the maker's **shared** tree and switching it would relocate
  the maker's HEAD. (A bare, un-scoped read under an isolated run would point a session-CWD reviewer
  at the shared tree instead of the workspace and pass vacuously — the T612 trap.) Or a binding may
  grant the reviewer **no shell** and **provide** the committed diff in the dispatch prompt — then the
  reviewer runs no `git` at all and has no branch-switch vector (read-only **by construction**). A
  providing binding must not trust its diff-obtaining step blindly: what that step returns is what
  the reviewers audit, so the provided output must satisfy a **checked, fail-closed contract** — a
  completion marker emitted only when the diff command succeeded, and non-empty diff-shaped content
  preceding it. Anything else (no output, a failure message, a summary, a truncated patch, an empty
  diff) **aborts the round as unverified** — gate FAIL, no reviewer dispatched, the classification
  recorded in the telemetry `fail_reports` keyed to the diff-providing step and round — rather than
  being embedded, so the gate can never pass on reviewers that audited something other than the real
  committed diff (the T612 vacuous-pass class, closed structurally rather than by asking a reviewer
  to notice). When the audited tree is the **shared** working tree (review mode), that same
  fail-closed diff-obtaining step **also verifies the shared tree's HEAD still matches the
  task-branch ref**, atomically as part of producing the diff, **at dispatch and at each
  re-dispatch**, and classifies a **mismatch** as unverified the same way — a concurrent session
  relocated the shared checkout between dispatch and fan-out, so grading its diff would be
  wrong/vacuous. This is the review-mode analogue of the isolated run's explicit `git -C <workspace>`:
  an explicit, verified ref in place of an inferred HEAD, so neither mode audits a tree whose
  identity it has not pinned. The
  non-switching rule is the prevention layer for the shell-holding case; the deterministic backstop —
  the restore, applied by the loop before each fix/re-dispatch step (review mode) and by the dispatcher
  after the run — heals a drifted HEAD on every path in both cases, since a shell-holding fixer or diff
  helper remains in the loop regardless.
- The constitution reviewer's **[strong tier]** floor applies to its dispatch parameter —
  strong-model is mandatory input precisely so the floor never depends on inherited
  session state.
- The per-stage tier map in `next-task.md` is unchanged: acceptance + contract reviewers
  on the **[cheap tier]**, the fix step at the task's own tier.
- A `gate: FAIL` return is blocking, exactly as §7.4: the dispatcher surfaces it; it never
  re-grades or overrides the verdicts.
