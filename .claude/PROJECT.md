# Project Profile — Creance

This file is the **single source of project-specific truth** the generic `.claude/`
workflow engine reads for the Creance repo's own build (the harness template developing
itself). It doubles as a real filled example of `PROJECT.template.md`.

## Identity
- **Project:** Creance — a runtime-neutral autonomous-coding harness template; this
  profile drives its self-hosted build (currently the harness-feedback-loop epic, #18).
- **Repo model:** direct. Issues/PRs live on `origin`; derive the slug at runtime
  (e.g. `gh repo view --json nameWithOwner -q .nameWithOwner`), never hardcode it.
- **Base branch:** main

## Paths
- **Constitution (law):** `memory/constitution.md` (filled from
  `memory/constitution.template.md`; the reviewers fail closed without it).
- **Spec (acceptance criteria):** `specs/001-harness-feedback-loop/spec.md`;
  `specs/002-spec-quality-gate/spec.md`; `specs/003-maker-eval-corpus/spec.md`;
  `specs/004-autonomous-backlog-loop/spec.md`; `specs/005-held-out-acceptance/spec.md`;
  `specs/006-adoption-context-preservation/spec.md`;
  `specs/007-workflow-context-economy/spec.md`;
  `specs/008-fast-lane-workflow/spec.md`
- **Tasks (backlog):** the live tasks files are `specs/001-harness-feedback-loop/tasks.md`,
  `specs/002-spec-quality-gate/tasks.md`, `specs/003-maker-eval-corpus/tasks.md`,
  `specs/004-autonomous-backlog-loop/tasks.md`,
  `specs/005-held-out-acceptance/tasks.md`,
  `specs/006-adoption-context-preservation/tasks.md`,
  `specs/007-workflow-context-economy/tasks.md`, and
  `specs/008-fast-lane-workflow/tasks.md` — the
  engine selects across all `specs/*/tasks.md`; task IDs are unique across them
  (001 = T1xx–T6xx, 002 = T7xx, 003 = T8xx, 004 = T9xx, 005 = T10xx, 006 = T11xx,
  007 = T12xx, 008 = T13xx).
  `specs/000-template/tasks.template.md` is a skeleton, never a backlog.
- **Task index (selection):** `specs/TASK_INDEX.md` — a generated digest of every backlog
  task's selection-critical fields (spec 007 US5), regenerated from `specs/*/tasks.md` by
  `.claude/hooks/task-index.py --write` and staleness-checked (`--check`) in `verify`.
  `/next-task` §1 reads it first to pick the candidate, then loads the selected task's full
  spec/tasks context; it is a read optimization, never a second authority over the tasks files.
- **Contracts dir:** none (the epic has no swappable provider seams; the workflow docs
  themselves are the contract surface).
- **Architecture guardrails:** `AGENTS.md` → "Architecture Guardrails" (template-level;
  no vendor seams in this repo).
- **Telemetry:** default per `.claude/workflow/telemetry.md` — out-of-repo beside the triage
  inbox: `<triage inbox dir>/creance-telemetry.jsonl` (design default decided by silence
  on #18).
- **Maker-eval records:** default per `.claude/workflow/maker-eval.md` — out-of-repo beside the
  triage inbox in its **own channel directory, kept distinct from the telemetry stream** so
  the US2.AC3 P5 fence (T804) can scope to it: `<triage inbox dir>/creance-maker-eval/`,
  holding `records.jsonl` (append-only, one line per (corpus task × maker tier) per run) and a `packets/`
  subtree for the per-(task × tier) transcript review packets — any in-record packet link resolves
  only inside this directory.

## Task & branch conventions
- **Task ID format:** `T` + 3–4 digits, unique across all live `specs/*/tasks.md` — each
  spec owns a disjoint block (see Paths: 001 = T1xx–T6xx, 002 = T7xx, 003 = T8xx,
  004 = T9xx, 005 = T10xx, 006 = T11xx, 007 = T12xx, 008 = T13xx). The 4-digit extension was owner-ratified on #213 when the
  3-digit hundreds blocks were exhausted; every deterministic consumer parses `T[0-9]+`,
  so no hook or CI change accompanies it.
- **Model tier tag:** every task line carries `[frontier]`/`[strong]`/`[cheap]` — the
  task's MINIMUM capability tier, resolved via `.claude/MODELS.md`. Untagged → executor
  judges, leaning strong.
- **Criterion ownership (multi-task stories):** each live `specs/*/tasks.md` carries a
  "Criterion ownership" section mapping each `US#.AC<n>` to exactly one owning task
  (the live tasks files are enumerated once, under Paths → "Tasks (backlog)").
- **Issue / PR / commit title:** `<type>: [<task-id>] <description>` for task work;
  `<type>: <description>` for repo maintenance (matches existing history).
- **Branch name:** `<type>/<issue#>-<short-slug>` (e.g. `fix/21-template-tasks-glob-collision`).
- **Issue lifecycle:** create-on-demand — an issue is opened before the first file edit
  and closed by the PR (`Closes #<n>`).

## Blocked / owner-only tasks (never auto-start — surface them instead)
- none. (T101 carries an owner-overridable design default — telemetry stored out-of-repo —
  decided by silence on #18; see the note in the tasks file.)

## CI / merge gate / definition of done
- **Required check:** `verify` (`.github/workflows/ci.yml` — guard hook tests + repo
  consistency checks).
- **Merge-gate ruleset:** none — never merge without explicit owner authorization
  regardless.
- **Reviewer profile:** standard engineering review; the owner reads PR bodies directly,
  so lead with risk, keep verdicts verbatim.
- **Coverage policy:** none (the repo is mostly prose + bash; `guard.test.sh` must cover
  every guard behavior change).

## Review passes
The skill-backed advisory passes that run during the §7 gate's advisory layer and `pr-review`,
as an owner-editable set the engine reads by [role] reference ("the profile's review-pass
set"). The schema and the closed column domains live in `.claude/PROJECT.template.md` →
"Review passes". This list governs **skill-backed passes only** — the §7 roster `[reviewer]`s
(acceptance / constitution / contract / spec-quality) are engine-governed
(`.claude/workflow/gate-loop.md`) and are **not** configurable here.

| pass (role) | enabled | condition | applies-to |
|---|---|---|---|
| `[code-review pass]` | true | always | both |
| `[security-review pass]` | true | sensitive-diff | both |
| `[craft-review pass]` | true | always | both |

- `[code-review pass]` and `[craft-review pass]` run on every review (`always`). The
  `[craft-review pass]` is advisory (the external craft-review skill); when its backing
  mechanism is absent it degrades **loudly** in the PR per the review standard — never a
  silent drop.
- `[security-review pass]` runs only on a `sensitive-diff` — a change touching this repo's
  privacy / location / payment surface (no such capability ships here today, so it rarely
  fires), the single surface the review standard's `[security-review pass]` row defines.
- `applies-to: both` for all three: each runs at the §7 gate's advisory step **and** in
  `pr-review` (which reuses the gate's passes).

## Write intents
Which write-intent roles each writing [workflow] may use (the closed role family, each
role's inputs/outputs/constraints, and the family-wide exclusions live in
`.claude/workflow/README.md` → "Write intents (safe outputs)"; the schema and closed
column domains live in `.claude/PROJECT.template.md` → "Write intents"). This table is
the **declaration of record**: a workflow with no row here has no write authority, and
`none` declares the empty set. Composing workflows (the [backlog-loop], the
[orchestrated run]) write only through the rituals they run and carry no row.
`write-intents-check.sh` verifies every declared intent against the contract family and
the active adapter's mapping table.

| workflow | allowed intents |
|---|---|
| `next-task` | `[create-issue output]`, `[add-issue-comment output]`, `[push-task-branch output]`, `[open-pr output]`, `[update-pr output]`, `[add-pr-comment output]` |
| `pr-review` | `[add-pr-comment output]` |
| `review-response` | `[push-task-branch output]`, `[add-pr-comment output]` |
| `triage` | none |
| `intake` | `[add-issue-comment output]`, `[update-issue-metadata output]`, `[push-task-branch output]`, `[open-pr output]`, `[update-pr output]`, `[add-pr-comment output]` |
| `retrospective` | `[create-issue output]`, `[add-issue-comment output]`, `[push-task-branch output]`, `[open-pr output]`, `[update-pr output]`, `[add-pr-comment output]` |

- `triage` is detection-only by its own write posture ("triage posts nothing, marks
  nothing") — the empty declaration makes that auditable rather than implicit.
- `intake` and `retrospective` reach `[open-pr output]`/`[update-pr output]`/
  `[add-pr-comment output]` because each lands its output through the `next-task.md`
  §3–§8 PR path; `intake` additionally retitles/labels converted issues
  (`[update-issue-metadata output]`) and never closes one.
- No workflow declares a merge, base-branch write, branch deletion, or review-approval
  intent — no such intent exists in the family (the contract's family-wide exclusions).

## Autonomy (isolated autonomous mode — the [isolated workspace] activation fact)
The runtime-neutral model is `.claude/workflow/README.md` → the `[isolated workspace]` role +
"Isolation and the guard's fail-open posture". This section is the **project opt-in fact** the
`[autonomy activation]` check (`.claude/hooks/autonomy-mode.sh`) reads.
- **Opt-in:** `autonomy-opt-in: disabled` — the default. This project runs in **review mode**
  (open PRs, a human merges). To opt in to isolated autonomous execution with §7-gated
  promotion, change that one line's value to `enabled`. That is the **only** line that may
  carry the opt-in token, inside its backtick code span: the check treats a
  duplicate/ambiguous declaration, a non-`enabled` value, a commented-out line or a prose
  mention of the token, or an unreadable profile as **review** — it fails closed (the
  inverse of the fail-open `[guard]`). Engaging autonomy per-session instead — an explicit in-session
  authorization — needs no file edit.
- **Opting in is a governance change**, ratified by the human-reviewed PR that lands the flag
  (reconciled with "merge authorization is session-explicit only" in the neutral model).
- **As of T612 (epic #81 part c) the worktree lifecycle, the activation wiring, AND gate-in-place
  all exist** — an autonomous run reads the activation decision and, when engaged, executes inside
  an ephemeral `[isolated workspace]` (`.claude/hooks/isolated-workspace.sh` enter/exit/discard, wired in
  `next-task.md` §0.5/§4); the §7 gate reads the **workspace** diff (the path passed explicitly to
  the [orchestrated run]), and §8 **promotes on a PASS / discards on a FAIL**. But **promotion is a
  PR, not a merge** — merge stays session-explicit (§8), so even with the opt-in on, an engaged
  autonomous run still terminates at a PR; nothing reaches the base branch without a human (or
  session-authorized) merge. Setting the opt-in on changes *where* autonomous work runs (an
  isolated worktree) and wires PASS→promote / FAIL→discard, but still not *whether* it auto-merges
  — it does not.
- **T613 (epic #81 part d) closes the epic** with the falsification proof that an un-gated change
  cannot reach the base branch — `.claude/hooks/isolation-falsification.test.sh`, wired into `verify`,
  adversarially proves the un-gated commit is unreachable from base after `exit`, destroyed whole by
  `discard`, that a forged `branch=main` marker cannot make `discard` delete the checked-out base,
  and that the lifecycle source carries no base-writing door — plus the live **P-IW** conformance
  probe that the isolation tier actually fires on a real driver (recorded in
  `.claude/adapters/claude-code-probes.md`'s probe-results table). The epic umbrella #81 can close once all
  four sub-tasks (T610–T613) land.

## Edit-time checks (the [edit guard] map — `guard.sh` rule 7 reads this)
The [edit guard] (adapter: the `PostToolUse` hook `guard.sh`, rule 7) runs the matching
checker on a touched file and rejects an edit that adds a *new* diagnostic — measured as a
**delta** against the file's committed `HEAD` baseline, so an edit that leaves diagnostics
no worse than before is allowed. A file type with **no row** → no check → the guard fails
open. Concrete check commands are project facts and live here, never in the engine. Each
row's first two backticked tokens are the glob and its checker: `` `<glob>` → `<checker>` ``.
- `*.sh` → `.claude/hooks/shell-lint.sh`
  (`bash -n` syntax + a BSD/GNU portability denylist — a `yes` dash-leading arg, an `awk`
  `{n}`/`{n,m}` interval — folding in #97; the standing CI lint runs the same checker over
  every `.claude/hooks/*.sh`).

## Architecture boundaries (the only allowed seams)
- Workflow layer (`.claude/workflow/**`) stays runtime-neutral: roles in **[brackets]**
  only; runtime-specific mechanisms live in `.claude/adapters/` and skill bindings. A
  Claude-Code-specific instruction inside `workflow/**` is a FAIL.
- Project facts live in this file; engine files (`workflow/**`, skills, agents) carry no
  project facts of their own. **One documented exception:**
  `.claude/workflow/reviewers/evasion-register.md` is a cumulative escape *log* — its real-escape
  exhibits cite this repo's own commits/paths by design (the catalogue's value is *this*
  project's worked escapes; the universal pattern exhibits carry no project facts). Those
  instance facts are confined to that file, labeled as such, and **reset to spec-derived
  seeds at extraction** (`EXTRACTION.md` → the register's GENERICIZE rule), so they never
  reach an adopter intact.
- **Banned vendors / sources:** none.

## Invariant checklist (the auditors enforce these exactly)
- A `workflow/**` file naming a concrete runtime mechanism (tool, CLI flag, model ID)
  instead of a bracketed role — FAIL. **Exempt:** `git`, the assumed universal VCS
  substrate, may be named directly (e.g. `git rev-parse --show-toplevel` for the repo
  root); the ban binds runtime-specific mechanisms — `gh` and other vendor CLIs, model
  IDs, and Claude-Code-only tokens (`--model`, `--json`, `PreToolUse`, `settings.json`) —
  the set `lib-neutrality-scan.sh` exposes to the distributed docs encoding tests.
- Guard behavior changed without a matching `guard.test.sh` case, or settings.json
  matcher drift the wiring assertion would miss — FAIL (the "silently dead guard" class,
  DESIGN-NOTES §"the guard was silently dead").
- A selectable spec/tasks artifact added under a template/skeleton dir (anything in
  `specs/000-template/` matching `spec.md`/`tasks.md`), or duplicate task IDs across
  live tasks files — FAIL (issue #21 class; CI backstop in `ci.yml`).
- Engine text that depends on the model "noticing" something a deterministic check could
  enforce — JUSTIFY or add the backstop.
- `AGENTS.md` (the only always-resident engine file — `CLAUDE.md` imports it into every
  session; DESIGN-NOTES §11) grown past its line ceiling — FAIL (deterministic backstop:
  `agents-residency-check.sh` in CI `verify`). The auditor still owns the subtler form: a
  procedure inlined *under* the ceiling that a `workflow/**` pointer could carry (P3).
- A change that lets telemetry or evaluation records influence gate outcomes, model-tier
  assignment, or gate semantics (round limits, veto authority, tier floors) — FAIL
  (constitution P5; spec 001 non-goals). The **maker-eval** records, scores, regression
  flags, and fingerprints are evaluation records under this rule (spec 003 US1.AC4); the
  deterministic path-fence that no gate/tier/guard/selection code references the eval channel
  is `maker-eval-fence.sh` (+ `maker-eval-fence.test.sh`) in CI `verify` (T804, spec 003 US2.AC3).
- Reviewer specs (the auditor specs **and the evasion register**, **plus the maker-eval
  instrument — the corpus, rubrics, per-dimension lifecycle metadata, judge prompt/spec, scoring
  schema, and owner-labeled calibration set with its labels and floor** — all under
  `.claude/workflow/reviewers/`), invariants, guards, or `memory/constitution.md` modified
  by automation outside a human-reviewed PR — e.g. an auto-rewrite or a side effect of a
  gate run or an eval run — FAIL (constitution P4; spec 001 / spec 003 US1.AC4 non-goals).
- A `.claude/hooks/*.sh` script carrying a known BSD-vs-GNU-divergent construct (a `yes`
  dash-leading argument, an `awk` `{n}`/`{n,m}` regex interval) — FAIL (the
  passes-locally-fails-CI class, #97). The same `shell-lint.sh` checker backs the
  [edit guard] (`guard.sh` rule 7), which rejects an edit that adds a *new* diagnostic to a
  checked file measured against its committed baseline (#79) — guard-behavior change, so it
  ships with `guard.test.sh` cases (P2) and fails open when no checker is configured.
- `next-task.md` selection that trusts a tasks-file checkbox without the deterministic
  **[live-state reconciliation]** precondition — a candidate whose box is unchecked but whose
  work has merged/landed must be refused, not started (the recurring stale-pick class,
  #21/#80) — FAIL. The runtime selector (`reconcile-task-selection.sh`) **shares**
  `lib-tasks-drift.sh` with CI's `check-tasks-consistency.sh` and the announce decision
  (`announce-task-selection.sh`) — one drift definition, three consumers; a forked copy is
  itself a FAIL, P2 — and **fails open** when live state is unavailable. The **in-flight** axis
  (`reconcile-inflight-selection.sh`, #105/T615) extends the same refusal to a candidate whose
  mapped issue has an open, unmerged PR/branch: a tracker read that lives in the adapter (no
  `gh` in `workflow/**`, P1) and **fails open** to the merged-only result when the tracker is
  unavailable — trusting the checkbox while in-flight work exists is the same stale-pick FAIL.
  Its UX complement,
  **[selection announce-and-confirm]** (`announce-task-selection.sh`), must likewise decide the
  confirm pause **deterministically** (implicit + contradicted → pause; explicit or
  uncontradicted → no pause; live state unreadable → announce-only), never by model judgment,
  and the pause must never *start* the contradicted candidate — a model-gated pause, a false
  pause, or a pause that starts stale work is a FAIL (#103/T614).
- Autonomous mode (the `[isolated workspace]` path by which §7-gated work can reach the base
  branch without human review) reachable **without** the deterministic **[autonomy activation]**
  check, or that check failing **open** (any uncertainty resolving to autonomous instead of
  review) — FAIL. Activation is **off by default**, engaged only by an explicit in-session
  authorization or the profile `autonomy-opt-in` flag; the check (`autonomy-mode.sh`) **fails
  closed to review** — the deliberate inverse of the fail-open `[guard]`, whose own posture is
  unchanged because isolation moves the wall to the workspace + §7 gate (P3/P4). A promotion
  path that lets the isolation mechanism write the base branch directly, bypassing the §7
  gate — FAIL (P4). The **gate-in-place** read of the workspace diff must be by **explicit
  context** (the workspace location passed to the gate), never an inferred working directory — a
  CWD-only scheme could audit the empty main tree and pass vacuously (T612). Promotion is a PR
  through the §7-gated path, **never an auto-merge** (merge stays session-explicit); the discard
  path deletes only the ephemeral `creance-ws-*` branch, never the base branch.
- The §7 `[orchestrated run]` auditing an **inferred working-directory HEAD** on ANY dispatch —
  **review mode included**, not only the autonomous gate-in-place path above — FAIL (T639/#240).
  Every dispatch audits an **explicit** ref: an `[isolated workspace]`/worktree pinned to the task
  branch (autonomous), or the task branch the review-mode diff-provider **verifies the shared
  tree's HEAD against at dispatch and at each re-dispatch**, failing the gate **loud** on mismatch
  rather than grading a diff a concurrent session's branch switch relocated (the same
  vacuity/mismatch class the autonomous rule forbids, triggered by a second session instead of a
  wrong CWD). The inferred-HEAD default is removed; the audited ref is a **required** gate input.
  Distinct from T622/#140 (the loop's own shell-holding agents relocating the shared tree — healed
  by the restore, not a grading refusal) and #214 (a dispatcher rooted outside the repo).

### Invariant → enforcement mapping

| Invariant | Auditor rule | Deterministic backstop (lint/test) |
|---|---|---|
| Runtime-neutral workflow layer | contract-auditor: hunt concrete mechanisms in `workflow/**` | `lib-neutrality-scan.test.sh` pins the shared scanner contract; `neutrality-scan-coverage.test.sh` scans every tracked neutral workflow doc through that banned-token set; distributed docs encoding tests also scan their owned workflow docs at the local acceptance surface |
| Guard change ↔ guard test | constitution-auditor: diff touching `guard.sh` without `guard.test.sh` | `guard.test.sh` in CI `verify` (incl. matcher-wiring assertion) |
| No selectable template artifacts / duplicate task IDs | spec-auditor: tasks-file resolution per this profile | CI `verify` repo-consistency step (fails on `specs/000-template/{spec,tasks}.md` or duplicate `T<nnn>` across live tasks files) |
| Telemetry observes, never decides (P5) | constitution-auditor: hunt gate/tier logic reading telemetry or evaluation records | none yet — judgment-only |
| No silent self-modification (P4) | constitution-auditor: hunt automation that writes reviewer specs, guards, invariants, or the constitution outside a PR | none yet — judgment-only |
| Reviewers enforce maker≠checker — they grade but never apply their own fixes (P4) | constitution-auditor: a reviewer binding granting a file-editing **or shell** tool, or a gate/§7 path that lets a reviewer apply/commit its own finding instead of returning a verdict for a separate fix step | `reviewer-roster.test.sh` AC5 (every reviewer agent grants **no edit tools and no shell** — Read/Grep/Glob only, read-only by construction, #188) + `gate-loop.test.js` (reviewers dispatched verdict-only; a separate fix step, the maker role, owns edits). The former shell-write gap (reviewers also granted `Bash`) is **closed structurally** by #188 (Option 2): the reviewer cannot shell-write at all, and the [orchestrated run] hands it the committed diff instead of it running `git`; AC5 rejects any reviewer whose `tools:` line carries `Bash`, still spot-checked by the P-RV mutation lure |
| `AGENTS.md` residency (the L1 always-resident file stays lean; DESIGN-NOTES §11, P3) | constitution-auditor: a procedure inlined into `AGENTS.md` that a `workflow/**` pointer could carry | `agents-residency-check.sh` line ceiling in CI `verify` |
| Hook scripts (`.claude/hooks/*.sh`) stay BSD/GNU-portable; an edit adds no new diagnostic to a checked file ([edit guard], #79/#97) | constitution-auditor: a `guard.sh` behavior change (incl. rule 7) without a matching `guard.test.sh` case | `shell-lint.sh` + `shell-lint.test.sh` over `.claude/hooks/*.sh` in CI `verify`; `guard.test.sh` rule-7 delta cases |
| Selection reconciles live state before starting — **merged/landed** (P3) **and in-flight** (open PR/branch; P3) — announces/confirms the resolved target deterministically (P3), sharing the drift logic not forking it (P2) | constitution-auditor: a `next-task.md` selection step trusting the checkbox without the deterministic reconciliation (merged **or** in-flight), a model-gated (not deterministic) confirm pause, or a forked copy of the drift detection | `reconcile-task-selection.test.sh` (paired: open selected + drifted refused) + `reconcile-inflight-selection.test.sh` (paired: in-flight PR/branch refused + genuinely-open selected; `gh` mocked; fail-open when the tracker is unavailable) + `announce-task-selection.test.sh` (paired: implicit-contradicted → confirm, implicit-consistent + explicit → proceed, fail-open → announce-only; **plus the composed reconcile+announce path** so `confirm` is proven reachable on the real flow, not just the hook in isolation); each git-drift consumer asserts it sources the shared `lib-tasks-drift.sh` (the in-flight check is exempt — a distinct tracker signal, not a drift fork), in CI `verify` |
| Autonomous mode off by default + activation fails closed to review; promotion stays §7-gated (P3/P4; `[isolated workspace]`) | constitution-auditor: an activation path reachable without the deterministic `[autonomy activation]` check, the check failing open, or isolation writing the base branch directly | `autonomy-mode.test.sh` (default-off + fail-closed cases; asserts ci.yml runs the check+test and the neutral role + profile flag exist) in CI `verify` |
| Isolation lifecycle never writes the base branch; the activation read is wired into the autonomous path; gate-in-place reads the workspace diff by explicit context and promote/discard never auto-merges or writes the base ref (P4; T611 lifecycle + T612 gate-in-place + T613 full falsification proof) | constitution-auditor: a `discard`/`exit`/promote path that writes the base ref or auto-merges, a gate that reads an inferred CWD instead of the passed workspace path, or an `enter` that falls back to the base branch instead of failing loud | `isolated-workspace.test.sh` (discard removes the dir + deletes only the ephemeral branch + leaves the base ref untouched + refuses a non-owned worktree; enter→work→exit leaves base untouched; enter fails loud) + `isolation-falsification.test.sh` (T613: the un-gated commit unreachable from base after exit, destroyed by discard, a forged `branch=main` marker cannot delete the checked-out base, no base-writing door in the script) + `gate-loop.test.js` (workspacePath retargets the reviewer/fixer prompt; absent → unchanged main-tree diff) in CI `verify`; live counterpart is the **P-IW** conformance probe |
| The §7 gate audits an explicit, HEAD-verified ref on **every** dispatch — review mode included, never an inferred shared-tree HEAD (T639/#240; extends T612 to review mode) | constitution-auditor: a `gate-loop` dispatch path (review OR autonomous) auditing an inferred working directory instead of an explicit ref, or a review-mode dispatch with no HEAD-stability verification against the task branch | `gate-diff.test.sh` (real-git red→green: a stable HEAD grades the task branch's real diff, a concurrent branch switch is refused loud with no wrong/vacuous grade, a fix-round commit stays stable, plus the fail-loud aborts and marker/invocation/CI wiring) + `gate-loop.test.js` (an explicit ref is required; the review-mode HEAD-stability hook is invoked pinned to the task branch; a HEAD-mismatch marker fails the gate closed with no reviewer dispatched; workspace/T612 unchanged) in CI `verify` |
| Maker-eval is observe-only (P5) + its frozen instrument changes only by PR (P4); the corpus/doc carry their frozen shape (spec 003 US1.AC1/AC4) | constitution-auditor: an eval record/score/flag reaching a gate/tier/guard/selection path, or automation writing the maker-eval instrument (corpus, rubrics, per-dimension lifecycle metadata, judge prompt/spec, scoring schema, calibration set) outside a PR | `maker-eval-docs.test.sh` (parses the corpus for the lifecycle/rubric contract + pins the triple-fingerprint components, the observe-only/PR-only sections, the records-path-via-profile, discoverability + CI-wiring, and the neutrality scan over both new neutral docs) in CI `verify`; the deterministic **P5 path-fence** over the eval channel + packets is `maker-eval-fence.sh` + `maker-eval-fence.test.sh` (paired plant/pass; fires on a cross-reference to either path, passes on the real tree) in CI `verify` (T804, spec 003 US2.AC3) |

## Constitution watch (high-risk upcoming work — for triage look-ahead)
- Telemetry must never affect gate outcomes (US1) → T102, T103.
- Retrospective proposes via PR only, never silent self-modification (US3 non-goals) →
  T301, T302.
- Machinery-freshness checks guard the guard itself → T401, T402.
- Spec 002 — the spec-quality reviewer is model judgment, so it ships an auditor-liveness
  fixture pair (P2) and its dispatch stays deterministic with a CI-lint backstop (P3); its
  strong-tier floor generalizes guard rule 5, a guard-behavior change shipping with its
  `guard.test.sh` case (P2/P4) → T701, T702, T703, T704.
- Spec 003 — the maker eval is a measurement channel, so it stays observe-only with a
  deterministic CI fence proving no gate/tier/guard/selection path reads it (P5) → T802,
  T804. Its judge is pinned independently of the maker model-table change and triage
  suppresses cross-judge comparisons, so the differential stays an independent
  measurement (P1) → T801, T802, T803.
- Spec 007 — context compaction must never weaken the workflow contract: every compact
  artifact is generated or drift-checked (P2/P3), the stage-card split keeps every
  neutral card inside the neutrality scan's coverage (P1), budget signals stay
  observe-and-gate-CI-only (P5's posture), and the `AGENTS.md` trim keeps the existing
  residency check live → T1201–T1206.
- Spec 008 — the fast lane must never become a gate bypass: eligibility/escalation is
  the deterministic checker's verdict alone, failing closed to the full workflow (P3);
  the required review passes stay blocking and the lane changes no gate semantics,
  roster, tier floor, autonomy behavior, or merge rule (P4); protected-path globs and
  thresholds stay profile facts out of neutral docs (P1) → T1301–T1303.
