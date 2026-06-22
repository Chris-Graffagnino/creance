# next-task — uniform per-task procedure (runtime-neutral)

One task → one issue → one branch → one PR. This procedure makes every task start
identically so autonomous runs are consistent. **Default to review mode: open the PR,
do not merge.**

> Runtime-neutral: roles in **[brackets]** (e.g. **[reviewer]**, **[code-review pass]**,
> **[strong tier]**) are defined in `workflow/README.md` → "binding contract" and mapped to
> concrete mechanisms by the active adapter.

**Project specifics come from `.claude/PROJECT.md`** — paths (tasks/spec/contracts/
constitution), task-ID format, blocked-task list, architecture boundaries, invariant
checklist, CI check, and merge gate. Read it once at the start; below, *the profile* means
that file. (If it's absent, fall back to conventions: `specs/*/tasks.md`, `specs/*/spec.md`,
`specs/*/contracts/`, `memory/constitution.md`.)

## Context discipline (one task → one clean window)
A task must fit in a single context without compaction. The conversation is disposable; the
**repo + issue + PR + profile + constitution are authoritative**.
- **Start fresh.** Run each task in its own session/process via a **[headless run]**; don't
  continue a long prior chat.
- **Offload bulk reading** with a **[bulk-read offload]** so file contents stay out of the
  main window; the **[reviewer]**s already work in their own context.
- **Read narrowly.** Prefer targeted search + ranged reads over whole-file dumps; never
  re-read a file you just edited.
- **Log-and-summarize verbose output** (tests, CI, API/JSON): capture to a temp log, print
  only failures + the summary.
- **Keep the diff surgical** — small diffs mean small reviewer/review inputs.
- **Checkpoint to disk continuously:** commit, open/update the PR, and record progress in the
  issue so state never lives only in the conversation.

## Resuming an interrupted or compacted task
Reconstruct from disk — do NOT trust conversation memory:
1. `git branch --show-current` + `git status` + `git log --oneline main..HEAD` — what's
   committed on this branch.
2. The open PR + its issue for the current branch, **including their comment threads**
   (§2.5): the newest unmarked owner-login comment is authoritative steering and
   **overrides the posted plan artifact and prior triage judgment**.
3. The task's spec/contracts + its tasks-file entry + the constitution (paths in the profile).
Then continue from the next undone step (§5–§8) and **re-run the §7 gate** before the PR.

## Model & usage economy
Usage may be a shared pool (interactive + scheduled + reviewers). Tiers form the ordinal
ladder from the binding contract (**[frontier tier]** > **[strong tier]** > **[cheap
tier]**); a tag is a **minimum capability requirement**, resolved through the adapter's
model table (round up when a tier is unavailable, never down).

**Per-stage tier map** (deterministic — no judgment call at dispatch time):

| Stage | Tier |
|-------|------|
| Planning + implementation (the session itself) | the task's tier tag; untagged → judgment below |
| **[bulk-read offload]** | **[cheap tier]** |
| Acceptance + contract **[reviewer]**s | **[cheap tier]** |
| Constitution **[reviewer]** | **[strong tier] FLOOR — never downgrades**, even when the task itself runs cheap |

- **Tier tags are authoritative.** If the task's line in the tasks file carries a tier
  tag (format per the profile), use that tier for the run — no judgment call: a
  **[headless run]** passes the model-table resolution as its model flag; an interactive
  session already on a stronger model never downgrades for a tagged task. Untagged tasks
  fall back to the judgment guidance below, leaning strong when the work touches the
  profile's invariant checklist.
- **[cheap tier]** for mechanical/low-risk work — config, scaffolding, stubs, docs, the
  bulk-read passes, and the contract and acceptance **[reviewer]**s.
- **[strong tier]** for constitution-critical, architecturally foundational, or ambiguous
  tasks. The constitution **[reviewer]** must ALWAYS run at-or-above the strong tier — the
  product-thesis check never downgrades, even when the task itself ran cheap.
- **[frontier tier]** only for genuinely long-horizon work — multi-hour autonomous scope,
  plan-and-port-scale changes. Rare: most tagged work is strong or cheap.
