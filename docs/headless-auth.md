# Headless auth & permissions for unattended runs

> **Claude Code adapter artifact** — a new adapter supplies its own equivalent; the
> normative contract is `.claude/workflow/triage.md` §6.

The triage heartbeat (and any scheduled [headless run]) executes with nobody watching.
Two things make that safe-ish, and both are deliberate tradeoffs you should understand
before enabling them. (This is the out-of-repo machinery `EXTRACTION.md` §3b warns a
cold session has zero visibility into — keep this doc current.)

## Auth: a token file, never a committed secret

Unattended runs can't complete an interactive login. Mint a long-lived token
(`claude setup-token`) and store it **outside the repo** (the launcher templates default
to `~/.claude/.oauth-token`). The launcher reads it at run time and exports it as
`CLAUDE_CODE_OAUTH_TOKEN`; if the file is missing it writes an
`exit=1 note=auth: .oauth-token missing` line to the run log and stops — a real failure
the source project's run log actually recorded, which is exactly the dead-man switch
doing its job.

- Never commit the token. This template's `.gitignore` excludes `.oauth-token`; keep it
  that way.
- Rotate it like any credential; the run log will tell you the day it expires.

## Permissions: `--dangerously-skip-permissions`, with compensating controls

Both launcher templates invoke `claude -p … --dangerously-skip-permissions`, because a
permission prompt in an unattended run hangs forever — the run dies silently, which is
worse than running promptless. That flag is acceptable **only** because compensating
controls hold — but the set is **not the same for both launchers**: a read-only heartbeat
and a write-capable loop do not earn it the same way.

**The deterministic [guard]** is the control both share (`.claude/hooks/guard.sh`, wired
via `settings.json`'s PreToolUse matcher): it vetoes the dangerous actions — base-branch
edits, bulk staging, commits/pushes to base, under-tier constitution-reviewer dispatch —
*before* they execute, with no model judgment in the decision. Beyond the guard, each
launcher's second control differs by blast radius:

1. **`/triage` (`triage-heartbeat.sh`) — read-only by contract**
   (`.claude/workflow/triage.md`): it never edits code, opens issues/PRs, or commits; its
   only write is the out-of-repo inbox + run log. Guard + that contract is the whole story.
2. **`[backlog-loop]` (`docs/launchers/backlog-loop.sh`) — write-capable, so it needs
   more.** A loop that opens PRs cannot rest on "read-only," so on top of the guard it
   composes three further controls: the fail-closed **[autonomy activation]** check
   (without the profile's `autonomy-opt-in` flag the loop stops before any iteration), the
   **[isolated workspace]** each engaged cycle runs in, and the **§7 gate** every promotion
   must pass. The launcher's own header carries this analysis at the point of use — keep
   the two in sync.

The `permissions.allow` list in `settings.json` serves *interactive* autonomy (keeping
`/next-task` runs promptless for routine commands); it is not what protects the
unattended path. The probe checklist's P-PA row records this split — keep that deviation
note honest if you change the arrangement.

If you schedule a **third** unattended workflow, re-derive this analysis from its blast
radius the way the backlog-loop launcher did: a workflow that can write needs more than
the guard and a read-only contract before it earns `--dangerously-skip-permissions`.
