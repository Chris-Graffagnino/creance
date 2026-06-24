# `workflow/` — the runtime-neutral methodology layer

These documents describe the **workflow engine** in plain prose, with **no dependency on
any specific LLM/agent runtime**. They are the source of truth for *what* each procedure
does. The runtime-specific *how* — packaging, dispatch, gating, permissions, model
selection — lives in a thin **adapter** layer outside this directory. The active adapter
and how to write a new one are documented in `.claude/README.md`.

```
.claude/
  workflow/                 ← THIS layer: runtime-neutral methodology (portable)
    next-task.md  triage.md  constitution-check.md  auditor-liveness.md
    reviewers/constitution-auditor.md  reviewers/contract-auditor.md  reviewers/spec-auditor.md  reviewers/evasion-register.md  reviewers/auditor-liveness-corpus.md
  PROJECT.md                ← project facts (also runtime-neutral)
  <adapter files>           ← the active runtime's binding (see .claude/README.md)
```

To run this engine on a different runtime, you reuse `workflow/` + `PROJECT.md` +
`memory/constitution.md` unchanged, and write **one new adapter** that provides the
roles below. (`workflow/` lives under `.claude/` only for cohesion — its *content* is
runtime-neutral; copy it out when porting.)

## The binding contract

The methodology docs refer to **roles** in **[brackets]**. Each role is a capability the
adapter must provide; the table specifies it runtime-neutrally as **inputs → outputs +
constraints**. An adapter maps every role to a concrete mechanism (the active adapter's
mapping lives in `.claude/README.md`, *not* here). The neutral docs reference roles only —
never a mechanism — so new roles are added by appending rows, without reshaping the table.