- When unsure, start cheap — CI + the reviewers backstop quality, and you can escalate.

## 0. Preconditions (stop if any fail)
- You're in the canonical repo working tree — `git rev-parse --show-toplevel` succeeds and is
  the project you intend to build (not a stray or cloud-synced duplicate). If not, stop.
- `git status` is clean and you are on an up-to-date base branch. If not, resolve first.
- The issue-tracker interface named by the active adapter's **[environment block]** is
  authenticated using that block's concrete check. If not, ask the user to authenticate
  the named interface before tracker-dependent steps.
- **Usage headroom:** if you're deep into a usage window, do ONE task and stop. An
  interrupted task is recoverable (commit + PR + the resume protocol), so never start work
  you can't checkpoint before the limit hits.

## 0.5 Run mode — review (default) or isolated autonomous
Decide the run's mode once, at the start, from the **[autonomy activation]** check — never from
model memory. It is deterministic and **fails closed to review** (the inverse of the [guard]).
- **Review mode (default).** Run exactly as written below: edit in the main working tree on the
  task branch (§4), open the PR, and **stop** for a human merge.
- **Isolated autonomous mode** — engaged only by an explicit in-session authorization or the
  profile opt-in. The task runs inside an **[isolated workspace]**: **enter** it in place of the
  plain branch (§4) and **tear it down** at the end; work happens there, never in the main tree.
  If entry fails, **abort the run** — never fall back to editing the main tree on the base branch
  (a silent fallback would run un-isolated autonomous work, the one thing isolation prevents).

