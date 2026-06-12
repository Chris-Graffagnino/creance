---
name: next-task
description: Start the next unblocked task in the build with full ceremony (project specifics from .claude/PROJECT.md). Use when the user says "next task", "work the next task", "continue the build", "what's next", or names a task ID to implement. Picks the task, opens the issue, cuts the branch, implements with tests, verifies, and runs review — stopping at PR (review mode).
---

# /next-task — Claude Code binding

The workflow logic is runtime-neutral and lives in **`.claude/workflow/next-task.md`** —
**read that file now and execute it.** This file only maps its abstract **[roles]** to the
concrete Claude Code mechanisms:

| Neutral role | Claude Code mechanism |
|---|---|
| **[reviewer]** | the `spec-auditor` / `constitution-auditor` / `contract-auditor` subagents (`.claude/agents/`), dispatched via the Agent tool — read-only, own context (pass `spec-auditor` the task ID in its prompt) |
| **[frontier tier] / [strong tier] / [cheap tier]** | resolved per the model table **`.claude/MODELS.md`** (the adapter's ONLY file naming models) — `--model` headless; the Agent tool's `model` parameter on EVERY reviewer dispatch (the agents carry no model pin; the constitution reviewer is always dispatched at-or-above the strong-tier row) |
| **[code-review pass] / [security-review pass]** | `/code-review` / `/security-review` |
| **[visual verification]** | `/run` + `/verify` launch and drive the app; the preview tooling captures screenshots (screen-recording where available, for animation work); commit evidence under `docs/visual-evidence/<task-id>/` on the task branch and embed it in the PR body's "your call" section via commit-SHA-pinned raw URLs (URL form: the [environment block] below) |
| **[orchestrated run]** | the Workflow tool running `.claude/workflows/gate-loop.js` (binding of `workflow/gate-loop.md`) for §7 steps 2/4/5 — commit first, resolve `{strongModel, cheapModel}` from `.claude/MODELS.md`, then invoke with `args: {taskId, strongModel, cheapModel, dispatchContract}`; it returns every verdict verbatim for §8 posting, plus `telemetry`: the gate-run record payload (`workflow/telemetry.md`). **After the workflow returns** (any outcome), append the record: take `result.telemetry`, add the envelope (`timestamp` ISO-8601 UTC now; `repo` = basename of `git rev-parse --show-toplevel`), resolve the stream path from `.claude/PROJECT.md` → "Paths" → Telemetry (create the parent directory if missing), and append it as ONE JSON line (`jq -c` or equivalent — never pretty-printed, never rewriting the file). A failed append is silent-to-the-gate: note it in the session and proceed exactly as if it had succeeded — the gate outcome, §8 posting, and the PR are unaffected. If the Workflow tool is unavailable, fall back to §7's prose (dispatch the reviewers via the Agent tool yourself; build and append the same record from your own dispatch history) |
| **[bulk-read offload]** | the `Explore` subagent (spawn on the [cheap tier] model per `.claude/MODELS.md`) |
| **[headless run]** | `claude -p "/next-task <id>"` |
| **[guard]** | the PreToolUse hook → `.claude/hooks/guard.sh` |
| **[permission allowlist]** | `.claude/settings.json` → `permissions.allow` |
| **[environment block]** | "This environment's concrete forms" below (the single copy) |
| **[comment marker]** | "The [comment marker] concrete form" below (the single copy) — appended to every engine-posted `gh issue comment` / `gh pr comment` body |

Plan note: usage may be account-wide (interactive + heartbeat + reviewers sharing one
pool) — apply the methodology's "Model & usage economy" tiering as written.

**The [comment marker] concrete form** — the single adapter-wide definition (other
bindings reference it; the role's semantics live in `workflow/README.md` and the reading
rules in `workflow/next-task.md` §2.5). Every engine-posted issue/PR comment body ends
with this literal final line (write it into the temp `.md` before the `--body-file` call):

```
🤖 harness comment — engine-authored, not owner steering
```

The line is exact and machine-checkable (P-CM greps for it verbatim) and plainly readable
by a non-developer. **Recognition is anchored to the comment's final line ONLY**: a
comment is marked iff its last non-empty line is exactly this string. The marker appearing
anywhere else (e.g. quoted mid-body) neither marks the comment nor demotes an owner
comment that embeds it. A comment not so marked, posted from the owner login, is owner
steering per §2.5. When quoting an owner comment inside a marked comment, render the
quoted text as a blockquote so it stays visibly distinct from the engine wrapper, and
never append the footer to the quoted text itself.

**This environment's concrete forms** (Windows PowerShell 5.1 + `gh`) — this section is the
**[environment block]**: the ONE home for OS/shell/CLI gotchas. Other bindings (e.g.
`/triage`) reference it; never copy these facts elsewhere.
**Per-machine — rewrite on adoption:** the bullets below are the *Windows PowerShell 5.1*
instantiation, shipped as a worked example. On macOS/Linux, replace them with your forms
(e.g. heredocs are UTF-8 by default, so the `Out-File -Encoding utf8` rule becomes "write
the temp `.md` with a plain heredoc"; `gh` falls back to `/opt/homebrew/bin/gh` or
`/usr/local/bin/gh` instead of a `Program Files` path). Keep this section the single
[environment block] either way.
- `gh` invocation — use it from PATH; in a headless run it may be absent, so fall back to
  the absolute install path (`C:\Program Files\GitHub CLI\gh.exe`). `gh repo set-default`
  is set to the fork locally, so a bare `gh` targets the right repo — no slug-derivation
  preamble needed in interactive sessions (re-run `set-default` after any re-clone/port).
- **Allowlist-shaped commands (autonomy):** the [permission allowlist] matches command
  *prefixes*, so issue tool calls as single plain commands (`git …`, `gh …`, `npm …`,
  `npx …`). A leading variable assignment (`$x = …;`), a bespoke polling loop, or an
  `&`-invoked absolute path can never match a prefix rule and WILL interrupt an
  unattended run with a prompt. To wait on CI, use `gh pr checks <n> --watch` (allowlisted)
  instead of a hand-rolled loop.
- §8 PR body — write the temp `.md` with `Out-File -Encoding utf8` (PS 5.1 defaults to
  UTF-16+BOM, which breaks `gh ... --body-file`), then `gh pr create --body-file <tempfile>`.
- §8 verdict comments — write each reviewer's saved verdict report to its own temp `.md`
  (same `Out-File -Encoding utf8` rule), then `gh pr comment <n> --body-file <tempfile>` —
  one comment per dispatched reviewer, PASS results included.
- §8 visual evidence — images cannot be uploaded to GitHub from the CLI (`gh` has no
  comment/body image-upload). Commit the evidence (small PNGs; short MP4/GIF for animation
  work) under `docs/visual-evidence/<task-id>/` on the task branch, push, then embed
  `https://raw.githubusercontent.com/<slug>/<full-commit-sha>/<path>` in the PR body
  (slug per the profile). **Pin to the full commit SHA, never the branch name** — branches
  auto-delete on squash-merge and the URL would die; PR head commits stay reachable.
- §8 verify — `gh pr view <n> --json number,url,state,mergeStateStatus,statusCheckRollup`.
- §3 issue body — use a heredoc with `gh issue create`.
- `/triage` inbox/run-log default (`triage.md` §4.3 / §1.5.3) — when neither the `inbox:`
  argument nor `TRIAGE_INBOX` is given, the portable default directory is
  `<home>/.claude/triage/` (`<home>` = `$HOME`; PS 5.1: `$env:USERPROFILE`), so the inbox
  is `<home>/.claude/triage/<repo-basename>-triage.md` and the run log sits beside it as
  `<repo-basename>-heartbeat.log`. `<repo-basename>` = last segment of
  `git rev-parse --show-toplevel`.
