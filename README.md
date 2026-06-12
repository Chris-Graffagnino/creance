# Creance

**A tethered-autonomy harness for coding agents.**

A *creance* is the light line a falconer uses to fly a hawk that has not yet earned free
flight. That is this harness's whole philosophy in one word: treat an autonomous coding
agent like a CI pipeline you don't trust — give it real autonomy, on a tether. Every run
starts identically, the dangerous actions are deterministically impossible rather than
discouraged, a *different* context grades the work, and every "done" claim is verified
against an artifact rather than the model's say-so.

## What you get

A complete, probe-tested workflow engine for running engineering work as
**one task → one issue → one branch → one PR**, with an adversarial **maker ≠ checker**
review gate. Three layers, each independently swappable:

| Layer | Lives in | You change it when… |
|---|---|---|
| **Methodology** — runtime-neutral engine logic, written against abstract `[roles]` | `.claude/workflow/**` | never (see the do-not-break list) |
| **Adapter** — maps each role to a concrete mechanism (shipped: Claude Code; spec'd: Codex CLI) | `.claude/` skills, agents, hooks, `settings.json`, `MODELS.md` | you port to a new runtime |
| **Profile** — every project-specific fact | `.claude/PROJECT.md`, `memory/constitution.md`, `specs/` | every new project (that's the template part) |

Concretely, that includes:

- **`/next-task`** — the full-ceremony per-task loop: pick the task, open the issue, cut
  the branch, implement with tests, verify, run an adversarial multi-reviewer gate, stop
  at PR.
- **Three read-only auditor subagents** (spec / constitution / contract) dispatched in
  separate contexts, so the agent that wrote the code is never the one grading it.
- **A deterministic PreToolUse guard** (`hooks/guard.sh`) that vetoes editing on the base
  branch, bulk staging, commits/pushes to base, and under-tier dispatch of the
  constitution reviewer — before execution, with regression tests in CI.
- **`/triage`** — a read-only daily heartbeat with a dead-man-switch launcher contract
  (templates in `docs/launchers/`).
- **A model table** (`.claude/MODELS.md`) — the only file naming models; capability tiers
  everywhere else, so a model swap is a one-line edit.
- **Conformance probes** — one verifiable probe per role, because a binding that reads
  correctly can still be dead on a live driver (that exact failure was caught twice in
  this harness's source project).

## Quickstart

### Prerequisites

- **`git`** — the engine's branch/issue/PR discipline assumes it.
- **`gh`** (GitHub CLI), authenticated — issues, PRs, and review status all go through it.
- **`bash` on PATH — including on Windows (Git Bash).** The guard hook is wired as
  `bash "$CLAUDE_PROJECT_DIR/.claude/hooks/guard.sh"`; on a machine without `bash` the
  guard is **silently dead** (the exact failure class in `DESIGN-NOTES.md` §"the guard
  was silently dead"). CI's wiring check runs on Linux and cannot catch this — run the
  guard probes (P-GD) on each workstation.
- **`rg`** (ripgrep) — bundled with Claude Code; not guaranteed on other runtimes, where
  the verification greps need it installed separately.

### Steps

1. **Use this template** (GitHub) or clone it.
2. `cp .claude/PROJECT.template.md .claude/PROJECT.md` and fill every `<...>` — it is the
   single source of project facts the engine reads.
3. Write your `memory/constitution.md` (start from `memory/constitution.template.md`) —
   the project's non-negotiable principles. The constitution auditor enforces it as law.
4. Fill the `specs/` tree: copy `specs/000-template/` to `specs/001-<feature>/`, rename
   `spec.template.md` → `spec.md` and `tasks.template.md` → `tasks.md`, then fill in a
   spec with `US#` acceptance criteria, a task backlog, and provider contracts if you
   have swappable seams. Keep the `.template.md` suffix on the originals — it keeps the
   skeleton out of the engine's `specs/*/tasks.md` fallback glob, so its placeholder
   tasks are never selectable by `/next-task`.
5. Adapt the placeholders in `AGENTS.md` and add your toolchain's commands to
   `.claude/settings.json` → `permissions.allow` (e.g. `Bash(npm test:*)`) and to
   `.github/workflows/ci.yml`.
6. Rewrite the **[environment block]** in `.claude/skills/next-task/SKILL.md` for your
   machine (the shipped one is the Windows PowerShell 5.1 worked example).
7. **Probe before you trust:** run the conformance probes
   (`.claude/adapters/claude-code-probes.md`) and the verification greps in
   `.claude/EXTRACTION.md` §5. Do not run the harness unattended until they pass.

## Reading order

- [`.claude/README.md`](.claude/README.md) — the adapter layer and how to port to a new
  runtime.
- [`.claude/workflow/README.md`](.claude/workflow/README.md) — the binding contract (the
  abstract roles every adapter must provide).
- [`.claude/DESIGN-NOTES.md`](.claude/DESIGN-NOTES.md) — *why* the harness is shaped this
  way; read it before deleting anything that looks like ceremony.
- [`.claude/EXTRACTION.md`](.claude/EXTRACTION.md) — how this template was cut from its
  source project, and the verification that the cut is clean.

## Provenance

Extracted from a production project (a privacy-first iOS app built owner-absent under
this workflow), where the harness ran real tasks, caught real constitution violations in
review, and had its probe suite catch two live adapter failures before they could bite.
The scar tissue is documented, not sanded off.

## License

[MIT](LICENSE)
