---
name: intake
description: Convert owner-filed GitHub issues into the tasks-file backlog via PR (project specifics from the profile). Classifies each unmapped issue (no task ID in title, unreferenced by any live tasks file) into spec work / repo-maintenance / bug / duplicate / underspecified, screens it against the constitution, drafts the backlog entry on a branch, and lands it as a PR the owner ratifies by merging. Use when the user says "intake", "run intake", "convert issue #N to a task", or when the triage snapshot's "Unmapped tracker work" section says to run /intake. Writes the repo only on an intake branch; never closes issues or merges PRs.
---

# /intake — Claude Code binding

The workflow logic is runtime-neutral and lives in **`.claude/workflow/intake.md`** —
**read that file now and execute it.** Mapping of its abstract **[roles]**:

| Neutral role | Claude Code mechanism |
|---|---|
| **[workflow]** (this one) | this skill; arguments (e.g. specific issue numbers) arrive in the invocation text |
| **[reviewer]** / §7 gate | as bound in `.claude/skills/next-task/SKILL.md` (the gate on the conversion PR runs exactly as next-task's does, [orchestrated run] included) |
| **[comment marker]** | the footer line defined in `.claude/skills/next-task/SKILL.md` → "The [comment marker] concrete form" (the single copy) — on every `gh issue comment` / `gh pr comment` body this workflow posts |
| **[environment block]** | `.claude/skills/next-task/SKILL.md` → "This environment's concrete forms" (the single copy — multi-line bodies via UTF-8 temp file + `--body-file`, `gh` PATH fallback) |
| **[headless run]** | `claude -p "/intake"` |
| tracker reads/writes | `gh issue list/view` (read), `gh issue comment` / `gh issue edit --title` / `gh issue edit --add-label` (additive writes only — never `gh issue close`, never a merge) |

Write posture per the workflow doc: repo edits happen **only on an intake branch** (the
PreToolUse guard blocks base-branch edits deterministically); the conversion PR carries
**no closing keyword** for the source issue; merge is the owner's alone.

**Profile read — packet first (spec 007 US3.AC3).** Read **`.claude/PROJECT.compact.md`**
by default for the routing facts (tasks-file paths, task-ID blocks, title/branch
conventions, required check — drift-checked by `.claude/hooks/compact-packet-drift.sh`
in CI). **Escalate to the full `.claude/PROJECT.md` explicitly** — say you are escalating
and why — when a classification needs a fact the packet deliberately omits (an
invariant's full text, architecture boundaries, blocked-task detail); the full profile
stays the source of truth.
