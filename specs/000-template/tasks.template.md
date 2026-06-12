# Tasks — <FEATURE NAME>

> Skeleton backlog for `/next-task`. Rename to `tasks.md` when you copy the template dir
> — the `.template.md` suffix keeps this file out of the `specs/*/tasks.md` fallback glob,
> so its placeholder task IDs are never selectable. Task-line format (state the
> conventions you choose in `.claude/PROJECT.md` → "Task & branch conventions"):
>
> `- [ ] T<nnn> [<tier>] <description> (US<#>)`
>
> The `[frontier]`/`[strong]`/`[cheap]` tag is the task's **minimum capability tier**,
> resolved through `.claude/MODELS.md` at run time. Tag generously toward `[strong]` for
> anything constitution-critical, foundational, or money/privacy/copy-adjacent;
> `[cheap]` only for mechanical work. Untagged → the executor judges, leaning strong.

## Phase 1 — <name>

- [ ] T101 [strong] <description> (US1)
- [ ] T102 [cheap] <description> (US1)

## Phase 2 — <name>

- [ ] T201 [strong] <description> (US2)

## Criterion ownership (multi-task user stories)

> When one `US#` spans several tasks, assign each acceptance criterion to exactly one
> owning task — the acceptance [reviewer] grades a task hard only on the criteria it
> owns; sibling criteria are labeled `deferred-to:<task>`, not failed. Delete this
> section if every story maps to one task.

| Criterion | Owning task |
|---|---|
| US1.AC1 | T101 |
| US1.AC2 | T102 |

## Blocked / owner-only tasks (never auto-start — surface them instead)

- <task IDs that need human input / API keys / decisions, and why> — or "none".