The §7 gate now reads the workspace diff and the promote/discard path is wired (the gate-in-place
step). On a gate **PASS** the work is **promoted** — opened as a PR through this same §7-gated
path (§8); on a gate **FAIL** the **[isolated workspace]** is **discarded** and nothing is opened.
Promotion is always the §7 gate's PASS, **never a direct write from the workspace** to the base
branch (`workflow/README.md` → "[isolated workspace]"); a FAIL leaves the base branch untouched.
Crucially, **promotion is a PR, not a merge** — merging still requires session-explicit
authorization (§8), so an engaged autonomous run still ends at a PR, not on the base branch. A
deterministic falsification proof that an un-gated change cannot reach the base branch through the
lifecycle — plus a live probe that the isolation tier fires on a real driver — now backs this
property (the enforcing checks are named in the profile's invariant checklist).

## 1. Select the task
- If the user named a task ID, use it. Otherwise read the profile's **tasks file** and pick
  the **lowest-numbered unchecked task whose dependencies are met** (task-ID format per the
  profile).
- **Skip blocked tasks and say why.** Treat every task in the profile's **"Blocked /
  owner-only tasks"** list as non-startable — surface it, don't begin it.
- **Reconcile the candidate against live state before committing to it
  ([live-state reconciliation]).** A tasks-file checkbox drifts from reality — a task can be
  already merged or in-flight while its box still reads unchecked — so a *prose* "cross-check
  git/PRs" habit is exactly the model-judgment dependency a deterministic check should
  replace. Before selecting, a **deterministic precondition** — the runtime counterpart of
  CI's tasks-consistency backstop, **sharing** its logic rather than forking a second copy —
  reconciles the candidate's box against authoritative live `git`/tracker state. A candidate
  whose live state shows landed/merged work for its ID is **not selectable**: refuse it and
  surface the drift with its conflicting evidence (the commit/PR) instead of starting stale
  work (for an *implicitly* resolved auto-pick this same refusal is delivered by the
  announce-and-confirm step below as a pause for redirection — still never starting the
  candidate). This precondition currently reconciles against **landed/merged** evidence only;
  refusing a candidate that is merely **in-flight** — an open PR/branch with no landed work yet
  — is a known gap deferred to a tracked follow-up, not yet part of this check. The check
  **fails open** — when live state is unavailable it degrades to the prior behavior with a
  surfaced warning, never a hard stall.
- **Announce the resolved target, and confirm an implicit pick that live state contradicts
  ([selection announce-and-confirm]).** After the candidate is resolved, announce the resolved
  target — its task ID and issue — before the first file edit. Whether to also **pause for
  confirmation** is a deterministic decision, not a model "noticing": pause only when the
  selection was **implicit** (no task ID/issue was named) *and* live state **contradicts** the
  auto-picked candidate. The contradiction is the same done-but-unchecked drift reconciliation
  refuses on, but the two responses are **keyed to the pick's provenance**: an **explicit** stale
  pick is reconciliation's terminal refusal above (the user named it), whereas an **implicit**
  contradicted auto-pick is surfaced *here* as the confirm pause — reachable on the composed
  path, not pre-empted by the refusal. Either response invites a *redirect* and never starts the
  contradicted candidate. An explicit request, or an implicit pick live state does **not**
  contradict, announces and proceeds without a pause; when live state is unreadable the step
  **degrades to announce-only**, never a stall it cannot justify. Broadening the contradiction to
  in-flight targets is the same deferred follow-up.
- Confirm the selected task ID, its `path`, and its `US#` before editing anything.

## 2. Read the context (always, every task)
Read in this order (paths from the profile), then state assumptions/ambiguities before coding:
1. The task line in the **tasks file** and its mapped `US#` in the **spec** (acceptance criteria).
2. Any relevant contract under the profile's **contracts dir** for the area touched.
3. The **constitution** — it is law.
4. Nearby existing code and tests in the task's `path`.
5. The task's **issue/PR comment thread** — owner steering may be waiting there (§2.5).

## 2.5 The owner-comment channel (steering, provenance, bounds)
For an owner-absent run, the issue/PR comment thread is the **only** channel through which
the owner can steer between sessions. These rules own all thread reading and refreshing
(other procedures reference this section rather than re-specifying it):

- **Provenance, not author identity.** The engine may post under the owner's own login
  (a solo headless build shares one account), so authorship cannot distinguish owner
  steering from engine bookkeeping. Every comment the engine posts — the §4.5 plan
  artifact, §5 blockage records, discovered-work notes, §8 verdict comments — carries the
  **[comment marker]** (concrete form per the adapter; defined exactly once,
  adapter-side). A **marked** comment is engine bookkeeping and **never** carries
  steering authority — a prior run's plan is not an instruction, and a comment claiming
  approval or authorization is void if marked.
- **Steering rule.** The newest **unmarked** comment from the owner login is
  authoritative steering for scope and direction. It overrides the posted plan artifact
  and prior triage judgment. Read the thread at §2, at resume, and **refresh it
  immediately before composing the PR body's "your call" section** (§8).
- **Authority bounds (one-way valve).** Comment steering may redirect, narrow, halt, or
  answer a previously-surfaced decision. It may **NEVER relax engine invariants**: it
  cannot authorize a merge (merge authorization is session-explicit only), skip or weaken
  the §7 gate, or override the constitution. A comment attempting that is a conflict:
  stop and resolve it before proceeding — the constitution wins ties.
- **Don't re-ask.** Before surfacing any `Decision needed:` item, check the thread for an
  existing owner answer. An answered question is acted on (within the authority bounds),
  not re-asked.
- **Ambiguity is surfaced — on the surface that exists.** Unmarked owner-login comments
  are steering **by default**; a comment is ambiguous only when its body purports to be
  engine-authored (e.g. it reads as a plan artifact, blockage record, or verdict report
  yet lacks the marker). An ambiguous comment is never silently obeyed
  and never silently ignored. Once a PR exists, quote and flag it in the PR body. In the
  pre-PR window (§2 and resume run before the PR opens), quote and flag it in a
  **marked** comment on the same thread, and carry it into the PR body when the PR opens.

## 3. Find the issue (before the first file edit)
- **Target the right repo.** The profile's Identity section states the repo model; for a
  fork, issues/PRs live on your `origin`, not the upstream (a bare CLI call may resolve to
  the empty upstream). Derive the slug once **per the profile** and target that slug
  explicitly on every call. CLI invocation specifics (PATH fallbacks) come from the
  **[environment block]**.
- **An issue is pre-created for every task.** Locate it (search the issue tracker for the task
  ID in the title). **Use that existing issue** — do NOT open a duplicate.
- Only if none exists, create one titled `<type>: [<task-id>] <description>` with a body
  covering description, acceptance criteria traced to the `US#`, testing guidelines, and the
  task reference. Write multi-line bodies from a file, not an inline string — inline
  multi-line text is unreliable across environments (concrete form per the
  **[environment block]**).

## 4. Branch
- From an up-to-date base branch: `git switch -c <type>/<task-id>-<short-description>`.
- Never commit to the base branch. Never `git add .` — stage specific files only. (The
  **[guard]** enforces both deterministically where available.)
- **Isolated autonomous mode (§0.5):** instead of switching the main tree, **enter** the
  **[isolated workspace]** for this branch and run every later step inside it. Its end-of-run
  fate is driven by the §7 gate outcome, not a blanket teardown: **promote** it on a PASS,
  **discard** it on a FAIL (§8). Review mode uses the plain `git switch -c` above.

## 4.5 Plan artifact ([strong tier] and above — a checkpoint, not a gate)
Before the first file edit on a **[strong tier]** or **[frontier tier]** task (tagged, or
untagged-but-judged-strong per "Model & usage economy"), post a short plan as a comment on
the task's issue (multi-line body via a file, per the **[environment block]**; carrying
the **[comment marker]** per §2.5, like every engine-posted comment):
- **Approach** — a few sentences on the intended shape of the change.
- **Files to touch** — the expected list.
- **Test plan** — which tests will encode which acceptance criteria.
Then **proceed immediately. This is a checkpoint artifact, not an approval gate** —
autonomous runs do not pause on it and no reply is awaited. Its value: an alignment point
the owner can audit asynchronously; deterministic scaffolding that converges output shape
across models; and a durable recovery source for the resume protocol (the plan survives
context loss because it lives on the issue). **[cheap tier]** tasks skip it.

