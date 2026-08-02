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

- [x] T902 [strong] Deterministic stop-condition enforcement + activation-gating: max-N
      (N resolved from configuration/invocation, never hardcoded), no-unblocked-candidate,
      same-task-fails-gate-twice, and any lifecycle/`[autonomy activation]` failing closed
      — evaluated only *between* iterations, never mid-task. Ships paired tests: run halts
      at N (cannot exceed) **and** completes M < N eligible tasks without stopping early;
      plus the activation-bypass-FAILs and opt-in-absent-resolves-to-review cases. Any
      constraint on the loop's control flow that is guard-enforced ships its matching
      `guard.test.sh` case (P2) (US1)
- [x] T903 [strong] No-merge / no-base-write falsification proof across iterations:
      extend the T613 proof to the multi-iteration case — a test proving that across N
      iterations no merge and no base-branch write occurs and that an un-gated change from
      any iteration is unreachable from base; promotion reuses the existing T612 PR path
      unchanged (merge stays session-explicit). Wired into `verify` (US1)

## Phase 3 — Observe-only reporting & live proof

- [x] T904 [strong] Run report as observe-only telemetry: one line per iteration (task
      ID, gate verdict, PR ref or discard) written to the out-of-repo triage-inbox channel
      (existing triage default — no new path convention); `/triage` surfaces the batch. A
      deterministic P5 fence proves no gate-outcome / model-tier / task-selection path
      reads the run report or iteration counters, **paired** with a control proving the
      reporting path does resolve them (non-vacuous). Write-failure is silent-to-the-run;
      partial run is not a baseline (US1)
- [x] T905 [cheap] Adapter binding for the `[backlog-loop]` (the `[scheduled run]` /
      loop-wrapper mechanism) + conformance probe: one real multi-task unattended run on
      the live adapter, recorded with dated fingerprints (the T303/P-IW pattern) including
      the observed stop condition, in the adapter probe-results table. Blocked by
      T901–T904 (US1)

## Phase 4 — Loop concurrency & crash recovery (issue #267; bug)

> Two fail-safe operational-robustness gaps in the autonomous loop, surfaced by triage as
> unmapped tracker work and converted via intake (`workflow/intake.md`). Both fail **safe**
> (leaked/duplicated work, never base-branch corruption — the isolation delete-guards stay
> provenance-marker gated), so they are latent over long unattended runs. It is a bug — no
> new `US#`; the acceptance reviewer grades it against the done-when criteria carried in
> issue #267's intake cross-link comment, exactly as it would a `US#`.

- [ ] T906 [strong] Add a **concurrency lock** and a **crash-recovery startup sweep** to the
      autonomous loop (`#267`): (a) `.claude/hooks/backlog-loop.sh` currently has no lock or
      `trap` (verified: no `flock`/lockdir/`trap`), so two overlapping runs can both select the
      same task with only an incidental `git worktree add -b` name collision as an accidental
      mutex — acquire an **atomic** lock at loop start (e.g. a `mkdir` lockdir or `flock`) and
      release it via a `trap` on exit/signal, so a second concurrent loop while one holds the
      lock does not start a second selection/iteration (it declines or waits, deterministically);
      (b) `.claude/hooks/isolated-workspace.sh` reaps a workspace only on a caught in-process
      `fail`, never on a `SIGKILL`, and nothing reaps orphans at startup — add a **startup sweep**
      that cross-references `git worktree list --porcelain` against the `.creance-ws-owner`
      provenance markers and prunes ONLY dead-session, marker-owned orphans, leaving any live
      workspace and any non-lifecycle/marker-less worktree untouched. Any new delete path stays
      **provenance-marker gated** and falsification-tested exactly as the existing lifecycle is
      (`isolated-workspace.test.sh`, `isolation-falsification.test.sh`, #111/#114/#131), and the
      no-base-write / no-merge isolation invariants and `backlog-loop-fence.sh` / `autonomy-mode`
      checks stay green. Ships two-sided tests: two concurrent loop starts → exactly one proceeds
      and a normal single run still acquires+releases (no deadlock); a simulated mid-iteration kill
      → the orphaned worktree/marker/branch is reaped while a live workspace and a foreign
      marker-less worktree are left untouched (reverting either fix flips its test)
      (#267; bug — done-when on issue) — strong: closes two fail-safe robustness gaps in the
      autonomy surface without weakening the isolation delete-guards (constitution P2/P3/P4)

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
