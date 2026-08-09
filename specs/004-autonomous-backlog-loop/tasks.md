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

## Phase 5 — Fan-out child containment & bounded hooks (issue #324; bug)

> An **ungracefully** stopped loop session (SIGKILL / app crash / force-quit) strands the
> parallel tool shells its auditor/gate rounds spawned: they reparent to PID 1 and, being
> mid busy-loop, burn CPU indefinitely. One observed incident held ~24 orphaned shells plus
> one runaway metric hook alive for 6h+ at load ~60 with 0% idle. This is the orphaned
> **process** axis and is disjoint from T906, which reaps orphaned **worktrees/branches** —
> but the two rewrite the same control paths, so T907 is sequenced behind it. Surfaced by
> the owner as unmapped tracker work and converted via intake (`workflow/intake.md`). It is
> a bug — no new `US#`; the acceptance reviewer grades it against the done-when criteria
> carried in issue #324's intake cross-link comment, exactly as it would a `US#`.

- [ ] T907 [strong] Contain and reap the loop's fan-out child processes, and bound the one
      hook that can spin on its own (`#324`): (a) `.claude/hooks/effective-fix-rate.sh:111-153`
      pipes the whole telemetry stream through `jq -s` (slurp-all) with **no wall-clock bound
      and no input-size cap**, so a large or pathological stream churns CPU without
      self-limiting — add both, and give the bound its **own distinct terminal state**: a run
      that hits the time bound or the size cap must be reported as such, never collapsed into
      the documented `no-data` state (`effective-fix-rate.sh:42,50,94-107` — only an absent or
      empty stream is `no-data`; a broken source already fails loud), and the observe-only
      posture (P5) is unchanged — it still writes nothing and still returns nothing any gate,
      tier, guard, or selection path reads. (b) `.claude/settings.json:64-88` wires `guard.sh`
      on `PreToolUse` (`Edit|Write|MultiEdit|NotebookEdit|Bash|PowerShell|Agent|Task`) and
      `PostToolUse` with **no explicit `timeout`** — declare one, and because that is a change
      to guard *wiring* it ships its matching `guard.test.sh` case in the same diff (P2's
      settings.json wiring assertion). Establish the timeout's **fail direction** by
      observation, not assumption: a `PreToolUse` guard that times out must not let the tool
      call proceed ungated, so record the runtime's actual behavior as a dated adapter probe
      (the T303/P-IW pattern) and, if it fails *open*, say so and carry the residual risk
      explicitly rather than shipping a silently dead guard. (c) `.claude/hooks/backlog-loop.sh`
      and `backlog-loop-iterate.sh` contain **no** `trap`, `kill`, or process-group handling
      (verified: zero hits), and `docs/launchers/backlog-loop.sh:58-64` traps only `EXIT` to
      append its run log — it never signals children — so launch each iteration's fan-out in
      its own **process group** and tear the whole group down on launcher exit, giving a
      graceful stop a single "kill the round" handle. (d) `SIGKILL` cannot be trapped, so add
      the backstop: a **reaper**, runnable as a loop pre-flight, that terminates orphaned
      (reparented) harness-owned spinners. Its kill predicate is **provenance-gated** exactly
      as the isolation lifecycle's delete paths are (`isolated-workspace.sh`, #114) — a
      command-string match like `shell-snapshots` alone would also kill a *live* concurrent
      session's shells and is rejected. **Portability is load-bearing here, not incidental:**
      `timeout`, `gtimeout`, `setsid`, and `flock` are all **absent** on the environment that
      hit this bug (verified), so (a)/(c)/(d) must be built from primitives that exist there
      and stay `shell-lint.sh`-clean with no new diagnostic. Ships two-sided tests, each
      flipping when its fix is reverted: a pathological stream terminates within the bound
      with the distinct state **while** a normal stream still yields byte-identical
      `rate`/`no-fix-rounds`/`no-data` output; an over-cap and an under-cap stream take
      different paths; every wired `guard.sh` entry declares a timeout and removing the field
      fails the wiring case; killing the launcher leaves zero surviving descendants **while**
      an ordinary run still completes every iteration un-killed; and a planted orphan matching
      the ownership predicate is reaped **while** a live session's shell and a foreign PID-1
      process that merely matches the command pattern are left untouched. Blocked by T906
      (it rewrites the same `backlog-loop.sh` control path and adds the sibling startup sweep;
      landing these out of order guarantees a conflicting rewrite and a second competing sweep,
      P2) (#324; bug — done-when on issue) — strong: spans the guard wiring, the autonomy
      launcher's process control, and a new provenance-gated kill path, each under a
      constitution invariant (P2/P3/P5) [#324]

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