## 5. Implement (minimum scoped change)
- Keep changes surgical; every line traces to the task. No speculative abstraction.
- Respect the profile's **"Architecture boundaries"**: route each capability only through its
  named interface (never a vendor SDK from UI/component code), and never use a banned
  vendor/source listed there.
- For behavior changes, add/update meaningful tests incl. negative/edge cases.
- **Blocked by an external dependency? Mock it behind the seam — never abort.** When
  progress is blocked by something outside the repo (a provider API key, an unprovisioned
  service, an owner-only credential, an unreleased upstream), do all four:
  1. scaffold a **documented mock behind the existing interface seam** — the named
     interface from the profile's "Architecture boundaries", never inline in callers;
  2. record the blockage and the mock's location as a comment on the issue (marked, per
     §2.5);
  3. continue the task against the mock;
  4. list it in the PR body under **"Mocked dependencies"** (§8).
  Swappability is preserved by construction — the real provider later replaces the mock
  without touching callers. (Distinct from the profile's *blocked/owner-only task list*:
  those tasks are never started at all, per §1; this rule is for a task already legitimately
  underway that hits an external wall.)

## 5.5 Discovered work (file it, don't fix it)
Implementing one task often uncovers others — a bug, a missing test, a stale doc, a security
risk. Capture these durably WITHOUT widening the current diff. Classify each finding at the
moment of discovery:
- **Blocks this task?** If it prevents meeting the task's acceptance criteria, it is part of
  the task: record it on the issue and handle it in scope (or stop and surface it if it
  reshapes the task).
- **Concrete, actionable, out of scope?** Search the tracker for an existing issue first (no
  duplicates), and if none exists **file one now** — title per the issue convention, body
  self-contained (file/line evidence, enough context for a cold start) plus a "Discovered
  while working #N" line. When the bug's origin is traceable with bounded effort
  (`git log -S`/`-G`, `git blame`, linked PRs), add a one-line **provenance** note —
  `introduced by` / `made visible by` / `carried forward by` `<commit/PR>` — with an
  explicit confidence label: `clear`, `likely`, or `unknown`. **Say `unknown` rather than
  guessing**, consistent with §6.5's anti-fabrication posture (never report an unverified
  claim as established). Provenance is best-effort and **never a filing blocker** — an
  untraceable bug is filed with `provenance: unknown`, not held back. Filing at discovery
  time beats reconstructing from memory at PR time.
