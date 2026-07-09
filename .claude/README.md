# `.claude/` — portable task-driven workflow harness

A reusable engine for running engineering work as **one task → one issue → one branch →
one PR**, with an adversarial **maker ≠ checker** review gate. It is layered for two kinds
of portability:

- **Project-portable** — no project facts in the engine; everything specific lives in
  `PROJECT.md` + `memory/constitution.md`. Reuse on a new project by rewriting those.
- **Runtime-portable** — the *methodology* is runtime-neutral prose in `workflow/`, written
  against abstract **[roles]**; a per-runtime **adapter** maps each role to a concrete
  mechanism. The shipped adapter targets Claude Code. Reuse on a non-Claude runtime by
  writing one new adapter against `workflow/README.md`'s binding contract — the neutral
  core is reused unchanged.

## The three layers

| Layer | Files | Project-specific? | Runtime-specific? |
|-------|-------|-------------------|-------------------|
| **Profile** | `PROJECT.md`, `PROJECT.template.md` | **Yes — edit this** | no |
| **Methodology** (the engine logic) | `workflow/*.md`, `workflow/reviewers/*.md` | no (reads the profile) | **no — references [roles] only** |
| **Adapter** (Claude Code binding) | `skills/*/SKILL.md`, `agents/*.md`, `hooks/guard.sh`, `settings.json`, `MODELS.md` | no | yes |

Each binding is thin: a skill/agent file carries only its trigger frontmatter + a
role→mechanism map, then points at its `workflow/` doc. `settings.local.json` (machine-
specific permission overrides) is gitignored and does not travel.

## The shipped adapter: Claude Code

How this adapter maps each contract role (the roles' runtime-neutral specs — inputs,
outputs, constraints — live in `workflow/README.md` → "The binding contract"; this table
is mechanisms only). Each skill file restates the subset it needs at trigger time — when
changing a mapping, update both.

