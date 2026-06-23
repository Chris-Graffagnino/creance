# Environment block — Omnigent adapter (this adapter's single copy)

This is the **[environment block]** for the Omnigent adapter: the ONE home for every
OS/shell/CLI/runtime-invocation concrete form. Other Omnigent binding files (`README.md`,
the future `config.yaml` / `reviewers/*.yaml` / `creance_omnigent/**`) **reference** this
file; they never re-state its contents (binding contract: "exactly ONE copy per adapter").

The neutral docs state portable *rules* (e.g. "pass multi-line text via a file, as
UTF-8"); this file gives their concrete Omnigent form. Facts marked **UNVERIFIED** could
not be confirmed from the cited docs and must be pinned on the first real-driver run
(T620), never assumed.

## Runtime invocation
- **Install:** Omnigent ships on **PyPI** — `uv tool install omnigent` or
  `pip install omnigent` (Python **3.12+**); also `brew install omnigent-ai/tap/omnigent`.
  (This contradicts T620's "not on PyPI — needs a from-source install" note, which predates
  the upstream release; see the PR's out-of-scope observations.)
- **Drive a config:** `omnigent run <path-to-config-dir-or-yaml>` (e.g.
  `omnigent run .claude/adapters/omnigent/` once `config.yaml` lands at T620). A specific
  built-in harness is `omnigent claude` / `omnigent codex`. Credentials: `omnigent setup`.
  Server/host lifecycle: `omnigent server start` / `omnigent host`; co-driving:
  `omnigent attach <session_id>`; conversation forking: `omnigent run --fork <session_id>`.
- **Primary surface is the web UI** at `http://localhost:6767`. There is **no documented
  non-interactive one-shot** mode (the `claude -p` / `codex exec` analog) — so the
  `[headless run]` and the scheduler half of `[workflow]` are **degradations** here: a
  scheduler drives `omnigent run <config>` with the workflow name, its arguments, and the
  repo root written **into the prompt/config text** (the explicit-context rule), and the
  non-interactive exit-code propagation is **UNVERIFIED** — pin it at T620.
- **Config / credential root:** the per-user Omnigent config + credential location is
  **UNVERIFIED** from the public docs (managed via `omnigent setup`); pin it at T620. Never
  rely on it for correctness — the repo root and all paths ride in the prompt text
  (explicit-context rule), exactly as for the other adapters.

## Sandboxing & isolation (backs `[isolated workspace]`)
- **git worktrees** for parallel agent work (native — each Polly dispatch launches a fresh
  worktree).
- **OS sandbox:** `bwrap` on Linux, the built-in **seatbelt** sandbox on macOS
  (`docs/AGENT_YAML_SPEC.md` sandbox types `linux_bwrap` / `darwin_seatbelt` / `none`).
- **Cloud sandbox:** disposable **Modal / Daytona / Islo** sandboxes, launched from the
  CLI or provisioned by the server per session.

## Issue-tracker interaction (backs the tracker-dependent steps + the `[comment marker]`)
- Tracker reads/writes go through `git` / `gh` shell commands governed by the
  `omnigent.policies.builtins.github.github_policy` builtin (`shell_tools: ["sys_os_shell"]`),
  or a GitHub MCP tool where one is configured. Whether to use the `gh` CLI vs. an MCP tool
  on a given host is **UNVERIFIED** — pin at T620.
- **Multi-line bodies** (issue/PR bodies, verdict comments) are written to a temp `.md`
  file and passed by path; on macOS/Linux a plain heredoc is UTF-8, so no special encoding
  step is needed (contrast the Claude adapter's PowerShell `Out-File -Encoding utf8` form).
- **Authentication precondition:** confirm `gh auth status` (or the configured GitHub MCP
  credential) before tracker-dependent steps; if it fails, authenticate first.

## Visual evidence (backs `[visual verification]`)
- Images cannot be uploaded to a tracker comment from the CLI. Commit the evidence (small
  PNGs; short MP4/GIF for animation work) under `docs/visual-evidence/<task-id>/` on the
  task branch, push, then embed
  `https://raw.githubusercontent.com/<slug>/<full-commit-sha>/<path>` in the PR body —
  pinned to the **full commit SHA, never the branch name** (squash-merge deletes the
  branch and the URL would die). This is a **repo convention shared across adapters**, not
  an Omnigent-specific mechanism.

## The [comment marker] concrete form (defined once, here)
Every engine-posted issue/PR comment body ends with this literal final line (write it into
the temp `.md` before the body-file call):

```
🤖 harness comment — engine-authored, not owner steering
```

Recognition is anchored to the comment's **final non-empty line only** (a non-developer can
read it; it separates harness bookkeeping from owner steering under a shared login). The
marker quoted mid-body neither marks a comment nor demotes an owner comment. Semantics:
`workflow/README.md` → `[comment marker]`; reading rules: `next-task.md` §2.5.

## Sources
Verified 2026-06-23 against `github.com/omnigent-ai/omnigent@main`: `README.md` (CLI
commands, install, web UI port, sandboxes), `docs/POLICIES.md` (`github_policy`,
`shell_tools`), `docs/AGENT_YAML_SPEC.md` (sandbox types). UNVERIFIED facts must be pinned
during wiring (T620).
