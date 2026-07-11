## 7. Pre-PR gate (required) — maker is not the checker; loop until PASS
You wrote this code, so you are the worst judge of it. The gate is a **loop, not a
checkpoint**: dispatch the reviewers, fix what they find, re-dispatch, and repeat — the gate
is passed only when **every dispatched reviewer returns PASS** (or JUSTIFY with the deviation
documented). The **rubric is fixed and checkable**: the task's `US#` acceptance criteria in
the spec (scoped to the criteria this task *owns* when the story spans several tasks — the
acceptance reviewer's scoping rule resolves ownership from the tasks file) plus the
profile's invariant checklist. Reviewers grade against that rubric, not against taste.

**Where the adapter provides an [orchestrated run]**, steps 2, 4 and 5 execute as code per
`workflow/gate-loop.md` — commit first (the loop audits the committed diff) and pass the
dispatch parameters that spec lists. Steps 1 and 3 stay with you either way. Without that
role, the numbered prose below is the procedure, exactly as written (the documented
degradation path).

**Gate-in-place under an engaged isolated autonomous run (§0.5).** When the run is isolated,
the diff the **[reviewer]**s grade — and the diff the fix step commits onto — is the
**[isolated workspace]**'s committed diff against the base branch, *not* the main working
tree's. The workspace location is supplied to the gate **explicitly** (the explicit-context
rule: never inferred from a working directory or env), so the reviewers audit the isolated
work even when they run from elsewhere. Review mode is unchanged: the gate reads the main
working tree exactly as before.

**Review-mode ref check.** Supply the task branch as the **explicit audited ref** and verify
the shared-tree HEAD matches it before every dispatch and re-dispatch; a mismatch must
**fail loud** before any reviewer grades the diff.
1. Self-review `git diff main..HEAD` — a quick sanity pass to catch the obvious before
   spending reviewer runs. It carries no verification authority on its own.
2. Dispatch **separate [reviewer]s** (their own context, adversarial posture, no edit
   tools), in parallel; they cannot edit, only report. **Membership, tier, and dispatch
   condition come from the reviewer roster** (`gate-loop.md` → "The reviewer roster") — the
   single source of truth; the bullets below add only the per-reviewer prose the roster
   can't carry (what each returns, and the acceptance reviewer's task-id):
   - The **acceptance [reviewer]** (`workflow/reviewers/spec-auditor.md`) — **always**, and
     pass it the task ID. It returns PASS/FAIL against the `US#` acceptance criteria
     (implementation AND encoding tests, criterion by criterion).
   - The **constitution [reviewer]** (`workflow/reviewers/constitution-auditor.md`) —
     **always**. It returns PASS/JUSTIFY/FAIL against the constitution + invariant checklist.
   - The **contract [reviewer]** (`workflow/reviewers/contract-auditor.md`) — only on the
     roster's `dispatch-contract` condition: when the change touches a provider interface,
     monetization, or the data model.
   - The **spec-quality [reviewer]** (`workflow/reviewers/spec-quality-auditor.md`) — only on
     the roster's `dispatch-spec` condition: when the diff adds, edits, or renames a
     `specs/*/spec.md` (git status `A`/`M`/`R`; a pure deletion `D` does not fire). It returns
     PASS/FAIL against the spec-content quality rubric, dispatched at the **[strong tier]**
     floor (the spec is the cheapest place to lose a project).
3. Run the **profile's review-pass set** — the skill-backed advisory passes declared in the
   profile (its "Review passes" list), each a binding-contract **[role]** — selecting those
   whose `applies-to` includes the gate (`gate`/`both`) and whose `condition` holds (a
   `sensitive-diff` pass runs only when the change touches the security-sensitive surface the
   review standard defines — the profile's privacy / location / payment invariants). These
   passes are **advisory** and run alongside the roster **[reviewer]**s — none is a roster
   reviewer, so none gates by PASS/FAIL; surface their findings in the PR body (§8), triaged
   as blocking unless documented. An enabled pass whose backing mechanism is absent degrades
   per the review standard → "How an adapter degrades gracefully" (named loudly in the PR,
   never silently dropped); a disabled pass produces no output.
4. Any reviewer **FAIL** is blocking: fix it and **re-dispatch that reviewer** until it
   passes. Do not mark the gate passed by overriding a reviewer yourself — that collapses
   the maker/checker split. Treat other material findings as blocking unless documented as
   false-positive/out-of-scope. If the loop is not converging (the same item still FAILs
   after two fix-and-re-dispatch rounds), stop and surface the disagreement in the PR body
   instead of grinding.
5. **Keep the verdicts.** Save each dispatched reviewer's final verdict report — the
   item-by-item table from its last (PASS or JUSTIFY) run — verbatim. §8 attaches them to
   the PR; the gate's outcome must not live only in this conversation. A reviewer that
   **FAILed then cleared** (to PASS *or* JUSTIFY) after a fix contributes only its latest
   report here; its intermediate FAIL report is retained verbatim in the gate-run record's
   `fail_reports` (`telemetry.md`), which is the source §8's risk-ranked digest cites for
   near-misses.

Next: [§8 Prepare the PR body](08-pr-body.md)
