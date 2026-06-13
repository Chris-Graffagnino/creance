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
| **[reviewer]** (the §3 auditor back-test — read-only, **report-only**) | the `spec-auditor` / `constitution-auditor` / `contract-auditor` subagents (`.claude/agents/`) dispatched via the Agent tool against the **§2 historical diff** (see "Reconstruct the historical diff" below) — own context, **no edit tools**. A **single report-only fan-out: no fix step, no re-dispatch loop** (unlike the §7 gate's converge-to-PASS loop — the retrospective classifies a *settled* diff, it does not repair it). Dispatch the **acceptance** reviewer with the introducing change's **task ID** (*unknown* when the change carried none); the **constitution** reviewer **always**; the **contract** reviewer only when the historical diff touched a provider interface, monetization, or the data model. Models per `.claude/MODELS.md` (the constitution reviewer **at-or-above the strong-tier row, never below** — see floor) |
| **[strong tier]** (the floor — §3, AC4) | resolved per `.claude/MODELS.md`; passed as the Agent tool's `model` parameter on **every** constitution-auditor dispatch, never inherited from the session |
| **[guard]** (enforces the floor — AC5) | the PreToolUse hook (`.claude/hooks/guard.sh`, **rule 5**) deterministically blocks any `constitution-auditor` dispatch whose `model` is absent or below the strong-tier row — **the same guarded path the §7 gate uses**, so the floor is enforced here, not merely asserted |
| **historical-diff reconstruction** (§2) | `git diff <parent>..<introducing-commit>` — a single commit against its predecessor; a squash-merged PR resolves to its head-ref commits, diffed against its merge base. Hand each auditor this explicit range in its dispatch prompt; their default `git diff main..HEAD` would grade the **live base branch**, not the change as written then (see note) |
| **telemetry read** (Fact B — §4) | read the `gate-run` records at the profile's Telemetry path (`.claude/PROJECT.md` → "Paths") **read-only** — to learn whether a gate ran on this change; never written, and it changes no gate outcome, tier, or gate semantics (constitution P5) |
| **proposal PR** (§5 — HUNT-RULE-GAP / INVARIANT-GAP) | the standard issue → branch → §7 gate → PR flow **as bound in `.claude/skills/next-task/SKILL.md`** (§3–§8, [orchestrated run] gate included) — the drafted reviewer-spec / invariant-row edit is itself gated, the constitution reviewer scrutinizing the rule change at its strong floor. **The owner merges to apply** — the retrospective stops at the PR |
| **known-gap filing** (§5 — WOULD-HAVE-CAUGHT / INCONSISTENT-CATCH) | `gh issue create` (multi-line body via the [environment block]) under the discovered-work discipline (`next-task.md` §5.5), so triage resurfaces it until closed |
| **[bulk-read offload]** | the `Explore` subagent (spawn on the [cheap tier] per `.claude/MODELS.md`) for a large historical diff or a long telemetry stream |
| **[comment marker]** | the footer line defined in `.claude/skills/next-task/SKILL.md` → "The [comment marker] concrete form" (the single copy) — on every `gh issue comment` / `gh pr comment` body this workflow posts |
| **[environment block]** | `.claude/skills/next-task/SKILL.md` → "This environment's concrete forms" (the single copy — multi-line bodies via a UTF-8 temp file + `--body-file`, `gh` PATH fallback) |
| **[headless run]** | `claude -p "/retrospective <commit-or-PR-ref> <defect-description>"` |

**Reconstruct the historical diff before dispatching the auditors.** The auditor subagents
grade `git diff main..HEAD` by default (their specs run it). The retrospective audits a
**different surface**: the introducing change against its parent — *the same diff the gate
would have graded when that change was made* — not the current base branch
(`retrospective.md` §2). So name that range explicitly in each auditor's dispatch prompt:
`<parent>..<introducing-commit>` for a single commit; a squash-merged PR's
`<merge-base>..<head>` (resolve the PR to its head-ref commits). The auditors' grading logic —
the rubric, the invariant hunt, the `file:line` evidence — is unchanged; only the **input
range** is the historical one. Without this they grade the live `main` and the back-test is
meaningless. This stays read-only: `git diff` over a range mutates nothing.

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
