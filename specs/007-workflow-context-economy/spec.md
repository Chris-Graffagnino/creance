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
#259 — see **Amendment** below): a repository token counter with documented,
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
