# Project Profile — <PROJECT NAME>

This file is the **single source of project-specific truth** the generic `.claude/`
workflow engine reads. The skills (`next-task`, `triage`, `constitution-check`) and the
auditor agents (`spec-auditor`, `constitution-auditor`, `contract-auditor`) carry NO project facts of
their own — they read them from here and from `memory/constitution.md`.

Copy this file to `.claude/PROJECT.md` and fill every `<...>`. Delete sections that don't
apply to your project (e.g. drop "Invariant checklist" items you don't have), but keep the
headings the engine looks for: **Identity, Paths, Task & branch conventions, Blocked tasks,
CI / merge gate, Review passes, Architecture boundaries, Invariant checklist, Constitution watch.**

> **Worked example:** [`docs/examples/lantern/PROJECT.md`](../docs/examples/lantern/PROJECT.md)
> is a fully filled version of this file (the fictional "Lantern" project).

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
- **Maker-eval records:** <eval channel per `workflow/maker-eval.md`, or "default" —
  out-of-repo beside the triage inbox in its own directory, kept distinct from the telemetry
  stream so the P5 fence can scope to it: `<triage inbox dir>/<repo-basename>-maker-eval/`
  (`records.jsonl` + a `packets/` subtree for per-task transcript review packets); or "none"
  if you do not run a maker eval>

## Finding things in this repo
The engine mandates search-first; these bounded `rg` recipes mine the growing `specs/` tree
by the artifact you need. Each uses only a path convention from **Paths** above — no new
convention invented. Fill the `<...>` for your lookup.
- **A story's acceptance criteria** — `rg -n "US<n>" specs/*/spec.md`
- **A task line by ID** — `rg -n "<task-id>" specs/*/tasks.md`
- **A contract by capability / seam** — `rg -n "<capability or seam>" specs/*/contracts/`
- **An invariant by keyword** — `rg -n "<keyword>" memory/constitution.md .claude/PROJECT.md`

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

## Review passes
The **skill-backed** review passes — the `[code-review pass]`, `[security-review pass]`, and
`[craft-review pass]` [role]s — that run during the §7 gate's advisory layer and the
`pr-review` ritual are an **owner-editable declarative set** the engine reads by [role]
reference ("the profile's review-pass set"). Edit a row to enable/disable a pass, change the
`condition` it runs under, or re-scope which surfaces it `applies-to` — **without** touching
the runtime-neutral `workflow/**`. This list governs the **skill-backed advisory passes
only**: the law-bearing §7 roster `[reviewer]`s (acceptance / constitution / contract /
spec-quality) are **not** configurable here — they stay governed by the §7 reviewer roster
(`.claude/workflow/gate-loop.md`), so the maker≠checker / constitution-as-law boundary cannot
be edited away through this profile.

| pass (role) | enabled | condition | applies-to |
|---|---|---|---|
| <a legal pass role> | <true\|false> | <always\|sensitive-diff> | <gate\|pr-review\|both> |

**Every column's domain is closed and typed** (an off-enum value is a defect the
review-pass roster test rejects):
- **`pass (role)`** — one of the closed set of legal skill-backed pass roles:
  `[code-review pass]`, `[security-review pass]`, `[craft-review pass]`. Each role appears in
  **at most one** row (a duplicate row is illegal). A row naming a §7 roster `[reviewer]`
  (acceptance / constitution / contract / spec-quality) is rejected — those are not
  configurable here.
- **`enabled`** — boolean (`true` / `false`).
- **`condition`** — one of the closed enum:
  - `always` — the pass runs on every invocation of its applicable surface.
  - `sensitive-diff` — the pass runs only on a diff touching the **same security-sensitive
    surface the `[security-review pass]` already guards**: the profile's privacy / location /
    payment invariants, **defined once** in the review standard
    (`.claude/workflow/README.md`, the `[security-review pass]` row). `sensitive-diff` reuses
    that single definition — it adds no parallel sensitivity surface here.
- **`applies-to`** — one of the closed enum `gate` (the §7 gate's advisory step only) /
  `pr-review` (the `pr-review` ritual only) / `both`. A surface runs a pass only when its
  `applies-to` includes that surface.

Carry **one row per skill-backed pass your adapter maps** (the adapter's role→skill table),
with that pass's real `enabled` / `condition` / `applies-to` values — not a placeholder.

## Write intents
The per-workflow **write-intent declarations** — which of the closed write-intent /
safe-output roles (`.claude/workflow/README.md` → "Write intents (safe outputs)") each
writing [workflow] may use. The declaration lives **here in the profile**, never in
neutral workflow prose; the adapter maps every declared intent to a concrete mechanism
(the active adapter's mapping table). A workflow with no row has no write authority.

| workflow | allowed intents |
|---|---|
| <a writing workflow name> | <comma-separated intent roles from the closed family, or `none`> |

**Every column's domain is closed and typed** (an off-enum value is a defect the
write-intent check rejects):
- **`workflow`** — a workflow ritual that writes shared surfaces. Carry one row for
  **each** of the writing rituals your harness runs (this repo's set: `next-task`,
  `pr-review`, `review-response`, `triage`, `intake`, `retrospective`); a missing row is
  a defect, not an implicit empty set. Composing workflows (the [backlog-loop], the
  [orchestrated run]) carry no row — they write only through the rituals they run.
- **`allowed intents`** — either the literal `none` (the empty set — a declared read-only
  posture) or backtick-quoted intent roles drawn **only** from the contract's closed
  family. An intent outside the family, or a catch-all, is rejected.

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
