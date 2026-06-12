---
name: constitution-check
description: Verify a change complies with the project's constitution and cost/privacy invariants before a PR. Use when reviewing a diff, before opening a PR, when the user asks "does this pass the constitution", "constitution check", or whenever a feature touches the project's high-risk invariants (e.g. streaks/momentum, user data, identification, monetization, first-run).
---

# /constitution-check — Claude Code binding

The gate logic is runtime-neutral and lives in **`.claude/workflow/constitution-check.md`** —
**read that file now and execute it** against the current diff (`git diff main..HEAD`).

It reads `.claude/PROJECT.md` (invariant checklist + boundaries) and the constitution that
profile names. For maker≠checker independence, the same checklist is enforced by the
`constitution-auditor` subagent (`.claude/agents/`) during the `/next-task` §7 gate; this
skill is the inline self-check version.
