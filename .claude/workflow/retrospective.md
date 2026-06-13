# retrospective — back-test an escaped defect against the auditors (runtime-neutral)

Creance verifies every task at the §7 gate, but a defect that reaches the base branch is,
by definition, one the gate did not stop. This workflow closes that loop **per incident**:
given a defect found on the base branch, it re-runs the auditors against the *historical
diff that introduced it* — exactly as the gate would have — and converts the escape into
one durable outcome: a **tightened hunt rule**, a **new invariant row**, or a **documented
known-gap**. Every rule change lands as a human-reviewed PR; the retrospective never edits
a rule itself.

It runs **per incident, never as a retroactive sweep** (spec 001 non-goals): one defect in,
one classification and one proposal out.

> Runtime-neutral: roles in **[brackets]** are defined in `workflow/README.md` → "The
> binding contract". Project specifics — the constitution path, the invariant checklist,
> the task-ID and tier-tag formats, the tasks/spec paths — come from `.claude/PROJECT.md`.
> Below, *the profile* means that file. The retrospective **composes existing roles only**;
> it introduces no new binding-contract row.

## Write posture (the hard bounds)

- **It never edits a rule directly.** Reviewer specs, the invariant checklist, the guards,
  and the constitution are exactly the files the constitution's **no-silent-self-modification**
  principle protects: a feedback loop may *propose* a tightening, only a reviewed merge may
  *apply* it. Every rule/invariant change this workflow yields travels issue → branch → §7
  gate → PR (§5), and the owner merges to apply. A run that writes any of those files
  outside that PR flow has violated the principle (the profile's invariant: *reviewer specs,
  invariants, guards, or the constitution modified by automation outside a human-reviewed
  PR — FAIL*).
- **The auditor dispatch is read-only.** The auditors run in their own context with no
  file-mutation capability (the **[reviewer]** constraint); the retrospective adds no fix
  step — it classifies, it does not repair the historical diff.
- **Telemetry is read as evidence, never as a control input.** The retrospective *reads* the
  `gate-run` records (`telemetry.md`) to learn whether a gate actually ran on the historical
  change; that reading informs a human-reviewed proposal and **never** alters a gate
  outcome, a tier, or gate semantics (the constitution's **telemetry-observes-never-decides**
  principle). The measurement channel gains no control authority by being read here.

## 1. Inputs (the incident)

The retrospective is triggered when a defect or constitution violation is found on the base
branch. Its inputs:

- **A commit or PR reference** — the change that introduced the defect (the historical diff
  to back-test).
- **A defect description** — what went wrong, in enough detail to recognize the failure in a
  diff (the *class* of mistake, not only the symptom).

Both arrive in the invocation text (the explicit-context rule, `README.md`). When the
introducing change is not yet known, identify it first with the ordinary provenance search
the discovered-work rule already uses (`next-task.md` §5.5: the change-introduces-defect
search), and pass the resolved reference; an unresolved origin is stated as such, never
guessed.

## 2. Reconstruct the historical diff

The diff the auditors see is the **introducing change against its parent** — the same diff
the gate would have graded when that change was made (a single commit against its
predecessor; a PR against its merge base). This, not the current base branch, is the audited
surface: the retrospective asks "what would the auditors have said about *this change, as
written then*?"

## 3. Dispatch the auditors — exactly as the gate would (AC1)

Dispatch the **same auditor [reviewer]s the §7 gate would have dispatched for this diff**,
against the §2 historical diff, **read-only**:

- the **acceptance [reviewer]** with the introducing change's task ID (the one its
  title/issue claimed; *unknown* when the change carried none);
- the **constitution [reviewer]** — **always**, at the **[strong tier]** floor (below);
- the **contract [reviewer]** — when the historical diff touched a provider interface,
  monetization, or the data model (§7's contract-reviewer condition).

Run them as a **single report-only fan-out — no fix step, no re-dispatch loop** (the
report-only shape of `gate-loop.md`, its fix step disabled): the gate's fix-and-converge
cycle exists to drive a *live* task to PASS, but the retrospective classifies a *settled*
historical diff, it does not repair it. Each auditor returns its ordinary verdict report
verbatim, with the **file:line evidence** its spec already produces.

**Strong-tier floor (AC4).** The constitution [reviewer] is dispatched at-or-above the
**[strong tier]** — the *same floor the guard enforces for gate runs* (the **[guard]** rule
on the constitution-reviewer dispatch; `README.md` binding contract: the constitution
reviewer never downgrades). The floor binds the retrospective's dispatch exactly as it binds
the gate's; the adapter routes this dispatch through the same guarded path the gate uses, so
the floor is enforced, not merely asserted.

## 4. Classify — exactly one bucket, with file:line evidence

Two facts decide the bucket:

- **Fact A — do the auditors FAIL the historical diff under *today's* rules?** (the §3
  result).
- **Fact B — did a gate actually run *on this change* and pass?** Read the `gate-run` records
  for the introducing change's task ID (`telemetry.md`). A task ID can carry **several**
  records — a diff gated, then amended and merged without a fresh gate; a re-gate; an
  accidentally reused ID — so sharing the task ID alone never proves the gate ran on *this*
  diff. **Prefer the record's `commit` ref (`telemetry.md` → "The `gate-run` record"): it
  pins each record to the exact diff its gate audited, making attribution deterministic.**
  Resolve the introducing change to its commit(s) — a single commit is itself; a
  squash-merged PR resolves to the commits on its head ref. Then judge **each** `gate-run`
  record for the task ID by the evidence it carries: a record **with** a `commit` is
  attributable iff that `commit` is among them (deterministic); a **legacy** record **without**
  a `commit` — written before the field existed (the stream is append-only) — is attributable
  iff its `timestamp` brackets the change's commit/merge. This timing fallback is judged **per
  record** and is **never suppressed by another record** that happens to carry a `commit`: a
  newer re-gate of a *different* diff must not hide an older legacy gate of *this* one. Fact B
  is true when an attributable record has `outcome: pass`. Anything else — no record, the
  catching auditor absent from the dispatched round, or only records that match neither by
  `commit` nor (for a legacy line) by timing — leaves Fact B **unproven**, which the table
  reads as ¬B (the safe-fallback note below).

