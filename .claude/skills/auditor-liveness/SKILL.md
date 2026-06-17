---
name: auditor-liveness
description: Run the standing auditor-liveness corpus (project specifics from .claude/PROJECT.md). Re-confirms each judgment auditor (acceptance / constitution / contract) still catches its planted-violation fixtures and still passes its clean fixtures, after a reviewer-spec edit or model drift — the model-driven analog of guard.test.sh, promoted from the one-time P-RV probe. Dispatches the auditors READ-ONLY and report-only against materialized plants, compares each verdict to the corpus's expected verdict, and records an OBSERVE-ONLY outcome that never feeds gate outcomes, tier assignment, or gate semantics (P5). Use when the user says "auditor liveness", "run the auditor corpus", "re-confirm the auditors", when triage flags CORPUS-STALE, or on the weekly schedule. Read-and-report only — never edits a reviewer spec, never gates, never merges.
---

# /auditor-liveness — Claude Code binding

The workflow logic is runtime-neutral and lives in **`.claude/workflow/auditor-liveness.md`**
— **read that file now and execute it.** The fixtures it runs are
`.claude/workflow/reviewers/auditor-liveness-corpus.md`. It **composes existing roles only**
(it introduces no new binding-contract row); the mapping of its abstract **[roles]**:

| Neutral role | Claude Code mechanism |
|---|---|
| **[workflow]** (this one) | this skill; a run takes no required argument — it runs the whole corpus and records a **`full`** results row. An optional fixture-id (e.g. `AL-CON-FAIL-01`) in the invocation text scopes the run to one fixture (the explicit-context rule) — a diagnostic that records a **`partial:<fixture-id>`** row which **never serves as the CORPUS-STALE baseline** (a subset run has not re-confirmed every auditor — `workflow/auditor-liveness.md` → "Re-run policy") |
| **[reviewer]** (the corpus run — read-only, **report-only**) | the `spec-auditor` / `constitution-auditor` / `contract-auditor` subagents (`.claude/agents/`) dispatched via the Agent tool against each **materialized fixture plant** — own context, **no edit tools**. A **single report-only fan-out per fixture: no fix step, no re-dispatch loop** (unlike the §7 gate's converge-to-PASS loop — the corpus *measures* an auditor, it does not repair a diff). Models per `.claude/MODELS.md` (the constitution reviewer **at-or-above the strong-tier row, never below** — see floor) |
| **[strong tier]** (the floor on the constitution dispatch) | resolved per `.claude/MODELS.md`; passed as the Agent tool's `model` parameter on **every** constitution-auditor dispatch, never inherited from the session |
| **[guard]** (enforces the floor) | the PreToolUse hook (`.claude/hooks/guard.sh`, **rule 5**) deterministically blocks any `constitution-auditor` dispatch whose `model` is absent or below the strong-tier row — **the same guarded path the §7 gate and the retrospective use**, so the floor is enforced here, not merely asserted |
| **fixture materialization** (the run, step 1) | for each fixture, `git worktree add --detach <tmp> <base>` then plant the fixture's scenario in `<tmp>` (the same planting the `P-RV` / `P-EV` probes use, in the throwaway-worktree path the retrospective uses to grade a tree as-it-was); dispatch the fixture's auditor **pointed at `<tmp>`**, instruct it to grade `git diff <base>..HEAD` and read surrounding context **only within `<tmp>`**; `git worktree remove <tmp>` after. Read-only — a detached worktree + a planted commit on it mutate no tracked branch, and the run leaves the repo as it found it |
| **verdict comparison** (the run, step 3) | compare the auditor's returned verdict to the fixture's **Expected** cell in `auditor-liveness-corpus.md` (and, for a FAIL fixture, that the **evidence anchor** was named): match ⇒ `PASS`, mismatch ⇒ `MISMATCH`. No tool acts on the result — it is recorded and surfaced only |
| **observe-only results channel** | the **"Corpus-run results"** table in this file (below) — one appended dated row per run: date, **run scope** (`full` or `partial:<fixture-id>`), driver model, reviewer-spec fingerprint, and each fixture's `PASS`/`MISMATCH`. Append-only; **never** read by any gate, tier resolver, or gate-semantic. The triage **CORPUS-STALE** check reads the most recent **`full`-scope** row's fingerprint + date as its baseline (a `partial` row is an audit-trail diagnostic, never a freshness baseline) |
| **[headless run]** + the **≥ weekly schedule** | `claude -p "/auditor-liveness"` on the same scheduler substrate the read-only triage heartbeat uses (the launcher contract, `workflow/triage.md` §6). The named **minimum cadence is weekly**; the on-reviewer-spec-change trigger is the deterministic CORPUS-STALE flag the daily heartbeat surfaces |
| **[bulk-read offload]** | the `Explore` subagent (spawn on the [cheap tier] per `.claude/MODELS.md`) for a large materialized fixture |
| **[comment marker]** | the footer line defined in `.claude/skills/next-task/SKILL.md` → "The [comment marker] concrete form" — on any `gh issue comment` / `gh pr comment` body a run posts (e.g. when proposing a new fixture via PR) |
| **[environment block]** | `.claude/skills/next-task/SKILL.md` → "This environment's concrete forms" (the single copy — `gh` PATH fallback, UTF-8 temp-file bodies) |

## The reviewer-spec fingerprint (the deterministic on-reviewer-spec-change detector)

`auditor-liveness.md` → "Re-run policy" defers the concrete hash recipe to the adapter. It is
a single content hash over the **auditor specs the reviewers load** — the three `*-auditor.md`
specs plus the evasion register they consult at dispatch — reproducible from a clean checkout
(the same `git hash-object` shape the guard-machinery fingerprint uses,
`adapters/claude-code-probes.md` → "Probe-run fingerprint"):

```
git hash-object \
  .claude/workflow/reviewers/spec-auditor.md \
  .claude/workflow/reviewers/constitution-auditor.md \
  .claude/workflow/reviewers/contract-auditor.md \
  .claude/workflow/reviewers/evasion-register.md \
  | git hash-object --stdin
```

Recorded in each results row's **Reviewer-spec fingerprint** cell as `specs=<sha7>`. The
files are **listed explicitly, never globbed** — so adding the corpus manifest or another
non-spec file under `reviewers/` does not perturb the fingerprint, and a real auditor-spec
edit always does. Triage recomputes this same recipe (it reuses it, never re-derives it) and
flags **CORPUS-STALE** when the current value differs from the most recent **`full`-scope** row
below — it skips `partial:<fixture-id>` rows, since a scoped diagnostic has not re-confirmed
every auditor and so never refreshes the baseline.

## Observe-only — the hard boundary (constitution P5)

The results table is an **evaluation record**: append-only observation. It **never** feeds a
gate outcome, a model-tier assignment, or any gate semantic (round limits, veto authority,
tier floors). A `MISMATCH` surfaces for a human to act on through the ordinary task flow — it
never auto-edits a reviewer spec, never re-dispatches the gate, never moves a tier. This is
the same fence the profile's telemetry/evaluation invariant draws (`.claude/PROJECT.md` →
"Invariant checklist": a change that lets evaluation records influence gate outcomes,
model-tier assignment, or gate semantics is a FAIL).

