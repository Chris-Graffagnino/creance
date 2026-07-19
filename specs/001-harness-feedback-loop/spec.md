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
As a harness operator, I want a retry of a task after a gate non-convergence stop to
start from the prior attempt's reviewer verdicts instead of cold, so that feedback the
gate already produced converts into progress instead of being discarded with the
session. Scope: the posting half fires on gate non-convergence only — a passed-gate PR
round-trip has no blocking verdicts to persist, and human PR-review feedback lives on
the PR thread, outside this story; a retry that finds an existing marked retry comment
consumes it (AC2) regardless of what prompted the retry.

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
  input before re-implementation — when no such comment exists, the retry proceeds as
  an ordinary cold start, never an error — addressing each recorded finding or stating
  why not —
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

### US12 — Bounded maker retry and structured blocking owner contact
As a harness operator, I want a run that keeps failing the same deterministic check to
stop and ask rather than retry indefinitely, and I want every comment that *blocks* on my
answer to state exactly what is being asked and what counts as an answer, so that a
session cannot spin on a broken approach and an ambiguous reply is never mistaken for
consent.

Motivation: two residual gaps against 12-factor-agents, which Creance already satisfies
structurally in about ten of twelve places. Factor 9 (compact errors into context, bound
consecutive failures, then escalate) is implemented at the §7 gate by the two-round
non-convergence stop, but the **maker's inner loop** — verification failures, edit-guard
rejections, flaky checks, failed pushes — has no formalized bound. Factor 7 (human contact
as a structured call) is partly implemented by the `Decision needed:` / `Recommendation:`
pair, which this story **extends** rather than replaces. Intake of issue #296.

**Recorded trade-off calls.**
- **The decision-ready pair is extended, not superseded.** The issue frames blocking
  comments as free text; that is only half true — §6.5 already requires a
  `Decision needed:` / `Recommendation:` pair with enumerated choices, an
  exhaust-autonomous-work-first rule, and a world-state refresh. US12 adds machine-readable
  answer semantics on top of that contract. Defining a parallel schema would contradict an
  unchanged §6.5, so every criterion below composes with it.
