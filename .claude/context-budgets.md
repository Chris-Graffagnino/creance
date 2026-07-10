# Context budgets — owner-ratified token budgets for the named context surfaces

This registry is the **single home of the owner-ratified token budgets** for Creance's
context artifacts and bundles (spec 007 US1.AC1; initial values ratified from the epic
issue #166's measurements). `.claude/hooks/token-budget-check.sh` parses the table below,
measures every surface that exists, reports per-file and per-bundle counts, and FAILs
standing verification when an `active` surface exceeds its budget.

**The override path (owner-ratified, never tooling-chosen):** to raise, lower, or
re-compose a budget, edit the table row in a PR the owner reviews and merges — the same
way any invariant changes (constitution P4). The check only ever *reads* this file; a
budget the tooling chooses or adjusts itself violates US1.AC1.

**Counter identity (a project/adapter fact — never named in `workflow/**`):** tokens are
measured with **tiktoken, `o200k_base` encoding**, invoked through `python3` — the same
counter the #166 baseline measurements used, so these budgets and the check's reports
share one scale. CI installs it in the `verify` job; locally the check fails **open**
(loud warning, exit 0) when the counter is unavailable, and CI passes `--require-counter`
so verification can never go silently green without measuring.

## The surfaces

| surface | mode | budget (tokens) | gating | composition |
|---|---|---|---|---|
| `agents-resident` | `total` | `1200` | `active` | `AGENTS.md` |
| `compact-packet` | `total` | `2000` | `active` | `.claude/PROJECT.compact.md` |
| `stage-cards` | `each` | `1500` | `deferred` | `.claude/workflow/next-task/*.md` |
| `task-index` | `total` | `4000` | `active` | `specs/TASK_INDEX.md` |
| `next-task-bundle` | `total` | `18000` | `deferred` | `AGENTS.md` `.claude/skills/next-task/SKILL.md` `.claude/workflow/next-task.md` `.claude/workflow/README.md` `.claude/PROJECT.compact.md` `memory/constitution.md` `specs/*/spec.md` `specs/*/tasks.md` |
| `pr-review-bundle` | `total` | `10000` | `active` | `AGENTS.md` `.claude/skills/pr-review/SKILL.md` `.claude/workflow/pr-review.md` `.claude/PROJECT.compact.md` `memory/constitution.md` |

Column semantics (the check parses exactly these):

- **mode** — `total`: the budget bounds the *sum* over the composition (a bundle or a
  single artifact). `each`: the budget bounds *every matched file individually* (the
  stage-card rule: each card ≤ 1.5k, not their sum).
- **budget (tokens)** — the owner-ratified ceiling, inclusive (a surface *at* its budget
  passes).
- **gating** — `active`: an overage FAILs verification. `deferred`: the surface is
  measured and reported (registered from the start, per US1.AC1's deferred-activation
  rule) but an overage does not fail — its gate begins in the diff that lands or
  restructures the surface.
- **composition** — the backticked paths that make up the surface. `*` is the only glob
  syntax the check expands; a token using any other metacharacter (`?`, `[...]`) is
  treated as a literal path.

## Deferred-activation map (who flips each row to `active`)

Per US1.AC1, each of US2–US5's AC1 owns activating its own budget gate in the same diff
that lands or restructures its surface; T1201 (the substrate) gates nothing it exists to
measure:

- `agents-resident` → **T1202** — **landed; the gate is `active`**. `AGENTS.md` is
  trimmed to per-turn rules + pointers (US2.AC1; measured 1958 → within budget at
  activation), alongside the unchanged line-ceiling residency check
  (`.claude/hooks/agents-residency-check.sh` — two measures, one target, US2.AC3).
- `compact-packet` → **T1203** — **landed; the gate is `active`**. The packet
  (`.claude/PROJECT.compact.md`) is the default profile read for ordinary runs
  (US3.AC3) and is drift-checked against `.claude/PROJECT.md` by
  `.claude/hooks/compact-packet-drift.sh` (US3.AC2).
- `stage-cards` → **T1204** (US4.AC1; placeholder glob, same correction rule; a
  documented per-card overage goes through the override path above).
- `task-index` → **T1205** — **landed; the gate is `active`**. `specs/TASK_INDEX.md` is
  the generated selection index (US5.AC1), generated from `specs/*/tasks.md` by
  `.claude/hooks/task-index.py` and staleness-checked by `--check` in `verify` (US5.AC2).
- `next-task-bundle`, `pr-review-bundle` → the diff that **restructures the bundle's
  read set** (US2–US5 as they land; final shape per the spec's target outcomes). The
  compositions above reflect **today's** declared entrypoint read sets; a restructuring
  diff updates the composition and activates the gate when the bundle reaches its
  budgeted shape. **`pr-review-bundle` is `active`** — T1203's packet-default read
  brought it within budget (measured 8454 ≤ 10000 at activation). `next-task-bundle`
  stays deferred until the stage-card split (T1204) and task index (T1205) land.
