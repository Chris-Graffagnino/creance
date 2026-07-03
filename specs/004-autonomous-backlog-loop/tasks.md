# Tasks — Autonomous Backlog Loop

> Task-line format: `- [ ] T<nnn> [<tier>] <description> (US<#>)`. The
> `[frontier]`/`[strong]`/`[cheap]` tag is the task's minimum capability tier, resolved
> through `.claude/MODELS.md` at run time. Task-ID block for this spec: **004 = T9xx**
> (unique across all live tasks files).

## Phase 1 — The neutral loop model

- [x] T901 [strong] Specify the runtime-neutral `[backlog-loop]` in
      `.claude/workflow/**`: a bounded iteration model whose each iteration is a complete,
      unmodified `next-task` cycle (`[live-state reconciliation]` → implement in the
      `[isolated workspace]` → §7 gate → PASS→PR / FAIL→discard), composing existing roles
      only and adding no new gate semantics (round limits, veto authority, tier floors,
      reviewer roster unchanged). Capabilities as bracketed [roles] only; `workflow/**`
      neutrality scan green. Reachable **only** via the existing `[autonomy activation]`
      check (US1)

## Phase 2 — Deterministic bounds & safety proofs

- [ ] T902 [strong] Deterministic stop-condition enforcement + activation-gating: max-N
      (N resolved from configuration/invocation, never hardcoded), no-unblocked-candidate,
      same-task-fails-gate-twice, and any lifecycle/`[autonomy activation]` failing closed
      — evaluated only *between* iterations, never mid-task. Ships paired tests: run halts
      at N (cannot exceed) **and** completes M < N eligible tasks without stopping early;
      plus the activation-bypass-FAILs and opt-in-absent-resolves-to-review cases. Any
      constraint on the loop's control flow that is guard-enforced ships its matching
      `guard.test.sh` case (P2) (US1)
- [ ] T903 [strong] No-merge / no-base-write falsification proof across iterations:
      extend the T613 proof to the multi-iteration case — a test proving that across N
      iterations no merge and no base-branch write occurs and that an un-gated change from
      any iteration is unreachable from base; promotion reuses the existing T612 PR path
      unchanged (merge stays session-explicit). Wired into `verify` (US1)

## Phase 3 — Observe-only reporting & live proof

- [ ] T904 [strong] Run report as observe-only telemetry: one line per iteration (task
      ID, gate verdict, PR ref or discard) written to the out-of-repo triage-inbox channel
      (existing triage default — no new path convention); `/triage` surfaces the batch. A
      deterministic P5 fence proves no gate-outcome / model-tier / task-selection path
      reads the run report or iteration counters, **paired** with a control proving the
      reporting path does resolve them (non-vacuous). Write-failure is silent-to-the-run;
      partial run is not a baseline (US1)
- [ ] T905 [cheap] Adapter binding for the `[backlog-loop]` (the `[scheduled run]` /
      loop-wrapper mechanism) + conformance probe: one real multi-task unattended run on
      the live adapter, recorded with dated fingerprints (the T303/P-IW pattern) including
      the observed stop condition, in the adapter probe-results table. Blocked by
      T901–T904 (US1)

## Criterion ownership (multi-task user stories)

| Criterion | Owning task |
|---|---|
| US1.AC1 | T901 |
| US1.AC2 | T902 |
| US1.AC3 | T902 |
| US1.AC4 | T903 |
| US1.AC5 | T904 |
| US1.AC6 | T904 |
| US1.AC7 | T905 |

## Blocked / owner-only tasks (never auto-start — surface them instead)

- none. (Autonomous execution of these tasks still requires the profile
  `autonomy-opt-in: enabled` or explicit in-session authorization; absent that, they run
  in review mode like all other work.)
