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

## Verification-machinery freshness — concrete instantiation (`triage.md` §1.7 / §2)

`triage.md`'s **PROBES-STALE** check needs two adapter facts the neutral doc defers:

- **Recompute the current `[guard]`-machinery fingerprint** using the recipe defined **once**
  in **`.claude/adapters/claude-code-probes.md` → "Probe-run fingerprint"** (the guard-script
  content hash + the matcher-only hook-wiring hash), rendered `guard=<sha7> wiring=<sha7>`.
  Reuse that recipe — never re-derive it here — so a future change to *what the fingerprint
  covers* stays a one-place edit and the comparison hashes exactly what the probe runs hashed.
  Both halves are content hashes: recomputing is **read-only**, no repo write.
- **The recorded baseline** is the **most recent** non-placeholder row of that same file's
  **"## Probe results"** table: its **Fingerprint** cell is the value to compare against, and
  its date is the age source. No non-placeholder row ⇒ the neutral "no probe run recorded yet"
  state.

Equal ⇒ machinery current; different ⇒ **PROBES-STALE** (report the last run's age either way).
The **GUARD-SILENT** check needs no extra adapter fact — it reads the telemetry stream
(profile → "Paths" → Telemetry, the source `triage.md` §1.6 already reads) and tells `gate-run`
from `[guard]` `evaluation` records by the neutral `record` field (`workflow/telemetry.md`).
Both checks mutate nothing, honoring the read-only-on-the-repo contract above.
