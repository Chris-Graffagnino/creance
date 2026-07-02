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
| **PR checkout** (before the lens passes) | `gh pr checkout <n>` — make the working tree and `git diff main..HEAD` BE PR #N's head before dispatching the lenses below (see "Check out the PR head" note) |
| **[code-review pass] / [security-review pass]** | `/code-review` / `/security-review` over the **checked-out PR head** (the security lens when the PR touches privacy, credentials, or payments) |
| **[reviewer]** (auditor lenses, read-only) | the `constitution-auditor` / `contract-auditor` / `spec-auditor` subagents (`.claude/agents/`) dispatched via the Agent tool against the **checked-out PR head** — **pass each the committed diff (`git diff main..HEAD`) in its prompt**, since the reviewer bindings grant no shell to run it themselves (read-only by construction, #188); own context, no edit tools; models per `.claude/MODELS.md` (the constitution reviewer at-or-above the strong-tier row, never below) |
| **[comment marker]** | the footer line defined in `.claude/skills/next-task/SKILL.md` → "The [comment marker] concrete form" (the single copy) — appended to the review comment this workflow posts |
| **[environment block]** | `.claude/skills/next-task/SKILL.md` → "This environment's concrete forms" (the single copy — multi-line bodies via a UTF-8 temp file + `--body-file`, `gh` PATH fallback) |
| **[headless run]** | `claude -p "/pr-review <pr>"` |
| PR reads | `gh pr view <n> --json title,body,state,baseRefName,headRefName,url,comments` (the `comments` field returns the **timeline / issue-level** comments — the §2.5 owner-steering channel and any PR-level findings) and `gh pr diff <n>`, **plus the line-anchored inline findings `gh pr view` omits**: `gh api --method GET --paginate repos/{owner}/{repo}/pulls/<n>/comments` (inline review comments) and `.../pulls/<n>/reviews` (review summaries — where some bots/Codex post) — the bot/automated inline findings the timeline view misses. **`--method GET` keeps these reads write-incapable**, so their allowlist entry can't auto-approve a write. Where the **GitHub MCP server** (`mcp__github__*`) is connected, its PR review-comment / diff tools are a drop-in alternative for these reads — MCP tools are permission-gated on their own, needing no shell allowlist |
| PR writes (additive only) | `gh pr comment <n> --body-file <tempfile>` for the structured review — **never** `gh pr merge`, never `gh pr close`, never a push to the PR branch. (The deliverable is one consolidated review comment; an optional inline reply needs a write grant beyond the read-only `gh api --method GET` entry — or the GitHub MCP server) |

**Check out the PR head before the lens passes.** `/code-review` reads the current branch, and the
diff you hand the `[reviewer]` subagents must be PR #N's — so before the lens passes run
`gh pr checkout <n>` to make the working tree (and `git diff main..HEAD`) be PR #N's head. The reviewer
bindings grant **no shell** (read-only by construction, #188), so **you** (the dispatcher, on the
checked-out head) run `git diff main..HEAD` and paste it into each reviewer's Agent-tool prompt — the
reviewer audits that provided diff and reads surrounding files with Read/Grep/Glob. Without the
checkout, `/code-review` grades your current branch and the diff you'd capture is the wrong one, not
the PR under review (the runtime-neutral root is `pr-review.md` → "Write posture" → "Every lens grades
*this PR's* diff, not the reviewer's branch"). The PR **reads** above (`gh pr diff`,
`gh api .../comments` / `/reviews`) work from any branch — only the **lens** passes need the checkout.
For a PR **not based on `main`**, `main..HEAD` assumes base = `main`; capture the diff against the PR's
actual base (`gh pr view <n> --json baseRefName`) and hand the auditors that patch, noting the scoping
in the review. `gh pr checkout` only reads/creates a local branch — it stays within the
read-then-comment posture (no push).

Why the explicit `gh api .../pulls/<n>/comments` + `.../pulls/<n>/reviews` reads: `gh pr view --comments`
returns only the **timeline (issue-level)** comments, so a review built from it alone silently
skips every **line-anchored** inline finding — including the bot/Codex inline comments this
workflow's §2 requires. Fetching the pulls endpoints is what makes the §4 grounding gate's
"every inline comment enumerated" clause satisfiable rather than aspirational. For an unattended
`[headless run]` not to stall on a permission prompt before the grounding gate, the
**[permission allowlist]** (`.claude/settings.json`) needs read-scoped entries for both shells —
`gh api --method GET:*` and `gh pr checkout:*` (the `--method GET` form is write-incapable, so the
entry cannot auto-approve a GitHub write). The harness cannot add these itself — granting its own
allow rules is barred — so the **owner adds them directly**, or connects the **GitHub MCP server**
(whose PR tools need no shell allowlist); until then an interactive run simply prompts on the first
`gh api`.

**Enumerate first, filter second — a bot-login mismatch must never read as "no findings".**
§2's "enumerate every inline comment" and the §4 grounding gate are only satisfiable if the fetch
lists **all** comments first and identifies their authors **second**: never pre-filter the
`pulls/<n>/comments` / `pulls/<n>/reviews` reads by an exact author login. Match automated reviewers
by their `[bot]` login suffix, not an exact string — the Codex reviewer posts as
`chatgpt-codex-connector[bot]`, so a filter for `chatgpt-codex-connector` returns **zero** and a
naive "no comments → no findings" silently skips a real finding (this bit a review of PR #92/#94).
So treat an empty filtered set as suspicious: "no findings" is reachable only when the
unfiltered comment count is zero across **all three fetched sources** — timeline/issue-level
comments (`gh pr view ... --json ...,comments`), inline review comments (`pulls/<n>/comments`),
and review summaries (`pulls/<n>/reviews`) — or when every comment in that set has been
adjudicated per `pr-review.md` §3. **Fetch every source you count**: tallying `timeline` without
actually fetching it (`--json ...,comments`) is the same silent-clean defect. A login-string
mismatch — or an unfetched source — can then never masquerade as a clean PR.

Write posture per the workflow doc (`pr-review.md` → "Write posture"): the only write is the
review comment (plus inline replies where supported), each carrying the marker; merge / close /
push are out of scope; and this workflow changes **no** §7 pre-PR gate semantics — it is a
reviewer's pass on an already-open PR, complementing the pre-PR gate, not a second gate.
