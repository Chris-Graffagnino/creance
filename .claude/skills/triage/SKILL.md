---
name: triage
description: Morning read-only triage heartbeat for the build (project specifics from .claude/PROJECT.md). Reads the tasks file, git history, and GitHub issues/PRs, then writes a fresh state snapshot to the out-of-repo inbox. Surfaces the next unblocked task, stale checkboxes, open PRs needing review, blocked/owner items, and upcoming constitution risks. Use when the user says "triage", "morning triage", "what's the state of the build", or when fired on a schedule. NEVER edits code, opens issues/PRs, or commits.
---

# /triage — Claude Code binding

The workflow logic is runtime-neutral and lives in **`.claude/workflow/triage.md`** —
**read that file now and execute it.** Mapping of its abstract **[roles]**:

| Neutral role | Claude Code mechanism |
|---|---|
| **[workflow]** (next-task) | the `/next-task` skill the human runs later |
| **[headless run]** | `claude -p "/triage"` (the scheduled heartbeat) |
| **[environment block]** | `.claude/skills/next-task/SKILL.md` → "This environment's concrete forms" (the single copy of the OS/shell/CLI gotchas — e.g. the `gh` PATH fallback) |
| inbox write | the `Write` tool (out-of-repo path; allowed on `main` because it's outside the repo root) |

This procedure is **read-only on the repo**: no `Edit`/`Write`/`MultiEdit` under the repo
root, no `git add/commit/push`, no `gh issue/pr create`. The PreToolUse guard
(`.claude/hooks/guard.sh`) is the deterministic backstop.

## Verification-machinery freshness — concrete instantiation (`triage.md` §1.7 / §2)

`triage.md`'s **PROBES-STALE** check needs two adapter facts the neutral doc defers:

- **Recompute the current `[guard]`-machinery fingerprint** using the recipe defined **once**
  in **`.claude/adapters/claude-code-probes.md` → "Probe-run fingerprint"** (the guard-script
  content hash + the matcher-only hook-wiring hash), rendered `guard=<sha7> wiring=<sha7>`.
  Reuse that recipe — never re-derive it here — so a future change to *what the fingerprint
  covers* stays a one-place edit and the comparison hashes exactly what the probe runs hashed.
  Both halves are content hashes: recomputing is **read-only**, no repo write.
- **The recorded baseline** is the **most recent** non-placeholder row of that same file's
  **"## Probe results"** table: its **Fingerprint** cell is the value to compare against, and
  its date is the age source. No non-placeholder row ⇒ the neutral "no probe run recorded yet"
  state.

Equal ⇒ machinery current; different ⇒ **PROBES-STALE** (report the last run's age either way).
The **GUARD-SILENT** check needs no extra adapter fact — it reads the telemetry stream
(profile → "Paths" → Telemetry, the source `triage.md` §1.6 already reads) and tells `gate-run`
from `[guard]` `evaluation` records by the neutral `record` field (`workflow/telemetry.md`).

`triage.md`'s **CORPUS-STALE** check (auditor-liveness corpus currency) needs the auditor
analog of the two PROBES-STALE facts:

- **Recompute the current reviewer-spec fingerprint** using the recipe defined **once** in
  **`.claude/skills/auditor-liveness/SKILL.md` → "The reviewer-spec fingerprint"** (the
  `git hash-object` over the three `*-auditor.md` specs + the evasion register, rendered
  `specs=<sha7>`). Reuse that recipe — never re-derive it here — so what the fingerprint
  covers stays a one-place edit. It is a content hash: recomputing is **read-only**.
- **The recorded baseline** is the most recent non-placeholder **`full`-scope** row of that
  same file's **"## Corpus-run results"** table — skip `partial:<fixture-id>` rows, since a
  scoped single-fixture diagnostic has not re-confirmed every auditor and so never serves as
  the freshness baseline (`workflow/auditor-liveness.md` → "Re-run policy"). Its
  **Reviewer-spec fingerprint** cell is the value to compare against, and its date is the age
  source. No non-placeholder `full` row ⇒ the neutral "no corpus run recorded yet" state.

Equal ⇒ auditors confirmed-live as of that run; different ⇒ **CORPUS-STALE** (report the last
run's age either way). All three checks mutate nothing, honoring the read-only-on-the-repo
contract above.

## Maker-eval surfacing — concrete instantiation (`triage.md` §1.8 / §2)

`triage.md`'s **"Maker eval"** section needs the adapter facts the neutral doc defers — where
the records live, how to recompute the current maker-behavior fingerprint, and the record
fields the differential reads. All reads here are **read-only** (honoring the contract above);
triage **never** runs the eval or writes a record.

- **The records + the packet link.** The channel is the profile → "Paths" → **Maker-eval
  records** (out-of-repo, beside the telemetry stream — the same path
  `.claude/hooks/maker-eval-emit.sh` resolves). Read `<channel>/records.jsonl` — one append-only
  record per (corpus task × maker tier) per run, each carrying `run_id`, `task_id`, `maker_tier`,
  the `fingerprint` `{maker_behavior, judge_identity, eval_instrument}` object, the per-dimension
  `dimensions` verdicts (each with its `lifecycle`), the `overall` verdict, and a relative `packet`
  path. A flagged regression's packet link is that `packet` field, which resolves only **inside** the
  channel (the US2.AC3 fence, T804) — render it as the path, not a repo link.
- **The two runs to difference.** Group `records.jsonl` by `run_id`; a run is **complete** iff
  every corpus task has a record under it **at every maker tier** — the read-only completeness
  oracle is `bash .claude/hooks/maker-eval-emit.sh complete --run-id <id>` (exit 0 = complete,
  exit 3 = incomplete). The **last complete** run and the **prior complete** run are the
  differential's two inputs; an incomplete latest run (including a single-tier run) is never a
  silent baseline.
- **Recompute the current maker-behavior fingerprint** with the single-source recipe
  `bash .claude/hooks/maker-eval-emit.sh fingerprint` → the `.maker_behavior` field of the
  printed triple-fingerprint object. **Reuse that recipe — never re-derive it here** — so what
  the maker-behavior surface covers (the model rows + the instruction/runtime surfaces) stays a
  one-place edit; it is a content hash, so recomputing is read-only.
- **MAKER-EVAL-STALE** compares that recomputed `.maker_behavior` against the **last run's**
  recorded `fingerprint.maker_behavior`. Equal ⇒ current; different ⇒ **MAKER-EVAL-STALE** (an
  eval is overdue). This is the maker analog of PROBES-STALE/CORPUS-STALE above.
- **JUDGE-CHANGED / INSTRUMENT-CHANGED** compare the **two runs being differenced** (not the
  live tree): the last complete run's `fingerprint.judge_identity` / `fingerprint.eval_instrument`
  against the prior complete run's. A difference makes the pair **not-comparable** and suppresses
  the regression call.
- **JUDGE-MISCALIBRATED** reads the recorded judge↔owner agreement and its floor from the run's
  records (added by US1.AC5 / T806 — the calibration set and agreement computation). Until those
  fields are emitted, no agreement is present ⇒ render the neutral "no agreement recorded yet"
  state. All of this stays observe-only (`maker-eval.md` → "Observe-only"): the section feeds no
  gate, tier, guard, or selection path.