- **A structured answer never becomes authority.** The pair already forbids a merge/land as
  an offered choice (§2.5's one-way valve). Making answers machine-parsable would otherwise
  create exactly the channel the merge rules exist to deny — so AC7 states the exclusion
  explicitly and extends it past merge to autonomy activation, which neither §2.5's
  enumerated list nor the family-wide write-intent exclusions name at all. (Gate semantics
  *are* named by both, so AC7 restates rather than extends there; what neither pins is a
  deterministic **check**, which is why AC7 assigns falsification to that arm.)
- **No new backlog-loop outcome, and no new obligation row.** AC2 is deliberately confined
  to a **review-mode stage halt**. The `[backlog-loop]`'s outcome grammar keeps its four
  tokens *and their documented causes*, so maker retry exhaustion does not enter that grammar
  in this story: `gate FAIL + discard` would fabricate a §7 result that never occurred, and
  `aborted` remains reserved for a lifecycle or activation check failing closed. A future
  backlog-loop route requires its own outcome-and-accounting contract change. The next-task
  obligations inventory "guards preservation, not accretion", so US12's executor obligation
  is carried in the stage card and a docs-encoding test, not appended to the frozen ratchet.
- **The bound's counter is durable, and its source is the tracker.** A resumed run cannot
  read a counter from conversation memory. Its sole durable source is the tracker channel —
  never the run's transient return value or the telemetry stream, whose `fix_rounds_used`
  field is the convenient and forbidden implementation (AC1, mirroring US10.AC3's boundary).

**Acceptance Criteria**
- AC1: For a **review-mode** run, `next-task.md`'s implement/verify territory carries a runtime-neutral
  **bounded-retry rule** with both of its terms defined, because neither is inferable.
  **"The same check"** is defined positively by a normalized invocation signature: the
  declared check/checker name, its repository-relative working directory, its stable
  target or scope, and its ordered stable arguments and selected configuration inputs.
  Distinct signatures never contribute to the same counter; one constant identity for all
  checks is non-conforming. The signature is **insensitive to run-varying content** —
  error-message payloads, timing/duration, absolute-path prefixes, and result ordering are
  excluded — because an identity that varies per run makes the bound unreachable while
  leaving identical-failure tests green. **"A distinct intervening
  change"** is defined by its **content**, not merely by its role: a change to the artifact
  under test, or to an input the failing check actually reads. A retry with no change, a
  retry after an edit the failing check does not read, and a mandated response to a stall
  all leave the counter **intact** — otherwise "any edit resets it" makes three
  *consecutive* failures unreachable and the bound silently dead, the same evasion the
  identity half closes. If the executor cannot establish that the check reads a changed
  input, it treats that input as unread and leaves the counter intact. The rule states
  explicitly that a mandated stall response does not reset it — decomposing a stalled failure into
  subproblems (the unchanged §5 rule) starts a counter for any new check it introduces while
  the original check's counter persists, so the bound stays reachable in exactly the spin
  scenario this story exists to stop. The rule is **two-sided**: the run does **not**
  escalate before the third consecutive failure of the same check, and does **not** continue
  retrying past it. A rule stating only an upper bound does not satisfy this — an
  implementation escalating on the first failure would satisfy "never exceeds three". The
  counter must survive a resume, and its durable source across that resume is **the tracker
  channel** — the run's own return value carries only the terminal escalation outcome to its
  caller and does not outlive the run, so it cannot serve as the durable source; **no path
  reads the counter from the telemetry stream** (constitution P5, the
  boundary US10.AC3 states for the retry channel).
- AC2: On reaching the bound, a **review-mode** run compacts the failure evidence, posts it
  to the task's issue as a marked comment via the existing comment write-intent, and halts
  the stage. The `[backlog-loop]` route is explicitly **out of scope** for this criterion:
  no `gate FAIL + discard` result is emitted because §7 has not run, and `aborted` is not
  reused because its documented cause is a lifecycle or activation check failing closed.
  Any backlog-loop route must first define and test a distinct outcome plus its stop
  accounting; this story neither adds nor widens an outcome-grammar token or cause. It never
  silently continues and never merges. **Compaction is bounded by a stated number, not by the
  word "compact":** the
  criterion names an explicit ceiling (at most 50 lines or 4 KB, whichever is smaller) and
  requires the **exit code** and the **failing check's identity** to survive compaction.
  Falsification covers both misses: a full-log paste fails the bound, and an excerpt that
  drops the check identity fails the content requirement.
- AC3: The bound is encoded where the failures actually occur — the maker's inner loop —
  and the criterion **names that locus explicitly** rather than delegating to a counter that
  does not observe check failures. (The orchestrated gate loop's `fixRoundsUsed` counts
  *reviewer verdict rounds* against its own 2-round non-convergence bound; it never sees a
  verification failure, an edit-guard rejection, or a failed push. Encoding US12's bound
  there would either change §7 gate semantics — barred by this spec's own Non-goals — or be
  unreachable behind the existing non-convergence return.) The boundary cases are pinned
  **against a scripted stand-in for the review-mode maker loop — a fixture driver — regardless of
  whether the active adapter holds the counter as code**, so the test obligation never
  collapses to nothing when the honest answer is "executor discipline". They pin: no escalation at two consecutive
  failures, escalation at three, and a reset proven by a distinct intervening change followed
  by failures that do **not** escalate — plus a fourth case in which the same check fails
  three times with **differing output text** and still escalates, proving the identity is
  run-invariant per AC1, and a fifth case in which check A fails twice, a distinct-signature
  check B fails once without escalating, and A's third failure escalates A only, proving that
  distinct checks do not share a counter. A test covering only the escalation boundary does
  not satisfy this.
  Where the bound stays executor discipline, it is stated in the stage card and asserted by
  a **new docs-encoding test in the established `*-docs.test.sh` family** (the frozen
  stage-card hash check will not see a new rule, so it cannot serve here); the
  docs-encoding assertion is **additional to** the fixture-driver cases, never a substitute.
  It is **not** appended to the frozen obligations inventory, which guards preservation
  rather than accretion.
- AC4: The orchestration-level failure procedure is generalized from operator lore into a
  stated rule in `gate-loop.md` as a **new `## Orchestration-level failure and the prose
  fallback` section placed after "Constraints inherited"** — the doc's existing headings are
  What the loop owns / Inputs / The reviewer roster / The loop / The fix step / Verdict
  capture / Telemetry / Constraints inherited, none of which is a degradation-notes section,
  so the criterion creates a named home rather than pointing at prose in an untitled
  preamble: on an orchestration-level failure, make **one** fresh
  re-attempt, and on a failure **of the same class as the first** stop re-attempting and
  fall back to the documented prose path. "Same class" is defined as the same failing step
  plus the same diagnostic class. The diagnostic-class discriminator is defined positively
  as the step's stable reason code or error category; where the step emits neither, it is the
  exception/failure type plus the static message template after variable payloads are removed.
  The step name alone, or one constant class for every diagnostic from that step, is
  non-conforming. The class is **insensitive to run-varying content** (the same exclusion list
  AC1 names), so the rule is neither vacuous (byte-strict identity, where nothing ever repeats
  and re-attempts are unbounded) nor trivially satisfied (loose identity, where it always stops
  after one). A **paired fixture** pins both directions at the same failing step: a same-class
  second failure stops and falls back, while a different reason code/category from that step
  earns its re-attempt.
  The **routing predicate** separating AC1 from AC4 is stated outright, not posed: a
  failure inside the maker's own verify / edit / push work is **AC1's** (three strikes), and
  a failure of the orchestration mechanism itself — reviewer dispatch, diff provision, role
  or model resolution — is **AC4's** (one re-attempt). A failed push is the maker's work and
  is therefore AC1's, so the two rules cannot both claim it. The criterion also records that
  this re-attempt bound is **dispatcher-level** and changes no §7 round limit, veto
  authority, or tier floor, so it sits outside this spec's Non-goal on gate semantics — the
  same Non-goal AC3 invokes to bar a different gate-loop edit.
- AC5: The existing decision-ready contract (`Decision needed:` / `Recommendation:`) is
  **extended** — in place, not duplicated — for comments that **block** on an owner answer,
  with: the attempt identity, a monotonically increasing **ask sequence unique across all
  attempts for the task issue** that never resets when a new attempt starts, a
  `question_format` of **`yes-no | choice`**, the question, the enumerated
  options when the format is `choice`, and **the engine's action for each answer**.
  `free-text` is deliberately **excluded from the blocking enum**: §6.5's second
  condition requires the exact choices and their consequences be enumerated so the owner
  answers in a word, and a free-text blocking question cannot satisfy it — admitting the
  value would relax the very condition this criterion promises to preserve. The
  `Decision needed: none (informational)` form is preserved unchanged for non-blocking
  items, which may still carry prose. The extension composes with §6.5's three existing
  conditions rather than restating or relaxing any of them; a second, parallel schema
  defined elsewhere does not satisfy this and contradicts the unchanged §6.5.
- AC6: The criterion states the **predicate** for a blocking ask — *the engine cannot act on
  **this item** until an owner reply is read* — scoped to the work item rather than to the
  run, because most of these sites surface the ask and let the run continue (the §7
  non-convergence stop surfaces in the PR body and proceeds to §8; intake's stops skip the
  issue and move on). A run-scoped predicate would match only two members and contradict its
  own non-vacuity list. The enforced set is **derived** from a machine-readable marker — an
  explicit **`[blocking ask]` tag** carried at each such site in `workflow/**` — never a
  semantic read of prose and never a hard-coded path list, so the derivation is independent
  of the emission markers it grades and a newly-added site is caught. A non-vacuity assertion
  requires the derived set to contain the known members. Swept from the live tree, those are: the §7 gate's non-convergence stop
  (the pre-PR-gate stage card and `gate-loop.md`), the review-response non-convergence stop,
  intake's underspecified bucket **and** its constitution-screen conflict stop, the
  `[selection announce-and-confirm]` confirm pause, the §6.5 "your call" decision items in
  the PR body, and AC2's own escalation comment. `retry.md`'s marked retry comment is
  **excluded and stated as excluded**: it is engine bookkeeping consumed by the next attempt
  as maker input, it asks the owner nothing, and the unchanged US10 gives it no steering
  authority — placing it in the blocking set would make the check's two directions
  contradict each other on one file. The check grades **emitted artifacts**, not whole
  files or sites: one site may emit both an excluded bookkeeping artifact and an included
  decision artifact. It fails **three** directions: a blocking decision artifact emitting a
  bare `Decision needed:` with no `question_format`; a **non**-blocking informational
  artifact given a `question_format`; and a blocking decision artifact emitting no
  `Decision needed:` at all, so an artifact that simply omits both markers cannot pass
  silently.
- AC7: Answer parsing is deterministic and **two-sided**. The parsing rule is stated in the
  §2.5 thread-reading stage card (`next-task/03-read-context.md`, which already owns
  marked-vs-unmarked provenance and the don't-re-ask rule) and encoded as a hook alongside
  the other contract checks in `.claude/hooks/`; it is called from that §2.5 thread-read step
  and from the resume protocol, which is where a prior blocking ask is re-encountered. Naming
  both is the point of this clause — a parser that exists with no caller is the failure mode
  it exists to prevent. When more than one blocking ask remains outstanding, a reply is
  paired with **exactly one**: the ask with the greatest task-wide ask sequence, including
  when the outstanding asks came from different attempts; earlier asks remain blocked and a
  reply is never consumed twice. Reply normalization trims outer ASCII whitespace, folds
  ASCII case, and collapses runs of horizontal whitespace in the answer token. The accepted
  grammar is `ANSWER` or `ANSWER — STEERING`, with that space-em-dash-space delimiter and a
  non-empty steering suffix. For `yes-no`, `ANSWER` is exactly `yes` or `no`; abbreviations,
  punctuation, and unseparated appended prose are rejected. For `choice`, `ANSWER` equals
  exactly one enumerated option after the same normalization. A reply is treated as an
  answer **only** when it matches that ask's offered grammar, and any other reply is owner
  steering to be read, **never** consent. Both directions are proven — including acceptance
  of ` YES ` and `yes — narrow the scope`, and rejection of `y`, `yes!`, `yes please`, an
  empty reply, and a token matching more than one normalized choice — so a conforming reply
  *is* accepted and a non-conforming reply is *not*, and a parser that accepts everything or
  nothing fails. That test runs in the required check. A reply that **both** conforms and steers (`yes — and narrow the
  scope`) is stated to be **both**: the answer is taken and the steering is read, since
  §2.5 makes the newest unmarked owner comment authoritative regardless. Independently of
  format, a conforming reply **applies the asked decision only**: it never authorizes a
  merge, never engages autonomous mode, never alters gate semantics (round limits, veto
  authority, tier floors), and never reaches any family-wide write-intent exclusion. Merge
  authorization stays session-explicit. An implementation letting a conforming reply satisfy
  any of those violates this criterion — the merge arm is already backstopped
  deterministically, and the criterion's falsification covers the activation and
  gate-semantics arms, which no existing check pins.
- AC8: The blocking-contact schema is named in the write-intent contract rows for the
  marked-comment intents, and the contract check is **extended with a new assertion** to
  backstop it — stated as work, not as an existing property, because the check today parses
  those rows only for role names and reads no constraint-cell content, so a dropped schema
  reference would fail nothing. The new diagnostic is stated literally, matching the check's
  existing repair-clause style: `intent role '<role>' constraint cell omits the
  blocking-contact schema reference (repair: name the schema, or the documented exemption)`.
  Falsification runs on **planted fixtures** rather than the live contract this story edits:
  a fixture whose marked-comment row omits the schema reference fails with **that exact
  diagnostic**, and a positive fixture passes. The row-level fixture is **paired with an emission-level one**, so
  the schema reference is load-bearing rather than a string sitting in a table cell.
  Sequencing: the conversion of issue #295 edits the same contract rows, so whichever of the
  two lands second rebases onto the other's rows rather than re-authoring them.
- AC9: A conformance probe exercises **all three** of this story's runtime behaviors — the
  bound as well as the contact schema — two-sided in each: three consecutive same-check
  failures escalate while two do not; a blocking site posts a comment carrying the schema
  while an informational item posts one without it; and a conforming reply is consumed as an
  answer while a non-conforming reply is not (it remains steering, and the item stays
  blocked); and with two outstanding asks from different attempts, a conforming reply applies
  only to the one with the greater task-wide ask sequence.
  The bounded-retry pair is required rather than left to a document scan, because
  stop-and-ask at the third strike is the one behavior this story exists to deliver. A probe
  covering only the contact halves, or only one direction of any pair, does not satisfy this.
  Without this criterion every other criterion in the story grades a document or a
  docs-encoding scan, and neither the emitted comment nor the parse decision would ever be
  proven to execute.
### US11 — Resume-safe shared-surface writes and attempt-scoped identity
As a harness operator, I want a re-run of an interrupted task to reconcile against what
the previous attempt already wrote instead of writing a second copy, and I want every
attempt to carry an identity a later promotion can verify, so that a crashed or resumed
run cannot double-create an issue, double-post a marked comment, or open a duplicate PR,
and a discarded attempt can never be promoted against a different workspace.

Motivation: durable-execution runtimes force an admission that applies to Creance with no
framework involved — internal state transitions may replay, but external writes are not
exactly-once. The closed write-intent family (`workflow/README.md` → "Write intents (safe
outputs)") already names every shared-surface write as exactly one auditable role; that
naming is the substrate, and each role simply lacks a resume-safety clause. Intake of
issue #295, whose research (#294) **rejected** adopting the runtime that surfaced the
lesson: the concept transfers, the dependency does not.

**Recorded trade-off calls.** Three decisions this story makes deliberately, so the
acceptance reviewer grades them as intended rather than as drift:
- **Promotion gains a precondition, not a second veto.** `workflow/README.md` states
  promotion is *only* ever the §7 gate's PASS. AC2 does not add a competing authority: a
  gate PASS still decides *whether* the work is promotable, and the identity check only
  confirms the PASS is being applied to **the same attempt, workspace, and commit the gate
  actually audited**. A mismatch means the PASS does not describe this artifact, so there
  is no verdict to apply — the check refuses a misapplied PASS, never overrides a real one.
- **Reconciliation keys are resume-stable by construction.** The lookup that finds a prior
  artifact must key on something that survives re-entry. A fresh attempt/run ID and a fresh
  worktree path do not, so keying on them would produce a criterion that is fully
  satisfiable while preventing zero duplicates. The attempt identity is therefore the
  *promotion* key (AC2), and the *reconciliation* key is a separate, per-artifact,
  resume-stable one (AC4). Conflating the two is the defect, not the design. The retry
  comment's discriminator reuses the audited commit AC2's contract change already returns —
  one carrier, two consumers — and `retry.md`'s first-line shape gains that value so the
  key is readable off the artifact.
- **The gate's return shape gains one field, as an explicit contract change.** The audited
  commit AC2 compares is **not** returned by the §7 gate today — the loop returns the
  outcome and the verdicts, and the audited HEAD reaches only the telemetry stream, which
  AC3 forbids as a promotion input. Rather than infer HEAD live (the anti-pattern the
  explicit-ref invariant exists to prevent) or read telemetry (P5), this story **adds** the
  audited commit to the `[orchestrated run]` role's Outputs cell and to the gate-loop return
  shape, as a reviewed contract change under P4 (AC2). No other role's meaning is widened.

**Acceptance Criteria**
- AC1: The **attempt identity** is defined in exactly **one** neutral location, as an
  authoritative and complete list of **atoms** — task ID; attempt/run ID; worktree path;
  expected base commit; and the commit the §7 gate audited — with each atom's **allocation
  and stability rule** stated (which atoms are freshly allocated per re-entry and which
  survive it), because AC2 and AC4 key on opposite halves of that split and cannot both be
  satisfied without it. Every other doc that uses the identity references this definition
  rather than restating its fields, and a deterministic drift assertion (the independent
  oracle + mutation-case shape of `reviewer-roster.test.sh`, applied as a negative-existence
  scan) fails on a second field-list definition elsewhere. That assertion **runs in the
  project's required check** and ships a planted second-definition fixture proving it trips
  — a check that exists but is not wired is treated as broken, not as probably-fine
  (constitution P2/P3). The scan is shape-bound: it catches a restated field list matching
  the definition's structure, not a paraphrase — the reference-don't-restate rule for prose
  remains reviewer-enforced.
- AC2: The isolated-workspace promotion path verifies, before a PR is opened from an
  attempt, that the §7 gate's PASS actually describes this artifact: **every atom** of AC1's
  identity matches. Promotion **proceeds** when every atom matches and is **refused** when
  any single atom differs; `isolated-workspace.test.sh` plants a mismatch in **each atom
  separately** — five distinct plants, with the worktree path and the expected base commit
  counted separately so a check comparing only the path cannot pass the suite, and the
  audited commit carrying its own plant so an implementation that never compares it fails —
  **and** asserts the all-match case is not blocked. A check that refuses everything fails
  this criterion exactly as one that refuses nothing does. The audited commit is carried as
  an explicit field of the §7 gate's **return value**: this story adds it to the
  `[orchestrated run]` role's Outputs cell (`workflow/README.md`) and to `gate-loop.md`'s
  documented return shape as a reviewed contract change (P4), and the promotion check reads
  it from there — never from the telemetry stream (AC3), never from a marked comment, and
  never by re-resolving HEAD live.
- AC3: The attempt identity is written into telemetry records as a correlation key and is
  never read back as one. No gate outcome, tier resolution, task selection, promotion
  decision, or merge authorization obtains it from the telemetry stream — the stream keeps
  zero consumers with control authority (constitution P5 unchanged). AC2's promotion check
  reads it from the live workspace, the gate's return value, and the tracker's **issue/PR
  state** — never from a **marked** comment, which is engine bookkeeping and carries no
  authority (`next-task.md` §2.5); a promotion that obtains any atom from the stream or from
  a marked comment violates this criterion. Consistent with the telemetry emitter law, a
  failed correlation-key write never blocks, fails, or alters promotion — the measurement
  channel cannot gate the thing it measures in either direction.
- AC4: The contract's write-intent table carries a **reconciliation precondition** on each
  of the four **creating** intents — `[create-issue output]`, `[add-issue-comment output]`,
  `[add-pr-comment output]`, `[open-pr output]` — where re-execution would produce a second
  artifact rather than converge on the same end state. Each precondition states **both
  halves**:
  - **(i) a lookup key stable across exactly the re-executions it must reconcile** — the
    **task ID** for the issue; the **head branch** for the PR; and, for a marked comment,
    the **marker plus the task ID and a per-call-site discriminator** that is resume-stable
    under AC1's split. The two comment intents are generic roles — every engine-posted
    comment (intake classifications, review findings, review-response replies, the retry
    comment) flows through them, and most carry no gate round at all — so the precondition
    on the two comment rows names this key **shape** and requires each comment-posting call
    site to declare its discriminator in the workflow doc that defines the comment; a call
    site with no declared discriminator posts additively as today and is **outside
    reconciliation's scope**, a recorded decision rather than an omission. The call site
    this story specifies concretely is the gate non-convergence retry comment
    (`retry.md`): its discriminator is **the audited commit the verdicts describe** —
    available to the dispatcher as a field of the gate's return value by AC2's own contract
    change, stable across a re-execution of the same gate run, and distinct across a
    genuinely new attempt, whose gate audited a different commit — so a same-run replay
    adopts or skips while a new attempt posts a new comment, and US10.AC1's verbatim
    posting and US10.AC2's read of the *newest* marked retry comment both continue to hold.
    The gate round ordinal is explicitly **not** the discriminator: `retry.md` posts **one**
    comment per non-convergence stop whose body spans multiple `{auditor, round}` sections
    (US10.AC1's `{auditor, round}` keying is the body's internal section keying, not an
    artifact key), and the gate restarts round numbering on every invocation, so an
    ordinal-keyed lookup would match a prior attempt's comment and silently drop the new
    verdicts. So that the key is readable off the artifact itself, `retry.md`'s
    deterministic first line carries the audited commit alongside the task ID it already
    carries. Each
    key is stated explicitly as **not** the worktree path and **not** a per-re-entry
    attempt/run ID, since those are freshly allocated on every re-entry (AC1) and a lookup
    keyed on them can never match a prior attempt. The issue lookup adopts **by key alone,
    regardless of author** — an owner-filed issue retitled by intake to carry the task ID
    (`intake.md`) *is* the task's issue, so author is not part of the key; the PR's head
    branch is engine-allocated per the branch convention, so a head-branch match is
    engine-created by construction; the marked comment's key already embeds authorship via
    the marker. An author predicate added to "harden" the lookup would break every
    intake-converted task.
  - **(ii) the outcome: adopt the existing artifact or skip — never "update" it.** All four
    creating roles are constrained create-only/additive in cells this story leaves unchanged
    (`[create-issue output]` "never … edits an existing issue"; both comment intents
    "Additive only … never edits or deletes an existing comment"), and the family rule is
    flat: a new write appears as a new role row through a reviewed PR, **never by widening
    an existing role's meaning**. Adopting is therefore *using* the existing artifact rather
    than creating a second one, and grants the creating roles nothing new. Where a mutation
    of an adopted artifact is genuinely wanted **and a convergent intent already owns it**,
    it is performed by that intent (`[update-pr output]`, `[update-issue-metadata output]`);
    comments have **no** convergent intent by design, so for comments the outcome is
    adopt-or-skip only and the additive-only guarantee is preserved intact. This story does
    **not** redefine `[update-pr output]`'s "a PR the run itself opened" — adopting a prior
    attempt's PR means declining to open a second one, not editing it.

  The three **convergent** intents — `[update-pr output]`, `[update-issue-metadata output]`,
  `[push-task-branch output]` — instead carry an explicit note stating why re-execution is
  already safe, so their lack of a lookup clause is a recorded decision rather than an
  omission. A diff that clauses all seven, or that clauses only some of the four, does not
  satisfy this.
- AC5: `write-intents-check.sh` gains a reconciliation check whose oracle is **independent
  of the prose it grades** — it carries the expected creating/convergent partition rather
  than inferring it from which rows happen to have clauses — and FAILs when: (a) a creating
  intent's row lacks a clause naming both halves; (b) a convergent intent's row carries a
  lookup clause but no convergent note; (c) the contract family contains a role the
  partition does not classify, so a future intent added by reviewed PR cannot land silently
  unreconciled; **or (d) a role the partition carries has no matching contract row** — the
  under-match direction, which catches a removed role and a row parser that silently
  degrades. The check FAILs unless **family size, classified count, and the carried
  partition's size are all equal and non-zero**; a bare non-zero floor is insufficient,
  since a regex matching one row of seven clears it while grading one row (P2 — never a
  vacuous pass).
- AC6: `write-intents-check.test.sh` gains **planted-negative fixtures** proving each
  failure direction actually fires — a contract fixture with a creating intent's clause
  deleted; one whose clause names the lookup key but not the adopt-or-skip outcome; one
  whose convergent intent carries a lookup clause without the note; one adding a role the
  partition does not classify; and one **removing** a role the partition carries (AC5's (d)
  direction) — each asserting the **specific diagnostic**, not merely a non-zero exit, plus
  a positive fixture satisfying every rule that exits OK. These cases run against fixtures
  via the check's existing surface overrides rather than against the live contract, so they
  keep proving the check works after the live contract is edited by this same story.
- AC7: The concrete lookup mechanisms implementing each precondition live only in the
  **adapter layer** — the adapter's own binding surfaces and mapping rows, and the
  orchestrated-run implementation — and **never** in `workflow/**`. The neutral surfaces
  that invoke them (the next-task stage cards covering the issue and PR writes, and the
  gate-loop non-convergence comment path) are themselves `workflow/**` residents and
  neutrality-scanned: they name the **[role]** only and carry no concrete command. The
  existing neutrality scan and the write-intents leak scan both stay green (constitution
  P1). Because the leak scan's pattern covers tracker *write* verbs only, a **read**-shaped
  lookup would evade it — so the neutrality scan is the load-bearing fence here, and the
  criterion is not satisfied by the leak scan passing alone.
- AC8: A conformance probe exercises reconciliation **at runtime**, across three executions
  and both decision directions — match and no-match — asserted by **counting artifacts**,
  not by inspecting prose:
  1. a first execution creates exactly one artifact;
  2. a re-execution under the **same** resume-stable key finds it and adopts it, leaving
     exactly one;
  3. a third execution under a **different** resume-stable key (a different task ID / head
     branch / audited commit) creates a **second** artifact, leaving two.
  Step 3 is what makes the criterion two-sided: a lookup that adopts unconditionally passes
  steps 1–2 and fails step 3. The probe covers the **issue**, the **marked comment**, and
  the **PR** kinds: the comment leg exercises the commit-scoped retry-comment key of
  AC4(i) rather than the cheapest artifact kind alone, and the PR leg runs against a
  fixture or override surface rather than a live tracker write (the AC6 posture), so the
  head-branch lookup executes without opening a real PR. A probe covering only the create
  path, only the adopt path, or only one artifact kind does not satisfy this.
