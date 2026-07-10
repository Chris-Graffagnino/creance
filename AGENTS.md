# <PROJECT NAME> — Development Rules

> Creance harness template. Fill every `<...>`, keep the section headings — the guard
> hook, the workflow docs, and CI reference this file by name (`AGENTS.md`; `CLAUDE.md`
> imports it). This file carries only **per-turn rules + pointers** and is resident in
> every session, line-ceilinged and token-budget-gated (`.claude/context-budgets.md`):
> project *facts* live in `.claude/PROJECT.md`, full *procedures* in
> `.claude/workflow/**` behind pointers (`DESIGN-NOTES.md` §11); the per-task procedure
> is `.claude/workflow/next-task.md`.

## Operating Principles
- `<specs path, e.g. specs/001-your-feature/>` is the source of truth for scope,
  contracts, and acceptance criteria. `memory/constitution.md` is **law**: on any
  conflict, stop and resolve first — **the constitution wins ties**.
- Keep changes surgical and minimal: every changed line traces to the issue, task ID,
  or explicit user request; no speculative abstraction or adjacent cleanup. Match
  existing code style and architecture. Remove only orphaned code your change created.
- Update specs/contracts/checklists when behavior or public artifacts change.
- State assumptions, ambiguities, and tradeoffs before implementing; anchor work in
  deterministic checks over model judgment.
- Use `rg`/`rg --files` first for repository search.

## Issue, Branch, and Scope
- One task, one issue, one branch, one PR. An issue precedes the first file edit —
  code, docs, config, generated artifacts, and tests alike; plan-only/read-only work
  needs none.
- Identify the task ID from the tasks file (`.claude/PROJECT.md` → "Paths") before
  implementing; if none applies to PR-bound work, ask whether it is a spec task or
  repo-maintenance first.
- Issue/PR titles, branch names, and the issue lifecycle follow `.claude/PROJECT.md` →
  "Task & branch conventions".
- Never commit directly to the base branch. Stage specific files only — never
  `git add .`. Do not revert or overwrite unrelated user changes.

## Discovered Work
Out-of-scope findings are **filed, not fixed** — never widen the current diff. The full
classification and filing procedure, and the PR body's required "Discovered work" line:
`.claude/workflow/next-task.md` §5.5.

## Architecture Guardrails
The allowed seams — swappable provider interfaces, banned vendors, cost/privacy
invariants — live in `.claude/PROJECT.md` → "Architecture boundaries" and "Invariant
checklist". The short form:
- <Every external capability goes through a named interface; UI/component code never
  calls a vendor SDK/API directly.>
- <Your non-negotiable cost / privacy / safety invariants, one line each.>

## Verification Commands
Stack: **<language / framework>**, tested with **<test runner>**, linted with
**<linter>**, type-checked with **<type checker>**.
- Lint: `<lint command>` — Type check: `<type-check command>`
- Narrow test: `<test command> <path-or-pattern>` — Full suite: `<full test command>`

Run the narrowest relevant check first, then broaden; log-and-summarize broad runs
(`.claude/workflow/next-task.md` §6 + "Context discipline"). If a relevant check cannot
be run, document why and describe the residual risk. Behavior changes ship falsified
tests — red→green evidence in the PR body, per-instance assertions (falsification
rule: `.claude/workflow/next-task.md` §5).

## Required Pre-PR Review
The §7 gate must pass before any PR: adversarial **[reviewer]**s in their own contexts
(maker is never the checker) plus the profile's review-pass set — the
**[code-review pass]** always; the **[security-review pass]** when the change touches
privacy, credentials, or payments (`.claude/PROJECT.md` → "Review passes"). Unresolved
material findings block. Procedure:
`.claude/workflow/next-task.md` §7–§8; standard: `.claude/workflow/README.md` → "The
review standard". Every PR body includes `Closes #<issue-number>`; pass bodies via
file, never inline.

## Autonomy and Merge Rules
- Default mode is review mode: open PRs but do not merge. **Isolated autonomous mode**
  is **off by default** and fails *closed* to review, per the deterministic
  **[autonomy activation]** check (`workflow/README.md` → `[isolated workspace]`;
  `workflow/next-task.md` §0.5).
- "Work autonomously" allows implementation, PR updates, and automated-review
  response — never merging.
- Merge only when the user explicitly authorizes autonomous merging in the session AND
  all checks/reviews are verified green with concrete tracker data; unavailable,
  ambiguous, or delayed status means do not merge. (Deterministic backstop — no
  allowlist entry pre-approves a merge command: `guard.test.sh`; accounting:
  `.claude/governance-rules.md`.)
- Squash merge is preferred; after any merge, switch to the base branch and update
  from origin before new work.
