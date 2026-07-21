# Spec — Workflow Context Economy

> Epic for the Creance repo itself. The acceptance [reviewer] (`spec-auditor`) grades
> each task against the `US#` acceptance criteria below — bullets are addressable as
> `US1.AC1`, `US1.AC2`, … (the nth bullet under that story), so they are written as
> independently checkable statements.

## Overview

Creance's routine context footprint is unmeasured and creeping: the owner's baseline
measurements on the source issue put the typical `next-task` read set at ~40.9k tokens,
PR review at ~18.2k, and an eager `.claude` docs read at ~124.7k — with
`workflow/next-task.md` (~8.8k), `workflow/README.md` (~5.9k), and `.claude/PROJECT.md`
(~5.3k) the largest routine contributors. The methodology is the product, so the fix is
**not** trimming the contract: the full workflow docs stay authoritative source of truth,
while the *active* per-run context becomes demand-loaded, compact, and **CI-verified** —
generated or drift-checked artifacts, never hand-maintained summaries that silently rot
(the silently-dead-guard class, constitution P2, applied to context artifacts). Target
outcomes from the source issue: passive residency ~2k–3k tokens, an ordinary `next-task`
path ~12k–18k, a PR-review path ~7k–10k.

The spec lands the capability in six stories (later amended with a seventh, US7, by issue
#259, an eighth, US8, by issue #273, and a ninth, US9, by issue #303 — see **Amendments**
below): a repository token
counter with documented,
owner-ratified budgets wired into standing verification (US1 — the measurement substrate
the other stories' budgets resolve against); a lean resident `AGENTS.md` (US2); a compact,
drift-checked project packet (US3); demand-loaded stage cards for the per-task procedure
(US4); a generated task index for selection (US5); and governance rules moved from prompt
prose into deterministic checks (US6). US↔slice traceability to the source issue:
US1 = slice 6, US2 = slice 1, US3 = slice 2, US4 = slice 3, US5 = slice 4, US6 = slice 5
(reordered so the measurement substrate precedes its consumers).

Motivation and provenance: intake of issue #166 (filed 2026-06-26; no thread comments —
the body is the sole owner steering). The issue's baseline table and suggested budgets
are owner measurements, adopted here as the initial ratified budget values (US1.AC1).
One translation applied per constitution P1: the issue's slice-1 bullet names a concrete
vendor review command (`codex review --base main`, drafted against a different adapter);
this spec renders it as the required pre-PR review **[roles]** — the §7 gate plus the
profile's review-pass set — so no runtime-specific mechanism enters a neutral surface.
The task-ID block is **T12xx** (block assignment ratified by merging this spec's
conversion PR).

