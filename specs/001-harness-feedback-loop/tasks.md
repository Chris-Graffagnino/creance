# Tasks — Harness Feedback Loop

> Task-line format: `- [ ] T<nnn> [<tier>] <description> (US<#>)`. The
> `[frontier]`/`[strong]`/`[cheap]` tag is the task's minimum capability tier,
> resolved through `.claude/MODELS.md` at run time.

## Phase 1 — Telemetry foundation

- [x] T101 [strong] Define runtime-neutral telemetry record + storage path
      convention in the workflow layer; add "Telemetry" row to
      `PROJECT.template.md` → "Paths" (US1)
- [x] T102 [strong] Emit gate-run records from the Claude adapter gate loop;
      telemetry write failures never affect gate outcome (US1)
- [x] T103 [strong] Guard block-logging plus a per-gate-run evaluation record
      (liveness signal) + regression tests incl. the silent-failure case (US1)
- [x] T104 [strong] Carry the introducing-change ref (audited head commit) on
      the `gate-run` record — dispatcher-stamped, observe-only — so the
      retrospective's Fact B attribution is deterministic; doc encoding test +
      P-NT probe extension (US1)

## Phase 2 — Surfacing & review throughput

- [x] T201 [cheap] Triage "Gate trends" section with explicit no-data state (US2)
- [x] T202 [cheap] Triage "Discovered-work clusters" section (US2)
- [x] T203 [strong] Risk-ranked PR digest leading the next-task PR body;
      verbatim per-reviewer verdict comments retained unmodified (US4)
- [x] T204 [cheap] Triage "Unacknowledged owner comments" section: unmarked
      owner-login comments newer than the last harness-marked activity, read-only,
      referencing the [comment marker] role (US7)

## Phase 3 — Retrospective back-test

- [x] T301 [strong] Retrospective workflow doc: dispatch, classification
      taxonomy, propose-via-PR rule, strong-tier floor (US3)
- [x] T302 [cheap] Claude Code skill binding for the retrospective;
      dispatches the constitution auditor at-or-above the strong-tier
      floor (US3)
- [x] T303 [cheap] Conformance probe for the retrospective workflow; run on
      the live adapter and record results (US3)

## Phase 4 — Machinery freshness

- [x] T401 [cheap] Probe-run fingerprint (guard script + hook wiring hash)
      recorded with probe results (US5)
- [x] T402 [strong] Triage PROBES-STALE and GUARD-SILENT checks (US5) —
      strong: this machinery guards the guard (see DESIGN-NOTES §4)

## Phase 5 — Issue intake

- [x] T501 [strong] Issue intake: triage "Unmapped tracker work" detection,
      runtime-neutral intake workflow doc + skill binding, README row +
      conformance probe run on the live adapter (US6) — strong: defines how
      owner requests become scope, constitution-screen semantics included

## Phase 6 — PR review

