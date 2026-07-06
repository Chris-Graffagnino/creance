# triage — the read-only heartbeat (runtime-neutral)

You are doing **discovery and triage only**. You surface work; you do not do it. This
procedure is safe to run unattended because it cannot change the repo.

> Runtime-neutral: roles in **[brackets]** are defined in `workflow/README.md`. Project
> specifics come from `.claude/PROJECT.md` — the tasks-file path, task-ID format, the
> blocked-task list, and the constitution-watch map. Below, *the profile* means that file.

## Hard constraints (do not cross)
- **Read-only on the repo.** No file edits to anything under the repo root
  (`git rev-parse --show-toplevel`). No `git add/commit/push`, no branch changes, no issue/PR
  creation. If a finding is actionable, *name it* — the human runs the **next-task [workflow]**
  later.
- **The ONLY write is the inbox file**, which is out-of-repo (see §4). That write is permitted
  on the base branch because it lives outside the repo root.
- If any read fails (e.g. the tracker read mechanism is unavailable), note it under "Heartbeat health" and
  continue; never let one failed read abort the run.

## 1. Read the sources (all read-only)
1. The profile's **tasks file** — the backlog. Note every task ID and whether its checkbox is
   `[ ]` or `[x]`, its phase, `[US#]`, and `path`.
2. `git log --oneline -20` — recent commits. Commit subjects carry the task ID and PR number
   (e.g. `<type>: [<task-id>] … (#<pr>)`).
3. Tracker state via the adapter's read mechanism. Two gotchas, both mandatory:
   - The read mechanism **may be unavailable** in a headless run — try it first, then fall
     back per the **[environment block]**.
   - **If this repo is a FORK,** issues/PRs live on your `origin`, not the upstream (usually
     empty). A bare call may resolve to *upstream* and falsely report "nothing open." Derive
     the `origin` slug once **per the profile's Identity section** and target that slug
     explicitly on every call.
   - List open issues and open PRs (with review decision + check status + last-updated).
   - **For each open issue, read its body** for the discovered-work provenance line
     (`Discovered while working #N`, the `next-task.md` §5.5 convention) and the
     file/line evidence it cites — the "Discovered-work clusters" derivation (§2)
     groups discovered-work issues by the subsystem/path that evidence points at, so
     without the bodies a run cannot form the clusters.
   - **For each open issue and PR, fetch its comment thread and cross-referenced
     timeline events** — comment bodies, authors, and timestamps, plus the harness
     commit/PR events cross-referenced on the thread. The "Unacknowledged owner comments"
     derivation (§2) needs this evidence: without it a headless run renders that section
     empty or stale and silently misses owner steering. The **[comment marker]** tells the
     owner-login comments apart from harness bookkeeping (§2; channel rules in
     `next-task.md` §2.5).
   - An issue is pre-created for every task (one per task ID); reference the existing issue
     number, don't imply a new one.
4. The **constitution** (path in the profile) is law; you needn't re-read it every run, but use
   its high-risk principles for the "Constitution watch" below.