| Role | Inputs | Outputs | Constraints |
|------|--------|---------|-------------|
| **[workflow]** | A procedure name from this directory, plus optional arguments as plain text | A complete run of that procedure | Triggerable on demand by a user AND by a scheduler; arguments arrive in the invocation text |
| **[reviewer]** | A reviewer spec from `reviewers/`, plus the dispatch parameters that spec requires (e.g. a task ID) | The spec's verdict report, returned to the dispatcher verbatim | Runs in a context **separate from the maker's**, with **no file-mutation capability**; adversarial posture per its spec; multiple reviewers dispatchable in parallel |
| **[frontier tier] / [strong tier] / [cheap tier]** | A tier selection per run or per dispatch | Execution of that run on a model **at or above** the selected tier | An **ordinal ladder** (frontier > strong > cheap): frontier = long-horizon work (multi-hour autonomous scope, plan-and-port-scale); strong = constitution-critical / ambiguous reasoning; cheap = mechanical. A tier is a **minimum capability requirement** — the adapter resolves it through its **model table** (one model + optional **effort** level per tier; the table is the adapter's only file naming models), rounding up when a tier is unavailable, never down. The constitution [reviewer] always runs at-or-above strong; a session already on a stronger model never downgrades a tagged task |
| **[code-review pass]** | The current branch's diff against the base branch | The toolchain's general code-review findings | Independent of the maker's self-review; findings are triaged as blocking unless documented otherwise |
| **[security-review pass]** | The current branch's diff against the base branch | Security-focused review findings | Same as [code-review pass], security lens; used when the change touches privacy, location, or payments |
| **[craft-review pass]** *(optional)* | The current branch's diff against the base branch | Craft-layer findings — testing discipline, failure/error handling, extension & boundary design, resource control / backpressure, observability, API & backward-compat, implementation simplicity | Same isolation and maker-independence as [code-review pass], craft lens; **advisory** — findings are triaged as blocking unless documented, but graded against craft practice rather than the fixed acceptance/constitution/contract rubric (so its test-adequacy findings carry the standard's existing weight on dimension 6, while its clarity/simplicity findings stay advisory per dimensions 7–8). **Complements** [code-review pass] (which owns correctness/bug-hunting); never replaces it. Run alongside the [code-review pass] at the §7 gate. **Optional** — an adapter without it runs the gate exactly as before, losing only the craft layer |
| **[visual verification]** | The task branch's running app, plus the user-visible surfaces the task touched | Machine-generated visual evidence of the running app — screenshots; video/animated capture for animation or transition work — attached to the task's PR | Required for any task touching user-visible UI. The evidence is produced by the runtime **actually rendering the app** — never described, mocked up, or recreated from the model's imagination (a model's *claim* that the UI looks right is worth nothing; an artifact is model-independent). **The frame carries fixtures only:** the evidence channel is typically public and permanent, so evidence frames may contain only synthetic/fixture data — never real or imported user content, credentials, or real locations; screens that can show user content must be seeded with fixtures first. **Degrades loudly, never silently:** when no evidence can be produced (tooling flake, headless run without a display/device), the PR must state **"tests only — no visual evidence produced"** and list the affected surfaces as **unverified** — the flake surfaces as unverified, it neither blocks the pipeline nor passes silently |
| **[orchestrated run]** *(optional)* | The gate-loop spec (`gate-loop.md`) plus its dispatch parameters: task ID, the reviewer selection, the tier→model resolutions (resolved by the **dispatcher** through the adapter's model table — the loop names no models), and the fix-round cap | A machine-executed run of the §7 gate loop: the overall gate outcome (PASS / FAIL) plus **every** dispatched reviewer's latest verdict report, verbatim, returned to the dispatcher | **Optional** — an adapter without it degrades to `next-task.md` §7's prose procedure, exactly as written. When provided: the loop's control flow (parallel fan-out, latest-verdict retention, re-dispatch-only-failures, the two-fix-round non-convergence stop) is enforced **by code, never by executor discipline**; every dispatched reviewer still satisfies every [reviewer] constraint; the constitution reviewer's [strong tier] floor applies to its dispatch parameter; a reviewer that returns no verdict counts as failing, never as passed; the fix step is a maker-role executor, never a reviewer |
| **[bulk-read offload]** | A reading/searching brief (what to find, where to look) | An answer/summary small enough to not bloat the requesting context | Executes in a **separate context**; read-only; returns conclusions, never full file dumps |
| **[headless run]** | One [workflow] name plus arguments | A fresh, non-interactive run of that workflow; its exit code propagates to the caller | No prior conversation state; anything the run must honor is passed **in the invocation text**, not only via environment hints (the explicit-context rule below) |
| **[guard]** | Every imminent repo-mutating action, *before* it executes | Allow, or a deterministic VETO that blocks execution (not a warning) | **Deterministic** — no model judgment in the decision; **fails open** (uncertainty → allow); enforces exactly the guard rules below |
| **[edit guard]** | A just-applied file edit and the file it touched | Allow, or a deterministic **fix-forward rejection** naming the new diagnostics so the next action repairs them | **Deterministic** and **delta-based**: reruns the project's configured **syntax/type check** for the touched file's type (the check commands are a profile fact, never named here) and rejects only when the edit raises the file's diagnostics **above its pre-edit baseline** — an edit leaving them no worse than before is allowed, so a pre-existing failure never blocks unrelated work. **Fails open** when no check is configured for the type, the path is unknown/out-of-repo, or the baseline is unavailable. Distinct from [guard] in timing: where a runtime cannot veto before the write, this is enforced **after** it as fix-forward feedback (the edit stands; the next action fixes it), never a silent revert |
| **[isolated workspace]** *(optional)* | An autonomous task run, its **activation signals** (an explicit in-session authorization and/or a profile config opt-in), and the §7 gate outcome for that run | Either nothing reaches the base branch (review mode, or gate FAIL → the workspace is discarded), or — on a gate **PASS** under an *engaged* autonomous run — the change is promoted through the **normal §7-gated path** | **Optional** — an adapter without it runs review mode only (the default), losing nothing. **Off by default:** with neither activation signal the autonomous-promotion path is **deterministically unreachable** (review mode), decided by a check that **fails *closed* to review** on any uncertainty — never by model memory (P3). This is the deliberate **inverse** of the [guard]'s fail-*open* posture (a fail-open activation check would silently switch autonomy on). Work executes in an **ephemeral** workspace; on gate FAIL it is discarded and the base branch is untouched. Promotion is **only** ever the §7 gate's PASS — the isolation mechanism is **never itself a path that writes the base branch** (P4). The **model** (activation semantics, promote-on-PASS / discard-on-FAIL) is neutral here; the **workspace mechanism and the config-opt-in read live only in the adapter** (P1). The guard keeps failing open under autonomy — see "Isolation and the guard's fail-open posture" below for why that stays safe |
| **[permission allowlist]** | A proposed routine action | Pre-approval, so unattended runs proceed without an interactive prompt | Matched mechanically against a maintained list; the list lives in the adapter, never in these docs |
| **[environment block]** | A portable rule stated in a neutral doc (e.g. "pass multi-line text via a file, as UTF-8") | The concrete OS/shell/CLI form of that rule for the active environment | Exactly **ONE copy per adapter** — every OS/shell/CLI specific (encodings, install paths, quoting, invocation forms) lives there and nowhere else; neutral docs may point to this role but never inline its contents |
| **[comment marker]** | An engine-authored comment body bound for a task's issue/PR thread | The same body carrying a deterministic self-identification marker | The marker's concrete form is defined **exactly once, adapter-side** (never in these docs), is **visible to a non-developer reader** of the thread, and is applied to **every** engine-posted comment. Its job is provenance under a **shared login**: the engine may post under the owner's own account, so author identity cannot separate harness bookkeeping from owner steering — the marker does (third parties cannot post as the owner login, so it need only separate harness-authored from human-authored). Recognition is **deterministic and position-anchored** per the adapter's definition — marker text merely quoted or embedded mid-body neither marks a comment nor demotes an owner comment. Reading rule: a **marked** comment is engine bookkeeping and **never** carries steering authority; the newest **unmarked** owner-login comment is authoritative owner steering, within the authority bounds in `next-task.md` §2.5 |

### The [guard] rules (what the gate must enforce)
The deterministic gate blocks, before execution:
1. Any **file edit while on the base branch** (`main`) whose target is **inside the repo**
   (out-of-repo writes — e.g. the triage inbox — are allowed).
2. **Staging the entire tree at once** (`git add .` / `-A` / `--all`) — stage specific
   files instead.
3. **`git commit` / `git push` while on the base branch.**
4. Any **`git push` whose refspec targets the base branch** (e.g. `HEAD:main`, `:main`,
   or `main` as the push destination), regardless of the branch currently checked out.
5. **Dispatching a strong-floored [reviewer] below the [strong tier]** — any [reviewer]
   dispatch of a **strong-floored reviewer** (the **constitution reviewer** and the
   **spec-quality reviewer**) whose model selection is **absent** (it would silently
   inherit the dispatching session's model) or resolves **below the strong-tier row of the
   adapter's model table**. The tier→model resolution is read from the model table at
   enforcement time, never hardcoded in the gate (the one-line-model-swap property); a
   model name the table cannot rank, or an unreadable table, falls open.
6. An **in-place text substitution whose delimiter also appears in the literal content
   being substituted in** — e.g. a URL whose `/` or `#` collides with the chosen
   delimiter — which silently corrupts or blanks the output instead of failing loudly.
   A delimiter absent from the content avoids it; this veto is the deterministic backstop
   for when one is chosen anyway. Scoped to a single command, and fails open on anything
   ambiguous (the recurring instance: a body-edit substitution blanking a live PR body).
It **fails open**: any uncertainty → allow. These rules are normative; each adapter
supplies its own implementation (the active adapter's is named in `.claude/README.md`).

### The explicit-context rule (binding on every adapter)
No workflow step may depend on an **environment variable or an inferred working
directory** for *correctness*. The wrapper that starts a run — a launcher, a scheduler
entry point, any [headless run] invocation — resolves every value the run must honor
(file paths, log locations, the repo root) and passes it **explicitly in the invocation's
prompt text**. Environment variables may still be set as redundant hints; they are never
the only carrier. Rationale: an LLM executor honors prompt text far more reliably than
environment hints (observed in production: a headless run ignored its env-var path hints
until the launcher moved the paths into the prompt). The triage launcher contract
(`triage.md` §6, rule 1) is the worked example of a conforming wrapper.

### Isolation and the guard's fail-open posture (binding when [isolated workspace] is provided)
The **[isolated workspace]** role introduces a path by which gated work can reach the base
branch **without a human in the loop**, so it changes the threat model the [guard] was built
against. That change is reconciled here — no principle is relaxed:

- **Activation is off by default and fails *closed*.** Autonomous mode engages **only** on an
  explicit in-session authorization **or** a profile config opt-in. With neither, the path is
  review mode and **deterministically unreachable** — decided by a check that fails **closed to
  review** on any uncertainty (unreadable config, ambiguous signal). This is the exact inverse
  of the [guard]'s fail-*open* default, and the inversion is the point: a fail-open *activation*
  check would silently switch autonomy on, the one thing the blast wall must never do (P3).
- **The [guard] keeps failing *open* — isolation is what makes that safe under autonomy.** The
  guard is **not** retuned for autonomous mode. Under review mode the human merge is the wall;
  under an engaged autonomous run the wall is the **[isolated workspace] boundary + the §7
  gate**: work happens in an ephemeral workspace and reaches the base branch **only** on a gate
  PASS. A guard that fails open *inside* that workspace cannot leak to the base branch — the
  workspace is discarded on FAIL and promotion is the gate's PASS, never a direct write (P4).
  Moving the wall from the guard to the workspace+gate is precisely what lets the guard's
  fail-open posture stand unchanged.
- **Relation to "merge authorization is session-explicit only" (`next-task.md` §2.5).** That
  rule bars the **comment channel** from authorizing a merge — a comment is unreviewed and
  posted under a shared login. A **config opt-in is different in kind:** it is a committed
  setting that lands only through a human-reviewed PR, so the human ratification the merge rule
  requires happens **at opt-in time**, once, rather than per run. Adding the config-opt-in path
  is the one deliberate **extension** of the autonomy default this role introduces; because it
  shifts a governance default, an adapter wiring it surfaces the opt-in for **owner
  ratification**, never as an engine decision.

## The review standard (binding on every review pass)

Any review of PR-bound work — a [reviewer] dispatch, a [code-review pass], or a degraded
same-context pass — must inspect the linked issue, the task ID, the relevant
contracts/specs, the constitution, the PR diff, and the test plan/results.

Prioritize findings in this order:
1. **Constitution compliance**
2. Correctness against acceptance criteria
3. Regression risk
4. Spec and contract compliance (including provider-swappability and cost invariants)
5. Scope discipline
6. Test adequacy, including negative/edge cases
7. Maintainability and clarity
8. Style last

Block approval when a constitution principle is violated, acceptance criteria are
unclear, contracts drift, a vendor is called outside its interface, cost invariants are
broken, tests are missing/weak, scope is too broad, or correctness cannot be determined.

Approval comments must be evidence-based: name the issue/task reviewed, checks run,
contract + constitution alignment, and any intentional follow-up scope. (The reviewer
specs under `reviewers/` are this standard's per-dimension instantiations for dimensions
1, 2, and 4; their verdict-table output shapes are what "evidence-based" looks like in
practice. The optional **[craft-review pass]** is the standard's advisory instrument for
dimensions 6–7 — test adequacy, maintainability and clarity — run alongside the
[code-review pass] and graded against craft practice rather than the fixed rubric.)

This standard governs **both** review moments: the **pre-PR** §7 gate (`next-task.md` §7,
maker-side, before the PR exists) and the end-to-end review of an **already-open** PR —
including its inline reviewer comments — which is the `pr-review.md` ritual. `pr-review.md`
**applies** this priority order and evidence rule rather than restating them, and adds only
what an open PR needs over the pre-PR gate: enumerating every inline comment (bot/automated
included) and grounding each finding to current source before any "no findings" conclusion.
It changes no §7 gate semantics.

## How an adapter degrades gracefully
If a runtime lacks a role, the methodology still runs, more weakly:
- **No [reviewer] isolation** → run the reviewer spec as a second pass in the same context
  (you lose maker≠checker independence; note it). This also carries a **context cost**: the
  reviewer specs then load into the dispatching run's own context instead of a separate one,
  so the heaviest review artifacts tax every step of the main run — weigh that against the
  run's context budget when deciding how much review to inline.
- **No [guard]** → the base-branch / bulk-staging rules become advisory prose the agent must
  self-enforce (weaker; lean harder on review).
- **A tagged tier is unavailable** → round up to the nearest tier above. Only when nothing
  at-or-above exists may the run drop below its tag — and the PR must record that loudly.
- **One model tier only** → use it everywhere; never silently downgrade the constitution
  reviewer.
- **No [code-review pass] mechanism** → run an independent read-only review of the branch
  diff vs. base, in a context separate from the maker's, with a general code-review brief.
  This borrows the **[reviewer]** *isolation constraints* (separate context, no file
  mutation) to supply maker≠checker independence — it is **not** a spec-bound [reviewer]
  dispatch, so no `reviewers/` spec is required; the brief is general. Note the degradation
  in the PR.
- **No [security-review pass] mechanism** → same, with a security-lens brief scoped to the
  profile's privacy / location / payment invariants (the dimensions the [security-review
  pass] role guards). Note the degradation in the PR.
- **No [craft-review pass] mechanism** → skip the craft layer; the gate runs exactly as
  before (the role is optional and adds dimensions 6–7 on top — its absence loses no core
  review). Note the skip in the PR. Do **not** fake it as a same-context self-pass: the
  maker self-grading craft has no maker≠checker value, unlike the [reviewer] degradation
  where a second pass at least applies a fixed rubric.
- **No [visual verification] mechanism** → the role's own degradation clause applies to
  every UI-touching task: the PR carries the explicit "tests only — no visual evidence
  produced" statement and lists the affected surfaces as unverified. The statement is
  mandatory — omitting it (passing silently on UI work) is non-conforming, not a degraded
  mode.
- **No [orchestrated run]** → run `next-task.md` §7's prose loop by hand — the
  methodology's shape is identical; the bookkeeping (re-dispatch only failures, stop after
  two fix rounds, keep every verdict verbatim) then rests on executor discipline, so
  follow it to the letter.
