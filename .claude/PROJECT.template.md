# Project Profile — <PROJECT NAME>

This file is the **single source of project-specific truth** the generic `.claude/`
workflow engine reads. The skills (`next-task`, `triage`, `constitution-check`) and the
auditor agents (`spec-auditor`, `constitution-auditor`, `contract-auditor`) carry NO project facts of
their own — they read them from here and from `memory/constitution.md`.

Copy this file to `.claude/PROJECT.md` and fill every `<...>`. Delete sections that don't
apply to your project (e.g. drop "Invariant checklist" items you don't have), but keep the
headings the engine looks for: **Identity, Paths, Task & branch conventions, Blocked tasks,
CI / merge gate, Architecture boundaries, Invariant checklist, Constitution watch.**

## Identity
- **Project:** <one-line description>
- **Repo model:** <fork | direct>. If a fork, issues/PRs live on `origin`; derive the slug
  at runtime, never hardcode it — carry over the slug-derivation one-liner from the
  reference profile's Identity section (`.claude/PROJECT.md` in the source repo) verbatim.
  Workflow docs say "derive the slug per the profile" and resolve to this bullet.
- **Base branch:** <main | master | ...>

## Paths
- **Constitution (law):** `memory/constitution.md`  <!-- or wherever your principles live -->
- **Spec (acceptance criteria):** <path to spec.md, or "none">
- **Tasks (backlog):** <path to tasks.md, or "none — issues are the backlog">
- **Contracts dir:** <path to contracts/, or "none">
- **Architecture guardrails:** <path / section, or "none">
- **Telemetry:** <append-only JSONL path per `workflow/telemetry.md`, or "default" —
  out-of-repo beside the triage inbox: `<triage inbox dir>/<repo-basename>-telemetry.jsonl`>

## Task & branch conventions
- **Task ID format:** <e.g. `T` + 3 digits; or "none — use issue numbers">
- **Model tier tag:** <do task lines carry `[frontier]`/`[strong]`/`[cheap]`? The tag is
  the task's MINIMUM capability tier, resolved by the active adapter's model table.
  State the tagging policy and the untagged fallback — or "none">
- **Criterion ownership (multi-task stories):** <if one user story can span several
  tasks, name the tasks-file section that maps each criterion (`US#.AC<n>` = nth
  acceptance-criteria bullet) to exactly one owning task — the acceptance [reviewer]'s
  scoping rule depends on it; or "none — one task per story">
- **Issue / PR / commit title:** `<type>: [<task-id>] <description>`
- **Branch name:** `<type>/<task-id>-<short-description>`
- **Issue lifecycle:** <pre-created per task | create-on-demand>

## Blocked / owner-only tasks (never auto-start — surface them instead)
- <task IDs that need human input / API keys / decisions, and why> — or "none".

## CI / merge gate / definition of done
- **Required check:** <CI check name, e.g. `verify`>
- **Merge-gate ruleset:** <name, or "none"> — never bypass.
- **Reviewer profile:** <e.g. "owner is NOT a developer — separate engineering vs.
  product in the PR body" | "standard engineering review">
- **Coverage policy:** <e.g. per-path threshold for critical files; or "none">

## Architecture boundaries (the only allowed seams)
All access to these capabilities must go through the named interface — never a vendor SDK
from UI/component code. A leaked vendor type/error/option in a public surface is a FAIL.
- <capability> → `<InterfaceName>`
- ...
- **Banned vendors / sources:** <names, and why> — or "none".

## Invariant checklist (the auditors enforce these exactly)
Concrete, checkable rules from your constitution + any cost/privacy/safety discipline.
Mark each FAIL or JUSTIFY. Phrase them as *failure modes to hunt for*, not abstractions.
- <invariant — what makes it a FAIL>
- ...

### Invariant → enforcement mapping
Map EVERY checklist item to the auditor rule that hunts it and, where one exists, a
deterministic lint/test backstop. Mark items with no concrete hunt rule **judgment-only**
explicitly — weak enforcement must be visible, not assumed.

| Invariant | Auditor rule | Deterministic backstop (lint/test) |
|---|---|---|
| <item> | <reviewer spec + its specific hunt rule, or **judgment-only**> | <test/lint that fails CI by itself, or "none yet — arrives with <task>"> |

## Constitution watch (high-risk upcoming work — for triage look-ahead)
- <risk area> → <task IDs / areas to guard when they land>
- ...
