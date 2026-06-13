---
name: pr-review
description: Verified review of an open PR — fetch the diff AND every inline reviewer comment (including bot/automated inline findings), verify each finding against current source (file:line) and run the project's checks where relevant, then post one structured, severity-ranked review comment. Never declares "no findings" until every inline comment is adjudicated and every finding is grounded to source. Project specifics from .claude/PROJECT.md. Use when the user says "review PR #N", "review this PR", "/pr-review <url>", or asks to review an existing/external pull request end-to-end. Read-then-comment only — never merges, closes, or pushes.
---

# /pr-review — Claude Code binding

The workflow logic is runtime-neutral and lives in **`.claude/workflow/pr-review.md`** —
**read that file now and execute it.** Mapping of its abstract **[roles]**:

| Neutral role | Claude Code mechanism |
|---|---|
| **[workflow]** (this one) | this skill; the PR number/URL arrives in the invocation text |
| **[bulk-read offload]** | the `Explore` subagent (spawn on the [cheap tier] per `.claude/MODELS.md`) for large diffs/threads |
| **[code-review pass] / [security-review pass]** | `/code-review` / `/security-review` over the PR diff (the security lens when the PR touches privacy, credentials, or payments) |
| **[reviewer]** (auditor lenses, read-only) | the `constitution-auditor` / `contract-auditor` / `spec-auditor` subagents (`.claude/agents/`) dispatched via the Agent tool against the PR diff — own context, no edit tools; models per `.claude/MODELS.md` (the constitution reviewer at-or-above the strong-tier row, never below) |
| **[comment marker]** | the footer line defined in `.claude/skills/next-task/SKILL.md` → "The [comment marker] concrete form" (the single copy) — appended to the review comment this workflow posts |
| **[environment block]** | `.claude/skills/next-task/SKILL.md` → "This environment's concrete forms" (the single copy — multi-line bodies via a UTF-8 temp file + `--body-file`, `gh` PATH fallback) |
| **[headless run]** | `claude -p "/pr-review <pr>"` |
| PR reads | `gh pr view <n> --json title,body,state,baseRefName,headRefName,url` and `gh pr diff <n>`, **plus the line-anchored inline findings `gh pr view` omits**: `gh api repos/{owner}/{repo}/pulls/<n>/comments` (inline review comments) and `gh api repos/{owner}/{repo}/pulls/<n>/reviews` (review summaries — where some bots/Codex post) — these are the bot/automated inline findings the timeline view misses (`--paginate` to the end) |
| PR writes (additive only) | `gh pr comment <n> --body-file <tempfile>` for the structured review (and `gh api .../pulls/<n>/comments` replies where useful) — **never** `gh pr merge`, never `gh pr close`, never a push to the PR branch |

Why the explicit `gh api .../pulls/<n>/comments` + `.../pulls/<n>/reviews` reads: `gh pr view --comments`
returns only the **timeline (issue-level)** comments, so a review built from it alone silently
skips every **line-anchored** inline finding — including the bot/Codex inline comments this
workflow's §2 requires. Fetching the pulls endpoints is what makes the §4 grounding gate's
"every inline comment enumerated" clause satisfiable rather than aspirational.

Write posture per the workflow doc (`pr-review.md` → "Write posture"): the only write is the
review comment (plus inline replies where supported), each carrying the marker; merge / close /
push are out of scope; and this workflow changes **no** §7 pre-PR gate semantics — it is a
reviewer's pass on an already-open PR, complementing the pre-PR gate, not a second gate.