| | Auditors **FAIL** now (A) | Auditors **PASS** now (¬A) |
|---|---|---|
| **Gate ran + passed then** (B) | **INCONSISTENT-CATCH** | **HUNT-RULE-GAP** or **INVARIANT-GAP** |
| **No gate / misconfigured** (¬B) | **WOULD-HAVE-CAUGHT** | **HUNT-RULE-GAP** or **INVARIANT-GAP** |

**Safe fallback — an unprovable Fact B biases toward WOULD-HAVE-CAUGHT, never
INCONSISTENT-CATCH.** The two error directions are not symmetric: assuming a gate covered a
change it never gated hides a real **process gap** (the missing-fix outcome), while assuming
no gate when one did run only triggers an extra check the record then settles. So when no
`gate-run` record is attributable to the introducing change, classify a now-failing diff as
WOULD-HAVE-CAUGHT and mark it *by fallback*, so the proposal is confirmed against the record
rather than inheriting a silent INCONSISTENT-CATCH. (The `gate-run` record's `commit` ref now
makes this attribution deterministic whenever it is present; the timing-correlation fallback
applies **per legacy record** — those written before that field existed — never gated on the
whole task ID.)

- **WOULD-HAVE-CAUGHT** — the auditors FAIL the historical diff, and **no `gate-run` record is
  attributable to that change** — none exists, the catching auditor was absent from the
  dispatched round, or the only same-task records cannot be tied to this diff (the Fact-B
  fallback). The rule already works; the escape is a **process gap** — the gate did not run
  where it should have.
- **INCONSISTENT-CATCH** — the auditors FAIL it now, but a gate **attributable to this
  change** *ran and passed* then. Either
  the rules were **tightened since** (the escape is already closed — the same diff would fail
  today) or the auditor was **nondeterministic** (a reliability defect: the same rules, a
  different verdict).
- **HUNT-RULE-GAP** — the auditors **still pass** the historical diff under current rules,
  **and an existing auditor owns the defect's dimension** but its hunt rules are too
  weak/narrow to fire on this instance. The covered dimension missed a case.
- **INVARIANT-GAP** — the auditors still pass it, **and nothing documented covers the
  defect** — no invariant-checklist row and no auditor hunt rule even names this class of
  mistake.

When ¬A, distinguish HUNT-RULE-GAP from INVARIANT-GAP by one question: *does any current
auditor hunt rule or invariant row even target this defect class?* Yes → HUNT-RULE-GAP
(tighten the rule that should have fired); No → INVARIANT-GAP (no rule names it; a row must be
added). Each classification carries **file:line evidence**: for Fact A, the auditor's FAIL
report cites it; for ¬A, cite the defect's own location in the historical diff and name the
rule(s) demonstrably silent on it.

## 5. Produce the outcome

Exactly one durable output per incident, by bucket:

- **HUNT-RULE-GAP → a proposed reviewer-spec tightening.** Draft the narrowest edit to the
  owning auditor's spec (`reviewers/…`) that would make it FAIL this defect class, with the
  §4 file:line evidence as the rationale.
- **INVARIANT-GAP → a proposed invariant-checklist row.** Draft a new row for the profile's
  invariant checklist (and its enforcement-mapping entry — a deterministic backstop where one
  is possible, per the constitution's **determinism-over-judgment** principle;
  auditor-judgment-only where it is not), naming the defect class.
- **WOULD-HAVE-CAUGHT → a documented known-gap (plus the process fix).** The rule already
  catches it; record the gap — *the gate did not run here* — durably, and where a concrete
  wiring/configuration fix exists (e.g. a dispatch condition that should have included the
  catching auditor), that fix lands like any change, via PR.
- **INCONSISTENT-CATCH → a documented known-gap.** Rules-tightened-since: record it as
  already-closed (no rule change — the rules FAIL it today). Nondeterminism: record the
  flakiness as a reliability known-gap to track. Neither yields a rule tightening here.

**The propose-via-PR rule (AC3) — never edits rules directly.** A HUNT-RULE-GAP or
INVARIANT-GAP edit changes the *protected* files (reviewer specs / the invariant checklist),
so it travels the **standard issue → branch → §7 gate → PR flow** exactly as task work
(`next-task.md` §3–§8): file an issue carrying the classification and file:line evidence as
rationale, draft the edit on a branch, run the full §7 gate on it (the constitution
[reviewer] scrutinizes the rule change at its strong floor), and open the PR. **The owner
merges to apply** — the retrospective stops at the PR. The retrospective process itself writes
none of those files; it produces the proposal a human ratifies (the constitution's
**no-silent-self-modification** principle). A **documented known-gap** is filed durably on the
tracker under the discovered-work discipline (`next-task.md` §5.5), so it resurfaces through
triage until closed.

Every comment the retrospective posts to a tracker thread carries the **[comment marker]**
(`next-task.md` §2.5), like all engine bookkeeping.

## 6. Report

Per incident: the introducing reference, the bucket with its file:line evidence, and the
outcome produced — the proposal PR (HUNT-RULE-GAP / INVARIANT-GAP) or the filed known-gap
(the other two). Name what was *not* done and why (e.g. an unresolved introducing origin, or
a known-gap with no available deterministic backstop). The retrospective is per-incident and
pull-based: nothing here listens for defects; it runs when one is brought to it.
