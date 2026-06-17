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
- **Spec (acceptance criteria):** `specs/001-harness-feedback-loop/spec.md`
- **Tasks (backlog):** `specs/001-harness-feedback-loop/tasks.md` — the canonical and
  only live tasks file. `specs/000-template/tasks.template.md` is a skeleton, never a
  backlog.
- **Contracts dir:** none (the epic has no swappable provider seams; the workflow docs
  themselves are the contract surface).
- **Architecture guardrails:** `AGENTS.md` → "Architecture Guardrails" (template-level;
  no vendor seams in this repo).
- **Telemetry:** default per `workflow/telemetry.md` — out-of-repo beside the triage
  inbox: `<triage inbox dir>/creance-telemetry.jsonl` (design default decided by silence
  on #18).

## Task & branch conventions
- **Task ID format:** `T` + 3 digits (phase-numbered: T1xx–T4xx), unique across the repo.
- **Model tier tag:** every task line carries `[frontier]`/`[strong]`/`[cheap]` — the
  task's MINIMUM capability tier, resolved via `.claude/MODELS.md`. Untagged → executor
  judges, leaning strong.
- **Criterion ownership (multi-task stories):** `specs/001-harness-feedback-loop/tasks.md`
  → "Criterion ownership" maps each `US#.AC<n>` to exactly one owning task.
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

## Architecture boundaries (the only allowed seams)
- Workflow layer (`.claude/workflow/**`) stays runtime-neutral: roles in **[brackets]**
  only; runtime-specific mechanisms live in `.claude/adapters/` and skill bindings. A
  Claude-Code-specific instruction inside `workflow/**` is a FAIL.
- Project facts live in this file; engine files (`workflow/**`, skills, agents) carry no
  project facts of their own. **One documented exception:**
  `workflow/reviewers/evasion-register.md` is a cumulative escape *log* — its real-escape
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
  the set the encoding-test mech scans enforce (`pr-review-docs.test.sh`,
  `telemetry-docs.test.sh`).
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
  (constitution P5; spec 001 non-goals).
- Reviewer specs (the auditor specs **and the evasion register**,
  `.claude/workflow/reviewers/`), invariants, guards, or `memory/constitution.md` modified
  by automation outside a human-reviewed PR — e.g. an auto-rewrite or a side effect of a
  gate run — FAIL (constitution P4; spec 001 non-goals).

### Invariant → enforcement mapping

| Invariant | Auditor rule | Deterministic backstop (lint/test) |
|---|---|---|
| Runtime-neutral workflow layer | contract-auditor: hunt concrete mechanisms in `workflow/**` | none yet — judgment-only |
| Guard change ↔ guard test | constitution-auditor: diff touching `guard.sh` without `guard.test.sh` | `guard.test.sh` in CI `verify` (incl. matcher-wiring assertion) |
| No selectable template artifacts / duplicate task IDs | spec-auditor: tasks-file resolution per this profile | CI `verify` repo-consistency step (fails on `specs/000-template/{spec,tasks}.md` or duplicate `T<nnn>` across live tasks files) |
| Telemetry observes, never decides (P5) | constitution-auditor: hunt gate/tier logic reading telemetry or evaluation records | none yet — judgment-only |
| No silent self-modification (P4) | constitution-auditor: hunt automation that writes reviewer specs, guards, invariants, or the constitution outside a PR | none yet — judgment-only |
| `AGENTS.md` residency (the L1 always-resident file stays lean; DESIGN-NOTES §11, P3) | constitution-auditor: a procedure inlined into `AGENTS.md` that a `workflow/**` pointer could carry | `agents-residency-check.sh` line ceiling in CI `verify` |

## Constitution watch (high-risk upcoming work — for triage look-ahead)
- Telemetry must never affect gate outcomes (US1) → T102, T103.
- Retrospective proposes via PR only, never silent self-modification (US3 non-goals) →
  T301, T302.
- Machinery-freshness checks guard the guard itself → T401, T402.
