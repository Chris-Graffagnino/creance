# Spec — Held-Out Acceptance Checks

> Epic for the Creance repo itself. The acceptance [reviewer] (`spec-auditor`) grades
> each task against the `US#` acceptance criteria below — bullets are addressable as
> `US1.AC1`, `US1.AC2`, … (the nth bullet under that story), so they are written as
> independently checkable statements.

## Overview

Makers overfit to visible checks. EdgeBench (ByteDance Seed, 2026-07-02,
https://edge-bench.org/paper.pdf §2.3) keeps hidden test cases, hidden seeds, and
private rubrics in a separate judge container precisely because agents "over-trust
local proxies" — they tune to whatever evaluation they can see. Creance's maker≠checker
gate separates the checker's *context* but not its *evidence*: the acceptance [reviewer]
grades against the same visible spec and tests the maker optimized toward, so a diff
tuned to the visible rubric alone can pass on overfitting. This spec adds a per-spec,
owner-curated **held-out check set** the acceptance [reviewer] additionally grades
against — stored out of the maker's reach, its integrity pinned in-repo by a content
hash so every change keeps a reviewed evidence trail (constitution P4) without revealing
content. Sequencing note: deliberately after spec 003's trajectory work (#211), whose
records show *whether* makers actually overfit to visible checks before this pays for
the fix. Done means: a planted failing held-out check FAILs a fixture diff the visible
rubric passes, a maker-phase read of the channel is deterministically denied, and a
held-out change without a reviewed manifest update is surfaced in triage.

Motivation and provenance: intake of issue #213 (EdgeBench paper review session,
2026-07-02). The task-ID block (T10xx, 4-digit) was owner-ratified on #213.

## Non-goals

- No change to gate semantics: round limits, veto authority, tier floors, and the
  reviewer roster's membership and dispatch conditions all stay (the spec 001 non-goals
  posture; what changes is the acceptance reviewer's *evidence*, by its own spec).
- The visible `US#` criteria remain the primary rubric — held-out checks supplement,
  never replace or shadow them, and a spec with no held-out set stays fully gradable.
- No per-run generated checks: generation is nondeterministic and unauditable; the fixed
  per-spec set is the deliberate choice (the #213 design fork, resolved for determinism —
  constitution P3). Recorded here as the rejected alternative.
- No hidden law: the constitution and the invariant checklist stay fully visible — only
  acceptance *test cases* are held out.
- No auto-generation, auto-tightening, or run-side mutation of held-out checks
  (constitution P4: reviewed change trail, always).

## User stories

### US1 — The held-out channel and its fence
As a harness operator, I want a per-spec held-out check set stored outside the maker's
reach with its integrity pinned in-repo, so that acceptance checks the maker never saw
stay both hidden and change-audited.

**Acceptance Criteria**
- AC1: A runtime-neutral workflow doc defines the held-out check set: per-spec,
  owner-curated, fixed between changes; stored **out-of-repo** at a profile-named path
  (`.claude/PROJECT.md` → "Paths" — its own channel, distinct from the telemetry and
  maker-eval channels); each entry maps to a `US#` and is independently verifiable by
  the acceptance [reviewer] **from read-only evidence**: an entry is either directly
  read-verifiable, or names a deterministic execution step that runs **outside the
  reviewer** (dispatcher-side, per the doc's [roles]) and writes result artifacts the
  reviewer reads — the acceptance [reviewer]'s shell-less construction (#188) is never
  relaxed to execute entries; the doc names **[roles]** only (constitution P1).
- AC2: An **in-repo manifest** records a content hash of each spec's held-out set; a
  hash update lands only by reviewed PR (constitution P4 — the evidence trail without
  the content), and triage surfaces an observe-only **HELD-OUT-DRIFT** warning when the
  channel's current hash differs from the manifest (constitution P5: warn, never gate),
  with explicit no-channel and no-manifest empty states — never silently omitted, never
  an error.
- AC3: The maker-role context **never reads the held-out channel**: a deterministic
  mechanism denies maker-phase reads of the channel path, proven live by a
  falsification test that fires on a planted maker-phase read of the channel AND passes
  a control where the acceptance [reviewer]'s dispatch consumes the same content
  (enforcement is deterministic, not prompt discipline — constitution P2/P3); the
  enforcement change ships its matching test cases in the same diff, wiring assertion
  included (constitution P2). A test exercising only the denial direction does not
  satisfy this. The fence governs the **stored set**, not the gate's feedback: a failed
  entry named in a FAIL report reaches the maker through the ordinary fix round
  (US2.AC1's reveal-by-failure path) — that is burning by design, not a fence breach,
  and requires no change to fix-round handling (the "no change to gate semantics"
  non-goal holds).

### US2 — Grading against held-out checks
As a harness operator, I want the acceptance reviewer to grade the mapped US#'s held-out
checks in addition to the visible criteria, so that a diff tuned to the visible checks
alone cannot pass on overfitting.

**Acceptance Criteria**
- AC1: The acceptance [reviewer]'s spec gains a held-out step: for the task's mapped
  `US#`, verify each held-out entry against its read-only evidence (where an entry
  needs execution, that happens in US1.AC1's deterministic step outside the reviewer —
  the reviewer reads its result artifacts, never executes); a failing entry is a
  blocking FAIL whose report names the failed entry — the burned entry is thereby
  revealed (to the maker as early as the next fix round, per US1.AC3's fence scope),
  which is the feedback loop working; a burned entry is spent, and its retirement or
  replacement travels the US1.AC2 reviewed-manifest path — while unrevealed entries
  stay unrevealed: the report never enumerates the set nor reveals entries that passed.
- AC2: Absence degrades loudly, never silently: when a spec has no held-out set, or the
  channel is unreachable, the reviewer's report states so explicitly and grades the
  visible rubric unchanged — a silent skip, and a FAIL issued solely for channel
  absence, each violates this.
- AC3: A two-sided conformance probe proves the channel is load-bearing on the live
  adapter: a planted failing held-out entry FAILs a fixture diff that the visible rubric
  passes, and the clean control (the same diff with a satisfying held-out set) passes —
  results recorded with independently readable artifacts (the spec 001 US8.AC6 evidence
  rule: a bare self-assertion does not satisfy this).