**Amendment (issue #259).** US1 budgets the surfaces the harness *authors and reads*; it
does not account for the surface the **runtime attaches on top of them** — tool schemas,
the MCP-server inventory and instructions, the auto-injected skill-description catalog, the
deferred-tool list, and system-reminders — which is resident every session and can dominate
the token floor yet appears in no budget row. **US7** extends US1's "measure before you
claim" across the authored/runtime boundary: an adapter-owned probe measures the
runtime-attached floor, a named baseline lets a budget report state
`authored surface + runtime floor = real resident`, and a governance ordering rider makes
explicit that a budget reduction removing context the adversarial auditors rely on is
blocked (the constitution's quality invariants outrank any budget row). Because the
runtime-attached surface is inherently runtime-specific, the probe is an **adapter fact**
(Claude Code side, beside `.claude/adapters/claude-code-probes.md`) — it never enters a
`workflow/**` neutral doc (constitution P1), exactly as US1.AC4 keeps the tokenizer identity
adapter-local. Measurement and baseline **only**: the floor is never gated on (runtime
internals are version-dependent; the probe fails open), so telemetry-observes-never-decides
(constitution P5) holds unchanged. Provenance: intake of issue #259 (filed 2026-07-08; no
thread comments — the body is the sole owner steering), surfaced while reviewing the
external `sunflower-of-parchman/codex-hygiene` skill at the owner's request; parent context
#166. US7 has no epic-#166 slice — it is a post-hoc amendment, not one of the original six
slices.

**Amendment (issue #273).** US2.AC2 makes reachable pointers a contract — every rule
trimmed from `AGENTS.md` must survive behind a *surviving pointer* — but nothing in
standing verification fails when a pointer's **target path stops existing**: a rename or
move under `.claude/**` silently strands every reference to it. PR #272 surfaced the class
concretely — three `AGENTS.md` pointers named bare `workflow/…` paths that do not resolve
from the repo root (fixed there by hand), and the advisory review found the same shape
still live in `.claude/PROJECT.md` and `.claude/PROJECT.compact.md`. **US8** adds the
missing deterministic backstop: a `verify`-wired check that extracts the backtick-quoted
repo-relative path pointers from the pointer-bearing surfaces and fails when one does not
exist from the repo root — constitution P3 (a rule enforced today only by a human or the
model *noticing* a dangling reference becomes a deterministic check) applied to the
pointer-reachability contract US2.AC2 introduced. Scope is **path existence only**;
section-anchor resolution (a pointer's `→ "Heading"`) is a named follow-on, not part of US8
(see Non-goals). Provenance: intake of issue #273 (filed 2026-07-10; the sole unmarked
owner steering is the issue body — the single thread comment is engine-authored bookkeeping
listing the known fix targets), relayed from the engineering-craft review pass on PR #272;
parent context #166 / US2. US8 has no epic-#166 slice — like US7 it is a post-hoc amendment.

**Amendment (issue #303).** Spec 007 economizes how much context a run *reads*; nothing yet
governs the **stability** of the context the harness *writes into each dispatch* — the §7
reviewer/fixer dispatch templates whose fixed text is what makes structurally similar runs
produce structurally similar trajectories. Issue #303 (motivated by an external analysis of
harness design: keep every model call locally in-distribution via context offloading and
programmatic sub-agent calling, so isomorphic tasks yield near-identical dispatches)
identifies three gaps: (1) no deterministic check catches a dispatch template quietly
accreting run-specific prose outside its interpolation slots — the silently-degrading-
machinery class (constitution P2) applied to prompt templates, the same shape the reviewer
roster closed for membership (DESIGN-NOTES §12); (2) two context-offloading practices the
harness already follows — bounded sub-agent returns ("handles, not payloads") and
code-over-prose gate orchestration — are unstated, so a future "optimization" has no named
rule to argue against; (3) the maker-eval corpus has no stated coverage argument — "is the
corpus complete" is answered by judgment instead of a table. **US9** adds: a committed
declared-slot manifest per dispatch template with a `verify`-wired template-stability check
(AC1); the two offloading practices as named design rules, including an explicit
adjudication of the retry feedback channel's verbatim-verdict granularity (AC2–AC3); and a
coverage-by-trajectory-class table for the frozen corpus (AC4). Provenance: intake of issue
#303 (filed 2026-07-21; no thread comments — the body is the sole owner steering; the body
was engine-drafted in-session at the owner's explicit direction from the owner's account,
so it is owner steering under `next-task.md` §2.5). Like US7/US8, US9 is a post-hoc
amendment with no epic-#166 slice.

## Non-goals

- **No removal of source-of-truth workflow documentation.** Every rule or procedure
  trimmed from a resident or default-loaded surface survives in a named source-of-truth
  doc; compaction relocates, it never deletes the contract.
- **No hand-written summaries without drift detection.** Every compact artifact this spec
  introduces is generated or CI-drift-checked against its source; a summary maintained by
  discipline alone is the failure class this spec exists to prevent.
- **No weakening of the workflow contract:** the issue/branch/PR lifecycle, guard
  behavior, constitution check, §7 pre-PR gate, and required review passes are unchanged
  in *what* they require; this spec changes only how much of that text is resident per
  run. A restructuring that drops or relaxes an obligation is a defect, not a savings.
- **No hiding required context without a deterministic replacement:** where the agent
  previously read prose to comply, either the prose remains reachable on demand or a
  deterministic check enforces the rule (constitution P3's posture).
- **The neutral/adapter split holds (P1):** stage cards and every other
  `workflow/**`-resident artifact stay runtime-neutral and neutrality-scan-covered; the
  concrete tokenizer/counter and token budgets are project/adapter facts and never enter
  a neutral doc.
- **Budget signals observe doc size only:** a token-budget or drift check gates CI like
  any lint; no budget measurement ever alters gate semantics, model tiers, or task
  selection (constitution P5's posture applied to the context surface).
- **All restructuring lands by human-reviewed PR** (constitution P4, unchanged).
- **The runtime-attached floor (US7) is measured and baselined only — never gated on.**
  Runtime internals (session/log/introspection shape) are version-dependent, so the US7
  probe fails open and loud and never blocks verification; the recorded floor is a
  non-decisional baseline that no gate, model tier, or task-selection path reads
  (constitution P5). US7 extends measurement past the authored boundary; it does not
  re-implement or replace US1's authored-surface counter (`token-budget-check.sh`).
- **Doc-pointer resolution (US8) checks path existence only.** The US8 check's contract is
  that a backtick-quoted repo-relative *path* named as a pointer exists from the repo root;
  **section-anchor** resolution (a pointer's `→ "Heading"` naming a heading that must exist
  in the target) is a deferred follow-on (issue #273), not part of US8. US8 adds a backstop
  for US2.AC2's reachable-pointer contract; it does not relax or restate US2.AC2 —
  compaction still relocates, never deletes; US8 only proves the relocation target still
  exists.
- **Template stability (US9) governs fixed text and slot inventory only — never content or
  semantics.** The declared-slot check constrains what a dispatch template's *fixed text*
  may interpolate; it never reads, grades, or constrains a reviewer's output, a verdict, or
  any gate semantics (round limits, veto authority, tier floors, roster membership are
  untouched — membership stays `reviewer-roster.test.sh`'s contract). Adding a legitimate
  new slot is a reviewed edit to the committed manifest in the same diff as the template
  change — the check exists to make drift *visible*, not to freeze template evolution.
- **The coverage table (US9.AC4) observes; it never decides.** Class-coverage documentation
  feeds no gate outcome, eval score, model tier, or task-selection path (constitution P5's
  posture, unchanged from the maker-eval channel it documents).
- **US9's design rules change no behavior by themselves.** The handles-not-payloads rule
  *records* an adjudication of the retry feedback channel's granularity; any behavior
  change to `.claude/workflow/retry.md` or any other surface lands as its own reviewed PR
  (constitution P4), never as a side effect of the design note landing.

## User stories

### US1 — Token-budget measurement tooling (issue slice 6)
As a harness operator, I want a repository token counter that measures the core context
bundles against documented, owner-ratified budgets and fails standing verification on an
overage, so that context growth is caught deterministically instead of noticed.

**Acceptance Criteria**
- AC1: A repository token-counting check measures the context artifacts and bundles this
  spec names (the resident `AGENTS.md`, the compact project packet, each workflow stage
  card, the task index, and the ordinary `next-task` and PR-review read bundles) and
  reports **per-file and per-bundle counts** in its output. The budgets are documented
  beside the check with an explicit owner-ratified override/update path for legitimate
  growth; the initial values are the source issue's (`AGENTS.md` ≤ 1.2k; compact packet
  ≤ 2k; each stage card ≤ 1.5k; task index ≤ 4k; ordinary `next-task` bundle ≤ 18k;
  ordinary PR-review bundle ≤ 10k tokens). A budget the check chooses or adjusts itself
  violates this criterion (the owner ratifies budget changes, never the tooling).
  The check measures and reports every named surface that exists when it runs; budgets
  for surfaces that later stories introduce or restructure (the compact packet, the
  stage cards, the task index, and the two read bundles) are documented and registered
  from the start but begin **gating** only in the diff that lands or restructures the
  surface — each of US2–US5's AC1 owns activating its own budget gate — so the
  measurement substrate stays narrow and never blocks on artifacts it exists to
  measure.
- AC2: The check is wired into the repo's standing verification (`verify`) with the
  wiring asserted — a check that exists but never runs is the silently-dead-guard class
  (constitution P2), and a hand-run script with no CI wiring does not satisfy this.
- AC3: The check ships falsification tests in the same diff covering **both**
  directions: a planted over-budget fixture fails with the offending artifact and its
  measured count named, AND a within-budget control passes — a test exercising only the
  failure direction (or only the passing direction) does not satisfy this.
- AC4: The concrete tokenizer/counter identity is a project/adapter fact documented
  beside the check; no `workflow/**` neutral doc names it, and the neutrality scan stays
  green over every neutral doc the change touches (constitution P1).
- AC5: Every PR implementing a task of this spec carries measured before/after token
  counts in its body for each context artifact or bundle its diff touches, produced by
  the AC1 counter (the substrate PR that introduces the counter reports the baseline
  counts it establishes; a diff touching no measured surface states that explicitly).
  A T12xx PR body without this evidence does not satisfy this criterion — the source
  issue's definition-of-done line, made gradable instead of carried as an ungraded
  sequencing note. This criterion is owned by **every** task of this spec, graded on
  each task's own PR.

### US2 — Lean resident `AGENTS.md` (issue slice 1)
As a harness operator, I want the always-resident `AGENTS.md` reduced to per-turn rules
plus pointers, so that every session stops paying for procedures that a demand-loaded
doc can carry.

**Acceptance Criteria**
- AC1: `AGENTS.md` carries only per-turn rules — at minimum: issue-before-edit; one
  task / one issue / one branch / one PR; never revert unrelated user changes; no merge
  without explicit authorization and concrete green tracker status; the required pre-PR
  review passes (the §7 gate and the profile's review-pass set, named as [roles]);
  repository-search-first; and pointers to the source-of-truth workflow/profile docs —
  and measures within its US1.AC1 budget under the repository token counter, with that
  budget's gate activated in the same diff (US1.AC1's deferred-activation rule).
- AC2: Every rule or procedure removed from `AGENTS.md` remains available in a named
  source-of-truth doc reachable by a pointer that survives in `AGENTS.md`; removed
  content with no surviving home, or a pointer to a doc that does not carry it,
  violates this criterion (compaction relocates, never deletes — the Non-goals rule made
  checkable per removal).
- AC3: Existing guard, workflow, and CI references to `AGENTS.md` still resolve after
  the trim — the [guard] and the existing residency check still target it — and the
  existing line-ceiling residency check (`agents-residency-check.sh`) remains enforced
  alongside the US1 token budget: two measures, one target, neither dropped nor forked
  into a drift-prone copy.

### US3 — Compact project packet (issue slice 2)
As a workflow entrypoint, I want a compact, drift-checked packet of active routing facts,
so that ordinary runs read ~2k tokens of profile instead of the full `.claude/PROJECT.md`.

**Acceptance Criteria**
- AC1: A compact project packet exists carrying only active routing facts — base branch,
  specs/tasks paths, issue/branch/PR naming conventions, required checks, autonomy
  status, the critical invariants with their deterministic backstops, and the edit-time
  checker map — and measures within its US1.AC1 budget under the repository token
  counter, with that budget's gate activated in the same diff (US1.AC1's
  deferred-activation rule).
- AC2: A deterministic drift check fails when the packet disagrees with
  `.claude/PROJECT.md` on any covered field, is proven in **both** directions in the
  same diff (a planted drift fixture fails with the drifted field named, AND an in-sync
  control passes), and is wired into standing verification with the wiring asserted — a
  hand-maintained packet with no such check does not satisfy this (Non-goals: no
  undetected summaries).
- AC3: Workflow entrypoints (the skill bindings' declared read sets) name the compact
  packet as the default profile read and the full `.claude/PROJECT.md` as an explicit
  escalation for the cases that need it; an entrypoint that still requires the full
  profile for ordinary work violates this criterion.

### US4 — Demand-loaded stage cards for the per-task procedure (issue slice 3)
As a per-task run, I want `workflow/next-task.md` split into small stage cards loaded on
demand, so that each stage pays for its own instructions instead of the whole procedure.

**Acceptance Criteria**
- AC1: The per-task procedure is split into stage cards (covering at least: preconditions
  and task selection; context read; issue and branch; implementation loop; verification;
  pre-PR gate; PR creation and stop condition), each measuring within its US1.AC1 budget
  under the repository token counter — or carrying a documented overage through US1.AC1's
  override path where a stage genuinely cannot compress — with the stage-card budget's
  gate activated in the same diff (US1.AC1's deferred-activation rule).
- AC2: The per-task entrypoint (the skill binding) loads only the current stage card plus
  the compact project packet for ordinary work — never the full assembled procedure by
  default; the escalation to the full source is explicit, not the default path.
- AC3: The full procedure remains coherent and authoritative: either a generated assembly
  drift-checked against the cards, or an index doc that orders and links them; existing
  references to the per-task procedure in docs, tests, and bindings resolve after the
  split, and the neutrality scan's coverage includes **every** resulting neutral card — a
  card that escapes the scan is the silently-dead-guard class (P1/P2).
- AC4: The split loses nothing: every obligation of the pre-split procedure exists in
  exactly one card (or the assembly), enforced deterministically against an
  **independent pre-split oracle** — an obligation inventory (e.g. section/heading IDs
  and rule anchors) captured from the pre-split `next-task.md` itself and committed as a
  fixture the cards cannot influence — via the AC3 drift check on a generated assembly
  or an explicit completeness check over the index, either one compared to that
  inventory, so a dropped section fails verification rather than passing silently. A
  check whose reference is derived solely from the post-split cards would reproduce an
  omission instead of detecting it and does not satisfy this; a restructuring proven
  only by eyeball does not satisfy this.

### US5 — Generated task index (issue slice 4)
As the task-selection step, I want a generated index of selection-critical fields, so
that picking a task reads ~4k tokens instead of every live tasks file.

**Acceptance Criteria**
- AC1: A generated task index exists carrying only selection-critical fields per task —
  task ID, title, model tier, checkbox state, owning acceptance criterion refs, spec
  path, and issue/PR link when known — and measures within its US1.AC1 budget under the
  repository token counter for the current repo, with that budget's gate activated in
  the same diff (US1.AC1's deferred-activation rule).
- AC2: A CI check fails when the index is stale relative to the live `specs/*/tasks.md`
  files, proven in **both** directions in the same diff (a planted stale fixture fails
  naming the stale entry, AND a freshly-regenerated control passes), wired into standing
  verification with the wiring asserted.
- AC3: Task selection reads the index first and then loads only the selected task's full
  spec/tasks context; the deterministic selection preconditions — [live-state
  reconciliation], the in-flight check, and [selection announce-and-confirm] — run
  unchanged on the selected candidate; an index-first path that bypasses any of them
  violates this criterion.

### US6 — Governance rules from prose into deterministic checks (issue slice 5)
As a harness operator, I want high-risk workflow rules encoded as hooks/CI checks instead
of resident prompt prose, so that compliance stops depending on the model re-reading the
rule every turn (constitution P3).

**Acceptance Criteria**
- AC1: Each rule from the initial candidate set is accounted for **without duplicating
  existing coverage**: (a) "a merge command must not be pre-approved by the [permission
  allowlist] in default review mode" is already encoded — the T623 regression in the
  [guard]'s test suite (`guard.test.sh`, `settings #165: no gh pr merge pre-approval`)
  is the carried implementation; this story cites it and asserts it still runs in
  standing verification, extending it only if an audit finds a concrete coverage gap,
  and re-implementing or re-proving the existing check is out of scope, not a
  deliverable. (b) "the compact-context/token-budget checks run in standing
  verification" is owned by US1.AC2 and is cited here, not re-encoded. Any **new** rule
  this story encodes ships as a deterministic check with focused tests covering **both**
  directions (a planted violating fixture fails, AND a compliant control passes). A
  candidate that cannot be made deterministic (e.g. the issue's "PR creation only after
  documented verification and review passes", which is procedural) is documented as
  prose with an explicit justification per constitution P3 — never silently dropped and
  never claimed as encoded.
- AC2: For each encoded rule, the resident prompt prose is reduced to a pointer at the
  deterministic check rather than restating the procedure; the full rationale survives in
  the source-of-truth doc per US2.AC2's posture.
- AC3: When any check introduced by this spec fails, its diagnostics name the source file
  or generated artifact that needs repair — a bare failure with no named repair target
  violates this criterion (the workflow must remain usable through a failure).

### US7 — Budget the runtime-attached context surface (issue #259 amendment)
As a harness operator, I want the runtime-attached context surface — tool schemas, the
MCP-server inventory and instructions, the auto-injected skill-description catalog, the
deferred-tool list, and system-reminders — measured and baselined as the floor the authored
budgets sit on top of, so that the owner-ratified authored budgets (US1) are defensible
against the real context ceiling rather than against zero. Measurement and baseline only —
never a new gate.

**Acceptance Criteria**
- AC1: An **adapter-owned** command (a Claude Code adapter fact, beside
  `.claude/adapters/claude-code-probes.md`; named in no `workflow/**` neutral doc, per
  constitution P1) reports, for a fresh session, **per-category counts** — at least MCP
  servers, enabled skills, non-deferred tools, and deferred-tool catalog size — and a
  single **token total** for the runtime-attached surface **measured with the same counter
  as US1's authored surface** (its identity an adapter fact per US1.AC4, documented in
  `.claude/context-budgets.md` and never restated in a `workflow/**` neutral doc), so that
  `real resident = X+Y` (AC2) sums like units. It emits **compact counts and totals only**.
  Proven in the same diff by a **two-sided fidelity** test that the reported **per-category
  counts _and_ the token total** are **derived from the actual inventory, not fabricated**:
  either (i) two structurally different populated fixtures yield correspondingly
  **different** per-category counts **and different token totals**, or (ii) a mixed-presence
  fixture in which a named category is genuinely **absent** reports **zero** for it (**and a
  correspondingly smaller token total** than the fully-present fixture) while present
  categories report nonzero — so a constant/hardcoded output (nonzero *or* zero, ignoring
  its input) fails; **AND** — because (i) and (ii) both leave the total free to co-vary with
  the counts, so a command that tokenizes **nothing** could still pass by returning `total =
  f(per-category counts)` — a **count-independent** limb that pins the total to a real
  measurement of the surface bytes: an **equal-count / different-content** fixture pair
  (**identical** per-category counts, but one fixture's surface body — a server's instruction
  text or a tool schema — materially longer) reports a **strictly larger token total for the
  larger body**, and that total **equals the US1 counter's measurement of that fixture's
  runtime-attached bytes** (the counter's identity an adapter fact per US1.AC4) — so any
  total derived from the counts alone, necessarily **equal** across the equal-count pair,
  fails the **test**, not merely the prose (this subsumes **a command that genuinely counts
  the cheap categories but hard-codes _or_ count-derives the load-bearing token total**);
  **AND** a negative assertion that the output carries **no tool-schema, MCP-config, or
  secret bytes** (the falsification rule). A test asserting only presence-of-counts, only
  nonzero-ness, only the counts (leaving the total unpinned), the total pinned **only to the
  counts** rather than to a measurement of the surface bytes, or only the privacy negative
  does not satisfy this criterion. The rejected escapes are dumping the full inventory
  (privacy), emitting constant zeros (vacuity), emitting constant nonzero counts
  (fabrication), hard-coding the token total while deriving the counts (partial fabrication),
  and **deriving the token total from the counts by any function without tokenizing the
  surface** (count-derived fabrication); the fidelity-plus-privacy test penalizes all of them.
- AC2: The fresh-session runtime floor is recorded as a **named baseline** that a budget
  report can consume to render `authored surface = X`, `runtime floor = Y`,
  `real resident = X+Y`. The baseline value is **produced by the AC1 command** (traceable
  to a real measurement, not a hand-typed constant) and is **non-decisional**: it is
  recorded **outside** the gating budget table (`.claude/context-budgets.md`) and **no** CI
  gate, model-tier assignment, or task-selection path reads it (constitution P5). A baseline
  that any gate consumes, that lives as an `active`/`deferred` row able to flip to gating,
  or that is a static literal not regenerable from the AC1 command, does not satisfy this
  criterion.
- AC3: The AC1 command **fails open, loud, and never gates** when the runtime's
  session/introspection shape is unavailable or unrecognized: an unrecognized-shape input
  yields a **human-visible loud notice** AND a **non-failing** exit (it never fails
  verification), mirroring how `token-budget-check.sh` fails open on a missing tiktoken
  counter. Proven **two-sided** in the same diff: a planted unrecognized-shape fixture
  asserts **both** the loud notice is emitted **and** verification is not failed, AND a
  supported-shape control asserts the command **actually reports its counts** (so an
  always-silent no-op cannot pass). The two-sided proof penalizes both the silent-green and
  the spurious-gate directions.
- AC4: An explicit **ordering statement** lands (in `memory/constitution.md` or
  `.claude/governance-rules.md`) that a budget-motivated reduction which removes context the
  adversarial auditors rely on is **rejected** — the constitution's quality invariants
  outrank any budget row. Following **US6.AC1's exact posture**: if the rule is
  deterministically encodable it ships as a check with **two-sided** focused tests (a
  planted budget-motivated removal of auditor-relied-on context **fails**, AND a benign
  budget change **passes**) and is registered in the `.claude/governance-rules.md`
  accounting; if it is genuinely non-encodable it is documented as prose with an **explicit
  constitution-P3 justification** in that registry — never silently prose-by-default and
  never silently dropped. A bare ordering sentence carrying neither an encoded two-sided
  check nor a registered P3 justification does not satisfy this criterion. (This criterion
  drafts future work; per constitution P4 the ordering statement itself lands only by the
  owner-reviewed T1207 implementation PR, never as a side effect of any gate run.)

### US8 — Deterministic doc-pointer resolution check (issue #273 amendment)
As a harness operator, I want a deterministic check that fails standing verification when a
documentation pointer names a repo-relative path that does not exist from the repo root, so
that the reachable-pointer contract (US2.AC2) is enforced by CI instead of relying on a
human or the model noticing a dangling reference after a file moves (constitution P3). The
class was found on PR #272 — three `AGENTS.md` pointers to bare `workflow/…` paths that do
not resolve from the repo root, fixed by hand there — and the same shape survives in
`.claude/PROJECT.md` and `.claude/PROJECT.compact.md`; this story adds the missing backstop.
Scope is **path existence only** — section-anchor resolution is a deferred follow-on (see
Non-goals).

**Acceptance Criteria**
- AC1: A deterministic check scans the pointer-bearing documentation surfaces — **at
  minimum** `AGENTS.md`, `.claude/PROJECT.md`, and `.claude/PROJECT.compact.md` — extracts
  the backtick-quoted **repo-relative path pointers** they contain and **fails** when any
  such path does not exist from the repo root, naming the offending surface, the unresolved
  path, and its line. A path pointer is recognized by **shape** — a backtick token carrying
  a `/` separator and a file-type suffix (e.g. `.md`/`.sh`/`.py`) — **minus** AC2's non-path
  forms **and minus any token that is not lexically repo-relative**. **Repo-relative** is
  defined lexically: a candidate is resolved by joining it to the repo root, so a token that
  is an **absolute path** (a leading `/`), carries a **`..` parent-traversal segment**, or is
  a **`scheme://` URI** is **out of contract — never resolved and never flagged** (AC2 lists
  these among the non-path forms; AC3 controls them). This keeps the check deterministic
  across machines — it never `test -e`s a machine-dependent absolute or escaping path — and
  never mis-flags a documentation URL as a dangling path. **Candidacy must not depend on the
  token's leading segment already existing**, so a bare `workflow/…md` pointer (one that
  resolves only under the `.claude/` prefix — the exact #272/#273 class) is extracted as a
  candidate and then **fails** the existence check rather than being silently skipped. The
  extraction is **non-vacuous** and **leading-segment-agnostic**, proven along **two decoupled
  axes** so neither depends on the mutable real tree AC4 rewrites. **Non-vacuity** is proven
  by a **positive-extraction assertion**: a test that the unmodified extractor, run over the
  real scanned surfaces, recovers the **complete** shape-matched pointer set present in them —
  not a hand-picked subset (an extractor that matches nothing, or that is narrowed to a
  synthetic fixture, does not satisfy this). **Leading-segment-agnosticism** is proven **off
  the real tree**: because AC4 rewrites the real-surface bare-nested danglers to their
  resolving `.claude/…` form **in this same diff**, the scanned surfaces no longer carry a
  non-root-resolving segment at `verify` time, so this property is proven by **AC3's held-out
  planted case** — a same-shape pointer whose leading segment neither resolves at the repo
  root nor appears in any allowlist is still extracted (hence flagged). An extractor that keys
  candidacy to a fixed **allowlist of leading segments** (silently skipping a same-shape
  pointer under an unlisted segment) does not satisfy this criterion. The positive-extraction
  test's expected set is an **independent oracle** — hand-verified against the surface text,
  not derived by re-running the extractor under test (a self-derived reference would reproduce
  an omission instead of catching it, mirroring US4.AC4's oracle discipline).
- AC2: The check does **not** flag backtick-quoted content that is not a concrete repo path
  — globs containing `*` (`specs/*/tasks.md`, `workflow/**`), brace-expansion notations
  (`specs/000-template/{spec,tasks}.md` and any `{…,…}` form), placeholder-bearing strings
  (`<triage inbox dir>/…` and any `<…>`), section-anchor references (`→ "Heading"`),
  command/flag tokens (`gh pr create`, `git rev-parse`, `--body-file`), and **tokens that are
  not lexically repo-relative** — absolute paths (a leading `/`, e.g. `/tmp/file.md`),
  parent-traversal paths (a `..` segment, e.g. `../outside.md`), and URI-scheme tokens
  (`scheme://…`, e.g. `https://example.com/file.md`) per AC1's repo-relative definition. This
  is proven by a **within-tree control** in which such forms are present and the check
  **passes**; a check
  that flags every backtick token containing `/` (making `verify` perpetually red) does not
  satisfy this. AC2 bounds the over-detection direction and AC1/AC3/AC4 bound
  under-detection — complementary axes: AC2 asks "is this a path at all", AC3 asks "does the
  path exist".
- AC3: The check ships falsification tests in the **same diff** covering both existence
  directions: a planted fixture containing a **dangling** repo-relative pointer **fails**,
  naming the offending surface, the unresolved path, and its line — and the planted form
  **includes the real-world shape found on #273** (a bare `workflow/…md` segment that
  resolves only with the `.claude/` prefix), so the check is proven against the actual class
  and not only a synthetic `nonexistent.md`; AND a control in which every referenced path
  **resolves passes**. To prove the recognizer is **leading-segment-agnostic** (not keyed to
  a fixed set of segments), the failure direction also includes a **held-out** bare-nested
  pointer whose leading segment appears in **none** of this spec's named examples or AC4's
  enumeration — the implementer picks it (a synthetic `<unlisted-segment>/…md` that resolves
  only under `.claude/`) — which must also be flagged; so neither an implementation keyed to
  the literal `workflow/` string nor one keyed to a fixed allowlist assembled from this
  spec's named segments passes. A test exercising only one direction, or only leading
  segments this spec enumerates, does not satisfy this. The falsification set additionally
  includes a **containment control** — a within-tree or planted surface carrying an
  **absolute** path (a leading `/`), a **parent-traversal** path (a `..` segment), and a
  **URI-scheme** token (`scheme://…`) — asserting the check **neither resolves nor flags** any
  of them (proving AC1/AC2's lexical-repo-relative exclusion, so machine-dependent state can
  never make `verify` flap and a documentation URL is never mis-flagged as a dangling path).
- AC4: The check must pass on the current tree: **every** shape-matched dangling
  repo-relative pointer the check flags — **regardless of leading segment** — is fixed in the
  **same diff**, rewritten to its real `.claude/…` path (with the compact-packet mirror kept
  in sync so `compact-packet-drift.sh` stays green). Success is the **`verify`-green
  invariant**, not a fixed edit list. The confirmed danglers are an **illustrative,
  non-exhaustive lower bound** (≥7 across the scanned surfaces as of drafting, spanning three
  distinct leading segments): in `.claude/PROJECT.md` — `workflow/telemetry.md`,
  `workflow/maker-eval.md`, `workflow/reviewers/evasion-register.md`,
  `hooks/isolated-workspace.sh`, `hooks/isolation-falsification.test.sh`,
  `adapters/claude-code-probes.md`; and in `.claude/PROJECT.compact.md` — the mirrored
  `workflow/telemetry.md`. A diff that fixes only an enumerated subset but leaves any other
  flagged instance red does not satisfy this. This enumeration is deliberately **not
  load-bearing**: the owner's #273 comment named three by eye, this spec's own round-1 draft
  named four — the check exists precisely because by-eye enumeration misses instances, so the
  binding requirement is the leading-segment-agnostic `verify`-green behavior, not any list.
- AC5: The check is wired into standing verification (`verify`) with the wiring asserted — a
  check that exists but never runs is the silently-dead-guard class (constitution P2); a
  hand-run script with no CI wiring does not satisfy this. Its failure diagnostics name the
  source surface and the specific unresolved path needing repair (US6.AC3's
  workflow-usable-through-failure posture, asserted by AC3's failure-direction test).

### US9 — Trajectory-stable dispatch templates and context-offloading discipline (issue #303 amendment)
As a harness operator, I want the §7 dispatch templates proven to interpolate only declared
slots, the harness's context-offloading practices stated as named design rules, and the
maker-eval corpus's coverage argued per trajectory class, so that the property that makes
runs predictable across tasks — structurally similar tasks producing structurally similar
dispatches — is enforced and documented deterministically instead of decaying invisibly
(constitution P2/P3 applied to the dispatch surface).

**Acceptance Criteria**
- AC1: A committed **declared-slot manifest** exists for each §7 dispatch template — the
  reviewer dispatch prompt and the fix-round (maker) prompt, at every site that carries the
  template's *text* (the executable gate `.claude/workflows/gate-loop.js`; any
  `workflow/**` site that restates a template's text rather than merely describing it) —
  enumerating by name the runtime-interpolated slots that template may carry (e.g. the task
  ID, the audited ref/diff payload, the workspace path, the round number, the verbatim FAIL
  reports). A deterministic check, wired into standing verification (`verify`) with the
  wiring asserted (constitution P2), extracts every interpolation/placeholder token from
  those template sites and **fails, naming the template site and the undeclared token**,
  when a token is absent from the manifest. The manifest is a hand-verified **independent
  oracle** — never regenerated from the template under test (US4.AC4/US8.AC1's oracle
  discipline: a self-derived manifest ratifies leakage instead of catching it). Two-sided
  falsification in the same diff: a planted template fixture carrying an undeclared
  interpolation **fails** naming site + token, AND the unmodified real templates **pass**
  as a control. Extraction is **non-vacuous**: a positive-extraction assertion proves the
  unmodified extractor recovers the **complete** slot set actually present in the real
  templates against a hand-verified expected set (an extractor that matches nothing, or a
  test asserting only the failure direction, does not satisfy this). The check **cites,
  never re-encodes,** `reviewer-roster.test.sh` — roster membership/tier/condition stays
  that test's contract (the `lib-tasks-drift.sh` one-definition anti-fork pattern); this
  check governs template text only. A check whose manifest declares a catch-all/wildcard
  slot, or that scans none of the sites carrying template text, does not satisfy this
  criterion.
- AC2: A named **handles-not-payloads** design rule lands in `.claude/DESIGN-NOTES.md`
  beside the §11 residency model: sub-agent and broad-run outputs return **bounded,
  structured results** into the dispatching context — where **bounded is defined
  structurally, not by size threshold**: the return carries a verdict/conclusion plus
  artifact pointers (file:line, report path, tracker link) and **no embedded analysis
  payload** — the full analysis body lives on disk or the tracker, never inline in the
  return. The rule (i) names the surfaces it governs — at minimum the §7
  reviewer verdict returns, [bulk-read offload] returns, and the retry feedback channel
  (`.claude/workflow/retry.md`) — (ii) **records the retry-granularity adjudication
  explicitly**: either the retry channel's verbatim-verdict comment stays verbatim with the
  recorded rationale, or it moves to a bounded structured form via its own reviewed PR
  (constitution P4) — the adjudication outcome and its why both appear in the note; and
  (iii) states what the rule does **not** license: no weakening of verbatim verdict
  posting to the PR (verdict durability, DESIGN-NOTES §2) and no removal of content with
  no surviving home (US2.AC2's relocates-never-deletes posture). Per US6.AC1's posture the
  rule is prose carrying an **explicit constitution-P3 justification recorded in the note
  itself** (why no deterministic check encodes the bound: it is the structural
  no-embedded-analysis-payload shape above, not a numeric threshold a check could
  measure) — never silently prose-by-default. A bare aspirational sentence naming no governed
  surfaces or recording no adjudication does not satisfy this criterion.
- AC3: A design-note entry records the **code-over-prose orchestration principle** with
  its two independent justifications named side by side — removing model judgment from
  load-bearing gate paths (constitution P3) AND keeping accumulated run detail out of the
  dispatching context (the issue-#303 root-context-abstraction rationale) — and explicitly
  designates the §7 prose procedure as the **degradation path** used when no
  [orchestrated run] exists, never the preferred path (consistent with the DESIGN-NOTES
  §12 derived-mirror contract, cited not restated). An entry naming only one of the two
  justifications, or omitting the degradation-path designation, does not satisfy this
  criterion.
- AC4: The maker-eval corpus documentation (`.claude/workflow/maker-eval.md`, or the
  corpus doc it points to) carries a **coverage-by-trajectory-class table**: an enumerated
  taxonomy of the structural task classes the harness runs — at minimum: spec/feature
  implementation, repo-maintenance/docs, bug fix against the base branch, spec
  drafting/amendment, and contract/architecture-touching change — with **every frozen
  golden task assigned to exactly one class** and **every class row naming ≥1 corpus task
  ID or an explicit literal gap marker** (a class with no representative appears as a
  named gap row, never omitted), so corpus completeness resolves to reading one table.
  Because the class descriptions can overlap (a contract-touching bug fix matches two),
  the taxonomy carries a **deterministic assignment rule** — a documented total precedence
  order over the classes, or equivalent mutually exclusive discriminators — under which a
  task matching several class descriptions resolves to exactly one; a table whose classes
  overlap with no recorded assignment rule does not satisfy this criterion. The table's
  coverage invariant is **mechanically enforced**: a standing deterministic check, wired
  into standing verification (`verify`) with the wiring asserted (constitution P2; P3 — an
  invariant a check can settle is never left to by-eye table maintenance), compares the
  table against the complete frozen corpus task set and the declared taxonomy and
  **fails, naming the offending task or row**, on an unassigned corpus task, a task
  assigned to more than one class, or a taxonomy class with neither a corpus task ID nor
  an explicit gap marker; planted omission and duplication fixtures falsify the check in
  its landing diff, with the unmodified real table passing as a control (US4.AC4
  discipline). The table is **documentation of coverage only**: neither the table nor its
  consistency check feeds any gate outcome, eval score, tier assignment, or task selection
  (constitution P5); the frozen instrument's documentation changes only by this
  reviewed-PR path (constitution P4); the existing maker-eval docs/fence checks and the
  neutrality scan stay green over the change (the table names task classes, corpus task
  IDs, and [roles] only — never a mechanism or model, P1). A table with a single catch-all
  class, an unassigned corpus task, or a silently omitted class row does not satisfy this
  criterion.
