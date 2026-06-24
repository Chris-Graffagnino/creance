# Spec — Spec-Quality Gate

> Epic for the Creance repo itself. The acceptance [reviewer] (`spec-auditor`)
> grades each task against the `US#` acceptance criteria below — bullets are
> addressable as `US1.AC1`, `US1.AC2`, … (the nth bullet under that story), so
> they are written as independently checkable statements.

## Overview

Creance grades every implementation against its spec but trusts the spec itself:
an ambiguous, contradictory, or gameable acceptance criterion is faithfully
certified the moment code matches it. This spec applies the harness's maker ≠
checker discipline one phase upstream. An adversarial, read-only [reviewer] grades
the spec content *in a diff under review* for testability, internal consistency,
unstated edge cases, gameability, and undocumented architecture calls; it is
dispatched deterministically whenever a diff touches a `specs/*/spec.md`; the
unambiguously-mechanizable smells fail in a CI lint, and the judgment reviewer
owns only the subtler forms. Done means: a `spec.md` cannot reach a gate PASS
without an adversarial quality verdict, and the mechanizable smells fail
deterministically in CI.

Motivation and provenance: the "New SDLC with vibe coding" analysis
(https://addyosmani.com/blog/new-sdlc-vibe-coding; the Kaggle whitepaper),
2026-06-23 — "specification is the bottleneck." Both stories extend patterns
Creance already owns: maker ≠ checker, the auditor-liveness corpus (T605), and the
intake gameability screen (T606). Issue: #142.

## Non-goals

- The reviewer never edits a spec — it reports; a human resolves in the spec PR
  (constitution P4).
- No new binding-contract **[role]** — reuses the existing [reviewer] role
  (constitution P1).
- No change to the §7 gate's control flow (round limits, veto authority, tier
  floors, parallel fan-out); US2 adds a roster *member* under a new *deterministic*
  dispatch condition only.
- Not a substitute for human architecture judgment — the reviewer flags an
  *undocumented* trade-off; it never makes the call (the analysis's "stubbornly
  human phase").

## User stories

### US1 — The adversarial spec-quality reviewer
As a harness operator, I want a read-only reviewer that adversarially grades the
spec content in a diff under review, so that a bad acceptance criterion is caught
before any code is written against it.

**Acceptance Criteria**
- AC1: A runtime-neutral reviewer spec (a new `reviewers/` entry) defines an
  adversarial, read-only **[reviewer]**: inputs are the added/edited spec content
  in the diff plus `memory/constitution.md`; for each criterion it hunts (a)
  untestability — no test could encode it as stated; (b) internal contradiction —
  one criterion negates or duplicates another; (c) unstated edge/negative cases the
  criterion implies but omits; (d) gameability — the cheapest way to satisfy it
  without doing the real work (generalizing the intake §4 / T606 screen); (e) an
  undocumented architecture/trade-off call the criterion forces but the spec leaves
  unrecorded. Output is PASS / FAIL with evidence addressed as `US#.AC#`. It names
  **[roles]** only — no concrete mechanism, vendor, or model (constitution P1).
- AC2: The reviewer holds **no file-mutation capability** and never edits the spec
  — it reports findings only, for a human to resolve in the spec PR (constitution
  P4); it consults `reviewers/evasion-register.md` at dispatch and cites the
  matching exhibit, exactly as the existing auditors do.
- AC3: It is dispatched **at or above the [strong tier]** with an explicit model
  resolution — an absent or below-strong selection is a guard veto, reusing guard
  rule 5's mechanism, not a new gate — because the spec is the cheapest place to
  lose a project (constitution P2/P3; the constitution-reviewer floor precedent,
  DESIGN-NOTES §6).
- AC4: The reviewer ships with a known-bad / known-good fixture pair in the
  auditor-liveness corpus (`reviewers/auditor-liveness-corpus.md`) — ≥1
  expected-FAIL spec (e.g. a contradictory AC pair) and ≥1 expected-PASS — so the
  judgment reviewer is proven live and stays so under model drift (constitution
  P2/P3; the T605 pattern). Liveness stays observe-only — it never feeds a gate
  outcome (constitution P5).

### US2 — Deterministic dispatch, the mechanizable backstop, and dedup
As a harness operator, I want the reviewer to fire deterministically on exactly
the diffs that change a spec, with the mechanizable smells caught by a CI lint and
the gameability rule shared with intake, so the gate's load-bearing path stays
deterministic and no rule is forked.

**Acceptance Criteria**
- AC1: The reviewer is added to the gate roster (`gate-loop.md`) under a third
  **deterministic** dispatch condition — a diff that adds or edits a
  `specs/*/spec.md` — alongside `always` / `dispatch-contract`, with both derived
  mirrors (the `next-task.md` §7 prose and the `gate-loop.js` array) and the drift
  test (`reviewer-roster.test.sh`) updated in the same diff (DESIGN-NOTES §12). The
  condition is deterministic; no model judgment lands on the dispatch decision
  (constitution P3; §12's two-value restriction widened to a third *deterministic*
  value, preserving the property).
- AC2: On a diff touching no `spec.md`, the reviewer is not dispatched and the gate
  runs exactly as before — no gate-semantics change for non-spec work.
- AC3: A **deterministic CI lint** over `specs/*/spec.md` FAILs the unambiguously-
  mechanizable smells — an empty AC bullet, a `US#` with zero ACs, an AC duplicated
  verbatim within a story — and the [reviewer] owns only the subtler judgment (the
  `AGENTS.md`-residency pattern: a deterministic backstop with the auditor owning
  the subtle form; constitution P3, "add the backstop"). The lint ships with a
  `.test.sh` proving it fires on planted smells and does not false-fire on a clean
  spec (constitution P2).
- AC4: The intake workflow's §4 gameability screen delegates to this reviewer's
  gameability check rather than carrying a forked copy of the rule — one
  definition, two consumers (the spec gate and intake) — with a test so a re-fork
  FAILs CI (the P2 anti-duplication pattern, cf. `lib-tasks-drift.sh`).
- AC5: A skill/agent binding exposes the reviewer, reusing the existing
  **[reviewer]** binding-contract role — no new role — and a conformance probe for
  the spec-touch dispatch is added to the neutral checklist, instantiated for the
  active adapter, and passes on it with results recorded.
