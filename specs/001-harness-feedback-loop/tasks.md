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
- [ ] T649 [strong] Extend the `#256` normalized-payload sweep to `[guard]` **rule 2**
      (bulk-staging `git add --all|-A|./`) in **both** implementations in parity
      (`.claude/hooks/guard.sh` and the Omnigent port `policies/guard.py`): rule 2 must
      apply the #256 tab-normalization plus a quote-aware evaluation that treats a
      fully-quoted `git add …` occurrence as inert data yet sees through quotes on the flag
      operand of an unquoted `git add`, so a tab-escaped `git add<TAB>-A` and a quoted-flag
      `git add "-A"` are DENIED (they currently slip past as exit-0 ALLOW — the #256 sweep
      never reached rule 2, which still matches the raw payload),
      while benign controls — a specific path `git add path/to/file`, and a non-git command
      merely mentioning `-A` inside a quoted string — stay ALLOWED, and the existing bare
      `git add ./` / `--all` / `-A` block is preserved. Ships matching mutation-proof cases
      in **both** `guard.test.sh` and `tests/test_guard.py` (the planted evasions block, the
      benign controls allow; reverting the fix flips the planted cases red)
      (#265; bug — done-when on issue) — strong: changes guard behavior across both
      implementations and adds the P2 regression coverage (constitution P2/P3)

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

- [x] T628 [strong] `## Review passes` schema in `PROJECT.template.md` (column schema with
      **every column domain closed/typed** — legal `pass` roles, boolean `enabled`, closed
      `condition` enum (`sensitive-diff` bound to the existing `[security-review pass]`
      trigger in the review standard — the profile's privacy/location/payment invariants —
      not a new surface), closed `applies-to` enum `gate`/`pr-review`/`both`,
      at-most-one-row-per-pass) plus one well-formed row per currently-shipped skill-backed
      pass in
      `.claude/PROJECT.md`; repoint **all three selection surfaces** — `pr-review.md`, the
      review standard (`workflow/README.md`), and the §7 gate's advisory-pass step
      (`next-task.md` §7 step 3) — at "the profile's review-pass set" ([roles] only),
      removing the hardcoded pass enumeration, `workflow/**` neutrality grep green (US8) —
      strong: edits the runtime-neutral workflow boundary + the profile schema (constitution
      P1/P3)
- [x] T629 [strong] Both surfaces honor the enabled set whose `condition` holds, filtered by
      `applies-to` (`pr-review` runs `pr-review`/`both`; the §7 gate's advisory step runs
      `gate`/`both`); `pr-review`'s §5 output distinguishes **disabled → silent** from
      **enabled-but-mechanism-absent → loud** (named in the PR body, never silently dropped);
      blocked by T628 (US8) — strong: a runtime-neutral workflow-output contract (constitution
      P1/P3)
- [x] T630 [strong] `review-pass-roster.test.sh` (sibling to `reviewer-roster.test.sh`,
      wired into CI `verify`) pins the profile rows against the adapter-mapped shipped pass
      set: FAILs on enabled-but-unmapped, **adapter-mapped-shipped-pass-missing-from-profile**
      (the silent-drop parity gap), duplicate row, and off-enum `condition`/`applies-to`,
      **and** rejects a row naming/disabling **any §7 roster auditor (acceptance /
      constitution / contract / spec-quality)**, while PASSing on the real skill-only roster
      (paired flag-defect / pass-control); blocked by T628, T629 (US8) — strong: a P2/P3
      deterministic backstop guarding the maker≠checker boundary (constitution P2/P3/P4)
- [x] T631 [cheap] Generalize the `P-CRAFT` conformance probe to a per-enabled-pass probe in
      the neutral checklist, instantiate for the Claude Code adapter, run live, and record
      per-enabled-pass dispatch in the adapter probe-results table; the probe is **two-sided
      on availability** — it also pins AC3's **enabled-but-mechanism-absent → loud** branch
      with an absent-mechanism fixture, recording the loud "unavailable/degraded" outcome
      with an artifact; blocked by T629 (US8) — cheap: a mechanical probe instantiation +
      recorded live run (two fixtures: available + absent)

## Phase 14 — Test-authoring & pre-commit hygiene (usage-insights intake)

> Two owner-filed issues surfaced by the 2026-07-01 usage-insights report as recurring
> friction, converted via intake (`workflow/intake.md`): a maker-side test-authoring rule
> that left-shifts the acceptance reviewer's existing anti-vacuous-assertion FAIL to
> authoring time (#201), and a local pre-commit run of the existing tasks-consistency
> check so checkbox drift is caught before CI, not after (#202). Each is repo-maintenance —
> no new `US#`; the acceptance reviewer grades each against the done-when criteria carried
> in the issue's intake cross-link comment, exactly as it would a `US#`. T633 changes
> `[guard]` behavior, so it ships its matching `guard.test.sh` case in the same diff
> (constitution P2). Independent — no ordering dependency between the two.

- [x] T632 [strong] Add a **maker-side falsification rule for tests** to
      `.claude/workflow/next-task.md` §5 (and mirror one line into `AGENTS.md` only if the
      residency ceiling allows — else a pointer): a new/changed test counts only if it is
      shown to **fail on incorrect output** (mutate or withhold the behavior and confirm it
      goes red) and asserts **per-instance / per-row** behavior, never a single match
      anywhere in the artifact — naming the vacuous shapes it forbids (prefix-only match,
      single-fingerprint-anywhere). Maker-side only: the acceptance reviewer already
      hard-FAILs vacuous assertions (`reviewers/spec-auditor.md`), whose grading semantics
      this must leave unchanged; `workflow/**` neutrality scan stays green
      (#201; repo-maintenance — done-when on issue) — strong: edits the runtime-neutral
      workflow boundary and must not drift reviewer/gate semantics (constitution P1/P3)
- [x] T633 [strong] Add a **local pre-commit tasks-consistency check** as a `[guard]` rule
      (or equivalent deterministic pre-commit path) that catches done-but-unchecked drift for
      the **commit being attempted** — it must read the pending commit's `[T###]` from the
      guard `command` payload (the un-landed commit is *not* yet in `git log`, so a bare
      re-run of the `git log`-based check would miss the core case), while **sharing**
      `lib-tasks-drift.sh` for the unchecked-box half (`tasks_drift_unchecked_ids`; never a
      forked drift definition — a fork is itself a FAIL, P2) and **failing open** when live
      state is unavailable; catches checkbox drift introduced *during* a task before it
      reaches CI, while CI's `check-tasks-consistency.sh` in `verify` stays the authoritative
      backstop (no gate-semantics change, P5). Guard-behavior change, so it ships matching
      `guard.test.sh` case(s) in the same diff: a **fires-on-drift fixture where the pending
      `git commit` message carries `[T###]` and that box is still `- [ ]`** (not merely
      planted history), a **passes-clean control where the box is checked**, the fail-open
      case, and the wiring assertion (#202; repo-maintenance — done-when on issue) — strong:
      changes `[guard]` behavior and adds its P2 regression coverage (constitution P2/P3)

## Phase 15 — Environment-learning intake (EdgeBench deltas, #209/#210)

- [x] T634 [cheap] Effective-fix-rate trend: define the read-only flip/re-dispatch
      derivation in `workflow/telemetry.md` → Consumers (a flip = FAIL in round *n*,
      PASS/JUSTIFY in round *n+1*; no new record type, no schema or writer change);
      render it in the triage "Gate trends" section with numerator/denominator shown,
      deterministic recipe (P3), read-only (US2.AC3 posture), explicit
      no-fix-rounds-vs-0-of-N and no-data states; fixture-backed test per US9.AC3
      (FAIL→PASS flip, FAIL→JUSTIFY flip, non-convergence, pass-first-try, both empty
      states); observe-only — no gate/tier/guard/selection consumer (P5) (#209) (US9)
- [x] T635 [strong] Retry experience retention: workflow retry sub-doc (pointer from
      `next-task.md`, budget check green) defining verbatim per-auditor/round posting of
      non-convergence verdicts as a marked issue comment + the retry-consumes-it
      procedure (maker input only — no steering authority, no verdict carry-over, every
      reviewer re-runs); tracker-not-telemetry source boundary stated (P5);
      `DESIGN-NOTES.md` entry on identical-starts vs experience retention; two-sided
      conformance probe (posts on non-convergence, silent on PASS) (#210) (US10)

## Phase 16 — Harness self-description & gate-execution intake (owner-filed)

> Five owner-filed issues converted via intake (`workflow/intake.md`): four
> repo-maintenance entries hardening the runtime-neutral split and harness
> observability — an adapter-neutral **write-intent / safe-output** [role] family so
> neutral docs name permitted writes as intents, not concrete tracker commands (#232); a
> deterministic **generated harness manifest** (a committed lock artifact) with a `verify`
> drift check (#233); a read-only, **observe-only** harness **status map** (#234); and
> binding-contract **table rows for three untabled roles** the registry already depends
> on — `[autonomy activation]`, `[live-state reconciliation]`,
> `[selection announce-and-confirm]` (#224) —
> plus one **gate-execution bug**: the review-mode §7 `[orchestrated run]` audits the
> shared tree's inferred HEAD, so a concurrent session's branch switch makes the auditors
> grade the wrong diff (#240). Each is rubric'd by the done-when criteria carried on its
> issue's intake cross-link comment (the acceptance reviewer grades against those exactly
> as a `US#`); no new `US#`. T638 reads T637's manifest when present but is valuable
> independently (soft, not a hard blocker). T639 is **distinct** from T622/#140 (the
> loop's *own* read-only auditor relocating the shared tree) and #214 (a dispatcher rooted
> *outside* the repo); it extends the T612 gate-in-place mechanism as the proven remedy.
> #232/#233 add deterministic checks that change no `[guard]` behavior; #240 protects the
> gate-execution boundary (constitution P1/P3/P4/P5).

- [x] T636 [strong] Define an adapter-neutral **write-intent / safe-output [role] family**
      — a closed, documented set of named write intents in `.claude/workflow/README.md` →
      the binding contract; each writing workflow **declares** its allowed intents
      (profile-declared in `.claude/PROJECT.md` / `PROJECT.template.md`, not baked into
      neutral prose); the active adapter (`.claude/README.md` + adapter specs) maps **every**
      declared intent to a concrete mechanism or a documented degradation; neutral
      `workflow/**` docs stop naming concrete tracker write commands where an intent exists
      (constitution P1); a **deterministic check** fails on a missing intent→mechanism
      mapping **and** on a forbidden neutral-doc write-command leak, each with a planted
      positive + passing control (P3); preserves every existing merge / base-branch
      protection and adds no auto-merge intent (#232; repo-maintenance — done-when on issue)
      — strong: extends the binding contract and the neutrality boundary (constitution P1/P3/P4)
- [x] T637 [strong] Add a **deterministic generated harness manifest** — a committed lock
      artifact (e.g. `.claude/HARNESS.lock.json`) compiled from existing source-of-truth
      (`PROJECT.md`, `workflow/**`, `MODELS.md`, adapter/reviewer/guard config) with an
      **explicitly versioned schema and no timestamps**, byte-stable across repeated
      generation on a clean tree; a generator that reads sources and prints deterministic
      JSON with **no model API / model judgment** (P3); `verify` FAILs on a stale manifest
      and names the regeneration command; the manifest is **compiled evidence, never
      authority** — a deterministic fence proves no gate/tier/guard/selection/autonomy path
      reads it (constitution P5), and source docs win on disagreement; fragile prose is
      content-hashed with a TODO, not mis-parsed (#233; repo-maintenance — done-when on
      issue) — strong: deterministic-governance tooling on the contract surface
      (constitution P3/P4/P5)
- [x] T638 [strong] Add a **read-only, observe-only harness status map** command/workflow
      emitting concise Markdown that mixes static profile facts with best-effort dynamic
      repo/GitHub state (mode, branch/worktree, task/issue/PR, required gates, live
      specs/tasks, observe-only channels); it **degrades explicitly** (`unknown`) when
      tracker/network is unavailable, needs no network for the local static summary, and
      **writes no tracked file** by default; **observe-only** — no gate/tier/guard/selection/
      autonomy consumer (constitution P5); **reuses** the shared drift/selection helpers
      rather than forking a drift definition (P2) and reads T637's manifest when present;
      output stays under a documented budget (#234; repo-maintenance — done-when on issue;
      soft-depends T637) — strong: governance-adjacent read surface preserving the
      observe-only fence (constitution P2/P5)
- [x] T639 [strong] Make the §7 `[orchestrated run]` audit an **explicit, verified ref for
      every dispatch**, not only autonomous ones: the invoker always passes the audited ref
      (a `[isolated workspace]`/worktree pinned to the task branch, or a `headRef` the
      script resolves) and the gate **verifies HEAD is still the expected sha at dispatch
      and at each re-dispatch, failing loud on mismatch** — closing the review-mode default
      where a concurrent session's branch switch in the **shared** working tree makes the
      auditors grade the wrong diff (the vacuity/mismatch class the invariant checklist
      forbids). Distinct from T622/#140 (the loop's own auditor relocating the shared tree)
      and #214 (dispatcher rooted outside the repo); reuses T612 gate-in-place as the proven
      remedy. Encoded by an automated test that **fails against current behavior** (a
      simulated mid-run HEAD switch is graded wrongly / passes vacuously) and **passes after
      the fix** (mismatch caught, run fails loud) (#240; bug — done-when on issue) — strong:
      protects the gate-execution boundary against silent wrong-diff audits (constitution P2/P3)
- [ ] T643 [strong] Append one **binding-contract table row** each for the three
      untabled roles — `[autonomy activation]`, `[live-state reconciliation]`, and
      `[selection announce-and-confirm]` — to `.claude/workflow/README.md` → "The
      binding contract". Each row populates inputs → outputs + constraints in the
      table's existing column shape and **points to the `next-task.md` section that
      owns its semantics** (`[autonomy activation]` → §0.5; the two selection roles →
      §1) so **no rule is forked** — the section stays authoritative, the row is a
      registry entry, not a restatement. Append-only: the pre-existing role rows stay
      unchanged (none reshaped or dropped). Keep the edited surface runtime-neutral
      (roles only; no hook-script or mechanism named), leaving the neutrality scan and
      the doc-pointer check green; and reconcile the `conformance-probes.md` coverage
      map so no newly-tabled role sits silently outside its "one probe per role" framing
      (a probe reference — `[autonomy activation]` already shares P-IW — or an explicit
      note; no hollow placeholder probe id). Neutral `workflow/**` is the only edited
      layer (#224; repo-maintenance — done-when on issue) — strong: extends the
      runtime-neutral role registry (constitution P1) and must summarize §0.5/§1
      semantics without forking them

## Phase 17 — PR review response

- [x] T640 [strong] **review-response** workflow + Claude Code skill: resolve the reviewer
      findings on the harness's own open PR end-to-end — ingest the diff + every inline comment
      (human AND bot/automated, matched by `[bot]` suffix, enumerate-first/filter-second),
      verify each against current source, apply the **minimum scoped fix** with **red→green**
      proof, **re-run the §7 gate on the fix** (maker ≠ checker — a fix is never self-certified),
      reply to every comment (reply ledger), and confirm the head is green — **without merging**
      (owner-only, session-explicit). The write-direction mirror of `pr-review` (T601): a WRITE
      workflow (pushes fixes + posts replies) that **composes existing roles** (no new
      binding-contract row). Ships neutral `workflow/review-response.md` + adapter
      `skills/review-response/SKILL.md`, encoded by `hooks/review-response-docs.test.sh`
      (CI-wired, mutation-proven) asserting the re-gate / red→green / enumerate-first / no-merge
      clauses (#255; engine workflow — done-when on issue) — strong: writes to the PR branch and
      re-runs the maker≠checker gate, guarding the review-response boundary (constitution P2/P4)

## Phase 18 — Merge-boundary guard hardening (discovered work)

> One base-branch bug surfaced during the #252/PR #253 review while adjudicating the
> `approves_merge` findings, then filed as #254. It hardens the same merge-pre-approval
> boundary T623/#165 established and T1206/#252 audited; rubric is the done-when criteria
> carried on the issue (the acceptance reviewer grades against those exactly as a `US#`).
> Constitution screen: the issue's "accept + document" option is foreclosed — a promptless
> merge command is a breach of the enforced merge boundary, not a soft P3 tradeoff — so it
> converts as a fix; the mechanism (narrow the settings entry vs extend `approves_merge`,
> or both) is left to implementation. Touches `.claude/hooks/guard.test.sh` +
> `.claude/settings.json`; a guard-behavior change ships its matching test in the same diff.

- [x] T641 [strong] Close the `gh api --method GET:*` merge-boundary evasion: the committed
      allowlist twins `Bash(gh api --method GET:*)` / `PowerShell(gh api --method GET:*)`
      (`.claude/settings.json:21`,`:49`) word-boundary-expand to `… GET *` (Claude's
      `Bash(pre:*)` ≡ `Bash(pre *)`), so `gh api --method GET <repos/…/pulls/N/merge> --method
      PUT` — a last-wins pflag override to the merge endpoint — is a **promptless merge**,
      defeating the T623/#165 boundary `approves_merge` (`guard.test.sh`) protects; the
      detector misses it because the *spec string* names no `merge` token (the `:782` control
      currently encodes the spec as **safe**). Close the hole (drop/narrow the settings entry
      AND/OR extend `approves_merge` to flag a `gh api …:*` wildcard whose trailing wildcard
      can append `--method PUT`/`-X PUT` to a merge endpoint) so the evasion class is no longer
      auto-approved on **either** twin, without silently killing genuinely read-only `gh api`
      use (preserve a read-only form or document dropping it). Guard-behavior change → ships
      matching two-sided `guard.test.sh` cases (fires on the GET-wildcard-that-can-append-PUT
      spec; passing control for a read-only spec that cannot reach a merge) and flips/removes
      the now-incorrect `:782` safe control, with red→green evidence (#254; bug — done-when on
      issue) — strong: changes `[guard]`/merge-boundary behavior and adds its regression
      coverage (constitution P2/P3/P4)

## Phase 19 — Gate-loop dispatch preflight (discovered work)

> One gate-execution bug surfaced while working the intake conversion for #209–#213, then
> filed as #214. It is the sibling gap T639/#240 explicitly **excluded**: #240 closed the
> shared-tree HEAD race (a concurrent session relocating the audited ref); #214 is a
> *different* vacuity vector — the `[orchestrated run]` reviewer **agent types** resolve
> from the dispatcher **session root's** `.claude/agents/`, so a dispatcher rooted outside
> the repo dispatches every reviewer to `agent type '…' not found`, gets 9× NO-RESULT
> across 3 rounds, and (correctly) refuses to pass but burns the whole fix budget grading
> nothing. `workspacePath` scopes the *diff* explicitly; the agent-type registry has no
> equivalent, so the fix adds the missing deterministic backstop. Rubric is the done-when
> criteria carried on the issue (the acceptance reviewer grades against those exactly as a
> `US#`). Constitution screen: the issue's option 1 (document-only) is a real but partial
> fix — a vacuous, budget-burning gate run is a determinism gap (P3: a failure mode a
> deterministic check can catch must have one), so it converts as a **fix** (owner's
> recommended option 3 = both), the doc precondition alone insufficient; the neutral
> `gate-loop.md` text stays mechanism-free (P1) with the concrete agent-type-resolution
> fact in the adapter/skill layer. Touches `.claude/workflows/gate-loop.js` +
> `gate-loop.test.js` + `gate-loop.md`; no `[guard]` behavior change.

- [x] T642 [strong] Stop the §7 `[orchestrated run]` from dispatching **vacuously** when the
      dispatcher session is rooted outside the repo: the runtime resolves custom reviewer
      agent types (`spec-auditor`, `constitution-auditor`, `spec-quality-auditor`,
      `contract-auditor`) from the **session root's** `.claude/agents/`, not the repo the
      diff lives in — `workspacePath` scopes the *diff* but has no agent-type equivalent — so
      every dispatch errors `agent type '…' not found`, all reviewers return NO-RESULT, and
      the loop correctly refuses to pass yet **burns the full `max-fix-rounds` budget returning
      `non-convergence` with zero grading** (evidence: telemetry `gate-run` `outcome:
      non-convergence`, 9× NO-RESULT across 3 rounds, commit `aaeec28d1358675ae403c14a252c6bb60a6e2bd0`).
      Add a **deterministic preflight** in `gate-loop.js` that verifies the roster agent types
      resolve **before round 1** and, on an unresolvable type, **aborts before any reviewer
      dispatch** (zero fix rounds consumed) with a diagnostic naming the unresolvable type(s)
      **and** this failure mode (dispatcher rooted outside the repo) — never a NO-RESULT
      fan-out that spends the budget; a run whose types DO resolve proceeds to dispatch
      unchanged. Document the invocation precondition **runtime-neutrally** in `gate-loop.md`
      → Inputs (the `[orchestrated run]` must be dispatched where its reviewer `[roles]`
      resolve; a dispatch that cannot resolve them fails fast, not vacuously — no concrete
      mechanism named, constitution P1), with the concrete agent-type-from-session-root fact
      in the adapter/skill layer (`skills/next-task` `[orchestrated run]` row / `.claude/README.md`).
      Encoded by an automated `gate-loop.test.js` case that **fails against current behavior**
      (a forced unresolvable agent type → today fans out to NO-RESULT and burns rounds) and
      **passes after the fix** (preflight aborts before dispatch, `fix_rounds_used == 0`, the
      diagnostic names the type + cause), plus a **passing control** (resolvable types →
      proceeds to dispatch) so the check is not trivially "always abort", with red→green
      evidence. Distinct from T639/#240 (shared-tree HEAD race) — this is the agent-type
      registry gap #240 excluded (#214; bug — done-when on issue) — strong: protects the
      gate-execution boundary against vacuous zero-grading dispatch (constitution P2/P3)

## Phase 20 — Permission & protected-path posture (usage-insights intake)

> One owner-filed decision issue converted via intake (`workflow/intake.md`): resolve
> whether the permission config pre-approves the recurring protected paths for
> autonomous/headless runs, or the friction is a deliberate, recorded choice (#226).
> The intake sweep corrected the issue's cold-start premise against the real tree:
> `settings.json` already blanket-allows the `Edit`/`Write` tools — but not
> `MultiEdit`/`NotebookEdit`, which the hook wiring treats as the same edit-tool class —
> so for `Edit`/`Write` the session-time protected-path wall is the `[guard]`, not a
> prompt, while an unattended run using the other two edit tools can still stall on a
> prompt before the `[guard]` fires; the confirmed friction is those un-pre-approved
> edit tools, the Bash allowlist (git/gh + one guard-test entry only), and the
> degraded-review reference-file readability in headless/worktree contexts. Rubric is
> the done-when criteria carried on the issue's intake cross-link comment (the
> acceptance reviewer grades against those exactly as a `US#`); no new `US#`. Either
> outcome (adopt or reject) closes it; both halves — write pre-approval and the
> read-only degraded-review class — must be explicitly resolved or
> rejected-with-residual-risk.

- [ ] T644 [strong] **Decide protected-path pre-approval for autonomous/headless runs**:
      adopt a scoped `permissions.allow` change or reject-with-recorded-rationale, grounded
      in the **actual** permission state (`settings.json` already blanket-allows `Edit`/`Write`
      but not `MultiEdit`/`NotebookEdit` — edit tools per the hook wiring — so those two can
      still prompt-stall an unattended run; for `Edit`/`Write` the session-time protected-path
      wall is `guard.sh`, not a prompt; the Bash allowlist covers git/gh + only
      `bash .claude/hooks/guard.test.sh`), not the issue's cold-start premise. Whichever
      outcome: the write-pre-approval scope is justified against P4 (a
      pre-approved edit still lands only via the §7-gated PR — no silent self-modification)
      and bounds what stays gated; any guard behavior change ships its `guard.test.sh` case
      (P2); and the **read-only degraded-review half** (craft/security reference files
      unreadable in headless/worktree → silent fallback-principle degradation) is explicitly
      resolved or rejected-with-residual-risk. Durable record only — no ephemeral comment
      (#226; repo-maintenance — done-when on issue) — strong: permission/config scoping on
      the maker≠checker protected-path surface, adjacent to P4 and the guard wall

> US12 (T647–T648) closes the two residual 12-factor-agents gaps. T647 is the cheaper
> change and the one with a production scar behind it (the orchestration-level flake
> procedure). The #295 conversion has landed as US11; because it edits the same write-intent
> contract rows, this story rebases onto those rows rather than re-authoring them.

- [ ] T647 [strong] Add a runtime-neutral **bounded-retry rule** to the implement/verify
      territory of `next-task.md`, with **both** terms defined — a **check identity** that
      positively includes the declared check/checker name, repository-relative working
      directory, stable target or scope, and ordered stable arguments/configuration inputs,
      while remaining **insensitive to run-varying content** (error text, timing, absolute
      paths, ordering are named as excluded, since a run-varying identity makes the bound
      unreachable while identical-failure tests stay green); distinct signatures never share
      a counter. A **distinct intervening change** is defined by
      its **content** — a change to the artifact under test or to an input the failing check
      reads; a retry with no change, an edit the check does not read, and a mandated stall
      response all leave the counter intact, since "any edit resets" makes three consecutive
      failures unreachable and the bound silently dead; if the executor cannot establish that
      a check reads a changed input, it treats the input as unread and does not reset the
      counter — stating explicitly that a mandated stall response does **not** reset it
      (the unchanged §5 decompose rule starts a counter for any new check while the original
      check's counter persists) — and stated **two-sided**: no escalation before the third
      consecutive failure of the same check, none past it. The counter survives a resume and its
      durable source across that resume is **the tracker channel** (the run's own return
      carries only the terminal escalation outcome and does not outlive the run), **never the
      telemetry stream** (P5, the boundary US10.AC3 states for the retry channel). On the
      bound, compact the evidence under a **stated numeric ceiling** (≤50 lines or 4 KB,
      whichever is smaller) with the exit code and failing check's identity surviving, post it
      to the task issue via the existing marked-comment intent, and halt the review-mode
      stage. The `[backlog-loop]` route is out of scope: it must not emit `gate FAIL +
      discard` before §7 runs or reuse `aborted`; a future route needs a distinct, tested
      outcome and stop-accounting contract. Encode the counter at the locus
      that actually observes check failures — the maker's inner loop — **not** the gate loop's
      `fixRoundsUsed`, which counts reviewer verdict rounds against its own 2-round bound and
      never sees a verification failure (encoding there would change §7 gate semantics, barred
      by this spec's Non-goals, or be unreachable dead code). Tests pin five cases **against a scripted
      fixture driver regardless of whether the adapter holds the counter as code** (so the
      obligation never collapses when the honest answer is "discipline"): no escalation at
      two, escalation at three, a proven reset, three failures with **differing output
      text** that still escalate, and two failures of check A followed by one of a
      distinct-signature check B (no escalation) then A's third failure (escalates A only).
      Where it stays executor discipline it is also stated in the
      stage card and asserted by a new test in the established `*-docs.test.sh` family — the
      frozen stage-card hash check cannot serve, and the docs assertion is additional, never a
      substitute — and **not** appended to the frozen obligations inventory, which guards
      preservation rather than accretion.
      Also generalize the orchestration-level flake procedure into a **new
      `## Orchestration-level failure and the prose fallback` section in `gate-loop.md`,
      placed after "Constraints inherited"** (no degradation-notes heading exists to reuse): one fresh re-attempt, then on a **same-class** failure stop and fall back,
      with "same class" defined as same failing step + same diagnostic class under the same
      run-varying exclusions, pinned by a paired fixture (same-class stops; genuinely
      different earns a re-attempt), plus the **routing predicate**, stated outright: a failure in
      the maker's own verify/edit/push work is the three-strike bound's, a failure of the
      orchestration mechanism itself (dispatch, diff provision, role/model resolution) is this
      one's, and a failed push is therefore the maker's. Record that this re-attempt bound is
      dispatcher-level and changes no round limit, veto authority, or tier floor, so it sits
      outside the Non-goal on gate semantics (#296, US12.AC1–AC4) — strong: edits the runtime-neutral workflow boundary and
      the gate's fallback contract (constitution P1/P3/P5)
- [ ] T648 [strong] **Extend** the existing decision-ready contract (`Decision needed:` /
      `Recommendation:`) in place — never a parallel schema, which would contradict the
      unchanged §6.5 — for comments that **block** on an owner answer: attempt identity, an
      ask sequence unique across all attempts for the task issue that never resets on a new
      attempt, `question_format` (**`yes-no | choice`** only — `free-text` is excluded from the
      blocking enum because §6.5 requires enumerated choices answerable in a word, and
      admitting it would relax the condition this task promises to preserve), the question,
      enumerated options for `choice`, and **the engine's action per answer**, preserving
      `Decision needed: none (informational)` unchanged. State the **predicate** for a blocking ask —
      *the engine cannot act on **this item** until an owner reply is read*, scoped to the
      work item rather than the run, since most sites surface the ask and continue — and
      **derive** the enforced set from an explicit machine-readable **`[blocking ask]` tag**
      at each site (never a prose read, never a hard-coded path list, so the derivation is
      independent of the emission markers it grades), with a non-vacuity assertion over: §7
      non-convergence (pre-PR-gate card, `gate-loop.md`), review-response non-convergence,
      intake's underspecified bucket **and** its constitution-screen stop, the
      `[selection announce-and-confirm]` confirm pause, §6.5 "your call" items in the PR body,
      and T647's own escalation comment. The set is **item-scoped and the exclusion
      artifact-scoped**, and one site may emit both: at the §7 stop the *retry-verdicts*
      comment is excluded (bookkeeping consumed as maker input, asking nothing) while the
      *decision item* that stop surfaces is included — scoping the exclusion to the artifact
      rather than the site is what keeps the check's directions from colliding on one file. The check fails
      **three** artifact-level directions: a blocking decision artifact with no
      `question_format`; an informational artifact given one; and a blocking decision
      artifact emitting no `Decision needed:` at all. Parsing is
      deterministic and two-sided with the parsing rule stated in the §2.5
      thread-reading card (`next-task/03-read-context.md`) and encoded as a hook in
      `.claude/hooks/`, called from that §2.5 thread-read step and from the resume protocol:
      only a reply matching the offered format is an answer, anything else is steering and never
      consent, both directions proven in the required check. Normalization trims outer ASCII
      whitespace, folds ASCII case, and collapses horizontal whitespace; the accepted grammar
      is `ANSWER` or `ANSWER — STEERING`, where `ANSWER` is exactly `yes`/`no` or one
      enumerated choice. With multiple outstanding asks, a reply applies only to the greatest
      task-wide ask sequence, including across attempts, and never more than one; a reply that both conforms and
      steers is **both** (§2.5 keeps the newest unmarked owner comment authoritative).
      Independently of format, a conforming reply applies **only** the asked decision — never
      authorizing a merge, engaging autonomous mode, altering gate semantics (round limits,
      veto authority, tier floors), or reaching a family-wide write-intent exclusion; the
      merge arm is already backstopped deterministically, and falsification covers the
      activation and gate-semantics arms, which nothing pins today. Name the schema in the
      marked-comment write-intent rows and **extend** the contract check with a new assertion
      (stated as work: the check reads no constraint-cell content today, so a dropped
      reference fails nothing), with the diagnostic stated literally — `intent role '<role>'
      constraint cell omits the blocking-contact schema reference (repair: name the schema, or
      the documented exemption)` — falsified on **planted fixtures** against that exact string
      and paired with an emission-level fixture so the reference is load-bearing. A conformance
      probe proves all three runtime behaviors, two-sided in each: three same-check failures
      escalate while two do not; a blocking site emits the schema while an informational item
      does not; and a conforming reply is consumed as an answer while a non-conforming one
      leaves the run blocked, with two outstanding asks from different attempts applying only
      to the one with the greater task-wide ask sequence. The
      #295 conversion edits the same
      contract rows — whichever lands second rebases; blocked by **T645 and T647**
      (#296, US12.AC5–AC9) — strong: edits the owner-contact contract adjacent to the merge
      and autonomy boundaries (constitution P1/P3/P4)
> US11 (T645–T646) hardens **resume safety**: an interrupted run that is re-run must
> reconcile against its own prior writes instead of duplicating them, and an attempt must
> carry an identity a later promotion can verify. T645 lands the identity first because
> T646's lookup predicates are keyed by it. Sequencing per the owner's note on #295:
> both follow **T620** (Omnigent live-driver conformance). Neither adopts a runtime
> dependency — #294 rejected that; only the concepts transfer.

- [ ] T645 [strong] Define the **attempt identity** as an authoritative, complete list of
      **atoms** — task ID, attempt/run ID, worktree path, expected base commit, **and the
      commit the §7 gate audited** — each with its **allocation/stability rule** (which atoms
      are freshly allocated per re-entry and which survive it), in exactly one neutral
      location, referenced (never restated field-by-field) everywhere else, with a
      deterministic drift assertion that **runs in the required check** and ships a planted
      second-definition fixture proving it trips (P2/P3 — an unwired check is broken, not
      probably-fine; the scan is shape-bound — a paraphrase stays reviewer-enforced); record the identity into telemetry as a **correlation key that is never
      read back**, with a failed write never blocking promotion (the emitter symmetry rule);
      and make it a **promotion precondition** — promotion proceeds only when **every atom**
      matches and refuses when any single atom differs, with `isolated-workspace.test.sh`
      planting a mismatch in **each atom separately** (five plants: path and base commit
      distinct so a path-only comparison fails, and the audited commit carrying its own plant
      so an implementation that never compares it fails) **and** asserting the all-match case
      is not blocked. The audited commit is **not returned by the gate today** — the loop
      returns outcome + verdicts and the audited HEAD reaches only telemetry — so this task
      **adds** it to the `[orchestrated run]` Outputs cell and the gate-loop return shape as a
      reviewed contract change (P4), and reads it from there: never from telemetry (P5), never
      from a marked comment, never by re-resolving HEAD live. The check confirms a PASS is
      applied to the artifact the gate audited — a precondition on applying the verdict,
      **not** a second promotion authority
      (#295, US11.AC1–AC3; blocked by T620) — strong: touches the isolation promotion
      boundary, the gate's return contract, and the P5 observe-only fence
- [ ] T646 [strong] Add **reconciliation preconditions** to the closed write-intent family:
      each of the four **creating** intents (`[create-issue output]`,
      `[add-issue-comment output]`, `[add-pr-comment output]`, `[open-pr output]`) gains a
      clause naming **both** (i) a **resume-stable** lookup key — task ID for the issue, head
      branch for the PR, and marker + task ID + **a per-call-site discriminator** for a
      marked comment: the comment rows name the key **shape**, each posting call site
      declares its discriminator in its own workflow doc (an undeclared call site posts
      additively as today, outside reconciliation's scope), and for the retry comment the
      discriminator is **the audited commit the verdicts describe** — carried by T645's
      gate-return contract change and on `retry.md`'s deterministic first line — never the
      round ordinal, since one retry comment spans many `{auditor, round}` body sections and
      the gate restarts numbering per invocation, so an ordinal-keyed lookup would adopt a
      prior attempt's comment and drop the new verdicts (US10.AC1/AC2 keep holding: a
      same-run replay adopts/skips, a new attempt's different audited commit still posts) —
      each stated explicitly as *not* the worktree path and *not* a per-re-entry
      attempt ID, since a lookup keyed on freshly-allocated atoms can never match a prior
      attempt, and adopting **by key alone, regardless of author** (an intake-retitled
      owner-filed issue *is* the task's issue); and (ii) the outcome, **adopt or skip — never "update"**, since all four roles
      are create-only/additive in cells this task leaves unchanged and the family rule is flat
      ("never by widening an existing role's meaning"). Adopting means *using* the existing
      artifact instead of creating a second; where a mutation is wanted **and a convergent
      intent already owns it**, that intent performs it — comments have none by design, so
      comments are adopt-or-skip only and stay additive-only. This task does **not** redefine
      `[update-pr output]`'s "a PR the run itself opened". The three **convergent** intents
      (`[update-pr output]`, `[update-issue-metadata output]`, `[push-task-branch output]`)
      instead carry an explicit why-it-is-already-safe note (clausing all seven does not
      satisfy this); `write-intents-check.sh` grows a reconciliation check whose
      creating/convergent partition is **carried by the check**, failing on a missing clause,
      a half-clause, a mis-clause, an **unclassified** role, **and** a carried role with **no
      matching row** (the under-match direction), requiring family size == classified count ==
      partition size, all non-zero (a bare non-zero floor is clearable by a regex matching one
      row of seven); `write-intents-check.test.sh` proves every direction on **planted
      fixtures** — not the live contract this task edits — each asserting its specific
      diagnostic, plus a passing positive control; concrete mechanisms stay adapter-side while
      the neutral stage cards name the [role] only, with the **neutrality** scan load-bearing
      (the leak scan covers write verbs, so a read-shaped lookup would evade it); and a
      conformance probe proves reconciliation **executes** across three runs and both decision
      directions — one artifact after a first run, still one after a same-key re-execution,
      **two** after a different-key run (so an unconditionally-adopting stub fails), covering
      the issue, marked-comment, **and** PR kinds (the PR leg on a fixture/override surface,
      never a live tracker write)
      (#295, US11.AC4–AC8; blocked by T620, T645) — strong: extends the write-intent
      contract and the neutrality boundary (constitution P1/P2/P3/P4)

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
| US9.AC1 | T634 |
| US9.AC2 | T634 |
| US9.AC3 | T634 |
| US9.AC4 | T634 |
| US10.AC1 | T635 |
| US10.AC2 | T635 |
| US10.AC3 | T635 |
| US10.AC4 | T635 |
| US10.AC5 | T635 |
| US12.AC1 | T647 |
| US12.AC2 | T647 |
| US12.AC3 | T647 |
| US12.AC4 | T647 |
| US12.AC5 | T648 |
| US12.AC6 | T648 |
| US12.AC7 | T648 |
| US12.AC8 | T648 |
| US12.AC9 | T648 |
| US11.AC1 | T645 |
| US11.AC2 | T645 |
| US11.AC3 | T645 |
| US11.AC4 | T646 |
| US11.AC5 | T646 |
| US11.AC6 | T646 |
| US11.AC7 | T646 |
| US11.AC8 | T646 |

## Blocked / owner-only tasks (never auto-start — surface them instead)

- none

> Note (not a blocker): T101 carries one design default — telemetry lives
> out-of-repo alongside the triage inbox (keeps project repos clean, matches
> the existing triage convention). The owner may override to in-repo on issue
> #18 any time before T101 starts; silence keeps the default.
