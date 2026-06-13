---
name: retrospective
description: Back-test an escaped defect against the auditors (project specifics from .claude/PROJECT.md). Given a defect found on the base branch plus the commit/PR that introduced it, re-runs the acceptance/constitution/contract auditors READ-ONLY against that historical diff — exactly as the §7 gate would have — classifies the escape (WOULD-HAVE-CAUGHT / INCONSISTENT-CATCH / HUNT-RULE-GAP / INVARIANT-GAP) with file:line evidence, and proposes the resulting tightening (a reviewer-spec hunt rule or an invariant-checklist row) as a normal PR — never editing a rule directly. Use when the user says "retrospective", "back-test this defect", "run the retrospective on <commit/PR>", or when a defect/constitution violation is found on main. Per-incident, never a retroactive sweep; read-and-propose only — never merges, never edits reviewer specs/invariants/guards/the constitution outside the proposal PR.
---

# /retrospective — Claude Code binding

The workflow logic is runtime-neutral and lives in **`.claude/workflow/retrospective.md`** —
**read that file now and execute it.** It composes existing roles only (it introduces no new
binding-contract row); the mapping of its abstract **[roles]**:

| Neutral role | Claude Code mechanism |
|---|---|
| **[workflow]** (this one) | this skill; the incident inputs — the introducing **commit/PR reference** and the **defect description** — arrive in the invocation text (the explicit-context rule). When the introducing change is unknown, resolve it first with the discovered-work provenance search (`next-task.md` §5.5: `git log -S`/`-G`, `git blame`) and state an unresolved origin as such, never guessed |
| **[reviewer]** (the §3 auditor back-test — read-only, **report-only**) | the `spec-auditor` / `constitution-auditor` / `contract-auditor` subagents (`.claude/agents/`) dispatched via the Agent tool against the **§2 historical change**, materialized as a worktree so they read the tree *as it was then* (see "Reconstruct the historical tree" below) — own context, **no edit tools**. A **single report-only fan-out: no fix step, no re-dispatch loop** (unlike the §7 gate's converge-to-PASS loop — the retrospective classifies a *settled* diff, it does not repair it). Dispatch the **acceptance** reviewer with the introducing change's **task ID** (*unknown* when the change carried none); the **constitution** reviewer **always**; the **contract** reviewer only when the historical diff touched a provider interface, monetization, or the data model. Models per `.claude/MODELS.md` (the constitution reviewer **at-or-above the strong-tier row, never below** — see floor) |
| **[strong tier]** (the floor — §3, AC4) | resolved per `.claude/MODELS.md`; passed as the Agent tool's `model` parameter on **every** constitution-auditor dispatch, never inherited from the session |
| **[guard]** (enforces the floor — AC5) | the PreToolUse hook (`.claude/hooks/guard.sh`, **rule 5**) deterministically blocks any `constitution-auditor` dispatch whose `model` is absent or below the strong-tier row — **the same guarded path the §7 gate uses**, so the floor is enforced here, not merely asserted |
| **historical-tree reconstruction** (§2) | materialize the introducing change's **tree**, not just its diff: `git worktree add --detach <tmp> <introducing-commit>` (a single commit; a squash-merged PR → its squash commit on the base, or resolve to its head-ref commits), then dispatch every auditor **pointed at `<tmp>`**. Inside it they grade `git diff <parent>..<introducing-commit>` **and** read surrounding files from the historical tree — **never the live repo root** (the auditor specs read neighbouring files, which on the live checkout would be today's `main`; see note). `git worktree remove <tmp>` after. Read-only: a detached worktree + ranged `git diff` mutate no branch |
| **telemetry read** (Fact B — §4) | read the `gate-run` records at the profile's Telemetry path (`.claude/PROJECT.md` → "Paths") **read-only** — to learn whether a gate ran on this change; never written, and it changes no gate outcome, tier, or gate semantics (constitution P5) |
| **proposal PR** (§5 — HUNT-RULE-GAP / INVARIANT-GAP) | the standard issue → branch → §7 gate → PR flow **as bound in `.claude/skills/next-task/SKILL.md`** (§3–§8, [orchestrated run] gate included) — the drafted reviewer-spec / invariant-row edit is itself gated, the constitution reviewer scrutinizing the rule change at its strong floor. **The owner merges to apply** — the retrospective stops at the PR |
| **known-gap filing** (§5 — WOULD-HAVE-CAUGHT / INCONSISTENT-CATCH) | `gh issue create` (multi-line body via the [environment block]) under the discovered-work discipline (`next-task.md` §5.5), so triage resurfaces it until closed |
| **[bulk-read offload]** | the `Explore` subagent (spawn on the [cheap tier] per `.claude/MODELS.md`) for a large historical diff or a long telemetry stream |
| **[comment marker]** | the footer line defined in `.claude/skills/next-task/SKILL.md` → "The [comment marker] concrete form" (the single copy) — on every `gh issue comment` / `gh pr comment` body this workflow posts |
| **[environment block]** | `.claude/skills/next-task/SKILL.md` → "This environment's concrete forms" (the single copy — multi-line bodies via a UTF-8 temp file + `--body-file`, `gh` PATH fallback) |
| **[headless run]** | `claude -p "/retrospective <commit-or-PR-ref> <defect-description>"` |

**Reconstruct the historical *tree* before dispatching the auditors — not just the diff.**
The auditor specs do two things: grade `git diff main..HEAD`, **and read the surrounding
files of any path the diff touches** (a violation often hides in an unchanged neighbour the
diff now calls — `reviewers/constitution-auditor.md`, `contract-auditor.md`,
`spec-auditor.md` all say so). Passing only a diff range fixes the first but not the second:
the auditor would still read those neighbours from the **live checkout**, mixing today's
`main` into a back-test of an old change — so a file refactored since would yield wrong line
numbers, missed violations, or invented ones. Materialize the historical state instead:
`git worktree add --detach <tmp> <introducing-commit>` gives a throwaway checkout whose tree
is the change *as written then*; dispatch the auditors **pointed at `<tmp>`**, instruct them
to grade `git diff <parent>..<introducing-commit>` and to read surrounding context **only
within `<tmp>`, never the live repo root** (their default `git diff main..HEAD` and a live
read would both grade the wrong tree). For a squash-merged PR the introducing commit is its
squash commit on the base (tree = the change applied to its merge base); for a regular commit
it is the commit itself. `git worktree remove <tmp>` when done. This stays read-only — a
detached worktree and a ranged `git diff` mutate no branch and no tracked state.

**Write posture per the workflow doc (`retrospective.md` → "Write posture"):**

- The auditor dispatch is **read-only** (no file-mutation tools, by the [reviewer]
  constraint) and **report-only** — no fix step; the retrospective classifies a settled diff,
  it never repairs it.
- It **never edits a rule directly.** Reviewer specs, the invariant checklist, the guards, and
  `memory/constitution.md` are exactly the files the constitution's
  no-silent-self-modification principle (P4) protects: every tightening this workflow yields
  travels the standard issue → branch → §7 gate → PR flow, and **the owner merges to apply**. A
  run that writes any of those files outside that PR flow is a violation.
- **Telemetry is read as evidence, never as a control input** (P5): reading the `gate-run`
  records informs a human-reviewed proposal and gains no control authority — it changes no gate
  outcome, no tier, no gate semantics.
- It changes **no §7 gate semantics** — it is a per-incident back-test, never a second gate and
  never a retroactive sweep.
