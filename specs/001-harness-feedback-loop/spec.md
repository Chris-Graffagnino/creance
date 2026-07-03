# Spec — Harness Feedback Loop ("self-tightening harness")

> Epic for the Creance repo itself. The acceptance [reviewer] (`spec-auditor`) grades
> each task against the `US#` acceptance criteria below — bullets are addressable as
> `US1.AC1`, `US1.AC2`, … (the nth bullet under that story).

## Overview

Creance verifies every task but never updates itself based on what verification
found. This epic closes that loop: every gate run leaves a machine-readable
record, escaped defects are back-tested against the auditors and converted into
tightened hunt rules or new invariants, PR bodies are restructured to minimize
human review time (the binding constraint), and the verification machinery
itself is monitored for silent decay. Done means: a project running Creance for
three months has measurably different (tighter) reviewer specs and invariant
checklists than it started with, and can show the evidence trail for each change.

Motivation and provenance: issue #18; adapted from the retrospective-review
technique described in Anthropic's "When AI Builds Itself"
(https://www.anthropic.com/institute/recursive-self-improvement).

## Non-goals

- No model fine-tuning or prompt auto-rewriting — all tightening lands as
  human-reviewed PRs against reviewer specs / `PROJECT.md`, never silently.
- No dashboards or visualization; telemetry is append-only JSONL read by triage.
- No changes to gate semantics (round limits, veto authority, tier floors stay).
- No retroactive sweep of historical defects; the retrospective runs per-incident.
- No tier auto-reassignment from telemetry, and no cross-project telemetry
  aggregation — each project's loop is its own.

## User stories

### US1 — Gate telemetry
As a harness operator, I want every §7 gate run to emit a machine-readable
outcome record, so that auditor behavior and task cost become trends I can
inspect rather than anecdotes.

**Acceptance Criteria**
- AC1: The workflow layer defines a runtime-neutral telemetry record (task ID,
  per-auditor verdict per round, fix-round count, tier dispatched per auditor,
  convergence outcome, timestamp, and — for FAIL verdicts — the verdict report
  text) and names where it is stored via `.claude/PROJECT.md` → "Paths".
- AC2: The Claude Code gate loop produces exactly one record per gate run —
  the loop builds the record payload on every return path, and its dispatcher
  appends it after the run returns (the loop's runtime has no clock or
  filesystem); a failed telemetry write never blocks or fails the gate itself.
- AC3: The guard hook appends a record for every blocked action (rule fired,
  tool, timestamp) to the same telemetry location, plus an evaluation record
  on at least one path guaranteed to fire during every gate run (e.g., the
  strong-tier floor check on the constitution-auditor dispatch), so guard
  liveness is distinguishable from "nothing to block"; logging failures never
  change guard exit behavior.
- AC4: Guard regression tests cover both logging paths (block records and
  evaluation records), including the failure-stays-silent case.
- AC5: The `gate-run` record carries a reference to the introducing change —
  the head commit of the diff the gate audited — stamped by the dispatcher at
  append time (the loop's runtime has no clock or filesystem), so the
  retrospective's Fact B attribution (US3) can be tied to the exact diff a gate
  graded rather than inferred from timing. The reference is observe-only: read
  only by the human-reviewed retrospective, never by any gate, tier resolution,
  or guard — it changes no gate semantics and no tier floor (a reference is not
  a model ID, so the tier-name discipline is unaffected).

### US2 — Triage trend surfacing
As a harness operator, I want the morning triage snapshot to surface telemetry
trends, so that recurring auditor failures and discovered-work clusters point
me at misplaced boundaries and missing specs.

**Acceptance Criteria**
- AC1: The triage snapshot includes a "Gate trends" section: FAIL counts by
  auditor over the snapshot window, tasks that hit the non-convergence stop,
  and tier-escalation events.
- AC2: The triage snapshot includes a "Discovered-work clusters" section
  grouping open discovered-work issues by subsystem/path, flagging any cluster
  of 3+ as a possible missing spec.
- AC3: The "Gate trends" section is read-only over telemetry (never writes or
  mutates it) and renders an explicit "no data yet" state when no telemetry
  exists, rather than erroring or being silently omitted.
- AC4: The "Discovered-work clusters" section is read-only and renders an
  explicit empty state when no open discovered-work issues exist, rather than
  erroring or being silently omitted.

### US3 — Retrospective back-test
As a harness operator, when a defect or constitution violation is found on the
base branch, I want a retrospective workflow that re-runs the auditors against
the historical diff that introduced it, so that every escape converts into a
tightened hunt rule, a new invariant row, or a documented known-gap.

**Acceptance Criteria**
- AC1: A runtime-neutral workflow doc defines the retrospective: input is a
  commit/PR reference plus defect description; the auditors are dispatched
  read-only against that historical diff exactly as the gate would have run
  them.
- AC2: The retrospective classifies the outcome as one of: WOULD-HAVE-CAUGHT
  (auditors FAIL the historical diff and the gate was skipped or misconfigured
  for that change), INCONSISTENT-CATCH (auditors FAIL it now but the gate ran
  and passed — nondeterminism, or rules tightened since), HUNT-RULE-GAP
  (auditors still pass it under current rules), or INVARIANT-GAP (nothing
  documented covers the defect), with file:line evidence.
- AC3: For HUNT-RULE-GAP and INVARIANT-GAP, the retrospective produces a
  proposed edit (reviewer spec change or invariant checklist row) as a normal
  PR through the standard issue/branch/gate flow — it never edits rules
  directly.
- AC4: The constitution auditor runs at strong tier in retrospectives, same
  floor the guard enforces for gate runs.
- AC5: A Claude Code skill binding exposes the workflow, which dispatches the
  existing reviewer roles read-only — no new binding-contract role is created —
  and dispatches the constitution auditor at or above the strong-tier floor
  (AC4), so the binding itself is reviewed against the floor, not just the
  workflow doc.
- AC6: A conformance probe for the retrospective workflow is added and passes
  on the live adapter, with results recorded.

### US4 — Risk-ranked PR digest
As a human reviewer, I want every PR body to lead with a risk-ranked digest of
what the gate found, so that my scarce review time goes to the riskiest parts
of the diff instead of re-deriving them from raw verdicts.

**Acceptance Criteria**
- AC1: The PR body template in the next-task workflow leads with a digest:
  near-misses (anything FAILed then fixed), all JUSTIFY items quoted verbatim,
  invariants the diff touched, and 1–3 recommended human focus areas with
  file:line references.
- AC2: Every digest claim links to or quotes the auditor verdict text it came
  from — live verdicts on the PR, or the telemetry-retained FAIL report text
  for near-misses (US1.AC1); the digest contains no maker self-assessment that
  lacks a verdict source.
- AC3: Verbatim verdicts remain on the PR as the per-reviewer comments the
  next-task workflow already specifies, unmodified; the digest leads the PR
  body and links to them.

### US5 — Verification-machinery freshness
As a harness operator, I want triage to detect when the guard or probe results
have gone stale, so that a silently dead guard is surfaced in days, not
discovered by the next adapter port.

**Acceptance Criteria**
- AC1: Probe runs record a fingerprint (content hash) of the guard script and
  the hook wiring (settings matcher) alongside their results.
- AC2: Triage flags PROBES-STALE when the current fingerprint differs from the
  last recorded probe run, and reports the age of the last probe run.
- AC3: Triage flags GUARD-SILENT when telemetry shows zero guard *evaluation*
  records (US1.AC3) over a window in which gate runs occurred (heuristic,
  reported as a warning not an error).

### US6 — Issue intake
As a project owner whose entire UI is the issue tracker, I want plain-language
issues I file to be detected and formalized into the backlog as reviewable PRs,
so that owner-requested work enters task selection instead of being walked past
indefinitely, and I ratify the harness's scoping by merging.

**Acceptance Criteria**
- AC1: The triage snapshot includes an "Unmapped tracker work" section — open
  issues whose title carries no task ID (format per `.claude/PROJECT.md`) and
  which no live tasks-file line references — one line per issue (number,
  title, age), with an explicit empty state when none exist; when non-empty
  the section ends with a pointer to run the intake [workflow]. Triage itself
  remains read-only: it detects, it never converts.
- AC2: A runtime-neutral intake workflow doc classifies each unmapped issue
  into exactly one of five buckets — spec work, repo-maintenance, bug against
  the base branch, duplicate, underspecified — and screens every conversion
  against the constitution before drafting: a request that conflicts with a
  principle is surfaced on the issue, never silently converted.
  Underspecified issues get a decision-ready ask (exact choices enumerated,
  recommendation attached) and are skipped — owner intent is never guessed
  into acceptance criteria.
- AC3: Conversions land only as PRs through the standard branch → gate flow:
  intake never edits a live tasks file or spec on the base branch, the
  conversion PR never closes the source issue (the owner ratifies the
  formalization by merging; the issue stays open for the work itself), and
  drafted task IDs are append-only — the next free ID, never renumbering.
- AC4: Each converted issue is retitled to the `<type>: [T###] <description>`
  convention and carries a marked harness comment (per the [comment marker]
  provenance rules) stating the assigned task ID and the drafted acceptance
  criteria.
- AC5: A skill binding exposes the intake workflow on the active adapter; no
  new binding-contract role is created — intake composes existing roles.
- AC6: A conformance probe for the intake workflow (a synthetic unmapped
  fixture issue; verify classification and drafting occur with no edits
  outside the intake branch) is added to the neutral probe checklist,
  instantiated for the active adapter, and passes on it with results recorded.

### US7 — Triage surfaces unacknowledged owner steering
As a project owner whose only steering channel between runs is the issue/PR
comment thread, I want the morning triage snapshot to surface owner comments the
harness has not yet acknowledged, so that steering I leave between runs is
provably seen instead of sitting unread until next-task happens to touch that
thread.

**Acceptance Criteria**
- AC1: The triage snapshot includes an "Unacknowledged owner comments" section —
  for each open issue and PR, unmarked owner-login comments (per the
  [comment marker] role) newer than the last harness-marked activity on that
  thread — one line per comment (item number/URL, comment date, first line of
  the comment), with an explicit empty state when none exist, rendered
  consistently with the other snapshot sections (never silently omitted).
- AC2: The workflow defines "last harness-marked activity" on a thread as the
  newest [comment marker]-marked comment or cross-referenced harness commit/PR
  event; when no marked activity exists, any owner comment newer than the item's
  last cross-referenced harness action counts as unacknowledged.
- AC3: The detection is read-only — triage posts no comment, marks nothing, and
  mutates no thread or repo state; acting on a surfaced comment remains the
  next-task [workflow]'s job, consistent with triage's existing read-only
  contract.
- AC4: The section references the [comment marker] role only — never a concrete
  marker string, tool, vendor, or model name — preserving the `workflow/**`
  grep discipline.

### US8 — Configurable review-pass set
As a Creance user, I want to change which review passes run during `pr-review`
(and the §7 gate's advisory layer) by editing a declarative list in
`.claude/PROJECT.md`, so that I can add, disable, or re-scope a skill-backed pass
without editing the runtime-neutral engine and without any enabled pass silently
falling out.

**Scope & recorded trade-off calls** (documented here so the calls are explicit, not
silent). The configurable surface is the **skill-backed review passes only** — the
`[code-review pass]`, `[security-review pass]`, and `[craft-review pass]` roles. The
**law-bearing auditors** — the acceptance / constitution / contract / spec-quality
`[reviewer]`s (the full §7 roster) — are **out of scope**: they stay governed by the
§7 reviewer roster (`gate-loop.md`)
and its ratchet, preserving maker≠checker and constitution-as-law. A profile list that
could disable the constitution auditor would hand a convenience surface veto authority
over law (constitution P4), so AC5 forbids it. This configures the **advisory**
skill-backed passes only; it **changes no gate semantics** — round limits, veto
authority, and tier floors are unchanged (epic Non-goals), and the gating roster
reviewers remain non-configurable. Two further v1 calls are recorded: (1) registering
an **arbitrary new skill** as a pass — adding a new `[pass]` role plus its adapter
mapping — is **out of v1 scope** (deferred to a later phase); v1 makes the three
existing passes configurable. (2) A pass's `applies-to` defaults to **both** the §7
gate and `pr-review`, honoring "pr-review reuses the gate's passes." (3) The v1 `condition`
vocabulary is the closed two-value enum `always` / `sensitive-diff` — the run-conditions
the three shipped passes actually use (code-review / craft = `always`; security-review =
`sensitive-diff`). `sensitive-diff` **reuses the existing `[security-review pass]` trigger
surface** from the review standard (the profile's privacy / location / payment invariants)
rather than defining a new sensitivity surface, so v1 introduces no parallel source of
truth; adding further `condition` values is **out of v1 scope**, like the
arbitrary-new-skill registration deferred above.

**Acceptance Criteria**
- AC1: `PROJECT.template.md` gains a `## Review passes` section documenting the column
  schema (`pass (role) | enabled | condition | applies-to`) with **every column's domain
  closed and typed**: `pass` is one of the closed set of legal skill-backed pass roles
  (`[code-review pass]`, `[security-review pass]`, `[craft-review pass]`), `enabled` is a
  boolean, `condition` is one of the closed enum `always` (the pass runs on every
  invocation of its applicable surface) / `sensitive-diff` (the pass runs only on a diff
  touching the **same security-sensitive surface the `[security-review pass]` already
  guards** — the profile's privacy / location / payment invariants, defined once in the
  review standard (`workflow/README.md`, `[security-review pass]` row); `sensitive-diff`
  **reuses that single definition** rather than introducing a parallel surface, so the
  condition resolves through one canonical anchor — the review-standard row — with no
  parallel definition added here), and `applies-to` is one of the
  closed enum `gate` / `pr-review` /
  `both`; each pass role appears **at most once**
  (duplicate rows are illegal). The active `.claude/PROJECT.md` carries one well-formed row
  per currently-shipped skill-backed pass with its real `enabled` / `condition` /
  `applies-to` values (a placeholder or empty section does not satisfy this — the rows must
  be the real, consistent set the roster test in AC4 validates, every column domain
  included).
- AC2: All three pass-selection surfaces — `pr-review.md`, the review standard
  (`workflow/README.md`), **and the §7 gate's advisory-pass step (`next-task.md` §7
  step 3)** — select which passes run **by reference to "the profile's review-pass set"**
  ([roles] only) and carry **no hardcoded enumeration** of the specific passes. Both
  directions are required and separately checkable per file: the reference is present
  **and** the hardcoded pass list is gone, with the `workflow/**` neutrality grep (no
  skill / vendor / mechanism names) passing over all three files. (The §7 gate is named
  here because the user story makes its advisory layer configurable too; without this
  surface the `applies-to: gate` column would never be read.)
- AC3: Each surface runs exactly the enabled passes whose `condition` holds **and whose
  `applies-to` includes that surface** — `pr-review` runs the passes with `applies-to` in
  {`pr-review`, `both`}, the §7 gate's advisory step runs those with `applies-to` in
  {`gate`, `both`} — so the `applies-to` column is load-bearing, not decorative (an
  enabled `applies-to: gate` pass must run in the gate; an `applies-to: pr-review` pass
  must not). `pr-review`'s §5 output enumerates each enabled pass it ran with its outcome.
  The two not-run cases are **distinguished**, penalizing both directions: a **disabled**
  pass produces **no** output line (silent — a project choice), while an **enabled** pass
  whose backing mechanism is **absent** is reported **loudly** (named in the PR body as
  unavailable — the review standard's existing "Note the degradation in the PR" rule,
  `workflow/README.md`), never silently dropped. Treating the two cases identically (all
  silent, or all loud) does not satisfy this. Because this enabled-but-absent → loud path
  is the silent-drop case the whole story exists to prevent, it is **pinned by a planted
  negative check, not left to runtime discretion**: the per-enabled-pass conformance probe
  in AC6 carries it (an absent-mechanism fixture asserting the loud unavailable line is
  emitted, not a silent drop).
- AC4: A deterministic `review-pass-roster.test.sh` (sibling to `reviewer-roster.test.sh`),
  wired into CI `verify`, **pins the profile rows against the adapter-mapped, currently-
  shipped skill-backed pass set** — the same parity discipline `reviewer-roster.test.sh`
  enforces for the §7 roster — and **FAILs on each of four planted defects**: (1) an
  `enabled` pass row whose role has **no adapter mapping**; (2) an **adapter-mapped shipped
  pass with no profile row** — the silent-drop parity gap: once AC2's surfaces read the
  list, an omitted pass disappears from every surface and nothing else catches it (testing
  "a workflow runs a pass the list omits" cannot, since the workflow now reads the list);
  (3) a **duplicate row** for a pass role; and (4) a row with an **off-enum `condition` or
  `applies-to`** value — **and PASSes on the real, consistent roster**. The paired
  flag-the-defect / pass-the-clean-control shape is required: a test that only ever FAILs
  (one-sided) does not satisfy this.
- AC5: The configurable list governs **only** skill-backed passes. A `## Review passes`
  row that names or disables **any §7 roster `[reviewer]` — acceptance / constitution /
  contract / spec-quality, i.e. every law-bearing auditor on the roster (`gate-loop.md`),
  not only the original three** — is **rejected** by `review-pass-roster.test.sh`, while a
  list containing only skill-backed passes is **accepted** — both directions checkable —
  so the maker≠checker / constitution-as-law boundary cannot be edited away through the
  profile (constitution P4). The test derives the rejected set from the roster, so a future
  reviewer added to `gate-loop.md` is fenced too, not silently left configurable.
- AC6: A per-enabled-pass conformance probe (the existing `P-CRAFT` probe generalized to
  every enabled pass) is added to the neutral conformance-probe checklist, instantiated
  for the Claude Code adapter, and **run on the live adapter**, with results recorded in
  the adapter probe-results table. Each recorded result must **cite an independently
  readable artifact** — a log excerpt, an invocation record, or dated output a cold-start
  reviewer can read and confirm shows the pass was **actually dispatched**; a bare
  `dispatched: yes` / `PASS` self-assertion with no supporting artifact does **not**
  satisfy this (closing the self-certification gap in both directions — a real dispatch
  is evidenced, a vacuous or fabricated one cannot pass). The probe is additionally
  **two-sided on availability**: beyond evidencing dispatch of an enabled, *available*
  pass, it must exercise the **enabled-but-mechanism-absent** branch from AC3 — a fixture
  in which an enabled pass's backing mechanism is made absent must show the run going
  **loud** (the pass named unavailable / degraded, per the review standard's "Note the
  degradation in the PR" rule), never silently dropped, that outcome likewise evidenced by
  a recorded artifact. A probe that only ever exercises the available path does not satisfy
  this.

### US9 — Effective-fix-rate trend (submission efficiency)
As a harness operator, I want triage to surface what fraction of gate fix rounds convert
a reviewer FAIL into a cleared verdict, so that how well the maker turns reviewer
feedback into accepted fixes becomes an inspectable trend rather than an anecdote.

Motivation: EdgeBench (ByteDance Seed, 2026-07-02,
https://edge-bench.org/paper.pdf §5.1) finds submission *efficiency* — not submission
count — separates strong from weak agents; the weak-agent signature ("over-trust local
proxies, bundle unrelated edits, continue exploration after feedback ruled a direction
out") is measurable from the existing gate-run records. Intake of issue #209.

**Acceptance Criteria**
- AC1: The telemetry doc's Consumers section defines the **effective-fix rate** as a
  read-only derivation over existing `gate-run` records — a **flip** is a reviewer whose
  verdict is FAIL in round *n* and PASS or JUSTIFY in round *n+1* of the same run; the
  rate is flips over FAIL-triggered re-dispatches, aggregated per snapshot window and
  broken out per auditor — introducing **no new record type, no schema change, and no
  writer change** (the derivation reads the stream exactly as US2's trends do).
- AC2: The triage snapshot's "Gate trends" section (US2.AC1) renders the effective-fix
  rate for the window **with its numerator and denominator shown** (never a bare
  percentage), computed by a deterministic recipe a non-scorer can re-run (constitution
  P3 — never model estimation), read-only over telemetry (the US2.AC3 posture), with an
  explicit "no fix rounds in window" state — distinguished from a genuine 0-of-N rate —
  and the existing "no data yet" state when no telemetry exists; neither state may be
  silently omitted or rendered as an error.
- AC3: The derivation ships with a fixture-backed test over a planted telemetry stream
  containing at least: a run with a FAIL→PASS flip, a run with a FAIL→JUSTIFY flip, a
  non-convergence run whose FAIL never cleared, and a pass-first-try run — asserting the
  first two each count once in the numerator, the first three contribute their
  re-dispatches to the denominator, the pass-first-try run contributes nothing, and both
  empty states from AC2 each render. A test that exercises only the happy path does not
  satisfy this.
- AC4: The rate is observe-only (constitution P5): it is rendered by triage and citable
  by the human-reviewed retrospective, and no gate, tier-resolution, guard, or selection
  path reads it; the derivation writes nothing to the stream.

### US10 — Retry consumes prior gate verdicts (experience retention)
As a harness operator, I want a retry of a task — after a gate non-convergence stop or a
PR round-trip — to start from the prior attempt's reviewer verdicts instead of cold, so
that feedback the gate already produced converts into progress instead of being
discarded with the session.

Motivation: EdgeBench §5.2 ablates continuous experience against independent restarts
under the same time budget (+6.9 points): accumulated feedback history, not extra
attempts, drives the gain. Identical starts are a harness property; discarding paid-for
verdicts on retry buys no safety. Intake of issue #210.

**Acceptance Criteria**
- AC1: The retry procedure lives in a workflow sub-doc referenced by pointer from
  `next-task.md` (whose line-budget check stays green — the accretion-sink rule), and
  defines the posting half: when a gate returns non-convergence, the dispatcher posts the
  blocking reviewers' verdict reports **verbatim, keyed by auditor and round**, as a
  **[comment marker]**'d comment on the task's issue — an empty or summarized posting
  does not satisfy this — so the feedback survives the session on the tracker channel.
- AC2: The same sub-doc defines the consuming half: a retry of the task (resume, or
  re-selection of the same task ID) reads the newest such marked retry comment as maker
  input before re-implementation, addressing each recorded finding or stating why not —
  while the comment, being marked, carries **no steering authority** (`next-task.md`
  §2.5) and relaxes nothing: every reviewer still re-runs from scratch on the retry's own
  diff, and **no prior verdict — PASS included — is carried forward as a current
  verdict**; a retry that skips a reviewer because it passed last time violates this
  criterion.
- AC3: The retry input's source is the issue's marked comment — the tracker channel —
  never the telemetry stream: the sub-doc states this boundary explicitly, and no retry,
  selection, or gate path reads telemetry to obtain the verdicts (constitution P5
  unchanged: the stream keeps zero consumers with control authority).
- AC4: A `DESIGN-NOTES.md` entry records the tension this story resolves — identical
  starts (harness determinism) versus experience retention (EdgeBench §5.2) — and its
  resolution: starts stay identical for the harness machinery; feedback history persists
  on the tracker.
- AC5: A conformance probe covers both directions: a simulated non-convergence return
  produces the marked retry comment carrying the verbatim reports, and a gate PASS
  produces no retry comment — a probe exercising only the posting path does not satisfy
  this.
