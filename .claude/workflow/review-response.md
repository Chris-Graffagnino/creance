# review-response — resolve the reviewer findings on an open PR (runtime-neutral)

Creance gates work **before** the PR exists (`next-task.md` §7, `gate-loop.md`) and reviews
**someone else's** open PR without touching it (`pr-review.md` — read-then-comment, never
pushes). But once **your own** PR is open, reviewers — human *and* bot/automated — leave
**inline findings** on it, and someone has to **resolve** them: verify each against current
source, fix the real ones, prove the fix, re-grade the fix, reply to every commenter, and
confirm the PR is green — **without merging**. That resolution loop is a distinct ritual,
and it has recurring failure modes this workflow exists to prevent:

- **self-certifying a repair** — pushing a fix the checker never re-graded, which collapses
  the maker ≠ checker split the §7 gate exists to hold;
- **"fixing" an ungrounded finding** — editing in reaction to the comment text rather than to
  the code **as it currently stands** (the line may have moved, been fixed, or been made moot);
- **a behavior fix with no red→green proof** — claiming *fixed* without a test that fails on
  the old code and passes on the new;
- **declaring the PR resolved with comments still unread** — bot/automated inline findings are
  the most-missed source; and
- **merging** — never; merge authorization is the owner's alone.

This workflow resolves the findings on **one open PR**: it ingests the diff **and every
inline comment**, grounds each finding to a current `file:line`, applies the minimum scoped
fix with red→green proof, **re-runs the §7 gate on the fix**, replies to every comment, and
confirms the head is green — then **stops for the owner's merge**. It **reuses** the pr-review
read-and-ground discipline, the next-task fix-and-gate discipline, and the auditor
**[reviewer]** specs rather than restating them, and it **changes no §7 gate semantics**.

> Runtime-neutral: roles in **[brackets]** are defined in `README.md` → "The binding
> contract". Project specifics — the constitution path, the invariant checklist, the
> tasks/spec paths, the required check, the title conventions — come from the profile
> (`.claude/PROJECT.md`, the source of truth); below, *the profile* means that file, and the
> active binding governs how it is read (it may default to a drift-checked compacted view and
> escalate to the full profile for omitted facts). This workflow **composes existing roles
> only**; it introduces no new binding-contract row.

## Write posture (the hard bounds)

- **This workflow writes to the PR branch — and that is its distinguishing bound.** Unlike
  `pr-review.md`, which never pushes, review-response **pushes fix commits** and **posts
  replies**. Both writes are constrained: a fix is the **minimum scoped change** to an
  **adjudicated** finding (`next-task.md` §5 — surgical, traceable, no adjacent cleanup); a
  behavior fix carries **red→green** proof (§5 falsification rule); a reply is **additive** and
  carries the **[comment marker]** (`next-task.md` §2.5). It **never merges**, never closes the
  PR — merge authorization is the owner's alone, session-explicit (the profile's merge-gate
  ruleset; never auto-merge).
- **Maker ≠ checker holds on the fix.** A fix is fresh maker work, so it **re-enters the §7
  gate** (§5 below) — the same **[reviewer]s**, adversarial, in their own context, grading the
  **fix commit's** diff. You do **not** self-certify a repair by pushing it under your own
  say-so; that is the first failure mode above. This is the discipline that separates a
  governed resolution from an ad-hoc "fix and push".
- **Findings are grounded in current source before any code is touched.** Every finding — from
  an inline comment or your own read — is resolved against the file **as it stands now**
  (`pr-review.md` §3), not the diff snapshot and not the comment's wording. A finding you
  cannot ground you do **not** edit blind — you reply with the grounding.
- **Owner steering is authoritative and blocking** (`next-task.md` §2.5). The newest **unmarked**
  owner-login comment steers; an owner relay of a reviewer finding is blocking and is resolved
  or explicitly answered, never silently dropped. A **marked** comment is engine bookkeeping and
  carries no steering authority.

## 1. Inputs (the open PR and its threads)

A **PR reference** — number or URL — arrives in the invocation text (the explicit-context
rule, `README.md`); the PR is the harness's own (the resolution case). Resolve its base and
head, its diff against the base, its linked issue and task ID (the profile's title
convention), and the **full inline-comment set** — human **and** bot/automated — plus the
timeline / owner-steering channel (§2.5), before touching anything. When the reference is
missing or resolves to no open PR, say so and **stop** — a run with no PR makes no writes.

## 2. Ingest the diff and every reviewer comment

Read two things, not one (`pr-review.md` §2, reused):

- **The diff** — the PR's change against its base; for a large diff, fan the read out through a
  **[bulk-read offload]** (read-only, separate context) that returns conclusions and `file:line`
  anchors, never raw dumps.
- **Every inline comment** — every line-anchored review comment, **including bot/automated
  inline findings** (the most-missed source). Enumerate them exhaustively; a thread that
  paginates is read to the end. The count you carry into §6's ledger is the count the PR
  actually has.

**Enumerate first, filter second.** Never pre-filter the comment reads by an author login: an
automated reviewer's login may not match the string you expect, and an empty filtered set must
never read as "nothing to address". Separate **inline findings** (to adjudicate) from
**engine-marked bookkeeping** ([comment marker]) from **owner steering** (newest unmarked
owner-login, §2.5).

