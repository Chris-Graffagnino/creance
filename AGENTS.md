# <PROJECT NAME> — Development Rules

> Creance harness template. Fill every `<...>`, delete what doesn't apply, keep the
> section headings — the guard hook and the workflow docs reference this file by name
> (`AGENTS.md`; `CLAUDE.md` imports it). Project facts belong in `.claude/PROJECT.md`,
> not here — this file carries the *rules*, the profile carries the *facts*.
> Everything in this file is resident in every session: keep it to per-turn rules, and
> push full procedures into `.claude/workflow/**` behind pointers (`DESIGN-NOTES.md` §11).

## Operating Principles
- Treat `<specs path, e.g. specs/001-your-feature/>` as the source of truth for scope,
  contracts, and acceptance criteria.
- Treat `memory/constitution.md` as **law**. A change that violates a principle is
  blocked, not negotiated.
- Do not hide uncertainty. State assumptions, ambiguities, and tradeoffs before
  implementation.
- Keep changes surgical: every changed line must trace to the issue, task ID, or
  explicit user request.
- Prefer the simplest implementation that satisfies the contract. No speculative
  abstractions, options, or adjacent cleanup.
- Match existing code style and architecture even when a different style would be
  preferred.
- Use deterministic checks to anchor work: tests, type checks, lint, the contract files,
  the requirements checklist, diffs, and the **[code-review pass]** (a binding-contract
  **[role]**; the active runtime's mechanism is named in `.claude/README.md`).
- Use `rg`/`rg --files` first for repository search.
- If specs, contracts, the constitution, or user instructions conflict, stop and
  resolve the conflict before coding. **The constitution wins ties.**

## Work Modes
- Plan-only work may read/search files, inspect git state, and draft a plan or
  proposed patch. Do not edit files, commit, push, or open PRs. No issue required.
- Implementation work requires an issue before the first file edit. This includes
  code, docs, config, generated artifact, and test changes.
- Review work uses code-review posture: findings first, ordered by severity, with
  file/line references and concrete risk.

## Issue, Branch, and Scope
- One task, one issue, one branch, one PR.
- Before implementation, identify the applicable task ID from the tasks file named in
  `.claude/PROJECT.md` → "Paths".
- If no task ID applies to PR-bound work, ask whether to create/update a spec task or
  classify it as repo-maintenance before editing.
- Issue and PR titles, branch names, and the issue lifecycle follow
  `.claude/PROJECT.md` → "Task & branch conventions".
- Never commit directly to the base branch.
- Use `git add <specific files>` only. Never use `git add .`.
- Do not revert or overwrite unrelated user changes.

## Discovered Work
Implementation often surfaces problems outside the current task's scope. Handle them
without widening the diff (full procedure: `.claude/workflow/next-task.md` §5.5):
- If a finding **blocks the current task's acceptance criteria**, it is in scope — record
  it on the issue and handle it (or stop and surface it if it reshapes the task).
- If it is **concrete, actionable, and out of scope**, search the tracker for an existing
  issue, then file one at discovery time: self-contained body (file/line evidence,
  cold-start context) plus a "Discovered while working #N" line. The tracker is the
  durable channel that the triage heartbeat resurfaces daily.
- If it is a **vague hunch or trivial nit**, list it in the PR body under "Out of scope,
  observed" instead of filing tracker noise.
- **Constitution or security findings already on the base branch** are always filed and
  flagged prominently in the PR body.
- Every PR body includes a **"Discovered work"** line naming the issues filed (or "none").

## Architecture Guardrails
The allowed seams — swappable provider interfaces, banned vendors, cost/privacy
invariants — live in `.claude/PROJECT.md` → "Architecture boundaries" and "Invariant
checklist". The short form:
- <Every external capability goes through a named interface; UI/component code never
  calls a vendor SDK/API directly.>
- <Your non-negotiable cost / privacy / safety invariants, one line each.>

## Implementation Loop
1. Read the issue, task entry, applicable spec/contracts, `memory/constitution.md`,
   nearby code, and existing tests.
2. Define success criteria and the smallest safe verification path.
3. For behavior changes, add or update meaningful tests, including negative/edge cases
   where contracts matter.
4. Implement the minimum scoped change.
5. Remove only orphaned code created by your change.
6. Update specs/contracts/checklist when behavior or public artifacts change.
7. Run targeted tests first, then the broader suite required by the change.
8. Self-review with `git diff main..HEAD` before PR creation.

## Verification Commands
Stack: **<language / framework>**, tested with **<test runner>**, linted with
**<linter>**, type-checked with **<type checker>**.
Use the narrowest relevant command, then broaden when risk warrants it.

- Lint: `<lint command>`
- Type check: `<type-check command>`
- Narrow test (single file/pattern): `<test command> <path-or-pattern>`
- Full unit suite: `<full test command>`
- Contract/spec check: manually verify the change against the requirements checklist
  and the relevant contract file (paths in `.claude/PROJECT.md`).

If a relevant check cannot be run, document why and describe the residual risk.

## Test Output Discipline
- Start with the narrowest test that exercises the changed behavior. Do not run the
  full suite after every small edit.
- For broad runs, capture full output to a temp log; print only the exit code, failure
  excerpts, and the final summary. Inspect the saved log with `rg`/`sed`/`tail` before
  rerunning.

## Required Pre-PR Review
Before creating any PR:
1. Run implementation verification (lint + relevant tests).
2. Self-review `git diff main..HEAD`.
3. Confirm the diff is stable, then run the **[code-review pass]** (mechanism per the
   active adapter, `.claude/README.md`); add the **[security-review pass]** when the change
   touches privacy, credentials, or payments.
4. Confirm the change passes the **Constitution Check** (`.claude/workflow/constitution-check.md`).
5. Treat unresolved material findings as blocking unless explicitly documented as false
   positives or out of scope.
6. Only then run `gh pr create`.

Every PR body must include `Closes #<issue-number>`. Use heredocs for `gh` bodies;
never use literal `\n` characters.

## Automated Review Standard
The full standard — inputs every review must inspect, the finding-priority order,
block conditions, and the evidence rule for approvals — lives in
`.claude/workflow/README.md` → "The review standard"; the reviewer specs under
`.claude/workflow/reviewers/` apply it per dimension.

## Autonomy and Merge Rules
- Default mode is review mode: open PRs but do not merge.
- "Work autonomously" allows implementation, PR updates, and automated-review response,
  but not merging.
- Merge only when the user explicitly authorizes autonomous merging in the session and
  all checks/reviews are green.
- Verify PR status with concrete GitHub data, for example:
  `gh pr view <number> --json reviews,statusCheckRollup,mergeStateStatus`
- If review/check status is unavailable, ambiguous, delayed, or absent, do not merge.
- Squash merge is preferred.
- After any merge, run `git switch main` and update from origin before starting new work.