- **Vague hunch or trivial nit?** Note it in the PR body under "Out of scope, observed";
  don't spam the tracker.
- **Constitution or security finding already on the base branch?** Never optional: file it
  AND flag it prominently in the PR body.
The PR body (§8) lists what was filed under **"Discovered work"** (or "none"). The triage
[workflow] resurfaces open issues without a branch/PR every run, so a filed issue cannot be
lost — no human dispatch needed.

## 6. Verify (narrow → broad)
- Run the changed file's tests first, then the type-checker and linter.
- Run the full suite only once the diff is stable; log-and-summarize its output.

## 6.5 Definition of done
Engineering quality must be machine-verifiable, not taken on trust (see the profile's
**reviewer profile** — e.g. when the owner is not a developer, lean harder on this). A task is
not done until:
- **CI is green** — the profile's **required check**. A red check blocks merge via the
  profile's **merge-gate ruleset**. **Never bypass it.**
- **Behavioral changes ship tests** encoding the acceptance criteria AND every touched item
  from the profile's **invariant checklist**.
- **Constitution-critical files carry a scoped coverage threshold** per the profile's
  **coverage policy**, so coverage can't silently regress.
- **UI-touching tasks carry [visual verification] evidence.** Any task touching
  user-visible UI must attach machine-generated evidence of the running app to the PR —
  screenshots; video/animated capture for animation or transition work — produced by the
  runtime actually rendering the app, never described from the model's imagination
  (tests are code-shaped evidence; this is the evidence a non-developer owner can judge).
  The frame carries **fixtures only** — the evidence channel is typically public and
  permanent, so never real or imported user content or real locations; seed
  user-content-bearing screens with synthetic data first.
  If the runtime cannot produce it (tooling flake, headless run without a display/device),
  **degrade loudly, never silently**: the PR states **"tests only — no visual evidence
  produced"** and lists the affected surfaces as unverified — the flake surfaces as
  *unverified*; it neither blocks the pipeline nor passes silently.
