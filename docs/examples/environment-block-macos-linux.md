# Worked example — a macOS/Linux `[environment block]`

> **Illustrative example — not a live `[environment block]`.** The harness keeps exactly
> **one** live environment block, and it ships as the Windows PowerShell 5.1 instantiation in
> [`.claude/skills/next-task/SKILL.md`](../../.claude/skills/next-task/SKILL.md) → "This
> environment's concrete forms". This file is an **example to copy from** when you adopt the
> harness on macOS or Linux: translate the live block in `SKILL.md` to these forms (don't add a
> second live block — the single-copy rule is what keeps `bash`/`gh` gotchas in one place). See
> [`docs/examples/README.md`](README.md) for the whole set.

The shipped block is bullet-for-bullet Windows PowerShell 5.1 + `gh`. Below is the same bullet
set translated to macOS/Linux + `bash` + `gh`. The biggest simplification: **heredocs are UTF-8
by default**, so the PowerShell "write the temp `.md` as UTF-8, not UTF-16+BOM" dance disappears
— a plain quoted heredoc is correct.

---

**This environment's concrete forms** (macOS/Linux + `bash` + `gh`) — this section is the
**[environment block]**: the ONE home for OS/shell/CLI gotchas. Other bindings (e.g. `/triage`)
reference it; never copy these facts elsewhere.

- `gh` invocation — use it from PATH; in a headless run it may be absent, so fall back to the
  absolute install path (`/opt/homebrew/bin/gh` on Apple-Silicon Homebrew, `/usr/local/bin/gh`
  on Intel macOS or Linux). `gh repo set-default` is set locally, so a bare `gh` targets the
  right repo — re-run `set-default` after any re-clone.
- Issue-tracker authentication precondition — run `gh auth status`; if it fails, ask the user
  to authenticate with `gh auth login` before tracker-dependent steps.
- **Allowlist-shaped commands (autonomy):** the [permission allowlist] matches command
  *prefixes*, so issue tool calls as single plain commands (`git …`, `gh …`, `npm …`). A leading
  variable assignment (`VAR=… cmd`), a `$(…)` command-substitution wrapper, or an absolute path
  backgrounded with `&`/`nohup` can never match a prefix rule and WILL interrupt an unattended
  run with a prompt. To wait on CI, use `gh pr checks <n> --watch` (allowlisted) instead of a
  hand-rolled loop.
- §8 PR body — write the temp `.md` with a plain quoted heredoc (UTF-8 by default — no encoding
  flag needed):
  ```bash
  cat > pr-body.md <<'EOF'
  ...body...
  EOF
  gh pr create --body-file pr-body.md
  ```
- §8 verdict comments — write each reviewer's saved verdict report to its own temp `.md` (same
  heredoc), then `gh pr comment <n> --body-file <tempfile>` — one comment per dispatched
  reviewer, PASS results included.
- §8 visual evidence — images cannot be uploaded to GitHub from the CLI (`gh` has no
  comment/body image-upload). Commit the evidence (small PNGs; short MP4/GIF for animation work)
  under `docs/visual-evidence/<task-id>/` on the task branch, push, then embed
  `https://raw.githubusercontent.com/<slug>/<full-commit-sha>/<path>` in the PR body (slug per
  the profile). **Pin to the full commit SHA, never the branch name** — branches auto-delete on
  squash-merge and the URL would die; PR head commits stay reachable.
- §8 verify — `gh pr view <n> --json number,url,state,mergeStateStatus,statusCheckRollup`.
- §3 issue body — use a heredoc with `gh issue create --body-file` (same `cat > … <<'EOF'`
  form as the PR body above).
- `/triage` inbox/run-log default — when neither the `inbox:` argument nor `TRIAGE_INBOX` is
  given, the portable default directory is `<home>/.claude/triage/` (`<home>` = `$HOME` on
  macOS/Linux), so the inbox is `<home>/.claude/triage/<repo-basename>-triage.md` and the run
  log sits beside it as `<repo-basename>-heartbeat.log`. `<repo-basename>` = last segment of
  `git rev-parse --show-toplevel`.