5. The **launcher run log** — read its **last line**. Resolve the path in this order, and
   actually check each step (a [headless run]'s launcher may pin a non-default location):
   1. a path passed as an argument to this workflow's invocation (e.g. `run log: <path>`);
   2. the `TRIAGE_RUNLOG` environment variable — read its value explicitly; do not assume
      it is unset without looking;
   3. the §6 default: `<dir of the resolved inbox>/<repo-basename>-heartbeat.log`.
   The launcher appends the current attempt's line only *after* the agent exits, so at read
   time the last line describes the **previous** attempt. Only report "no run log" after all
   three resolutions came up empty — a missing log at just the default path is not evidence
   the launcher never ran.
6. The **telemetry stream** (path from the profile → "Paths" → Telemetry; record shapes
   per `workflow/telemetry.md`, and the **[backlog-loop]** run-report records' shape per
   `workflow/backlog-loop.md` → "The run report (observe-only)") — **read-only, like every
   other source here**: never write
   to, truncate, or rewrite the stream. An absent or empty file is not a read failure —
   it feeds the "Gate trends" and "Backlog-loop run report" sections' explicit no-data
   states (§2).
7. The **probe-run records and the current machinery** (for the "Verification-machinery
   freshness" findings, §2) — both read-only:
   - The conformance probes record their results as a **dated table with a `[guard]`-machinery
     fingerprint per run** (`workflow/conformance-probes.md` → "Recording"). Read the **most
     recent run's** recorded fingerprint and its date — the comparison baseline and the age
     source for the PROBES-STALE check. No recorded run at all is not a read failure; it feeds
     that check's explicit "no probe run recorded yet" state (§2).
   - Recompute the **current `[guard]`-machinery fingerprint** from the live checkout, using
     the same reproducible recipe the probe runs record (`conformance-probes.md` → "Recording":
     the same machinery recomputes to the same fingerprint; it covers the `[guard]`'s decision
     logic **and** the wiring that routes events to it). Recomputing a content hash **reads**
     the machinery — it never edits it, so this honors the read-only-on-the-repo constraint.
   - The **auditor-liveness corpus** records its runs with a **reviewer-spec fingerprint** per
     run (`workflow/auditor-liveness.md` → "Re-run policy"). Read the **most recent corpus
     run's** recorded fingerprint and its date, and recompute the **current reviewer-spec
     fingerprint** from the live checkout — the baseline and comparison for the CORPUS-STALE
     check (§2). Recomputing the hash **reads** the specs, never edits them. No corpus run
     recorded at all is not a read failure; it feeds that check's explicit "no corpus run
     recorded yet" state (§2).
   Where the records live, and the concrete recipes for recomputing both fingerprints, are the
   adapter's to supply — this step names neither.
8. The **maker-eval records** (path from the profile → "Paths" → Maker-eval records; record
   shape per `workflow/maker-eval.md` → "The record and the transcript review packet") —
   **read-only, like every other source here**: never write to, run, or rewrite the eval. They
   feed the "Maker eval" section (§2). An absent or empty channel is not a read failure — it
   feeds that section's explicit "no data yet" state. Two reads:
   - **The two runs to difference.** Group the records by **run id**; find the **last
     *complete* run** (every corpus task has a record under its run id **at every maker tier** —
     `maker-eval.md` → "The record …") and the **prior complete run** before it. These two are the
     differential's inputs (§2). An **incomplete** latest run (including a single-tier run) is
     never a silent baseline. Records that fail to
     parse are skipped and counted in the section's "skipped malformed lines" note, never
     repaired in place.
   - **The current maker-behavior fingerprint.** Recompute it from the live checkout using the
     same reproducible recipe the eval records (the **maker-behavior** component of the triple
     fingerprint — `maker-eval.md` → "The triple fingerprint") — the baseline for the
     MAKER-EVAL-STALE check (§2). Recomputing a content hash **reads** the maker surfaces, never
     edits them, honoring the read-only-on-the-repo constraint.
   Where the channel lives and the concrete fingerprint recipe are the adapter's to supply —
   this step names neither.

## 2. Derive the findings
- **Next unblocked task.** Lowest-numbered `[ ]` task whose dependencies are met and which is
  *not* blocked. The headline recommendation.
- **Blocked / owner-action (surface, never start):** every task in the profile's "Blocked /
  owner-only tasks" list, with the reason the profile gives.
- **Stale state (high value).** A task still `[ ]` in the tasks file whose ID appears in a
  merged commit subject is **done-but-unchecked** — flag it with the commit hash and recommend
  ticking the box.
- **Open PRs needing attention.** Any open PR not approved, with failing checks, or untouched
  for a while → list it (protects the "review every PR" loop from staleness).
- **Open issues** without a matching branch/PR → list as ready-to-start.
- **Unmapped tracker work.** Open issues whose **title carries no task ID** (format per
  the profile) and which **no live tasks-file line references** (search every tasks file
  the profile names for the issue number and for a task line pointing at it) —
  owner-filed requests that task selection cannot see and will walk past indefinitely.
  One line per issue: number, title, age. The check is nearly deterministic (an issue
  list + a text search over the tasks files). **Detection only:** converting an unmapped
  issue into the backlog is the intake [workflow]'s job (`intake.md`) — triage names it
  and stays read-only.
- **Unacknowledged owner comments.** For each open issue and PR, the unmarked
  owner-login comments newer than the **last harness-marked activity** on that thread —
  owner steering the harness has not yet acted on. The **[comment marker]** separates
  engine bookkeeping from owner steering (its role is defined in the binding contract;
  the channel rules live in `next-task.md` §2.5): a **marked** comment is harness
  bookkeeping, the newest **unmarked** owner-login comment is authoritative steering.
  *Last harness-marked activity* = the newest **[comment marker]**-marked comment on the
  thread, or the newest cross-referenced harness commit/PR event; when the thread carries
  no marked activity, any owner comment newer than the item's last cross-referenced
  harness action counts. One line per comment: item number, comment date, the comment's
  first line. **Detection only:** triage names the unacknowledged comment and stays
  read-only — acting on it is the next-task [workflow]'s job (per `next-task.md`
  §2/resume rules); triage posts nothing, marks nothing, and mutates no thread state.
- **Constitution watch (look-ahead).** From the profile's "Constitution watch" map, name the
  *upcoming* tasks that touch the highest-risk principles so the human reviews them carefully
  when they land. Cross-reference with which of those are still `[ ]`.
- **Gate trends (from the telemetry stream).** Over the snapshot window — the trailing 7
  days unless the profile says otherwise — derive from the stream's `gate-run` records:
  - **FAIL counts by auditor:** for each auditor name appearing in any record's `rounds`,
    the count of FAIL verdicts it returned in the window.
  - **Non-convergence stops:** every record with `outcome: non-convergence`, listed by
    `task_id`.
  - **Tier-escalation events:** within a single record's `rounds`, a later round
    dispatching an auditor at a higher tier than an earlier round dispatched the same
    auditor — list each as `<task_id>: <auditor> <from-tier> → <to-tier>`.
  - **Effective-fix rate (submission efficiency):** over the window, the fraction of
    FAIL-triggered reviewer re-dispatches that **flipped** — a reviewer FAIL in round *n*
    that cleared to PASS or JUSTIFY in round *n+1* of the same record (defined in
    `workflow/telemetry.md` § Consumers). Render it **with its numerator and denominator
    shown — never a bare percentage** — as `<flips>/<re-dispatches>` (a percentage may
    accompany it) for the window and broken out per auditor, computed by a **deterministic
    recipe a non-scorer can re-run** (constitution P3 — never model estimation; the concrete
    recipe is the adapter's to supply). It has two explicit empty states, neither silently
    omitted nor rendered as an error: **"no fix rounds in window"** when the window holds
    `gate-run` records but **no FAIL-triggered re-dispatch** (denominator zero) —
    **distinguished from a genuine 0-of-N rate**, which renders as `0/<n>` because reviewers
    were re-dispatched but none flipped — and the existing **"no data yet"** state when the
    window holds no `gate-run` records at all.
  This derivation is **read-only over telemetry** (per `workflow/telemetry.md`, telemetry
  observes and never decides — trends inform the human, never a gate or tier). When the
  stream is absent, empty, or has no `gate-run` records in the window, the section still
  renders, with the explicit no-data state shown in the §4 template — it is never
  silently omitted and a missing file is never an error. Records that fail to parse are
  skipped and counted in the section's "skipped malformed lines" note, never repaired
  in place.
- **Backlog-loop run report (from the telemetry stream).** The latest **[backlog-loop]**
  run's observe-only report (`workflow/backlog-loop.md` → "The run report (observe-only)"),
  read from the same stream as the gate trends: group the stream's
  `backlog-loop-iteration` and `backlog-loop-summary` records by run id and surface the
  run whose summary record is newest. One line per iteration — the task ID plus that
  iteration's terminal outcome **in the outcome's own form**: a gated outcome's verdict
  and its PR reference or discard; a refused or aborted iteration shows the outcome
  itself, with no gate verdict and no PR-or-discard (the report never fabricates a gate
  result, and neither may this surfacing) — plus the run-summary line's stop condition
  and `iterations of N`. **Flag a partial run as partial**: a run whose stop condition is
  neither the drained budget nor the drained backlog (`backlog-loop.md` → "Stop
  conditions") stopped with eligible budget remaining, so mark it explicitly rather than
  letting it read as a clean drain — a partial run is a valid outcome, never an error
  baseline. This derivation is **read-only over telemetry** (per `workflow/telemetry.md`,
  telemetry observes and never decides — the loop itself consumes each iteration's
  outcome from the run's own return, never from this report). When the stream holds no
  backlog-loop records, the section still renders, with the explicit "no backlog-loop
  run recorded yet" state shown in the §4 template — never an error and never silently
  omitted. Records that fail to parse are skipped and counted in the section's "skipped
  malformed lines" note, never repaired in place.
- **Discovered-work clusters (from the open issues' bodies).** The open issues
  filed as discovered work — those whose body carries a `Discovered while working #N`
  provenance line (the `next-task.md` §5.5 convention) — grouped by the
  **subsystem/path** their file/line evidence points at: the path prefix the issue's
  evidence cites (when an issue cites several, group it under the area its title or
  first finding centers on). Report each group as `<path/subsystem>: #<n> #<n> …`.
  **Flag any group of 3+ open discovered-work issues as a possible missing spec** — a
  recurring cluster in one area is the signal that the area needs its own spec/contract
  rather than repeated one-off fixes. This derivation is **read-only over the tracker**:
  triage names the cluster and stays read-only; specifying or converting it is the
  human's call via the next-task / intake [workflow]s. When no open issue carries the
  discovered-work provenance line, the section still renders with the explicit empty
  state in the §4 template — it is never silently omitted, and an absence of
  discovered-work issues is never an error.
- **Verification-machinery freshness (US5 + auditor liveness).** Three read-only checks that
  surface silently dead verification machinery — a dead `[guard]`, or an auditor gone blind —
  in days rather than at the next adapter port (the "silently dead machinery" failure class —
  `DESIGN-NOTES.md` §4):
  - **PROBES-STALE (fingerprint currency).** Compare the **current** `[guard]`-machinery
    fingerprint (recomputed in §1.7) against the fingerprint recorded with the **most recent
    probe run** (§1.7). When they **differ**, flag **PROBES-STALE** — the recorded probe
    results predate a change to the machinery they were meant to exercise, so the binding is no
    longer known-good — and report the **age of the last probe run** (now − its recorded date)
    so the staleness is quantified. When they match, report the machinery as current **with the
    last probe run's age**, rather than omitting the line. When **no probe run is recorded
    yet** there is no baseline: render the explicit "no probe run recorded yet" state (§4),
    never an error and never a silent omission. This is a **definite flag, not a heuristic** —
    a fingerprint mismatch is deterministic.
  - **GUARD-SILENT (guard liveness).** Over the snapshot window (the "Gate trends" window
    above), from the telemetry stream (§1.6): if the window holds **one or more `gate-run`
    records but zero `[guard]` `evaluation` records** (`workflow/telemetry.md` — the
    `evaluation` record fires on a guard path guaranteed to run during *every* gate run, so its
    absence amid gate activity means the guard never fired), flag **GUARD-SILENT as a warning,
    not an error**: it is a **heuristic**, not a proof — a swallowed telemetry write is silent
    by design (`workflow/telemetry.md`), so a missing record is suggestive, not conclusive.
    When gate runs occurred and `evaluation` records are present, report the guard as
    demonstrably live. When **no gate runs occurred in the window** the absence of `evaluation`
    records implies nothing — render the explicit "no gate activity in window" state, never a
    GUARD-SILENT warning (a quiet window is not a dead guard).
  - **CORPUS-STALE (auditor-liveness corpus currency).** The auditor analog of PROBES-STALE,
    pointed at the judgment reviewers instead of the `[guard]`. Compare the **current**
    reviewer-spec fingerprint (recomputed in §1.7) against the fingerprint recorded with the
    **most recent auditor-liveness corpus run** (§1.7). When they **differ**, flag
    **CORPUS-STALE** — a reviewer spec changed since the corpus last confirmed the auditors
    live, so the planted-violation corpus (`workflow/auditor-liveness.md`) is due for a re-run
    — and report the **age of the last corpus run**. When they match, report the auditors as
    confirmed-live as of that run's date (with its age). When **no corpus run is recorded
    yet** there is no baseline: render the explicit "no corpus run recorded yet" state (§4),
    never an error. Like PROBES-STALE this is a **definite flag, not a heuristic** — a
    fingerprint mismatch is deterministic.
  All three checks **observe and report only**: they mutate nothing, and acting on a flag
  (re-running the probes or the corpus, repairing the wiring) is the human's call via the
  next-task / auditor-liveness `[workflow]`s. Per the telemetry law (`workflow/telemetry.md` —
  telemetry observes, never decides), none feeds any gate, tier, guard, or auditor decision.
- **Maker eval (from the maker-eval records).** The maker analog of "Gate trends" — a
  read-only differential over the observe-only maker-eval records (§1.8), surfacing a degrading
  maker before it reaches production. **Triage neither runs the eval nor writes records.** The
  regression differential compares the **last complete run** and the **prior complete run**; the
  MAKER-EVAL-STALE and JUDGE-MISCALIBRATED warnings each derive from the last complete run alone
  (§1.8):
  - **Regressions (noise-tolerant — not "any delta").** Per corpus task, compare the two runs'
    per-dimension verdicts on the frozen ordinal scale `meets` > `partial` > `fails` (and the
    overall `pass`/`fail` — `maker-eval.md` → the scoring schema), and flag a task as a
    **regression** only when the movement clears an **explicit noise threshold**, so the
    observe-only channel does not become alert noise. *The default threshold — unless the
    profile tightens or loosens it:* a task regresses when **(a)** any **`regression`**-lifecycle
    dimension worsens by ≥ 1 step (these pin known past failures, so a backslide there is signal,
    never noise), **or (b)** the task's total worsening across all dimensions is ≥ 2 steps (a
    `meets`→`fails` collapse, or two separate one-step drops). A lone one-step drop on a single
    `capability`/`saturated` dimension is **within noise** and not flagged on its own. Each
    flagged regression **links its transcript review packet** (the record's fenced `packet`
    path, US1.AC2) so the dropped score is reviewable in one hop, not a bare number.
  - **Baseline discipline.** Difference only **complete** runs; an **incomplete** latest run
    renders as incomplete and is **never** a silent baseline. Regressions and Comparability are
    the **two-run** signals: they need a comparable pair, so with fewer than two complete runs
    there is nothing to difference — render their explicit "only one complete run — not enough to
    difference" state. MAKER-EVAL-STALE and JUDGE-MISCALIBRATED are **single-run** signals that
    derive from the last complete run alone, so they still render from one complete run; only a
    wholly absent/empty channel — no complete run at all — collapses every line to "no data yet".
  - **MAKER-EVAL-STALE (a warning).** When the **current** maker-behavior fingerprint
    (recomputed §1.8) differs from the **last run's** recorded maker-behavior component, an eval
    is overdue — a maker swap or an instruction-surface edit happened with no fresh eval. A
    **definite flag, not a heuristic** (a fingerprint mismatch is deterministic); the maker
    analog of PROBES-STALE / CORPUS-STALE.
  - **JUDGE-CHANGED / INSTRUMENT-CHANGED (not-comparable).** When the **judge-identity**
    component differs between the two runs being differenced, annotate **JUDGE-CHANGED /
    not-comparable**; when the **eval-instrument** component differs, annotate
    **INSTRUMENT-CHANGED / not-comparable**. Either **suppresses the regression call** for that
    comparison rather than reporting a confounded delta (`maker-eval.md` → "The triple
    fingerprint" — only the maker is supposed to vary between two comparable runs).
  - **JUDGE-MISCALIBRATED (a warning).** When the last complete run's recorded judge↔owner
    agreement (US1.AC5) is **below its stated floor**, warn that the instrument's judge no longer
    tracks human judgment. When no agreement figure is recorded yet (the owner-labeled
    calibration set and the agreement computation are US1.AC5's task), render the explicit "no
    agreement recorded yet" state — never a silent omission.
  This derivation is **read-only over the records**; per the eval law (`maker-eval.md` →
  "Observe-only" — a measurement channel never decides), none of it feeds any gate, tier, guard,
  or selection path. Every state above renders in the §4 template, consistently with the other
  snapshot sections — an absent or empty channel is the explicit "no data yet" state, never an
  error and never silently omitted.
- **Heartbeat gap (from the run log's last line).** A nonzero exit, or a timestamp older than
  one cadence interval (daily → > ~1 day before now), means the heartbeat had been down and
  this run is the recovery — say so explicitly under "Heartbeat health" so the gap is visible
  in the inbox and not silently papered over by a fresh snapshot.

## 3. Discipline
- Re-derive everything from source each run; do not trust a prior inbox. An unactioned item
  naturally re-appears until resolved — that is the point.
- Every claim cites evidence: a tasks-file line, a commit hash, a PR number. No vibes.
- Keep it scannable. The human should know the single next action in five seconds.

## 4. Write the inbox (the only write)
Overwrite a single out-of-repo inbox file with a fresh snapshot (stamp with today's real date).
Resolve its path in the same order as the run log's (§1.5), and actually check each step:

1. a path passed as an argument to this workflow's invocation (e.g. `inbox: <path>`) — the
   authoritative carrier (the explicit-context rule, `README.md`);
2. the `TRIAGE_INBOX` environment variable — a **redundant hint only**, never the sole
   carrier; read its value explicitly, do not assume it is unset without looking;
3. the portable default — a stable home-relative location keyed by repo name; the concrete
   directory is supplied by the **[environment block]** (`README.md`), with `<repo-basename>`
   the last path segment of the repo root (`git rev-parse --show-toplevel`).

Create the parent directory if missing.

This stays outside the repo root, so writing it is permitted even on the base branch. Use this
shape:

```markdown
# <Project> — Triage  ·  <YYYY-MM-DD>  ·  next run expected <YYYY-MM-DD + one cadence interval>

## ▶ Next action
<one line: the recommended next unblocked task, e.g. "Run next-task → <task-id> (<short title>)">

## Stale state to fix
- [ ] <task> is unchecked but merged in <hash> — tick the box in the tasks file

## PRs needing review
- #<n> <title> — <review/check status>   (or "none open")

## Ready issues
- #<n> <title>   (or "none open")

## Unmapped tracker work
- #<n> <title> — opened <age/date>   (or "none — every open issue is mapped to a task ID")
- <when non-empty, end the section with:> run the intake [workflow] (`intake.md`) to convert them

## Unacknowledged owner comments
- #<n> (<issue|PR>) <comment-date> — "<comment's first line>"   (or "none — no unmarked owner comment is newer than the last harness-marked activity")

## Blocked / owner action
- <task IDs + reason, from the profile's blocked-task list>   (or "none")

## Constitution watch (upcoming)
- <task>: <which principle to guard>

## Gate trends (window: <YYYY-MM-DD>–<YYYY-MM-DD>)
- FAIL counts by auditor: <auditor>: <n> …   (or "none in window")
- Non-convergence stops: <task-id> …   (or "none in window")
- Tier escalations: <task-id>: <auditor> <from-tier> → <to-tier> …   (or "none in window")
- Effective-fix rate: <flips>/<re-dispatches> (<pct>%) for the window; per auditor <auditor>: <n>/<d> …   (or "no fix rounds in window" when there were gate-run records but no FAIL-triggered re-dispatch — distinct from a genuine 0-of-N, which shows 0/<n>)
- <"no data yet — telemetry stream absent/empty at <path>" replaces the four lines above
  when §2's gate-trends derivation found no gate-run records>
- <"skipped malformed lines: <n>" — present only when nonzero, whether or not data was found>

## Backlog-loop run report (latest run: <run-id | none>)
- <task-id>: <"gate <verdict> → PR <ref>"  |  "gate <verdict> → discarded"  |  "refused"  |  "aborted">   (one line per iteration, in run order)
- stop: <stop-condition> — <iterations> of <N> iterations   <append " — PARTIAL: stopped with budget remaining" when §2 flagged the run partial>
- <"no backlog-loop run recorded yet — nothing to surface" replaces the two lines above when the stream holds no backlog-loop records>
- <"skipped malformed lines: <n>" — present only when nonzero>

## Discovered-work clusters
- <path/subsystem>: #<n> #<n> …   <append " — 3+, possible missing spec" when the group has 3 or more>
- <"none — no open issue carries a discovered-work provenance line" when §2 found none>

## Verification-machinery freshness
- PROBES-STALE: <one of: "current — guard machinery matches the last probe run (<YYYY-MM-DD>, age <n>d)"  |  "STALE — current fingerprint differs from the last probe run (<YYYY-MM-DD>, age <n>d); re-run the probes"  |  "no probe run recorded yet — no baseline to compare against">
- GUARD-SILENT: <one of: "live — <n> gate-run record(s) and <n> guard evaluation record(s) in window"  |  "warning: GUARD-SILENT — <n> gate-run record(s) but zero guard evaluation records in window (heuristic; the guard may be silently dead — verify the wiring)"  |  "no gate activity in window — nothing to infer">
- CORPUS-STALE: <one of: "current — reviewer specs match the last auditor-liveness corpus run (<YYYY-MM-DD>, age <n>d)"  |  "STALE — reviewer specs changed since the last corpus run (<YYYY-MM-DD>, age <n>d); re-run the auditor-liveness corpus"  |  "no corpus run recorded yet — no baseline to compare against">

## Maker eval (last complete run: <run-id | none> · <YYYY-MM-DD>)
- Regressions (past the noise threshold): <task-id (dimension meets→fails, …) — packet: <fenced packet path>> …   (or "none past the noise threshold"; or "only one complete run — not enough to difference" when there is no prior complete run to difference against)
- MAKER-EVAL-STALE: <one of: "current — maker-behavior fingerprint matches the last run (<YYYY-MM-DD>, age <n>d)"  |  "STALE — current maker-behavior fingerprint differs from the last run (<YYYY-MM-DD>, age <n>d); an eval is overdue"  |  "no maker-eval run recorded yet — no baseline to compare against">
- Comparability: <one of: "comparable"  |  "JUDGE-CHANGED / not-comparable — judge identity moved between the two runs; regression call suppressed"  |  "INSTRUMENT-CHANGED / not-comparable — eval instrument moved between the two runs; regression call suppressed"  |  "only one complete run — not enough to difference">
- JUDGE-MISCALIBRATED: <one of: "within floor — judge↔owner agreement <x> ≥ floor <y>"  |  "warning: JUDGE-MISCALIBRATED — agreement <x> below floor <y>"  |  "no agreement recorded yet — calibration is US1.AC5's task">
- <"no data yet — maker-eval channel absent/empty at <path>" replaces all four lines above only when there is no complete run at all; with exactly one complete run, MAKER-EVAL-STALE and JUDGE-MISCALIBRATED still render against that run, while Regressions and Comparability show "only one complete run — not enough to difference">
- <"skipped malformed lines: <n>" — present only when nonzero>

## Heartbeat health
- cli: ok | not found   ·  reads completed: <n>/<n>   ·  notes: <…>
- previous launcher attempt: <last run-log line, verbatim>   (or "no run log found")
- <"recovered after a gap: <…>" only when §2's heartbeat-gap finding fired>
```

The "next run expected" header date is *now + one cadence interval* (the heartbeat is daily
unless the profile says otherwise) — it makes a stale inbox self-describing: a reader seeing
that date in the past knows the heartbeat is down without consulting anything else.

## 5. Report
After writing, print a 3–5 line summary ending with the single next action and the inbox path.
Do not take that action — that is the human's call.

## 6. Launcher contract — the dead-man switch (runtime-neutral)
This workflow can only report on runs that *happen*. If the scheduler stops firing, auth
expires, or the headless agent crashes before writing, no inbox is written and nothing inside
the workflow can flag it. Detection therefore lives one level down, in the **launcher** — the
out-of-repo, platform-specific scheduled entry point (Task Scheduler, cron, launchd, …) that
starts the [headless run]. The launcher is rewritten per platform; **this contract is what
every rewrite must honor:**

1. **One line per attempt, appended to a run log next to the inbox** — the `TRIAGE_RUNLOG`
   environment variable if set, else:

   `<dir of the resolved inbox>/<repo-basename>-heartbeat.log`

   Line shape (single line, space-separated, parseable but human-first):

   `<ISO-8601 local timestamp> exit=<code> duration=<seconds>s note=<short free-form reason>`

   The launcher MUST pass both the inbox path and the run-log path in the workflow
   invocation's argument text (e.g. `/triage inbox: <path> run log: <path>`) and MAY
   additionally set `TRIAGE_INBOX` / `TRIAGE_RUNLOG` as redundant hints —
   the binding contract's explicit-context rule (`README.md`): the agent honors prompt text
   far more reliably than environment hints (the same reason §4 and §1.5 resolve
   argument text first), and
   the dead-man switch only closes when the agent reads the same file the launcher writes.

2. **The line is unconditional.** The launcher wraps its entire body (resolve CLI → load
   auth → invoke agent) in its platform's try/finally equivalent — an unconditional
   finalization step — so that *every* attempt records a dated
   line with an exit code — including attempts where the agent never starts (CLI missing,
   token file missing/expired, crash). A failure that leaves no line is a contract violation;
   when in doubt the launcher writes `exit=1 note=<best guess>`.
3. **Append after the agent exits,** never before — so the log's last line always describes a
   *completed* attempt, and a run currently in flight reads as "previous attempt" (which is
   what §1.5 relies on).
4. **Nonzero exit propagates.** The launcher exits with the agent's exit code (or its own
   nonzero on pre-agent failure) so the platform scheduler's "last result" is also truthful.

How the pieces interlock: the run log catches *silent* failures (launcher fired, run died);
the scheduler's own history catches *unfired* launchers; and the inbox header's
"next run expected" date makes staleness visible to a reader who checks nothing else. The
launcher may keep a separate verbose log (full agent output) — that is implementation detail;
only the one-line-per-attempt run log is contractual.
