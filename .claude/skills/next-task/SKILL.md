---
name: next-task
description: Start the next unblocked task in the build with full ceremony (project specifics from the profile). Use when the user says "next task", "work the next task", "continue the build", "what's next", or names a task ID to implement. Picks the task, opens the issue, cuts the branch, implements with tests, verifies, and runs review — stopping at PR (review mode).
---

# /next-task — Claude Code binding

The workflow logic is runtime-neutral and demand-loaded from
**`.claude/workflow/next-task/*.md`**. Start with the compact project packet and
`next-task/00-foundations.md`; when a stage completes, load only the next card named by
the ordered `.claude/workflow/next-task.md` index. Do **not** preload the index, another
card, or the old full procedure for ordinary work. Escalate to the index only to navigate,
resume at an unknown stage, or audit the full procedure. This file only maps the cards'
abstract **[roles]** to concrete Claude Code mechanisms:

| Neutral role | Claude Code mechanism |
|---|---|
| **[reviewer]** | the `spec-auditor` / `constitution-auditor` / `contract-auditor` / `spec-quality-auditor` subagents (`.claude/agents/`), dispatched via the Agent tool — read-only, own context (pass `spec-auditor` the task ID in its prompt). **Membership, tier, and dispatch-condition are single-sourced in the roster (`gate-loop.md`) + §7, not this row** — so the Workflow-tool-absent fallback (this row → §7) dispatches the full set, the two conditional reviewers (`contract-auditor` / `spec-quality-auditor`) firing on their roster conditions; never omit the spec-quality reviewer on a `specs/*/spec.md` diff. `reviewer-roster.test.sh` pins this map's membership so a reviewer can't silently drop off it |
| **[frontier tier] / [strong tier] / [cheap tier]** | resolved per the model table **`.claude/MODELS.md`** (the adapter's ONLY file naming models) — `--model` headless; the Agent tool's `model` parameter on EVERY reviewer dispatch (the agents carry no model pin; the constitution reviewer is always dispatched at-or-above the strong-tier row) |
| **[code-review pass] / [security-review pass]** | `/code-review` / `/security-review` |
| **[craft-review pass]** *(optional)* | the `engineering-craft` skill's review mode — `engineering-craft review` (equivalently `/engineering-craft review`), run **alongside** `/code-review` at §7 step 3, **never** a roster `[reviewer]` and advisory only (findings to the PR body, no PASS/FAIL gate). An **external**, separately-installed skill (unlike the built-in `/code-review`), so when it is absent skip the craft layer and note the skip in the PR (`workflow/README.md` → "How an adapter degrades gracefully"). Full mechanism + external-dependency detail: `.claude/README.md` |
| **[visual verification]** | `/run` + `/verify` launch and drive the app; the preview tooling captures screenshots (screen-recording where available, for animation work); commit evidence under `docs/visual-evidence/<task-id>/` on the task branch and embed it in the PR body's "your call" section via commit-SHA-pinned raw URLs (URL form: the [environment block] below) |
| **[orchestrated run]** | the Workflow tool running `.claude/workflows/gate-loop.js` (binding of `workflow/gate-loop.md`) for §7 steps 2/4/5 — commit first, resolve `{strongModel, cheapModel}` from `.claude/MODELS.md`, then invoke with `args: {taskId, strongModel, cheapModel, dispatchContract, dispatchSpec, taskBranch}` **from a session rooted in the repo** — the reviewer subagents dispatch by custom `agentType`, which the runtime resolves from the **session root's `.claude/agents/`** (not `workspacePath`), so a dispatcher rooted elsewhere resolves none of them; a **deterministic preflight** (T642/#214) probes the roster agent types before round 1 and **aborts before any reviewer dispatch** (zero fix rounds) with a diagnostic naming the unresolvable type(s) + the dispatcher-rooted-outside-the-repo cause, never a NO-RESULT fan-out that burns the fix budget grading nothing. `taskBranch` is the branch you cut in §4 and is the **required review-mode audited ref** (T639/#240): the gate's diff-provider verifies the **shared** tree's HEAD still matches it before every dispatch — through `.claude/hooks/gate-diff.sh`, which fails the gate **loud** on a concurrent-session branch switch instead of letting the reviewers grade the wrong diff — AND the gate's fix step restores the **shared** working tree onto it before each fix-and-re-dispatch round (review mode: a shell-holding step in the loop — the diff-provider or the fixer — can drift the shared HEAD off the task branch, so the loop heals it at the fix boundary, not only after the run; the read-only reviewers can't, holding no shell — #140/T622, #188). One of `taskBranch` (review) or `workspacePath` (autonomous) is **required** — the loop hard-errors on neither, refusing to audit an inferred working directory — **plus `workspacePath`** (the `enter`-printed worktree path) under an engaged isolated autonomous run, so the diff-provider reads the **workspace's** committed diff via an explicit `git -C <path>` (the reviewers audit that provided diff, #188) and the fixer commits there (gate-in-place, T612; the work is isolated there, so the shared-tree `taskBranch` restore does not apply; omit `workspacePath` for review mode and those commands target the main tree instead); it returns every verdict verbatim for §8 posting, plus `telemetry`: the gate-run record payload (`workflow/telemetry.md`). **After the workflow returns** (any outcome), **first restore the task branch (review mode)** — run `.claude/hooks/restore-task-branch.sh <task-branch>` from the repo root: the loop's shell-holding steps (the diff-provider and the fixer) run in the **shared** working tree, so a stray `git checkout`/`switch` there can silently relocate the maker's HEAD off the task branch (#140/T622; the read-only reviewers no longer can — they hold no shell, #188); the helper is a no-op when nothing drifted and **fails loud** (exit 1) when it cannot guarantee the branch — surface that, never push/PR from a drifted HEAD. Run it **before** the `commit` capture below so telemetry records the restored HEAD, not a drifted one. (Autonomous mode's work lives in the ephemeral `[isolated workspace]` governed by the lifecycle, so this shared-tree restore is review-mode only.) Then append the record: take `result.telemetry`, add the envelope (`timestamp` ISO-8601 UTC now; `repo` = basename of `git rev-parse --show-toplevel`) **and** `commit` = `git rev-parse HEAD` (the head SHA of the audited diff — read it here, after the gate returns, so any fix-round commits the loop made on the task branch are included), resolve the stream path from the packet (`.claude/PROJECT.compact.md` → "Paths" → "Telemetry stream" — the packet carries this routing fact, drift-checked against the full profile; escalate to `.claude/PROJECT.md` only if the packet is absent), creating the parent directory if missing, and append it as ONE JSON line (`jq -c` or equivalent — never pretty-printed, never rewriting the file). A failed append is silent-to-the-gate: note it in the session and proceed exactly as if it had succeeded — the gate outcome, §8 posting, and the PR are unaffected. If the Workflow tool is unavailable, fall back to §7's prose (dispatch the reviewers via the Agent tool yourself; build and append the same record from your own dispatch history) |
| **[bulk-read offload]** | the `Explore` subagent (spawn on the [cheap tier] model per `.claude/MODELS.md`) |
| **[headless run]** | `claude -p "/next-task <id>"` |
| **[live-state reconciliation]** (the §1 selection precondition) | run `.claude/hooks/reconcile-task-selection.sh <candidate-id>` from the repo root before committing to a candidate: **exit 3** = drift — its box is unchecked but merged/landed work exists, so refuse the candidate and surface the printed evidence, never start it; **exit 0** = selectable; **exit 2** = usage. Git-based, so it shares `lib-tasks-drift.sh` with CI's `check-tasks-consistency.sh` (one drift definition, two consumers) and needs no network; it **fails open** (warns + exit 0) when git state is unreadable. This git-only check covers the **merged/landed** axis (a landed `[T<nnn>]` commit subject). Its **in-flight** companion is `.claude/hooks/reconcile-inflight-selection.sh <candidate-id>`, run **after** this one clears a candidate: it resolves the candidate's mapped issue and consults `gh` for an open PR whose title carries `[<task-id>]` or a remote branch `<type>/<issue#>-…` — **exit 3** = in-flight (refuse + surface the conflicting PR/branch), **exit 0** = selectable, **exit 2** = usage. Being a tracker read it **fails open** (warns + exit 0) when `gh`/network is unavailable, degrading to this git-only result — never a stall (T615/#105). It deliberately does **not** source `lib-tasks-drift.sh`: in-flight is a distinct tracker signal, not a fork of the git drift definition (P2) |
| **[selection announce-and-confirm]** (the §1 announce + conditional confirm) | After resolving the candidate, run `.claude/hooks/announce-task-selection.sh <candidate-id> <explicit\|implicit>` from the repo root, passing the mode **explicitly** — the binding knows whether the user named a task id/issue, never inferred. It prints the decision on stdout: **`proceed`** = announce the resolved target (task id + issue) and continue, no prompt; **`confirm`** = announce, then **pause and ask the user** before the first file edit (present the live-state contradiction + the drift evidence via the `AskUserQuestion` tool, offering "confirm this target" / "pick a different task or issue" — on a redirect re-run §1 with the named target; the pause **never starts the contradicted candidate**, and a merge is never an offered choice); **`announce-only`** = announce + continue, degraded (live state unreadable — no stall). Exit 0 (decision) / 2 (usage). **Composition with [live-state reconciliation], keyed to the selection's provenance:** for an **explicit** pick, reconcile's `exit 3` is the *terminal* refusal of a named stale task and announce then only ever `proceed`s; for an **implicit** pick, run announce on the lowest-unchecked candidate and let its `confirm` surface the *same* drift reconcile detects as a pause-for-redirect — so `confirm` is reachable on the real composed path and is **not** gated behind a reconcile `exit 0` (the composed path is pinned by `announce-task-selection.test.sh`'s `run_composed` cases). Shares `lib-tasks-drift.sh` — the third consumer (one drift definition, never forked). A `[headless run]` names the id explicitly, so it resolves to `proceed`; the confirm pause is an interactive-session affordance. T614 |
| **[autonomy activation]** (the §0.5 run-mode decision) | run `.claude/hooks/autonomy-mode.sh [--session-authorized]` from the repo root — it prints `review` or `autonomous` on stdout (exit 0; 2 = usage). Default-OFF and **fails closed to review** (the deliberate inverse of the [guard]); `autonomous` only when the profile carries `autonomy-opt-in: enabled` **or** `--session-authorized` is passed (the runtime sets that flag when the user authorizes autonomy in-session — explicit-context, never inferred from env). On `review` run the normal path; on `autonomous` enter the [isolated workspace] (next row). T610 / DESIGN-NOTES §13 |
| **[isolated workspace]** (the §4 enter; the §8 outcome-driven teardown) | the worktree lifecycle in `.claude/hooks/isolated-workspace.sh`: `enter <branch> [--base <ref>]` adds an ephemeral git worktree on a **fresh** branch and **prints its path** on stdout — capture it and carry it forward (explicit-context); `exit <path>` tears the workspace **directory** down, **leaving** the branch (the teardown half of promote); `discard <path>` tears the directory down **and deletes the ephemeral branch** (discard-on-FAIL). `enter` **fails loud** (non-zero, no path) → **abort** the autonomous run, never fall back to the base branch. **Gate-in-place (T612):** the §7 gate reads the workspace diff (pass the path as `workspacePath` to the [orchestrated run] above), then §8's terminal step follows the gate outcome — **PASS → promote** = commit + `git push` + `gh pr create`, then `exit <path>`; **FAIL → discard** = `discard <path>`, no push, no PR. Promotion is a PR (merge stays session-explicit, §8), never a direct base-branch write (P4). All three verbs refuse any path `enter` did not create — a provenance marker `enter` writes beside the workspace, not the `creance-ws-*` name alone, is the proof (Codex P2, #114). **Falsification proof (T613):** `.claude/hooks/isolation-falsification.test.sh` (wired into `verify`) adversarially proves an un-gated change cannot reach the base branch through the lifecycle, and the live **P-IW** conformance probe (`.claude/adapters/claude-code-probes.md`) confirms the isolation tier fires on a real driver. T611+T612+T613 / DESIGN-NOTES §14 |
| **[guard]** | the PreToolUse hook → `.claude/hooks/guard.sh` |
| **[permission allowlist]** | `.claude/settings.json` → `permissions.allow` |
| **[environment block]** | "This environment's concrete forms" below (the single copy) |
| **[comment marker]** | "The [comment marker] concrete form" below (the single copy) — appended to every engine-posted `gh issue comment` / `gh pr comment` body |

**Profile read — packet first (spec 007 US3.AC3).** The workflow doc's "read the profile
once at the start" resolves to **`.claude/PROJECT.compact.md`** by default — the compact
packet of active routing facts (base branch, paths, conventions, required check, autonomy
status, blocked list, review passes, critical invariants + backstops, the [edit guard]
map), drift-checked against the full profile by `.claude/hooks/compact-packet-drift.sh`
in CI `verify`. **Escalate to the full `.claude/PROJECT.md` explicitly** — say you are
escalating and why — when a step needs a fact the packet deliberately omits (an
invariant's full text or auditor rule, the maker-eval records path, architecture
boundaries, constitution watch, coverage policy, autonomy rationale). The full profile
stays the source of truth; the packet is the read optimization, never a second authority.

**Task index — selection reads it first (spec 007 US5.AC3).** §1's "read the profile's
**task index**" resolves to **`specs/TASK_INDEX.md`** — a generated digest of every backlog
task's selection-critical fields (id, tier, checkbox state, owning acceptance-criterion
refs, short title; the spec path is each section's heading), regenerated from
`specs/*/tasks.md` by `python3 .claude/hooks/task-index.py --write` and staleness-checked
(`--check`) in CI `verify`, so it can never silently rot. Read it to pick the candidate —
~3.5k tokens instead of every tasks file — then load only the **selected** task's full
spec/tasks context (§2, the profile's tasks/spec paths). The §1 selection preconditions —
`reconcile-task-selection.sh`, then `reconcile-inflight-selection.sh`, then
`announce-task-selection.sh` — run **unchanged** on that candidate: the index changes the
read surface, never the deterministic gates. If the index is absent or its `--check` is
red (stale), fall back to reading `specs/*/tasks.md` directly and regenerate it.

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
`/usr/local/bin/gh` instead of a `Program Files` path). A fully worked macOS/Linux
translation to copy from is `docs/examples/environment-block-macos-linux.md` (illustrative,
**not** a second live block). Keep this section the single [environment block] either way.
- `gh` invocation — use it from PATH; in a headless run it may be absent, so fall back to
  the absolute install path (`C:\Program Files\GitHub CLI\gh.exe`). `gh repo set-default`
  is set to the fork locally, so a bare `gh` targets the right repo — no slug-derivation
  preamble needed in interactive sessions (re-run `set-default` after any re-clone/port).
- Issue-tracker authentication precondition — run `gh auth status`; if it fails, ask the
  user to authenticate with `gh auth login` before tracker-dependent steps.
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
