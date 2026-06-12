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
- If any read fails (e.g. the GitHub CLI is missing), note it under "Heartbeat health" and
  continue; never let one failed read abort the run.

## 1. Read the sources (all read-only)
1. The profile's **tasks file** — the backlog. Note every task ID and whether its checkbox is
   `[ ]` or `[x]`, its phase, `[US#]`, and `path`.
2. `git log --oneline -20` — recent commits. Commit subjects carry the task ID and PR number
   (e.g. `<type>: [<task-id>] … (#<pr>)`).
3. GitHub state via its CLI. Two gotchas, both mandatory:
   - The CLI **may not be on PATH** in a headless run — try it first, then fall back per the
     **[environment block]**.
   - **If this repo is a FORK,** issues/PRs live on your `origin`, not the upstream (usually
     empty). A bare call may resolve to *upstream* and falsely report "nothing open." Derive
     the `origin` slug once **per the profile's Identity section** and target that slug
     explicitly on every call.
   - List open issues and open PRs (with review decision + check status + last-updated).
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
   per `workflow/telemetry.md`) — **read-only, like every other source here**: never write
   to, truncate, or rewrite the stream. An absent or empty file is not a read failure —
   it feeds the "Gate trends" section's explicit no-data state (§2).

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
  This derivation is **read-only over telemetry** (per `workflow/telemetry.md`, telemetry
  observes and never decides — trends inform the human, never a gate or tier). When the
  stream is absent, empty, or has no `gate-run` records in the window, the section still
  renders, with the explicit no-data state shown in the §4 template — it is never
  silently omitted and a missing file is never an error. Records that fail to parse are
  skipped and counted in the section's "skipped malformed lines" note, never repaired
  in place.
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
- <when non-empty, end the section with:> run the intake [workflow] (`intake.md`) to convert

## Blocked / owner action
- <task IDs + reason, from the profile's blocked-task list>   (or "none")

## Constitution watch (upcoming)
- <task>: <which principle to guard>

## Gate trends (window: <YYYY-MM-DD>–<YYYY-MM-DD>)
- FAIL counts by auditor: <auditor>: <n> …   (or "none in window")
- Non-convergence stops: <task-id> …   (or "none in window")
- Tier escalations: <task-id>: <auditor> <from-tier> → <to-tier> …   (or "none in window")
- <"no data yet — telemetry stream absent/empty at <path>" replaces the three lines above
  when §2's gate-trends derivation found no gate-run records>
- <"skipped malformed lines: <n>" — present only when nonzero, whether or not data was found>

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
