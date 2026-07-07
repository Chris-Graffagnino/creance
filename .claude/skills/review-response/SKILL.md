---
name: review-response
description: Resolve the reviewer findings on your own open PR end-to-end — fetch the diff AND every inline comment (human and bot/automated), verify each against current source (file:line), apply the minimum scoped fix with red→green proof, RE-RUN the §7 gate on the fix (maker ≠ checker — a fix is not self-certified), reply to every comment, and confirm the head is green. Never merges — stops for the owner. Pushes fixes and posts replies (the write posture pr-review lacks). Project specifics from the profile. Use when the user says "address the reviewer comments on PR #N", "resolve the Codex findings on PR #N", "respond to the review on this PR", or "/review-response <url>".
---

# /review-response — Claude Code binding

The workflow logic is runtime-neutral and lives in **`.claude/workflow/review-response.md`** —
**read that file now and execute it.** It **composes existing roles** (introduces no new
binding-contract row): the `pr-review` read-and-ground reads, the `next-task` §5 scoped-fix +
falsification and §7 re-gate, and the §8 digest / green / no-merge terminal. Mapping of its
abstract **[roles]** and the concrete reads/writes:

| Neutral role / step | Claude Code mechanism |
|---|---|
| **[workflow]** (this one) | this skill; the PR number/URL arrives in the invocation text |
| **[bulk-read offload]** | the `Explore` subagent (spawn on the [cheap tier] per `.claude/MODELS.md`) for large diffs/threads |
| **PR head checkout** (before fix + re-gate) | `gh pr checkout <n>` — make the working tree and `git diff main..HEAD` BE PR #N's head before editing or dispatching the gate (see "Check out the PR head" note) |
| **[reviewer]s / [orchestrated run]** (§5 re-gate) | the §7 gate on the **fix commit**: the Workflow tool running `.claude/workflows/gate-loop.js` (binding of `workflow/gate-loop.md`), models resolved from `.claude/MODELS.md` and passed in `args` `{taskId, strongModel, cheapModel, dispatchContract, dispatchSpec, fix?}`; or the `constitution-auditor` / `contract-auditor` / `spec-auditor` / `spec-quality-auditor` subagents (`.claude/agents/`) dispatched via the Agent tool, read-only, against `git diff main..HEAD` on the checked-out head |
| **[code-review pass]** | `/code-review` over the **checked-out PR head** (the §7-step-3 advisory pass; `/security-review` when the fix touches privacy, credentials, or payments) |
| **PR reads** (diff + every comment) | `gh pr view <n> --json title,body,state,baseRefName,headRefName,url,comments` (the `comments` field is the **timeline / issue-level** channel — §2.5 owner steering) and `gh pr diff <n>`, **plus the line-anchored inline findings `gh pr view` omits**: `gh api --method GET --paginate repos/{owner}/{repo}/pulls/<n>/comments` (inline review comments) and `.../pulls/<n>/reviews` (review summaries — where some bots/Codex post). Match automated reviewers by their **`[bot]` login suffix**, never an exact string (the Codex reviewer posts as `chatgpt-codex-connector[bot]`); **enumerate first, filter second** — an empty filtered set is suspicious, never "nothing to address". Where the **GitHub MCP server** (`mcp__github__*`) is connected, its PR review-comment / diff tools are a drop-in alternative for these reads |
| **PR writes** (fixes + replies) | **fixes**: commit the scoped change on the PR branch (stage specific files, never `git add .`; tick any owned tasks.md box in the same commit) and `git push` to PR #N's head branch. **replies**: `gh api --method POST repos/{owner}/{repo}/pulls/<n>/comments/<comment-id>/replies` (threaded reply to an inline finding) or `gh pr comment <n> --body-file <tempfile>` (timeline reply), each ending with the **[comment marker]**. **Never** `gh pr merge`, **never** `gh pr close` |
| **[comment marker]** | the footer line defined in `.claude/skills/next-task/SKILL.md` → "The [comment marker] concrete form" (the single copy) — appended to every reply this workflow posts |
| **[environment block]** | `.claude/skills/next-task/SKILL.md` → "This environment's concrete forms" (the single copy — multi-line bodies via a UTF-8 temp file + `--body-file`, `gh` PATH fallback) |
| **[headless run]** | `claude -p "/review-response <pr>"` |

**Profile read — packet first (spec 007 US3.AC3).** The workflow doc's project-specifics read
resolves to **`.claude/PROJECT.compact.md`** by default — the compact packet of active routing
facts (base branch, conventions, required check, review passes, critical invariants + backstops),
drift-checked against the full profile by `.claude/hooks/compact-packet-drift.sh` in CI `verify`.
**Escalate to the full `.claude/PROJECT.md` explicitly** — say you are escalating and why — when a
fix needs a fact the packet omits (an invariant's full text or auditor rule, architecture
boundaries, coverage policy). The full profile stays the source of truth.

**Check out the PR head before fixing or re-gating.** A fix must be committed onto PR #N's head,
and `/code-review` + the §7 gate read the current branch — so before §4/§5 run `gh pr checkout <n>`
to make the working tree (and `git diff main..HEAD`) be PR #N's head. Without the checkout you would
commit onto the wrong branch and the gate would grade the wrong diff. For a PR **not based on
`main`**, capture the diff against the PR's actual base (`gh pr view <n> --json baseRefName`) and pass
the auditors that patch. The PR **reads** work from any branch — only the fix, the lens passes, and
the re-gate need the checkout.

**Re-gate is not optional (the maker ≠ checker bound).** `review-response.md` §5 requires that any
fix be re-graded by the §7 **[reviewer]s** on the fix commit — you never push a fix as "resolved"
under your own say-so. Commit first (the gate audits the committed diff), dispatch the reviewers per
`gate-loop.md` → "The reviewer roster", loop until every dispatched reviewer returns PASS/JUSTIFY,
and keep every verdict verbatim (append the gate-run record per `telemetry.md`, as the `next-task`
[orchestrated run] row does). Non-convergence after two rounds → stop and surface in the reply/PR
body (§5).

**Write posture — the allowlist.** This skill **pushes to the PR branch and posts replies**, so
unlike `pr-review` (read-then-comment) it needs write grants beyond the read-only `gh api
--method GET` entries: `git push` to the PR branch and `gh api --method POST .../pulls/<n>/comments/*/replies`
(threaded replies) or `gh pr comment`. It still **never** merges or closes — `gh pr merge` / `gh pr
close` are out of scope and must not be allowlisted by this skill. The harness cannot grant its own
allow rules, so the **owner adds** the push/reply entries directly (or connects the **GitHub MCP
server**, whose write tools are permission-gated on their own); until then an interactive run prompts
on the first write, and a `[headless run]` degrades per `workflow/README.md` → "How an adapter
degrades gracefully" (surface the pending writes rather than silently skipping them).

**No new §7 gate semantics, and no merge.** Per `review-response.md` → "Write posture": this
workflow re-runs the existing §7 gate on its fixes (it does not create a second gate or alter the
gate's round limits, veto authority, or tier floors), and its terminal state is a **green PR with
every comment answered**, handed to the owner. Merge authorization is the owner's alone,
session-explicit (§2.5) — `review-response` never merges, even when every check is green.
