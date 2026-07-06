# Creance — compact project packet (active routing facts)

> The **default profile read** for ordinary workflow runs (spec 007 US3). Every covered
> field below mirrors `.claude/PROJECT.md` — the full profile, which stays the **source
> of truth** — and is drift-checked against it by
> `.claude/hooks/compact-packet-drift.sh` in CI `verify`: a field that disagrees with
> the profile fails verification, so this packet cannot silently rot (spec 007
> non-goals). **Escalate to the full `.claude/PROJECT.md` explicitly** — say you are
> escalating and why — when a run needs anything beyond these routing facts: an
> invariant's full text and auditor rule, the maker-eval records path, architecture
> boundaries, the constitution-watch look-ahead, coverage policy, autonomy rationale,
> or blocked-task detail.

## Core facts

- Base branch: `main`
- Required check: `verify`; merge gate: none — never merge without explicit owner
  authorization regardless
- Autonomy opt-in: `disabled` — review mode: open PRs, a human merges (full policy and
  the opt-in rules: PROJECT.md → "Autonomy")
- Constitution: `memory/constitution.md` (law)
- Repo model: direct — issues/PRs live on `origin`; derive the slug at runtime, never
  hardcode it

## Conventions

- Title: `<type>: [<task-id>] <description>` for task work; `<type>: <description>` for
  repo maintenance (issues, PRs, and commits alike)
- Branch: `<type>/<issue#>-<short-slug>`
- Task IDs: `T` + 3–4 digits, unique across the live tasks files (each spec owns a
  disjoint block); every task line carries a `[frontier]`/`[strong]`/`[cheap]` tier tag
  resolved via `.claude/MODELS.md`
- Issue lifecycle: create-on-demand before the first file edit; closed by the PR
  (`Closes #<n>`)

## Paths

- Specs (acceptance criteria): `specs/001-harness-feedback-loop/spec.md`,
  `specs/002-spec-quality-gate/spec.md`, `specs/003-maker-eval-corpus/spec.md`,
  `specs/004-autonomous-backlog-loop/spec.md`, `specs/005-held-out-acceptance/spec.md`,
  `specs/006-adoption-context-preservation/spec.md`,
  `specs/007-workflow-context-economy/spec.md`, `specs/008-fast-lane-workflow/spec.md`
- Tasks (backlog): `specs/001-harness-feedback-loop/tasks.md`,
  `specs/002-spec-quality-gate/tasks.md`, `specs/003-maker-eval-corpus/tasks.md`,
  `specs/004-autonomous-backlog-loop/tasks.md`, `specs/005-held-out-acceptance/tasks.md`,
  `specs/006-adoption-context-preservation/tasks.md`,
  `specs/007-workflow-context-economy/tasks.md`, `specs/008-fast-lane-workflow/tasks.md`
  — selection spans all; `specs/000-template/` is a skeleton, never a backlog
- Telemetry stream: `<triage inbox dir>/creance-telemetry.jsonl` (out-of-repo; storage
  convention: `workflow/telemetry.md`)

## Blocked / owner-only tasks

- none (detail and any owner-overridable defaults: PROJECT.md)

## Review passes

| pass (role) | enabled | condition | applies-to |
|---|---|---|---|
| `[code-review pass]` | true | always | both |
| `[security-review pass]` | true | sensitive-diff | both |
| `[craft-review pass]` | true | always | both |

## Edit-time checks (the [edit guard] map)

- `*.sh` → `.claude/hooks/shell-lint.sh`

## Critical invariants (deterministic backstops in backticks; full text + auditor rules: PROJECT.md → "Invariant checklist")

- Runtime-neutral workflow layer — no concrete mechanism in `workflow/**` —
  `lib-neutrality-scan.test.sh`, `neutrality-scan-coverage.test.sh`
- A guard-behavior change ships its guard-test case — `guard.test.sh`
- No selectable template artifacts / no duplicate task IDs — CI repo-consistency step
- Telemetry observes, never decides (P5) — judgment-only (constitution auditor)
- No silent self-modification of reviewer specs / invariants / guards / the
  constitution (P4) — judgment-only (constitution auditor)
- Reviewers grade, never apply fixes (maker ≠ checker, read-only by construction) —
  `reviewer-roster.test.sh`, `gate-loop.test.js`
- `AGENTS.md` residency ceiling — `agents-residency-check.sh`
- Hook scripts stay BSD/GNU-portable; an edit adds no new diagnostic —
  `shell-lint.sh`, `shell-lint.test.sh`, `guard.test.sh`
- Selection reconciles live state (merged + in-flight) and announces/confirms
  deterministically, one shared drift definition — `reconcile-task-selection.test.sh`,
  `reconcile-inflight-selection.test.sh`, `announce-task-selection.test.sh`,
  `lib-tasks-drift.sh`
- Autonomy off by default; activation fails closed to review; promotion stays §7-gated —
  `autonomy-mode.test.sh`
- Isolation lifecycle never writes the base branch; gate-in-place reads the workspace by
  explicit context; promote is a PR, never a merge — `isolated-workspace.test.sh`,
  `isolation-falsification.test.sh`, `gate-loop.test.js`
- The §7 gate audits an explicit, HEAD-verified ref on every dispatch — review mode
  included — `gate-diff.test.sh`, `gate-loop.test.js`
- Maker-eval is observe-only (P5); its frozen instrument changes only by PR (P4) —
  `maker-eval-docs.test.sh`, `maker-eval-fence.sh`, `maker-eval-fence.test.sh`