## 3. Verify each finding against current source (before any fix)

For each candidate — surfaced by a comment **or** found in your own read — resolve it against
the source **as it currently stands** (`pr-review.md` §3, reused):

- Open the cited file at the cited line and confirm the issue is present **now**. A comment
  anchored to a since-changed line is **re-resolved** against current source, not taken at face
  value.
- Classify each: **valid-unaddressed** (real, still present), **already-addressed** (the source
  no longer exhibits it), **stale-anchor** (the line moved — re-locate and re-judge), or
  **refuted** (not a real issue; say why). Each classification carries a current `file:line`.
- **Run the project's checks where a finding's validity is behavioral** — its tests, type
  check, or lint (the profile's required check names the suite), narrowest first. A correctness
  or regression claim a check can settle is settled by running it, not by reasoning about it.

## 4. Resolve each valid finding (minimum scoped change + proof)

For every **valid-unaddressed** finding, exactly one of:

- **Fix it** — the **minimum scoped change** (`next-task.md` §5): surgical, every changed line
  traceable to the finding, no adjacent cleanup. A behavior change carries a test that **fails
  on the pre-fix code and passes on the fix** (§5 falsification rule; per-instance assertions,
  negative/edge cases where contracts matter). *Fixed* without that red→green evidence is a
  claim, not a resolution. Update specs/contracts/checklist when the fix changes public
  behavior (§5 step 6).
- **File it as discovered work** — a finding that is **real but out of this PR's scope** is
  recorded per `next-task.md` §5.5 (self-contained issue, "Discovered while working #N"), **not**
  smuggled into the diff; the §6 reply points at the filed issue.
- **Reply only** — an **already-addressed**, **stale-anchor**, or **refuted** finding gets a
  grounded reply (§6) and **no** code change.

Keep the diff surgical: unrelated user changes are never reverted, and a fix that would widen
the PR beyond its task's scope is discovered work, not scope creep.

## 5. Re-gate the fixes (maker is not the checker — required)

If §4 changed any code, the fixes are **new maker work** and must be re-graded before they
count as resolved:

- **Commit the fixes on the PR branch first** (the gate reviews the committed diff).
- **Re-run the §7 pre-PR gate on the fix commit** — the **[orchestrated run]** where the adapter
  provides it, else the numbered `next-task.md` §7 procedure — dispatching the **[reviewer]s**
  whose dispatch condition the fix meets: the acceptance **[reviewer]** (always, passed the task
  ID) and the constitution **[reviewer]** (always, at the strong-tier floor); the contract and
  spec-quality **[reviewer]s** only on their `dispatch-contract` / `dispatch-spec` conditions
  (`gate-loop.md` → "The reviewer roster"). Advisory review passes run per the profile's
  review-pass set (§7 step 3).
- **Loop until every dispatched reviewer returns PASS** (or JUSTIFY with the deviation
  documented). Do not mark a fix resolved by overriding a reviewer yourself. If the loop is not
  converging — the same item FAILs after **two** fix-and-re-dispatch rounds — **stop and surface
  the disagreement** in the reply and PR body instead of grinding.
- **Keep each dispatched reviewer's final verdict verbatim** and record the gate-run
  (`telemetry.md`); §7 update the PR body's risk-ranked digest (near-misses / JUSTIFY / touched
  invariants, `next-task.md` §8) when the re-gate changes it.

## 6. Reply to every comment (grounded, credited, marked)

Post a reply on the thread of **every** comment enumerated in §2, stating its disposition:

- **resolved** — link the fix commit and cite the red→green evidence (§4);
- **already-addressed** — cite the current `file:line` that shows it (§3);
- **stale-anchor** — name where the line moved and the re-judgement (§3);
- **refuted** — say why, grounded in current source (§3);
- **filed as discovered** — link the issue (§4 / §5.5).

Every engine reply carries the **[comment marker]** (§2.5); a reply endorsing an automated or
human finding credits the original. The **reply ledger** — every §2 comment with its disposition
— is the evidence that **none was skipped**; state it explicitly (replied / of total, the empty
case named), so the "all addressed" conclusion is auditable rather than asserted, exactly as
`pr-review.md` §4(a) requires of a review's enumeration. Acknowledge any owner relay explicitly
(§2.5).

## 7. Confirm the PR is green — then STOP

Push the fix commit(s) to the PR branch. Then **verify against concrete tracker data**, not
assumption: the profile's **required check** passes on the new head and the **merge-gate status**
is clean. If a check is **red, unavailable, delayed, or ambiguous**, say so and treat resolution
as **not done** until the head is green or the residual is documented. **Do not merge** — merge
authorization is the owner's alone, session-explicit (§2.5); an isolated autonomous run
(`next-task.md` §0.5) still promotes only through the §7-gated PR path and never writes the base
branch (P4). This workflow's terminal state is a **green PR with every comment answered**, handed
to the owner.

## 8. Report

The PR resolved; the **reply ledger** (replied / of total); findings **resolved** (with red→green
evidence), **refuted**, and **filed as discovered** (with issue numbers); the **re-gate outcome**
(verdicts kept, any JUSTIFY or non-convergence); the **check and merge-gate status** on the new
head; and where the replies and any updated digest were posted. If the run stopped early — no PR
reference, no open PR, no comments to address, or a non-converging gate — say why.