- [x] T601 [strong] Verified PR-review workflow doc (`pr-review.md`) + Claude
      skill binding: ingest the PR diff **and every inline comment** (bot/Codex
      included), ground each finding to current `file:line`, post one
      severity-ranked review; reuse "The review standard" + the `reviewers/`
      specs and change no §7 gate semantics; encoding tests wired into CI
      (#53; new capability scoped in-PR per owner direction — done-when on issue)
      — strong: touches the runtime-neutral workflow boundary (constitution P1)

## Phase 7 — Reviewer roster

- [x] T602 [strong] Collapse the three-place §7 reviewer-set duplication
      (`next-task.md` §7 step 2, `gate-loop.md` "The loop", `gate-loop.js`
      `reviewers` array) into one declarative roster table in `gate-loop.md`,
      repoint `next-task.md` §7 at it, comment the `gate-loop.js` array as
      derived; plus a CI-wired bash drift backstop (`reviewer-roster.test.sh`
      in `verify`) asserting the three sites agree, each reviewer spec exists,
      and each reviewer's agent file excludes edit tools — the test ships in the
      same PR. Representation-only: no gate-semantics change (round limits, veto
      authority, tier floors, parallel fan-out unchanged) (#62; repo-maintenance
      — done-when on issue) — strong: edits the runtime-neutral workflow
      boundary and adds a P2 wiring assertion (constitution P1/P2/P3)
- [x] T603 [cheap] DESIGN-NOTES rationale entry for the reviewer roster + drift
      backstop — a row in the "Things that look like cruft but are not" index —
      so a future maintainer does not collapse it back into three hand-synced
      sites; blocked by T602 (#62; repo-maintenance — done-when on issue)

## Phase 8 — Gate hardening (LFD-delta epics)

> Three out-of-plan epics surfaced by a loss-function-development comparative
> analysis (github.com/elvisun/loss-function-development), intaked from #74/#75/#76.
> Each is engine-maintenance to the review/governance machinery; rubric is the
> done-when criteria carried on its issue (the acceptance reviewer grades against
> those exactly as a `US#`). May be split further at implementation time if a
> done-when exceeds one PR's reasonable scope.

- [x] T604 [strong] Evasion-register: add `reviewers/evasion-register.md`, a
      cumulative, exemplar-based catalog of observed gate evasions
      (`observed evasion → fence`, each with a `file:line` exemplar) that the
      auditors consult at dispatch and the retrospective appends to **via PR**
      (never silently) on HUNT-RULE-GAP / INVARIANT-GAP outcomes; seed it from
      the evasions already implicit in the auditor specs; note the deterministic
      lint each mechanizable exhibit should graduate into (#74; repo-maintenance
      — done-when on issue) — strong: edits the P4-protected reviewer specs and
      the retrospective workflow boundary (constitution P1/P3/P4)
- [x] T605 [strong] Auditor-liveness: promote the one-time `P-RV` reviewer
      conformance probe into a standing planted-violation regression corpus
      (≥1 expected-FAIL and ≥1 expected-PASS fixture per auditor), re-run on
      reviewer-spec change and on a schedule, seeded from retrospective
      incidents; **observe-only** — the liveness signal never feeds gate
      outcomes, tier assignment, or gate semantics (#75; repo-maintenance —
      done-when on issue) — strong: verification machinery guarding the guards,
      with a P5 observe-only boundary (constitution P2/P3/P5)
- [x] T606 [strong] Criteria-gameability: add a gameability screen to
      `intake.md` §4 (for each drafted criterion, name the cheapest way to
      satisfy it without doing the real work; if that path exists the criterion
      is one-sided or trivially satisfiable — tighten it before drafting) and
      mirror it in the acceptance reviewer's intake-conversion check, with an
      encoding test (#76; repo-maintenance — done-when on issue) — strong:
      edits the runtime-neutral intake workflow boundary (constitution P1/P3)

## Phase 9 — Edit-time & execution guardrails (agent-framework-analysis deltas)

> Three deltas surfaced by a comparative analysis of four coding-agent frameworks
> (vercel-labs/coding-agent-template, OpenHands/software-agent-sdk,
> SWE-agent/SWE-agent, SuperClaude_Framework), intaked from #79/#80/#81. Each
> hardens the harness's deterministic-governance surface at the moment work is
> created — edit, selection, execution; rubric is the done-when criteria carried on
> its issue (the acceptance reviewer grades against those exactly as a `US#`). T609
> is an epic and may be split further at implementation time if a done-when exceeds
> one PR's reasonable scope.

- [x] T607 [strong] Edit-time lint/typecheck-and-reject guard: a post-edit
      verification that runs the project's syntax/type check on touched files and
      rejects a change that adds a *new* diagnostic (fix-forward feedback), allowing
      an edit that leaves diagnostics no worse than before; failing open when no
      checker is configured. Ships in the same diff with a **delta-based**
      `guard.test.sh` case (a pre-existing failure + a no-new-diagnostic edit that
      must still be allowed), a matcher-wiring assertion that **enumerates the
      handled edit tools and fails if any is unrouted**, and a new
      invariant-checklist row (#79; repo-maintenance — done-when on issue) —
      strong: changes guard behavior and adds a P2 wiring assertion plus a P3
      determinism backstop (constitution P1/P2/P3)
- [x] T608 [strong] Live-state reconciliation before task selection: a
      deterministic precondition in `next-task.md` selection that reconciles the
      chosen task's checkbox against live tracker/branch state and refuses stale
      work, reusing (not duplicating) `check-tasks-consistency.sh` and failing open
      when tracker state is unavailable; a **paired** test (one open task selected
      + one drifted task refused in the same harness) encodes both the
      merged-but-unchecked refusal and the no-false-positive path (#80; bug —
      done-when on issue) — strong: replaces a prose cross-check with a
      deterministic selection precondition (constitution P1/P3)
> **T609 (epic, #81) — decomposed at implementation time** into the four sub-tasks below
> (T610–T613). The letter-suffix form `T609a` is deliberately **not** used: `[T609a]` fails
> the shared drift lib's `[T<nnn>]` match (`lib-tasks-drift.sh` / `check-tasks-consistency.sh`),
> so each sub-task carries its own 3-digit ID with an independently checkable box (one box →
> one PR → one rule-3 check). The epic umbrella **#81 stays open** until all four land; T609
> itself is intentionally a note here, not a checkbox.

- [x] T610 [strong] (T609a) Isolation model + activation gating: define the runtime-neutral
      `[isolated workspace]` role + the autonomous-mode activation model (off by default;
      engaged only by an explicit in-session authorization or a profile config opt-in;
      absence = review mode; promotion to `main` only via the §7 gate), enforced by a
      deterministic activation check that **fails closed to review**; resolve the
      constitutional question — the `[guard]` keeps its fail-**open** posture because
      isolation moves the wall to the workspace + §7 gate. Ships no worktree/promotion
      machinery (#106; epic #81 part a; repo-maintenance — done-when on issue) — strong:
      defines a runtime-neutral role and resolves a constitution question (P1/P3/P4)
- [x] T611 [strong] (T609b) Adapter: worktree enter/exit lifecycle + wire the activation
      read into the autonomous `next-task` path only (#108; epic #81 part b;
      repo-maintenance — done-when on issue) — strong: adapter execution path under
      autonomy
- [x] T612 [strong] (T609c) Gate-in-place: the §7 loop + auditors read the diff from the
      isolated workspace; the discard path on FAIL (#113; epic #81 part c;
      repo-maintenance — done-when on issue) — strong: gate-semantics boundary (P4)
- [x] T613 [strong] (T609d) Falsification proof: an automated test that an un-gated change
      cannot reach `main`, wired into `verify`, + a conformance probe that the isolation
      tier actually fires live (epic #81 part d; create issue on demand; repo-maintenance —
      done-when on issue) — strong: P2 falsification machinery guarding the wall

> **T614–T615 — `/insights` + PR-#104-review follow-ups to T608's selection reconciliation.**
> Same selection surface as T608 (Phase 9), different provenance: the announce-and-confirm UX
> half (#103, surfaced by the 2026-06-17 `/insights` analysis on #80) and the in-flight-refusal
> half (#105, surfaced by the Codex review on PR #104). Both extend `[live-state reconciliation]`;
> each carries its done-when rubric on its issue. Unblocked: T608 (PR #104) is merged.

- [x] T614 [strong] Announce-and-confirm the resolved next-task target: after the
      deterministic `[live-state reconciliation]` resolves a candidate, announce the resolved
      target before the first file edit, and pause for confirmation on an *implicit* selection
      (no explicit task ID/issue named) whose lowest-unchecked box is contradicted by live
      state — the UX complement to T608's refusal. Runtime-neutral `[role]` for the
      announce/confirm surface in `workflow/**`; concrete prompt mechanism in the adapter
      binding only; degrades to announce-only (no confirm-stall) when live state is
      unavailable; paired test (explicit→no-pause, implicit-contradiction→pause,
      implicit-consistent→no-false-pause) (#103; repo-maintenance — done-when on issue) —
      strong: edits the runtime-neutral workflow boundary (constitution P1/P3)
- [x] T615 [strong] Deterministically refuse in-flight (open-PR/branch) next-task candidates:
      after `[live-state reconciliation]` clears a candidate on the merged/landed axis,
      additionally refuse a candidate whose mapped issue has an open, unmerged PR/branch,
      surfacing the conflict — the in-flight half of the #80 stale-pick pair that T608
      (merged-only) left out. Runtime-neutral tracker read as a `[role]` in `workflow/**`
      (vendor CLI only in the adapter); paired test (in-flight refused + genuinely-open
      selected, no false positive); fails open to merged-only + warning when the tracker is
      unavailable (#105; repo-maintenance — done-when on issue) — strong: edits the
      runtime-neutral selection boundary (constitution P1/P3)

## Phase 10 — Multi-runtime adapters

> Creance ships a Claude Code adapter (`.claude/`) and a spec'd Codex CLI adapter
> (`.claude/adapters/codex-cli.md`). This phase binds the workflow roles to a third
> runtime — **Omnigent** (github.com/omnigent-ai/omnigent), an open-source meta-harness —
> exercising the `.claude/README.md` → "Adding a new adapter (different runtime)"
> procedure. The neutral core (`workflow/**`, `workflow/reviewers/**`,
> `memory/constitution.md`, profile) is consumed **unchanged**; all glue is adapter
> material under `.claude/adapters/omnigent/` (constitution P1: runtime mechanisms live in
> the adapter location, never in `workflow/**`). Rubric is the done-when criteria carried
> on the issue — the acceptance reviewer grades against those exactly as a `US#`. T616 is
> an epic and may be decomposed at implementation time (the T609→T610–T613 pattern) if a
> done-when exceeds one PR's reasonable scope.

> **T616 (epic, #119) — decomposed at implementation time** into the four sub-tasks below
> (T617–T620), following the T609→T610–T613 pattern. The letter-suffix form `T616a` is
> deliberately **not** used: `[T616a]` fails the shared drift lib's `[T<nnn>]` match
> (`lib-tasks-drift.sh` / `check-tasks-consistency.sh`), so each sub-task carries its own
> 3-digit ID with an independently checkable box (one box → one PR → one rule-3 check). The
> rubric is #119's AC1–AC5, **partitioned one-AC-set-per-sub-task** (AC1+AC4 → T617, AC2 →
> T618, AC3 → T619, AC5+Done-when → T620) so the acceptance reviewer grades each sub-task
> against the ACs it owns. Origin issue **#119 is closed** (intake landed via PR #120);
> unlike T609's umbrella #81 it is **not** an open tracker for the epic — completion is
> tracked by the four boxes below. T616 itself is intentionally a note here, not a checkbox.

- [x] T617 [strong] (T616a) Omnigent adapter skeleton + role→mechanism doc + neutral-core
      check: stand up `.claude/adapters/omnigent/` — a `README.md` role→mechanism table
      binding **every** `[role]` in `workflow/README.md`'s binding contract to an Omnigent
      mechanism (or a documented graceful degradation naming the absent runtime feature),
      `MODELS.md` (the adapter's ONLY tier→model table), and the `[environment block]` —
      grounded in Omnigent's real docs, not invented; **plus** the **paired** deterministic
      neutral-core-untouched CI check (a planted Omnigent-mechanism token in a `workflow/**`
      fixture FAILS, the real tree PASSES; no vendor/model names outside
      `.claude/adapters/omnigent/MODELS.md`), runnable in `verify`. No live driver required (#119
      AC1+AC4; T616 epic part a; create issue on demand; repo-maintenance — done-when on
      issue) — strong: defines the adapter binding across the runtime-neutral boundary (P1/P3)
- [x] T618 [strong] (T616b) `[guard]`/`[edit guard]` as Omnigent policies: implement the
      guard rules normatively listed in `workflow/README.md` as deterministic, **fail-open**
      `tool_call`/`tool_result` policies (under `.claude/adapters/omnigent/`) with unit tests —
      `git add .`/`-A`, commit/push-to-base, and base-branch edits return DENY; a passing
      control (explicit-file staging ALLOWED) + adversarial variants, not the literal banned
      strings. Unit-tested only here; real-driver liveness deferred to T620 (#119 AC2; T616
      epic part b; create issue on demand; repo-maintenance — done-when on issue) — strong:
      deterministic governance policy across the boundary (P2/P3)
- [x] T619 [strong] (T616c) Cross-vendor read-only `[reviewer]` sub-agents: three
      `purpose: review` sub-agents that receive the **full review-standard inputs** yet hold
      **no file-mutation capability**, with a deterministic assertion that each resolved
      vendor **differs** from the orchestrator's (expected-FAIL same-vendor, expected-PASS
      cross-vendor) and the constitution auditor's model pinned to `[frontier]`. Config +
      deterministic check here; the **P-RV** real-driver isolation probe deferred to T620
      (#119 AC3; T616 epic part c; create issue on demand; repo-maintenance — done-when on
      issue) — strong: maker≠checker enforced structurally across the boundary (P3/P4)
- [ ] T620 [strong] (T616d) Conformance probes + live integration on a real driver
      (**blocked: Omnigent provisioning** — not on PyPI; needs a from-source install +
      cross-vendor API keys): instantiate `.claude/adapters/omnigent/omnigent-probes.md` per
      `workflow/conformance-probes.md` and **run on a real driver** — guard, reviewer
      (P-RV), and isolation probes record PASS with dated fingerprints (expected-PASS **and**
      expected-FAIL fixtures, the T605 auditor-liveness pattern) — and prove the Done-when:
      `omnigent run …/config.yaml` drives a task in a worktree → three cross-vendor auditors
      gate it → PASS opens a PR (human merges) / FAIL discards; the guard DENYs the banned
      actions live; the neutral-core diff is empty. Closes the epic (#119 AC5+Done-when; T616
      epic part d; create issue on demand; repo-maintenance — done-when on issue) — strong:
      live cross-vendor proof closing the adapter binding (P1/P2/P3/P4)

## Phase 11 — Guard & gate hardening (discovered work)

> Three correctness gaps in the deterministic-governance surface, surfaced *after* the
> Phase 9 agent-framework deltas by later review/audit work: the guard's git-subcommand
> matcher and relative-path handling (engineering-craft audit + the #137 Codex P1 review)
> and the review-mode §7 gate-loop's shared-tree handling (the #139 gate run). Each
> hardens an existing enforcement boundary; rubric is the done-when criteria carried on
> its issue (the acceptance reviewer grades against those exactly as a `US#`). T621 and
> T623 both touch `.claude/hooks/guard.sh` + `guard.test.sh` — whichever lands second
> rebases; no hard ordering dependency.

- [x] T621 [strong] Harden `[guard]` rules 2/3/4 against global-option / cwd evasions in
      **both** guard implementations in parity (`.claude/hooks/guard.sh` and the Omnigent
      port `policies/guard.py`): a leading `git -C <path>` / `-c k=v` / `--git-dir` no
      longer slips past the bulk-staging and commit/push-on-base matchers, and the
      branch-gated rules resolve the **effective** repo (honoring `-C <path>`, best-effort
      a leading `cd <path> &&`) rather than only the event cwd; fail-open posture and a
      safe-control ALLOW preserved; the trailing-slash `git add ./`-operand variant folded
      in. Ships matching cases in **both** `guard.test.sh` and `tests/test_guard.py`
      (#138; bug — done-when on issue) — strong: changes guard behavior across both
      implementations and adds the P2 regression coverage (constitution P2/P3)
- [x] T622 [strong] Stop the review-mode §7 gate-loop (`[orchestrated run]`) from
      relocating the **shared** working tree off the task branch: a read-only auditor's
      `git checkout`/`switch` in the shared tree must not silently move the maker's HEAD,
      while auditors retain correct read access to base state (`git diff main..HEAD` /
      `git show main:<path>` / a throwaway worktree). Encoded by an automated test that
      fails against current behavior and passes after the fix; if the fix constrains
      auditor git usage it is a guard-behavior change shipping its matching test (#140;
      bug — done-when on issue) — strong: protects the gate-execution boundary against
      silent branch-state loss (constitution P2/P3)
- [x] T623 [strong] Close two enforcement-boundary bypasses found in the engineering-craft
      audit: (a) normalize a relative edit `file_path` to absolute against the hook
      cwd/repo root **before** the `in_repo` decision in `.claude/hooks/guard.sh`, so an
      in-repo relative path on the base branch is DENIED while a genuinely-outside relative
      path stays ALLOWED; (b) stop pre-approving `gh pr merge` in default review mode —
      remove the `gh pr merge:*` allow entries from `.claude/settings.json` or add a
      deterministic guard veto gated on explicit session authorization. Ships relative-path
      cases on **both** the PreToolUse edit-on-base and PostToolUse edit-guard paths plus a
      settings/guard regression proving review mode does not pre-approve `gh pr merge`
      (#165; bug — done-when on issue) — strong: base-branch-mutation and merge boundaries
      with their P2 regression coverage (constitution P2/P3/P4)

## Phase 12 — Documentation & adapter-consistency intake (discovered work)

> Four owner-filed issues surfaced by triage as unmapped tracker work, converted via
> intake (`workflow/intake.md`): three docs gaps in the template/onboarding surface
> (#11, #17, #16) plus one example-adapter roster-consistency gap (#150). Each is
> repo-maintenance — no new `US#`; the acceptance reviewer grades each against the
> done-when criteria carried in the issue's intake cross-link comment, exactly as it
> would a `US#`. T626 (#17) and T627 (#16) are companions, but not unordered: T626
> produces the worked-example set, and T627 is blocked by T626 because the onboarding
> prompt points at that set as the target shape.

- [x] T624 [cheap] Add a short **"Finding things in this repo"** recipe block to
      `.claude/PROJECT.template.md` — a bounded, known-cost lookup path for the adopted
      project's growing `specs/` tree (the engine mandates search-first but ships no recipe
      for mining its own artifact tree). The block carries at least the four lookup recipes
      (story acceptance criteria, a task line by ID, a contract by capability/seam, an
      invariant by keyword), each a runnable `rg` recipe in the file's existing `<...>`
      placeholder style, and references **only** path conventions the engine already
      documents (`specs/*/spec.md`, `specs/*/tasks.md`, `specs/*/contracts/`,
      `memory/constitution.md`, `.claude/PROJECT.md`) — no new path convention invented.
      Neutral layer (`workflow/**`) untouched (#11; repo-maintenance — done-when on issue)
      — cheap: a docs-only addition to the profile template with no judgment over engine
      invariants
- [ ] T625 [strong] Mirror the neutral §7 reviewer roster's fourth member into the
      **Omnigent example adapter**: add `.claude/adapters/omnigent/reviewers/spec-quality.yaml`
      with `purpose: review`, a vendor different from the implementer (cross-vendor
      isolation), read-only (no file-mutation `os_env`), and the `[strong tier]` floor
      (strong-floored like the constitution reviewer); extend `tests/test_reviewers.py`'s
      `REVIEWERS` set so the new YAML is covered by the cross-vendor / read-only / tier-pin
      property checks; and wire it into the Omnigent orchestrator's `dispatch-spec`
      condition (`config.yaml`, the gate-loop surface T620 lands) so a
      spec-touching diff actually dispatches it. Full `verify` green, Python adapter tests
      included; blocked by T620 (#150; repo-maintenance — done-when on issue) — strong:
      example-adapter review-roster semantics and its cross-vendor/read-only/tier-floor
      property surface
- [x] T626 [strong] Ship a **worked-example set** under `docs/examples/` for a clearly
      labeled **fictional** project: a filled `PROJECT.md` (every required heading, an
      invariant→enforcement mapping with ≥1 judgment-only row and ≥1 deterministic-backstop
      row), a filled `memory/constitution.md` (3–4 enforceable failure-mode-hunting
      principles), one `spec.md` + matching `tasks.md` slice (≥1 `US#.AC#` story, tier tags,
      the criterion-ownership mapping) + one contract file for a swappable seam, and a
      **macOS/Linux [environment block] example** explicitly labeled non-live (the
      single-copy rule stands). Internally consistent (spec `US#`s match the tasks file;
      the contract matches a seam named in the example `PROJECT.md`; the constitution's
      principles appear in the invariant checklist); the fiction exercises the hard cases
      (≥1 architecture boundary with a banned vendor, ≥1 blocked/owner-only task, ≥1
      principle with a deterministic backstop); each template file gains a one-line pointer
      to its example and the README names the set in the Quickstart/reading order;
      `.claude/EXTRACTION.md` §5 greps still pass over the whole tree with the examples
      added and no model name appears outside `MODELS.md`; `workflow/**` untouched (#17;
      repo-maintenance — done-when on issue) — strong: judgment-heavy authoring that must
      preserve the neutrality (P1) and single-[environment-block] invariants
- [x] T627 [strong] Ship **`docs/onboarding-prompt.md`** — a self-contained prompt an
      adopter pastes into their agent (executable cold, no prior context), linked from the
      README Quickstart. The prompt encodes as **explicit instructions** (not commentary)
      the three constraints that fall out of the harness's own design: (1) **interview, do
      not ghostwrite, the constitution** — elicit and transcribe principles, never draft
      plausible ones, and warn the owner what is written is enforced as law; (2)
      **onboarding obeys the harness it installs** — run setup as the project's first
      issue + branch + PR, with probe/grep outputs as the PR's automatic evidence; (3) **end
      on artifacts, not say-so** — the final steps run the probes
      (`.claude/adapters/claude-code-probes.md`), the `.claude/EXTRACTION.md` §5 greps, and
      a concrete residual-placeholder grep, reporting anything unanswerable as an open item.
      The prompt states the fill order, agrees step-for-step with the Quickstart (same fills,
      same order, same verification — a drift is a doc bug), points at the T626 worked-example
      set as the target shape, and states the runtime caveat that verification assumes
      `rg`/`bash`; blocked by T626 (#16; repo-maintenance — done-when on issue) — strong:
      encodes harness-design constraints and must stay in lockstep with the Quickstart

## Phase 13 — Configurable review passes (US8)

> Owner-filed #187, converted via intake (`workflow/intake.md`): a new capability — the
> **skill-backed** review passes (`[code-review pass]` / `[security-review pass]` / `[craft-review pass]`)
> become an owner-editable declarative set in the profile, while the **law-bearing roster
> reviewers stay engine-governed** (US8.AC5; constitution P4). Extends the Phase 6 PR-review
> surface; graded against **US8** in `spec.md`. T629/T630/T631 carry the blockers on their
> lines.

- [ ] T628 [strong] `## Review passes` schema in `PROJECT.template.md` (column schema with
      **every column domain closed/typed** — legal `pass` roles, boolean `enabled`, closed
      `condition` enum, closed `applies-to` enum `gate`/`pr-review`/`both`, at-most-one-row-
      per-pass) plus one well-formed row per currently-shipped skill-backed pass in
      `.claude/PROJECT.md`; repoint **all three selection surfaces** — `pr-review.md`, the
      review standard (`workflow/README.md`), and the §7 gate's advisory-pass step
      (`next-task.md` §7 step 3) — at "the profile's review-pass set" ([roles] only),
      removing the hardcoded pass enumeration, `workflow/**` neutrality grep green (US8) —
      strong: edits the runtime-neutral workflow boundary + the profile schema (constitution
      P1/P3)
- [ ] T629 [strong] Both surfaces honor the enabled set whose `condition` holds, filtered by
      `applies-to` (`pr-review` runs `pr-review`/`both`; the §7 gate's advisory step runs
      `gate`/`both`); `pr-review`'s §5 output distinguishes **disabled → silent** from
      **enabled-but-mechanism-absent → loud** (named in the PR body, never silently dropped);
      blocked by T628 (US8) — strong: a runtime-neutral workflow-output contract (constitution
      P1/P3)
- [ ] T630 [strong] `review-pass-roster.test.sh` (sibling to `reviewer-roster.test.sh`,
      wired into CI `verify`) pins the profile rows against the adapter-mapped shipped pass
      set: FAILs on enabled-but-unmapped, **adapter-mapped-shipped-pass-missing-from-profile**
      (the silent-drop parity gap), duplicate row, and off-enum `condition`/`applies-to`,
      **and** rejects a row naming/disabling **any §7 roster auditor (acceptance /
      constitution / contract / spec-quality)**, while PASSing on the real skill-only roster
      (paired flag-defect / pass-control); blocked by T628, T629 (US8) — strong: a P2/P3
      deterministic backstop guarding the maker≠checker boundary (constitution P2/P3/P4)
- [ ] T631 [cheap] Generalize the `P-CRAFT` conformance probe to a per-enabled-pass probe in
      the neutral checklist, instantiate for the Claude Code adapter, run live, and record
      per-enabled-pass dispatch in the adapter probe-results table; blocked by T629 (US8) —
      cheap: a mechanical probe instantiation + recorded live run

## Criterion ownership (multi-task user stories)

| Criterion | Owning task |
|---|---|
| US1.AC1 | T101 |
| US1.AC2 | T102 |
| US1.AC3 | T103 |
| US1.AC4 | T103 |
| US1.AC5 | T104 |
| US2.AC1 | T201 |
| US2.AC2 | T202 |
| US2.AC3 | T201 |
| US2.AC4 | T202 |
| US3.AC1 | T301 |
| US3.AC2 | T301 |
| US3.AC3 | T301 |
| US3.AC4 | T301 |
| US3.AC5 | T302 |
| US3.AC6 | T303 |
| US4.AC1 | T203 |
| US4.AC2 | T203 |
| US4.AC3 | T203 |
| US5.AC1 | T401 |
| US5.AC2 | T402 |
| US5.AC3 | T402 |
| US6.AC1 | T501 |
| US6.AC2 | T501 |
| US6.AC3 | T501 |
| US6.AC4 | T501 |
| US6.AC5 | T501 |
| US6.AC6 | T501 |
| US7.AC1 | T204 |
| US7.AC2 | T204 |
| US7.AC3 | T204 |
| US7.AC4 | T204 |
| US8.AC1 | T628 |
| US8.AC2 | T628 |
| US8.AC3 | T629 |
| US8.AC4 | T630 |
| US8.AC5 | T630 |
| US8.AC6 | T631 |

## Blocked / owner-only tasks (never auto-start — surface them instead)

- none

> Note (not a blocker): T101 carries one design default — telemetry lives
> out-of-repo alongside the triage inbox (keeps project repos clean, matches
> the existing triage convention). The owner may override to in-repo on issue
> #18 any time before T101 starts; silence keeps the default.