- **The PR body separates "verified automatically" (engineering) from "your call"
  (product/values)** so a non-developer reviews only what they can judge. **Every claim
  under "verified automatically" must point to evidence from this run** — a command output,
  CI result, or reviewer verdict you can cite (reviewer verdicts are posted on the PR per
  §8, so the citation is checkable from the PR itself). Anything not actually verified goes
  under "your call" or is explicitly labeled unverified; never report it as done.
  Symmetrically, **every "your call" item ends with a one-line `Decision needed:` … /
  `Recommendation:` … pair** — purely-informational items state
  `Decision needed: none (informational)` — so the owner sees exactly what they are
  deciding instead of inferring it from an observation. A decision-ready item meets
  three further conditions, so a one-word reply is always enough to proceed:
  - **Exhaust autonomous work first.** Surface an item only when no autonomous work on
    it remains. If the engine can still narrow the question — run a test, check a doc,
    prepare the reversible default behind its seam (the §5 blocked-dependency instinct,
    generalized to decision items) — it does that first and surfaces the *narrowed*
    question, never a half-prepared one that forces the owner to do the analysis or
    bounce it back.
  - **Enumerate the exact choices and each one's consequence** (typically 2–3: the
    recommendation, the main alternative, and reject/defer), so the owner answers in a
    word instead of asking "what are my options?". Every offered choice must be fully
    answerable through the comment channel within §2.5's authority bounds — that valve
    is one-way, so **a merge/land is never an offered choice**. Where the natural intent
    is "ship it," the item states that answering applies the decision while merging still
    requires session authorization, so the one-word answer is always fully actionable and
    never partially obeyed. Purely-informational items keep the
    `Decision needed: none (informational)` form.
  - **Refresh the item's world-state immediately before surfacing it** — re-verify it is
    still live: not already resolved, and not made moot by a newer commit. (The
    thread-side half — already answered or settled on the issue/PR thread — is §2.5's
    "don't re-ask" and thread-refresh rules; this condition owns only the world-state
    half and does not restate them.)

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
3. Run a **[code-review pass]** (use a **[security-review pass]** if the change touches
   privacy, location, or in-app purchases). Where the adapter provides one, also run a
   **[craft-review pass]** for the craft layer (the review standard's dimensions 6–7:
   testing, failure handling, boundaries, resource control, observability, API/compat,
   simplicity). It is **advisory**
   and runs alongside the others — never a roster **[reviewer]**, so it does not gate by
   PASS/FAIL; surface its findings in the PR body (§8), triaged as blocking unless
   documented. Absent the mechanism, skip it and note the skip (review standard → "How an
   adapter degrades gracefully").
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

## 8. Open the PR — then STOP
**Review mode (default)** runs the bullets below and stops at the PR for a human merge.
**Under an engaged isolated autonomous run (§0.5), the terminal step is driven by the §7 gate
outcome:**
- **Gate PASS → promote.** The work is preserved and opened as a PR through the bullets below
  (the *same* §7-gated path), then the **[isolated workspace]** is torn down. Promotion is a
  **PR, not a merge** — do **not** merge unless the user authorized autonomous merging this
  session (§2.5: merge authorization is session-explicit only).
- **Gate FAIL → discard.** The **[isolated workspace]** is **discarded** — torn down together
  with its branch — and **no PR is opened**. The base branch is untouched. (This is the one
  place an autonomous run diverges from review mode, which would surface a FAIL in a PR body;
  with no human in the loop there is no one to read it, so failed work is thrown away whole.)

Promotion is **only ever** the §7 gate's PASS; the isolation mechanism never writes the base
branch directly (P4). The numbered bullets below are the promote path (and all of review mode):

- Commit your work on the branch FIRST (the §7 reviewers review `git diff main..HEAD`, empty
  until you commit). Stage specific files; never `git add .`.
- Open the PR against the base branch, titled `<type>: [<task-id>] <description>`.
- **Lead the body with a risk-ranked digest of what the §7 gate found** — the human
  reviewer's entry point, placed **first**, ahead of "verified automatically" and "your
  call", so scarce review time targets the riskiest parts of the diff instead of
  re-deriving them from raw verdicts. The digest is composed **only** from the §7 gate's
  outputs — the **[reviewer]** verdicts posted on the PR (the per-reviewer comments below)
  and the gate-run record (`telemetry.md`) — **never** from maker self-assessment: every
  digest line **links to or quotes the verdict text it came from**, and a claim with no
  verdict source does not belong in the digest. In risk order it carries:
  - **Near-misses** — anything a reviewer **FAILed then cleared** after a fix this run,
    whether it ended **PASS or JUSTIFY** (a FAIL→JUSTIFY reviewer is a near-miss *and* a
    JUSTIFY item, listed under both — the FAIL report is the near-miss evidence, the final
    JUSTIFY is the documented deviation). The per-reviewer comment carries only the latest
    (PASS/JUSTIFY) verdict, so each near-miss instead quotes or links the verbatim FAIL
    report text retained in the gate-run record's `fail_reports` (`telemetry.md`; the
    telemetry record is US1's; §7.5). State the empty case explicitly (e.g. "none — the
    gate passed first try") rather than omitting it.
  - **JUSTIFY items** — every reviewer verdict of JUSTIFY **quoted verbatim**, with the
    documented deviation (a JUSTIFY clears the gate only with its deviation recorded here).
  - **Invariants the diff touched** — the profile's invariant-checklist items the change
    intersects, each pointing to the verdict that graded it.
  - **1–3 recommended human focus areas** — the riskiest spots for a human to read, each
    with a `file:line` reference and each tracing to one of the sources above (a near-miss,
    a JUSTIFY, or a touched invariant) — never a maker opinion no verdict backs.
  The digest **leads and links down to** the verbatim per-reviewer verdict comments
  ("Attach the gate's evidence" below), which remain on the PR **unmodified** — the digest
  summarizes and points; it never replaces, edits, or restates a verdict in place of it.
  A live-verdict comment link only resolves once that comment exists, so the digest's
  links to live verdicts are filled in by the body-update step below — composing the body
  before the comments are posted would leave them dangling. (A near-miss instead
  quotes/links the `fail_reports` text, which exists before the PR, so it needs no update.)
- **Pass the body via a file, never inline.** Inline bodies with embedded quotes/parens
  are unreliable across environments, and the temp `.md` must reach the CLI as UTF-8 —
  both concrete forms come from the **[environment block]**. The body must contain
  `Closes #<issue-number>`, a
  **"Discovered work"** line listing the issues filed under §5.5 (or "none"), a
  **"Mocked dependencies"** line whenever §5's blocked-dependency rule fired (which seam,
  the issue comment recording it, and — for each mocked seam — the `US#` acceptance criteria
  whose verification currently runs **against the mock rather than the real dependency**,
  listed as **live-unverified**; mock-verified is reported as mock-verified, never as done —
  the same degrade-loudly posture §6.5 applies to absent visual evidence, so the criterion
  neither blocks the pipeline nor passes silently), and a
  **"Run economics"** line — the tier, model, and effort that actually ran this task, plus
  any round-up/degradation applied (over time this is the evidence for re-tuning tier
  tags). Its **"verified automatically"**
  section cites the reviewer-verdict comments (next bullet) as its evidence for gate claims,
  rather than restating maker-written summaries of them. Every **"your call"** item meets
  §6.5's decision-ready contract — the **Decision needed / Recommendation** pair, autonomous
  work exhausted, the exact comment-answerable choices enumerated (merge never among them;
  purely-informational items keep the `Decision needed: none (informational)` form, no
  choices), and the world-state refresh — composed alongside the §2.5 thread refresh below.
