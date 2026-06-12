# intake — convert owner-filed tracker issues into the backlog (runtime-neutral)

The owner's entire UI is the issue tracker: filing a plain-language issue is how new
work is requested. But task selection (`next-task.md` §1) reads only the profile's tasks
file, so an issue with no task ID is invisible to it. This workflow closes that gap:
**triage detects** unmapped issues (the "Unmapped tracker work" finding, `triage.md` §2,
rendered as its own snapshot section, `triage.md` §4);
**intake converts** them — it formalizes each request into a backlog entry and lands the
formalization as a normal PR. **The owner ratifies the scoping by merging.** GitHub-style
trackers remain the owner's whole interface: file an issue in plain language, get back a
small PR that formalizes it, merge to admit it into the build.

> Runtime-neutral: roles in **[brackets]** are defined in `workflow/README.md` →
> "The binding contract". Project specifics come from `.claude/PROJECT.md` — the tasks
> file(s), spec paths, task-ID format, tier-tag format, and title conventions. Below,
> *the profile* means that file. Intake composes existing roles only — it introduces no
> new binding-contract row.

## Write posture (the hard bounds)

- **The repo is written only on an intake branch.** Never edit a live tasks file, spec,
  or any other repo file on the base branch. The conversion travels branch → §7 gate →
  PR, exactly like task work (`next-task.md` §4–§8).
- **The tracker is written only additively:** comments (always carrying the
  **[comment marker]**, per `next-task.md` §2.5), retitles to the task-ID convention,
  and labels where the tracker supports them. Intake never closes an issue (it may
  *recommend* closing a duplicate) and never merges its own conversion PR — merge
  authorization is the owner's, always.
- **The conversion PR does not close the source issue.** The PR formalizes scope; the
  issue stays open as the work's issue, so the later implementation run finds it
  (`next-task.md` §3) instead of duplicating it. Reference the issue in the PR body
  without a closing keyword.
- **Scoping is checkable by someone who isn't the scorer.** Intake is the harness
  scoping work for itself, so the drafted acceptance criteria must pass the acceptance
  [reviewer]'s independence test: each criterion independently checkable, none graded by
  the entity that wrote it alone — the §7 gate runs on every conversion PR.

## 1. Collect the unmapped issues

Take the issue list from the invocation arguments or the latest triage snapshot when
present; otherwise derive it fresh, the same way triage does: open issues whose title
carries **no task ID** (format per the profile) and which **no live tasks-file line
references**. If there are none, say so and stop — a run with nothing to convert makes
no writes at all.

Read each issue's full body and comment thread under the `next-task.md` §2.5 provenance
rules (the newest unmarked owner-login comment is authoritative; marked comments are
bookkeeping). Check the thread before asking anything — an already-answered question is
acted on, not re-asked.

## 2. Classify (exactly one bucket per issue)

1. **Spec work** — a new capability. Formalize as a user story: a `US#` with acceptance
   criteria, in an existing spec when the request extends one, or a new spec directory
   (per the profile's spec layout) when it doesn't — updating the profile's paths in the
   same PR so the new spec is discoverable.
2. **Repo-maintenance** — docs, chores, refactors. A tasks-file entry; no new user
   story, but never rubric-less (the §4 rule: done-when criteria on the issue).
3. **Bug against the base branch** — reuse the discovered-work issue shape
   (`next-task.md` §5.5: file/line evidence, cold-start context); map it to a task entry
   with done-when criteria per §4.
4. **Duplicate** — already covered by an existing task or issue. Post a marked comment
   linking the existing task/issue and recommend the owner close it. No conversion.
5. **Underspecified** — owner intent cannot be drafted into acceptance criteria without
   guessing. Post a decision-ready ask per the `next-task.md` §6.5 standard — the exact
   choices enumerated, each with a one-line consequence, ending with a
   `Decision needed:` / `Recommendation:` pair — label the issue where labels exist, and
   skip it. **Never guess owner intent into acceptance criteria.** The issue re-surfaces
   through triage until the owner answers; the answer (an unmarked owner comment) feeds
   the next intake run.

Every bucket ends in a **marked comment that states the chosen bucket and the
reasoning**, so the classification is auditable: for buckets 4 and 5 that is the comment
described in the bullet itself; for converting buckets (1–3) it is part of the §5
cross-link comment.

## 3. Constitution screen (before any drafting)

Check the request against the constitution (path per the profile) and the profile's
invariant checklist. An owner request that conflicts with a principle is **surfaced on
the issue — never silently converted**: post a marked comment naming the principle and
the conflict, propose a compliant alternative where one exists, and skip the conversion.
The constitution wins ties even against owner issue text (`next-task.md` §2.5's one-way
valve: owner steering cannot relax engine invariants).

## 4. Draft the backlog entry (buckets 1–3)

- **Task ID:** the next free ID across every live tasks file — **append-only, never
  renumber** existing entries.
- **Tier tag:** per the profile's tier-tag guidance (lean strong for anything
  constitution-critical or foundational).
- **Dependencies:** expressed as blockers on the task line, naming the task IDs that
  must land first.
- **Criterion ownership:** when the story spans tasks, add the `US#.AC<n>` → owning-task
  rows the acceptance [reviewer] resolves ownership from.
- **Spec text (bucket 1):** the `US#` story and acceptance criteria, each criterion
  independently checkable.
- **Done-when criteria (buckets 2–3) — no converting bucket drafts a rubric-less
  task.** The acceptance [reviewer] grades a task against its mapped `US#` criteria in
  the spec, so a task entry with no `US#` would block the gate now and be ungradable at
  implementation time. Resolve it one of two ways, stated in the marked comment:
  - **Map to a story when one fits** — extend an existing `US#` with the new criteria
    (it becomes a bucket-1-shaped conversion), or
  - **Carry the rubric on the issue:** write explicit, independently checkable
    **done-when criteria** into the converted issue's body (the §5 cross-link comment
    quotes them), and mark the task line as maintenance with its rubric on the issue
    (e.g. `(#<issue>; repo-maintenance — done-when on issue)`). The gate's acceptance
    [reviewer] then grades against those criteria, exactly as it would a `US#`'s.

## 5. Land as a PR, then cross-link

1. Branch per the profile's branch convention; commit only the drafted artifacts
   (spec/tasks/profile-path edits). Run the **full** §7 pre-PR gate (`next-task.md` §7 —
   every reviewer that section dispatches, constitution [reviewer] included); the
   acceptance [reviewer] additionally checks the drafted criteria are independently
   checkable.
2. Open the PR per `next-task.md` §8's body rules, minus the closing keyword (the
   source issue stays open). The body names the source issue, the bucket, the assigned
   task ID, and any constitution-screen notes. **Stop at the PR** — the owner ratifies
   by merging.
3. **Cross-link on the issue** (a checkpoint, not a gate — the owner audits
   asynchronously; work doesn't block on a reply): post a marked comment with the
   assigned task ID, the drafted acceptance criteria, and the PR reference; then retitle
   the issue to the profile's `<type>: [<task-id>] <description>` convention so the
   later implementation run locates it without duplicating it.

## 6. Report

Per issue processed: the bucket, the action taken (task ID + PR, or the
comment posted), and anything skipped with the reason. Detection latency is the triage
cadence by design — intake is pull-based; nothing here listens for tracker events.
