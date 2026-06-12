# telemetry — gate-run record & storage convention (runtime-neutral)

Every §7 gate run (`next-task.md`) leaves a machine-readable outcome record, so auditor
behavior and task cost become inspectable trends rather than anecdotes. This file defines
**what a record is and where records live**. It defines no writer: emission is owned by
the adapters' gate-loop binding (gate-run records) and the **[guard]** (block and
evaluation records, defined below).

> Runtime-neutral: roles in **[brackets]** are defined in `workflow/README.md` → "binding
> contract" and mapped to concrete mechanisms by the active adapter.

## The law this file lives under

**Telemetry observes; it never decides.** Records are append-only observations. Nothing —
no gate, no [reviewer] dispatch, no tier resolution, no triage write — may read telemetry
to alter a gate outcome, reassign a model tier, or change gate semantics (round limits,
veto authority, tier floors). Telemetry's only consumers are read-only surfacing (the
triage [workflow]) and human-reviewed retrospective analysis. Symmetrically, **a failed
telemetry write never blocks, fails, or alters the behavior of the thing being measured**:
emitters must treat write failure as silent-to-the-gate (the gate run or guard invocation
proceeds exactly as if the write had succeeded).

## Storage convention

- **Format:** one file, **append-only JSONL** — one JSON object per line, never edited or
  rewritten in place. No dashboards, no databases — the stream itself is the contract.
- **Location:** resolved from the profile — `.claude/PROJECT.md` → "Paths" → **Telemetry**
  is authoritative. The shipped default keeps project repos clean by living **out-of-repo
  beside the triage inbox**: `<triage inbox directory>/<repo-basename>-telemetry.jsonl`,
  where the directory is the same portable home-relative location the triage [workflow]
  resolves (`triage.md` §4; the concrete form comes from the **[environment block]**) and
  `<repo-basename>` is the last path segment of the repo root. A profile may override to
  any path, including in-repo.
- Emitters create the parent directory if missing. The location is shared by every record
  type below — one stream per project, discriminated by the `record` field.
- **No cross-project aggregation:** each project's stream is its own — each project's
  feedback loop is its own.

## Record envelope (all record types)

Every line carries:

| Field | Meaning |
|---|---|
| `record` | type discriminator: `gate-run`, `block`, or `evaluation` (each defined below) |
| `timestamp` | ISO-8601 UTC time the record was written |
| `repo` | `<repo-basename>` — keys the stream when files are ever co-located |

## The `gate-run` record

One record per completed §7 gate invocation (PASS, FAIL, or non-convergence stop),
appended by the dispatcher after the gate loop returns. Fields beyond the envelope:

| Field | Meaning |
|---|---|
| `task_id` | the task the gate graded (profile's task-ID format) |
| `rounds` | per-round dispatch history: an ordered list, one entry per dispatch round, each holding `{ auditor, tier, verdict }` for every [reviewer] dispatched that round — `auditor` is the reviewer role name (its spec file under `workflow/reviewers/`), `tier` the capability tier it was dispatched at (the bracketed tier name, not a model ID), `verdict` PASS / JUSTIFY / FAIL / NO-RESULT |
| `fix_rounds_used` | how many fix-and-re-dispatch rounds ran (`gate-loop.md`) |
| `outcome` | `pass`, `fail`, or `non-convergence` — the gate's overall return |
| `fail_reports` | for every FAIL verdict in `rounds`: the reviewer's verdict report text **verbatim**, keyed by auditor and round (a NO-RESULT dispatch has no report — record the literal string `NO-RESULT` for it) — this is what the risk-ranked PR digest later cites for near-misses |

Tier names, not model IDs: a record naming a concrete model would leak adapter facts into
a runtime-neutral artifact and break the one-line-model-swap property. The adapter's model
table remains the only place a tier resolves to a model.

## The `block` and `evaluation` records ([guard])

Both are appended by the **[guard]**, to the same stream, with the same fields beyond the
envelope:

| Field | Meaning |
|---|---|
| `rule` | the guard rule's stable identifier — which rule fired (`block`) or was evaluated (`evaluation`) |
| `tool` | the tool whose invocation the guard inspected |

- A **`block`** record is appended for **every blocked action**, whatever the rule.
- An **`evaluation`** record is appended on at least one guard path **guaranteed to fire
  during every gate run** — the strong-tier floor check on the constitution [reviewer]
  dispatch — whatever that check's outcome. This is the liveness signal: a window with
  gate runs but zero `evaluation` records means the guard is silently dead (the triage
  [workflow]'s GUARD-SILENT check), which "no `block` records" alone cannot distinguish
  from "nothing to block".
- Per the law above, a failed write is swallowed: the guard's allow/block decision and
  exit behavior are identical whether or not the record landed.

## Consumers

- The triage [workflow]'s trend surfacing reads this stream **read-only** and renders an
  explicit no-data state when the file is absent or empty.
- The retrospective [workflow] cites `fail_reports` as evidence; it proposes changes via
  PR only — telemetry never feeds an automatic rewrite of reviewer specs, guards, or the
  constitution.
