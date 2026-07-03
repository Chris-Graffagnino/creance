# Spec — Adoption Context Preservation

> Epic for the Creance repo itself. The acceptance [reviewer] (`spec-auditor`) grades
> each task against the `US#` acceptance criteria below — bullets are addressable as
> `US1.AC1`, `US1.AC2`, … (the nth bullet under that story), so they are written as
> independently checkable statements.

## Overview

Creance's onboarding is greenfield-only: the README Quickstart and `.claude/EXTRACTION.md`
document one direction — start a *new* project from the template. Adopting the harness
into a project that **already exists** has no documented path and no guard, and a
template-style install threatens two of that project's three context layers: the
**profile files it would overwrite** (a real `memory/constitution.md`,
`.claude/PROJECT.md`, or `specs/` tree silently clobbered by template copies — the very
files the reviewers enforce as law), and the **out-of-repo agent memory it would
orphan** (durable design rationale stranded in a per-project store the install neither
imports nor mentions, then lost to a machine migration or invisible to a cold/headless
run). The failure is silent and destructive — the class this repo treats as first-class
(DESIGN-NOTES §"the guard was silently dead"; constitution P2's posture) — and it
generalizes Creance's own extraction thesis: `.claude/DESIGN-NOTES.md` exists *because*
out-of-repo memory doesn't survive a copy. This spec promotes that one-time observation
into a standing onboarding contract: **adoption preserves pre-existing context — it
never overwrites or orphans it** — via a documented non-destructive adoption path
(US1), a deterministic preservation guard and conformance probe (US2), a one-time
context-promotion procedure whose prune is coverage-gated so the cure cannot introduce
a new silent loss (US3), a standing prevention rule so promoted-once context does not
re-accumulate as orphan risk (US4), and a recurring consolidation pass bounding the
always-loaded recall index promotion would otherwise quietly inflate (US5). The third
context layer — git history, issues, PRs — is safe by construction (an install cannot
reach it) and out of scope.

Motivation and provenance: intake of issue #78 (filed 2026-06-15, plus its two
refinement comments: the coverage-gated prune with its worked downstream example, and
the recall-index budget with the discoverability-gated pointer rule). Complements
#16/T627 (`docs/onboarding-prompt.md` — *filling* a profile via interview; this spec
covers *not destroying* one that already exists) and #17/T626 (worked examples). The
task-ID block is **T11xx** (4-digit format owner-ratified on #213; block assignment
ratified by merging this spec's conversion PR).

## Non-goals

- No change to the greenfield Quickstart: it stays the fast path for a new project;
  adoption is a **second** documented direction beside it, not a replacement.
- No autonomous reconcile decisions: where an existing profile artifact and template
  content conflict, the adoption path surfaces the conflict and the **adopter**
  decides — the harness proposes, the human ratifies (the P4 posture applied to the
  adopting repo's law).
- The third context layer (git history, issues, PRs) is out of scope — no adoption
  step reads, rewrites, or migrates it.
- No blind pruning: no memory content is deleted except through US3's coverage-gated
  path — a promotion step that deletes unverified content is a defect of this spec's
  own failure class, never a permissible shortcut.
- The consolidation pass (US5) maintains memory surfaces only; reviewer specs, guards,
  invariants, and the constitution stay PR-only (constitution P4, unchanged), and no
  index/memory state ever gains gate authority (constitution P5, unchanged).

## User stories

### US1 — A documented, non-destructive adoption path
As a project owner adopting Creance into an existing repo, I want a documented adoption
path alongside the greenfield Quickstart that treats my existing profile artifacts as
inputs to reconcile, so that installing the harness can never silently destroy my
project's law, profile, or scope.

**Acceptance Criteria**
- AC1: A documented adoption path ("adopting Creance into an existing project") exists,
  discoverable from the same surface as the greenfield Quickstart (the README links
  both directions); it names the profile artifacts — the constitution, the project
  profile, and the specs tree — as **reconcile inputs, never overwrite targets**, and
  states per artifact the reconcile procedure (what the adopting repo keeps, what
  merges, where template content goes when a real artifact already exists). A doc that
  anywhere instructs copying a template file over an existing profile artifact violates
  this criterion.
- AC2: The reconcile procedure derives from `.claude/EXTRACTION.md`'s GENERICIZE/TEMPLATE
  cut-list **run in reverse** — every profile-artifact entry that list marks has a
  named adoption action, enforced by a deterministic coverage check (a lint or test
  that fails when a cut-list profile entry has no adoption mapping) so the two
  directions cannot drift apart; the check is **wired into the repo's standing
  verification** with the wiring asserted (a check that exists but never runs is the
  silently-dead-guard class this spec exists to prevent — constitution P2), and a
  hand-maintained second list with no such check does not satisfy this.
- AC3: The adoption path composes with the agent-assisted onboarding prompt
  (`docs/onboarding-prompt.md`, #16/T627): the prompt itself states the branch
  condition — a target repo with any pre-existing profile artifact takes the
  reconcile/adoption branch, never the fill-from-template branch — so an agent-driven
  onboarding cannot route an existing project down the greenfield path. A prompt that
  merely links the adoption doc without the branch condition does not satisfy this.

### US2 — The preservation guard and the conformance probe
As an adopter, I want deterministic machinery that refuses to clobber my existing
profile artifacts and proves after install that nothing was silently overwritten, so
that "adoption succeeded" can never read as "context preserved" when it wasn't.

**Acceptance Criteria**
- AC1: A deterministic pre-adoption check — runnable standalone and invoked by the US1
  adoption path before any template file lands — detects each existing profile
  artifact the adoption doc names and **refuses to proceed, loudly** (non-zero exit,
  the artifacts named) when a template copy would overwrite any of them, forcing the
  explicit reconcile path instead. The check **fails closed** (unreadable state or any
  uncertainty → refuse) — the deliberate inverse of the harness [guard]'s fail-open
  posture, because the operation it fences is destructive and unattended.
- AC2: The check ships in the same diff as its falsification tests, covering **both**
  directions: a planted would-clobber fixture (a pre-existing artifact present) is
  refused with the artifact named, AND a clean greenfield fixture (no pre-existing
  artifacts) proceeds without a refusal — a test exercising only the refusal direction
  does not satisfy this (constitution P2/P3). AC1's fail-closed branch is fixtured
  too: a planted unreadable/uncertain state (an artifact whose presence cannot be
  determined) is refused, not proceeded past — untested, the fail-closed clause is
  words. The tests are **wired into the repo's standing verification** with the
  wiring asserted — unwired tests are the same silently-dead-guard class as an
  unwired check.
- AC3: A post-adoption conformance probe captures a content fingerprint of each
  pre-existing profile artifact **before** install and asserts **after** install that
  each is unchanged — or changed only by a reconcile decision the **adopter
  ratified**, recorded in an artifact **independent of the install run's own
  output**: the install logging its own overwrite as "reconciled" never satisfies the
  exemption (otherwise the run being audited certifies itself and the preservation
  guarantee is bypassed — the non-goal stands: the harness proposes, the adopter
  ratifies). The probe is proven in all three directions: a planted silent overwrite
  FAILs, an overwrite-free control run passes, AND a changed artifact passes only
  when its adopter-ratified reconcile record is present — the same change with no
  record (or with only the install's self-reported log) FAILs; results recorded as
  independently readable artifacts (the spec 001 US8.AC6 evidence rule: a bare
  self-assertion does not satisfy this). The captured fingerprints live **outside the
  install-target paths** — a fingerprint stored where the install writes could be
  clobbered by the very overwrite it exists to detect.

### US3 — One-time context promotion with a coverage-gated prune
As an adopter, I want an adoption-time procedure that audits the project's out-of-repo
agent memory and promotes durable, load-bearing facts into the repo, with any prune
gated on verified coverage, so that adoption captures existing context instead of
stranding it — and the cure never introduces a new silent loss.

**Acceptance Criteria**
- AC1: The adoption path defines the promotion procedure as **triage → promote →
  coverage-check → terminal state**, where triage is selective (cross-project and
  standing-preference memories are explicitly kept in agent memory — the documented end
  state is "scratchpad + recall index", never an emptied memory store), and the
  per-fact terminal state applies the **discoverability gate**: **delete** the memory
  when its repo home is self-discoverable by a cold instance (a well-named, indexed
  section), a **pointer** only when the home is not — pointer as the exception, never
  the default; a memory tracking a finished effort is **retired**, not pointered.
- AC2: The prune is gated **fact by fact** on the coverage-check: a fact leaves memory
  only after verification that it landed at its named repo home, and the gate is
  proven in both directions — a planted fixture where one fact's repo home is missing
  blocks **that fact's** prune (the covered facts still prune), and a fully-covered
  control prunes clean; a check exercising only one direction, or one that gates the
  batch instead of each fact, does not satisfy this.
- AC3: Promotion provenance — which adoption run, effort, or batch promoted a fact —
  lands in the repo's change history only, never in the always-loaded recall index: an
  index line carrying promotion provenance violates this criterion.
- AC4: The neutral/adapter split holds (constitution P1): any text of this procedure
  resident in `workflow/**` names the memory store as a bracketed role only; the
  concrete store location (a per-project, out-of-repo memory directory) appears only
  in adapter- or docs-layer files, and the neutrality scan stays green over every
  neutral doc the change touches.

### US4 — The standing prevention rule (durable facts go to the repo)
As a harness operator, I want a standing per-task rule that durable, non-obvious facts
surfaced during a run land in the repo — the system of record — not only in out-of-band
agent memory, so that a one-time promotion is not followed by immediate re-accumulation
of the same orphan risk.

**Acceptance Criteria**
- AC1: The rule ships as **two coordinated pieces in the same change**, each
  cross-referencing the other: a rationale entry in `.claude/DESIGN-NOTES.md` (adapter-aware —
  it may name the concrete store and why it is orphan-prone) and an operational
  trigger in the per-task loop (mechanism-neutral — no tool, vendor, model, or store
  name). A single-location version — rule without rationale, or rationale without an
  in-loop trigger — violates this criterion, because each alone has a documented
  failure mode (the rule gets "simplified" away; the rationale never fires).
- AC2: The operational piece lands within the existing accretion bounds: the per-task
  doc's line-budget check stays green — the budget is at its ceiling, so the trigger
  lands pointer-style into a workflow sub-doc or with compensating trim, never via a
  budget bump — and the neutrality scan stays green over the touched neutral docs.

### US5 — The recurring index-consolidation pass (steady-state GC)
As a harness operator, I want a recurring consolidation pass over the always-loaded
recall index — merge duplicates, fix stale entries, discoverability-gate pointers,
retire finished trackers — so that promotion does not trade orphaned memory for a
monotonically growing always-loaded surface.

**Acceptance Criteria**
- AC1: A consolidation procedure exists with a named cadence hook (invoked from the
  triage heartbeat or as its own scheduled entry point, per the profile) defining all
  four actions — merge duplicate entries, correct or remove stale facts, re-apply
  US3.AC1's discoverability gate to every standing pointer, retire finished-effort
  entries — plus an explicit "nothing to consolidate" empty state; a silent no-op run,
  or a procedure defining only a subset of the four actions, does not satisfy this.
- AC2: The pass enforces a deterministic bound on the always-loaded index (a line or
  size ceiling **stated in the profile, owner-ratified** — never a value the pass
  chooses or adjusts itself), surfaced when exceeded as an actionable, observe-only
  finding: it warns and names the overage, and no gate, tier, guard, or selection
  path reads it (constitution P5's posture applied to the memory surface).
- AC3: Every consolidation edit stays within the memory surfaces (the recall index and
  per-fact memory files, under US3.AC2's coverage gate for any deletion); the pass
  never edits reviewer specs, guards, invariants, or the constitution (P4 unchanged),
  and changes to the pass's own procedure land only by reviewed PR.