- **No effort dial** → ignore the model table's effort column; tier resolution is
  unaffected. (The effort column is optional per runtime.)
- **No [comment marker]** → provenance cannot be established, so every owner-login
  comment that reads like engine bookkeeping is **ambiguous**: apply `next-task.md`
  §2.5's ambiguity rule (quote and flag it on the surface that exists; never silently
  obey, never silently ignore). Note the degradation in the PR.

## Files
- `next-task.md` — the per-task loop (one task → one issue → one branch → one PR).
- `gate-loop.md` — the §7 pre-PR gate loop as runtime-neutral pseudocode (the
  [orchestrated run] spec; §7's prose is its degradation path).
- `conformance-probes.md` — one verifiable probe per role above (plus the guard rules and
  the explicit-context rule), runtime-neutral; every adapter instantiates them concretely
  before being trusted.
- `triage.md` — the read-only daily state snapshot.
- `intake.md` — converts owner-filed tracker issues into the backlog via PR (triage
  detects unmapped issues; intake classifies, constitution-screens, drafts, and lands
  the formalization for the owner to ratify by merging).
- `retrospective.md` — back-tests an escaped defect against the auditors: dispatches them
  read-only against the historical diff that introduced it, classifies the escape
  (would-have-caught / inconsistent-catch / hunt-rule-gap / invariant-gap), and proposes the
  resulting tightening (hunt rule / invariant row) via PR — never editing a rule directly.
- `auditor-liveness.md` — the standing planted-violation corpus that keeps the judgment
  [reviewer]s proven live: promotes the one-time `P-RV` probe into a known-bad/known-good
  fixture pair per auditor, re-run on every reviewer-spec change + ≥ weekly, **report-only**
  and **observe-only** (the model-driven analog of the [guard]'s `guard.test.sh`; never a
  gate — P5). Fixtures in `reviewers/auditor-liveness-corpus.md`.
- `pr-review.md` — end-to-end review of an **open** PR: ingests the diff **and every inline
  comment** (bot/automated included), grounds each finding to current `file:line`, and posts
  one severity-ranked review. Applies "The review standard" above and reuses the `reviewers/`
  specs rather than restating them; changes no §7 gate semantics (a complement to the pre-PR
  gate, run after the PR opens — the gate runs before it exists and never sees inline comments).
- `constitution-check.md` — the pre-PR compliance gate.
- `reviewers/constitution-auditor.md` — adversarial values/constitution [reviewer] spec.
- `reviewers/contract-auditor.md` — adversarial architecture/contract [reviewer] spec.
- `reviewers/spec-auditor.md` — adversarial acceptance-criteria [reviewer] spec (does the
  diff do what the task asked, with tests that encode each criterion).
- `reviewers/evasion-register.md` — the cumulative cheat museum: observed gate evasions →
  the fence that closed each, with `file:line` exemplars. Every [reviewer] consults it at
  dispatch and cites the matching exhibit; the retrospective appends new exhibits via PR.
- `reviewers/auditor-liveness-corpus.md` — the auditor-liveness fixture manifest: ≥1
  expected-FAIL and ≥1 expected-PASS planted-violation fixture per auditor (seeded from the
  evasion register), the known-bad/known-good corpus `auditor-liveness.md` runs.

All of them read project facts from `.claude/PROJECT.md` and the constitution it names.