## Relationship to `guard.test.sh` (the discipline this generalizes)

`guard.test.sh` proves the **deterministic** `[guard]` live on **every** gate run, as a hard
required check. This corpus is its **model-driven** analog for the judgment auditors: because
an auditor's verdict is nondeterministic, the corpus cannot be a hard merge gate (a flaky
verdict would block honest work), so it runs **report-only** on a schedule and on every
reviewer-spec change instead. `P-RV` is its origin — the one-time adoption probe made
standing and broadened to a known-bad/known-good pair per auditor. The neutral
`auditor-liveness.md` carries the full relationship table.

## Corpus-run results (observe-only — append one dated row per run)

Each `/auditor-liveness` run appends one row. **Scope** is `full` (the whole corpus) or
`partial:<fixture-id>` (a scoped diagnostic). **Only `full` rows are CORPUS-STALE baselines** —
a `partial` row records the diagnostic for the audit trail but never refreshes the freshness
baseline, because a subset run has not re-confirmed every auditor.

| Date | Scope | Driver model | Reviewer-spec fingerprint | Per-fixture outcome |
|---|---|---|---|---|
| _(append one row per `/auditor-liveness` run — date, scope (`full` / `partial:<fixture-id>`), the driver model/version, the `specs=<sha7>` fingerprint, and each fixture's PASS/MISMATCH — only `full` rows seed CORPUS-STALE)_ | | | | |
