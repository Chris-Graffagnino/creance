---
name: triage
description: Morning read-only triage heartbeat for the build (project specifics from .claude/PROJECT.md). Reads the tasks file, git history, and GitHub issues/PRs, then writes a fresh state snapshot to the out-of-repo inbox. Surfaces the next unblocked task, stale checkboxes, open PRs needing review, blocked/owner items, and upcoming constitution risks. Use when the user says "triage", "morning triage", "what's the state of the build", or when fired on a schedule. NEVER edits code, opens issues/PRs, or commits.
---

# /triage — Claude Code binding

The workflow logic is runtime-neutral and lives in **`.claude/workflow/triage.md`** —
**read that file now and execute it.** Mapping of its abstract **[roles]**:

| Neutral role | Claude Code mechanism |
|---|---|
| **[workflow]** (next-task) | the `/next-task` skill the human runs later |
| **[headless run]** | `claude -p "/triage"` (the scheduled heartbeat) |
| **[environment block]** | `.claude/skills/next-task/SKILL.md` → "This environment's concrete forms" (the single copy of the OS/shell/CLI gotchas — e.g. the `gh` PATH fallback) |
| inbox write | the `Write` tool (out-of-repo path; allowed on `main` because it's outside the repo root) |

This procedure is **read-only on the repo**: no `Edit`/`Write`/`MultiEdit` under the repo
root, no `git add/commit/push`, no `gh issue/pr create`. The PreToolUse guard
(`.claude/hooks/guard.sh`) is the deterministic backstop.