- **Refresh the thread before composing "your call"** (§2.5): re-read the issue/PR
  comment thread; act on any newer unmarked owner-login steering (within the §2.5
  authority bounds), do not re-ask a `Decision needed:` the owner already answered there,
  and quote/flag any provenance-ambiguous comment in the PR body per §2.5's ambiguity
  rule.
- **UI-touching task? The [visual verification] evidence attaches in the body's
  "your call" section** — screenshots/video per §6.5, embedded so they render on the PR
  itself (the owner judges the UI by looking at it, not by reading code). On the
  degradation path, the explicit **"tests only — no visual evidence produced"** statement
  goes in the same place, with the affected surfaces listed as unverified. The concrete
  attachment mechanism (how an image reaches the PR body from this environment) comes
  from the **[environment block]**.
- **Attach the gate's evidence.** Post each §7 reviewer's saved verdict report to the PR as
  a comment — one comment per reviewer, verbatim, **including PASS results**, each
  carrying the **[comment marker]** (§2.5) — using a file
  for each body (same file-based rules as the PR body). The verdicts must be readable on the PR
  itself, not only in the session transcript: that is what lets the post-PR review shrink to
  "read the verdicts, spot-check, merge".
- **Then update the PR body so the digest's live-verdict links resolve.** A comment URL
  exists only after the comment is posted, and a comment needs the PR — so the order is
  unavoidable: open the PR → post the per-reviewer verdict comments above → **update the
  body** to point each digest link at a live verdict (a JUSTIFY item, the verdict that
  graded a touched invariant, the verdict a focus area traces to) at its just-posted
  comment URL. The update edits **only the digest's link targets** in the body; the posted
  verdict comments stay byte-for-byte **unmodified** (AC3). Near-miss entries already
  quote/link the `fail_reports` text and are unaffected. (If the runtime cannot edit a body
  after creation, degrade loudly: state in the digest that the live-verdict links point to
  the per-reviewer comments **below on this PR** rather than to per-comment URLs, and say
  why — never leave a dangling link.)
- Capture the create command's output and print it; then verify the PR's state and checks
  (including the merge-gate status).
- Report the PR link and review/check status. Before reporting, audit each claim against a
  tool/command output from this session — report only what you can point to evidence for; if
  something is not yet verified, say so explicitly. **Do not merge** unless the user has
  explicitly authorized autonomous merging this session.
