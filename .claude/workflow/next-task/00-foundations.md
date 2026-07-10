# next-task — uniform per-task procedure (runtime-neutral)

One task → one issue → one branch → one PR. This procedure makes every task start
identically so autonomous runs are consistent. **Default to review mode: open the PR,
do not merge.**

> Runtime-neutral: roles in **[brackets]** (e.g. **[reviewer]**, **[code-review pass]**,
> **[strong tier]**) are defined in `workflow/README.md` → "binding contract" and mapped to
> concrete mechanisms by the active adapter.

**Project specifics come from the profile (`.claude/PROJECT.md`, the source of truth)** —
paths, task-ID format, blocked-task list, architecture boundaries, invariant checklist, CI
check, merge gate. Below, *the profile* means that file; **how it is read is the binding's
call** (default: a drift-checked compacted view, escalating to the full profile for omitted
facts). If absent, fall back to conventions: `specs/*/tasks.md`, `specs/*/spec.md`, `specs/*/contracts/`, `memory/constitution.md`.

## Context discipline (one task → one clean window)
A task must fit in a single context without compaction. The conversation is disposable; the
**repo + issue + PR + profile + constitution are authoritative**.
- **Start fresh.** Run each task in its own session/process via a **[headless run]**; don't
  continue a long prior chat.
- **Offload bulk reading** with a **[bulk-read offload]** so file contents stay out of the
  main window; the **[reviewer]**s already work in their own context.
- **Read narrowly.** Prefer targeted search + ranged reads over whole-file dumps; never
  re-read a file you just edited.
- **Log-and-summarize verbose output** (tests, CI, API/JSON): capture to a temp log, print
  only failures + the summary.
- **Keep the diff surgical** — small diffs mean small reviewer/review inputs.
- **Checkpoint to disk continuously:** commit, open/update the PR, and record progress in the
  issue so state never lives only in the conversation.

## Resuming an interrupted or compacted task
Reconstruct from disk — do NOT trust conversation memory:
1. `git branch --show-current` + `git status` + `git log --oneline main..HEAD` — what's
   committed on this branch.
2. The open PR + its issue for the current branch, **including their comment threads**
   (§2.5): the newest unmarked owner-login comment is authoritative steering and
   **overrides the posted plan artifact and prior triage judgment**.
3. The task's spec/contracts + its tasks-file entry + the constitution (paths in the profile).
Then continue from the next undone step (§5–§8) and **re-run the §7 gate** before the PR.

## Model & usage economy
Usage may be a shared pool (interactive + scheduled + reviewers). Tiers form the ordinal
ladder from the binding contract (**[frontier tier]** > **[strong tier]** > **[cheap
tier]**); a tag is a **minimum capability requirement**, resolved through the adapter's
model table (round up when a tier is unavailable, never down).

**Per-stage tier map** (deterministic — no judgment call at dispatch time):

| Stage | Tier |
|-------|------|
| Planning + implementation (the session itself) | the task's tier tag; untagged → judgment below |
| **[bulk-read offload]** | **[cheap tier]** |
| Acceptance + contract **[reviewer]**s | **[cheap tier]** |
| Constitution **[reviewer]** | **[strong tier] FLOOR — never downgrades**, even when the task itself runs cheap |

- **Tier tags are authoritative.** If the task's line in the tasks file carries a tier
  tag (format per the profile), use that tier for the run — no judgment call: a
  **[headless run]** passes the model-table resolution as its model flag; an interactive
  session already on a stronger model never downgrades for a tagged task. Untagged tasks
  fall back to the judgment guidance below, leaning strong when the work touches the
  profile's invariant checklist.
- **[cheap tier]** for mechanical/low-risk work — config, scaffolding, stubs, docs, the
  bulk-read passes, and the contract and acceptance **[reviewer]**s.
- **[strong tier]** for constitution-critical, architecturally foundational, or ambiguous
  tasks. The constitution **[reviewer]** must ALWAYS run at-or-above the strong tier — the
  product-thesis check never downgrades, even when the task itself ran cheap.
- **[frontier tier]** only for genuinely long-horizon work — multi-hour autonomous scope,
  plan-and-port-scale changes. Rare: most tagged work is strong or cheap.
- When unsure, start cheap — CI + the reviewers backstop quality, and you can escalate.