| Role | Claude Code mechanism |
|------|----------------------|
| **[workflow]** | A skill / slash command (`.claude/skills/<name>/SKILL.md`) |
| **[reviewer]** | A subagent (`.claude/agents/<name>.md`, `tools:` excludes Edit/Write) dispatched via the Agent tool |
| **[frontier tier] / [strong tier] / [cheap tier]** | Resolved per the model table in **`MODELS.md`** — the adapter's ONLY file naming models (`--model` headless; the Agent tool's `model` parameter per subagent dispatch — the agent files carry no model pin) |
| **[code-review pass] / [security-review pass]** | `/code-review` / `/security-review` |
| **[craft-review pass]** *(optional)* | The `engineering-craft` skill's review mode — `engineering-craft review` (equivalently `/engineering-craft review`), which acquires the branch/PR diff and reports the craft-layer findings. An **external** skill (see "Assumed runtime features"), not a built-in; absent it, the gate degrades per `workflow/README.md` → "How an adapter degrades gracefully" |
| **[visual verification]** | The `/run` and `/verify` skills launch and drive the app; the preview tooling captures screenshots (its screen-recording where available, for animation work). Evidence files are committed on the task branch under `docs/visual-evidence/<task-id>/` and embedded in the PR body via commit-SHA-pinned raw URLs (the URL form lives in the [environment block]) — the CLI cannot upload images to GitHub directly. That path is **world-readable** (public repo, permanent git history), so the role's fixtures-only frame constraint is a privacy boundary here, not a style rule |
| **[orchestrated run]** | The Workflow tool running the adapter script `.claude/workflows/gate-loop.js` (the binding of `workflow/gate-loop.md`). The invoker resolves the strong/cheap rows from `MODELS.md` and passes them in `args` — `{taskId, strongModel, cheapModel, dispatchContract, dispatchSpec, taskBranch|workspacePath, maxFixRounds?, fix?}` (exactly one of `taskBranch` — review mode — or `workspacePath` — isolated autonomous run — is the **required audited ref**; the script hard-errors without one, T639/#240); the script names no models and hard-fails on missing args. It dispatches the auditor subagents by custom `agentType`, which the runtime resolves from the **dispatcher session root's `.claude/agents/`** (NOT from `workspacePath`), so the script must be invoked **from a session rooted in the repo**; a **deterministic preflight** (T642/#214) probes each rostered agent type before round 1 and, on an unresolvable type, **aborts before any reviewer dispatch** (zero fix rounds) with a diagnostic naming the unresolvable type(s) and the dispatcher-rooted-outside-the-repo cause — never a NO-RESULT fan-out that burns the whole fix budget grading nothing. It dispatches with a structured verdict schema and returns every verdict verbatim, plus `telemetry`: the gate-run record payload (`workflow/telemetry.md`) — after the run returns (any outcome), the invoker appends that record per the next-task binding's [orchestrated run] row (envelope stamped at append time; a failed append is silent-to-the-gate); the fix stage is a maker-role agent inheriting the session's (task-tier) model |
| **[bulk-read offload]** | The `Explore` subagent (spawn on the cheap tier) |
| **[headless run]** | `claude -p "/<workflow> <args>"` |
| **[guard]** | A PreToolUse hook → `hooks/guard.sh` (exit 2 blocks; reads the hook's JSON payload on stdin; implements the guard rules normatively listed in `workflow/README.md`) |
| **[edit guard]** | A **PostToolUse** hook → the same `hooks/guard.sh` (rule 7), wired in `settings.json` for `Edit\|Write\|MultiEdit\|NotebookEdit`. On an edit to a file whose type maps to a checker in `PROJECT.md` → "Edit-time checks", it reruns that checker and exits 2 with the diagnostics when the edit adds one beyond the file's committed `HEAD` baseline (fix-forward — PostToolUse cannot revert). Shipped checker: `hooks/shell-lint.sh` (`bash -n` + a BSD/GNU portability denylist, also run standalone over `hooks/*.sh` in CI `verify`) |
| **[isolated workspace]** *(bound — T610+T611+T612+T613/epic #81)* | The **[autonomy activation]** decision is `hooks/autonomy-mode.sh`: it reads the profile `autonomy-opt-in` flag (`PROJECT.md` → "Autonomy") plus an explicit `--session-authorized` signal, prints `review`/`autonomous`, and **fails closed to review** (the deliberate inverse of `guard.sh`). The worktree lifecycle is `hooks/isolated-workspace.sh` (`enter <branch> [--base <ref>]` adds an ephemeral git worktree on a fresh branch and **prints its path**; `exit <path>` tears the workspace directory down, leaving the branch — the *promote* teardown; `discard <path>` tears it down **and deletes the ephemeral branch** — the *discard-on-FAIL* path; `enter` **fails loud** → the caller aborts, never falls back to the base branch), and `next-task.md` §0.5/§4 wires the activation read into the autonomous path (**T611**). **Gate-in-place (T612):** the §7 gate reads the **workspace** diff (the path is passed to the [orchestrated run] as `workspacePath`, an explicit `git -C <path>` — never an inferred CWD), and §8's terminal step follows the gate outcome: **PASS → promote** (push + open the PR through the §7-gated path, then `exit`), **FAIL → discard** (`discard`, no PR). Promotion is a **PR, not a merge** (merge stays session-explicit), and the isolation mechanism never writes the base branch directly (P4). **Falsification proof (T613):** `hooks/isolation-falsification.test.sh` (wired into `verify`) adversarially proves an un-gated change cannot reach the base branch — unreachable from base after `exit`, destroyed whole by `discard`, a forged `branch=main` marker cannot make `discard` delete the checked-out base, and the script source carries no base-writing door; the live counterpart is the **P-IW** conformance probe (`adapters/claude-code-probes.md`) that the isolation tier actually fires |
| **[backlog-loop]** *(optional; bound — T902+T904+T905/spec 004)* | The bounded unattended loop is the composition the launcher template `docs/launchers/backlog-loop.sh` (the [scheduled run] entry) drives: `hooks/backlog-loop.sh run <N>` — the deterministic control skeleton (closed stop-condition set, evaluated only between iterations; consults `hooks/autonomy-mode.sh` at loop start and between every iteration, **failing closed to review**: an unattended run is authorized ONLY by the profile `autonomy-opt-in` flag, never a launcher-manufactured session signal) — with its seams bound to `hooks/backlog-loop-select.sh` (lowest unchecked, deps-met, non-blocked candidate across the live tasks files) and `hooks/backlog-loop-iterate.sh` (one fresh `claude -p "/next-task <id>"` cycle per iteration, the task ID explicit in the prompt; the outcome read from the run's own return via the terminal `BACKLOG-LOOP-OUTCOME:` marker, failing closed to `aborted`). Under a run id the skeleton **drives** the T904 observe-only run-report emitter (write-only, silent-to-the-run; the P5 fence `hooks/backlog-loop-fence.sh` names the emitter and proves nothing reads the report back). Promotion inside an iteration is the existing §7-gated PR path — the loop **never merges, never writes the base branch**. Live proof: the **P-BL** conformance probe (`adapters/claude-code-probes.md`) |
| **[permission allowlist]** | `settings.json` → `permissions.allow` (prefix-matched) |
| **[environment block]** | `skills/next-task/SKILL.md` → "This environment's concrete forms" (the single copy; other bindings reference it, never copy it) |
| **[comment marker]** | Every engine-posted `gh issue comment` / `gh pr comment` body ends with the marker footer line defined in `skills/next-task/SKILL.md` → "The [comment marker] concrete form" (the single copy, alongside the [environment block]) |

### Assumed runtime features

The mappings above bind to Claude Code built-ins whose availability varies by version
and surface (CLI / desktop / web). This adapter assumes — last probed against the Claude
Code CLI current as of **2026-06-12**:

- The `/code-review`, `/security-review`, `/run`, and `/verify` built-in skills.
- The **`engineering-craft` skill** for the **[craft-review pass]** — unlike the built-ins
  above, this is an **external skill that must be separately installed** on the running
  machine/surface (e.g. under `~/.claude/skills/`); a fresh clone of this repo does not
  carry it. Its absence is the expected degradation case (skip the craft layer + note it
  in the PR, per `workflow/README.md` → "How an adapter degrades gracefully"), never a hard
  failure. Vendoring it into the repo (so the dependency travels) is a possible future
  hardening; today it is an assumed external feature like the built-ins.
- The **Workflow** tool (for [orchestrated run]) and the **Explore** subagent (for
  [bulk-read offload]).
- The Agent tool's **`model` parameter** (per-dispatch model selection — without it the
  tier floor for the constitution [reviewer] cannot be enforced).
- **PreToolUse hooks**, including the `"shell"` and `"statusMessage"` keys used in
  `settings.json` — verify these against the settings schema for *your* Claude Code
  version; an unrecognized key can leave the guard unwired.
- Headless mode (`claude -p`) and long-lived token minting (`claude setup-token`) for
  scheduled runs.

If any of these is absent on your version/surface, apply the degradation rules in
`workflow/README.md` rather than silently proceeding. The probes in
`adapters/claude-code-probes.md` are how you find out — run them on the actual machine
and surface that will drive the harness.

This adapter's conformance-probe instantiation and dated results live in
**`adapters/claude-code-probes.md`** (the `workflow/conformance-probes.md` checklist,
executed 2026-06-11 — re-probe per its header when a mechanism here changes).

## Reuse on a new **project** (same runtime)
1. Copy `.claude/` into the new repo.
2. `cp .claude/PROJECT.template.md .claude/PROJECT.md` and fill in every `<...>`.
3. Add a `memory/constitution.md` — the project's principles ("law"). The reviewers read it.
4. Add a `specs/` tree (or point `PROJECT.md` "Paths" at wherever your spec/tasks/contracts
   live; set unused paths to "none").
5. Confirm `settings.json`'s allowlist fits your tools; keep machine-specific rules in a
   gitignored `settings.local.json`.

## Adding a new adapter (different runtime)
1. Reuse `workflow/` + `PROJECT.md` + `memory/constitution.md` **unchanged** — never edit
   the neutral core to fit a runtime; if a runtime need leaks upward, the fix is a new
   role in the binding contract, not a mechanism name in `workflow/`.
2. Read `workflow/README.md` → "The binding contract": every **[role]** with its
   runtime-neutral spec (inputs / outputs / constraints).
3. Implement each role in the target runtime's native format — that set of artifacts *is*
   the adapter, replacing this repo's `skills/` + `agents/` + `hooks/` + `settings.json`.
   In particular:
   - Give the adapter exactly **one model table** (this adapter's is `MODELS.md`) mapping
     the three capability tiers to concrete models, with an effort column where the
     runtime has a dial — it must be the adapter's **only** file naming models, so a
     model swap is a one-line change.
   - Give the adapter exactly **one [environment block]** holding all OS/shell/CLI
     concrete forms for the new environment, and point every binding at it.
   - Implement the **[guard]** rules listed in `workflow/README.md` in whatever pre-action
     hook the runtime offers (deterministic, fails open).
4. For any role the runtime cannot provide, apply `workflow/README.md` → "How an adapter
   degrades gracefully" and document the degradation in the adapter.
5. Sanity-check the split: a search of `workflow/**` must surface no mechanism names from
   your runtime (or this one) — only `[role]` references — and **no vendor or model
   names** anywhere outside the adapter's model table (grep for your model table's
   vocabulary across `.claude/`; exactly one file may match).
6. **Probe it before trusting it.** Instantiate every probe in
   `workflow/conformance-probes.md` for the new adapter (the adapter spec carries the
   instantiation table) and run them — a binding that reads correctly can still not work
   on a real driver (the active adapter's own probe run caught two live failures; see
   `adapters/claude-code-probes.md`). Adapter specs and probe records live under
   `.claude/adapters/` (the Codex CLI spec/stub is `adapters/codex-cli.md` with its
   dry-run walkthrough alongside).

The engine derives the GitHub repo slug from the `origin` remote, so it works on forks and
direct repos without edits. No absolute machine paths are baked in.
