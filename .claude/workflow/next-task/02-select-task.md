## 1. Select the task
- If the user named a task ID, use it. Otherwise read the profile's **task index** — a
  generated digest of each task's selection-critical fields (path per the profile) — as a
  selection **prefilter**: take the **lowest-numbered unchecked** candidate, then load its full context (§2) and confirm it is startable there — **dependencies met, not blocked** — since the index omits that state by design. Task-ID format per the profile.
- **Skip blocked tasks and say why.** Treat every task in the profile's **"Blocked /
  owner-only tasks"** list as non-startable — surface it, don't begin it.
- **Reconcile the candidate against live state before committing to it
  ([live-state reconciliation]).** A tasks-file checkbox drifts from reality — a task can be
  already merged or in-flight while its box still reads unchecked — so a *prose* "cross-check
  git/PRs" habit is exactly the model-judgment dependency a deterministic check should
  replace. Before selecting, a **deterministic precondition** — the runtime counterpart of
  CI's tasks-consistency backstop, **sharing** its logic rather than forking a second copy —
  reconciles the candidate's box against authoritative live `git`/tracker state. A candidate
  whose live state shows landed/merged work for its ID is **not selectable**: refuse it and
  surface the drift with its conflicting evidence (the commit/PR) instead of starting stale
  work (for an *implicitly* resolved auto-pick this same refusal is delivered by the
  announce-and-confirm step below as a pause for redirection — still never starting the
  candidate). This precondition reconciles two axes: a **git-only** check refuses a candidate
  whose ID carries **landed/merged** work, and a **tracker [role]** read refuses one merely
  **in-flight** — a mapped issue with an open, unmerged PR/branch — surfacing the conflict. Each
  **fails open** with a surfaced warning (the in-flight axis, a network read, degrades to the
  git-only result when the tracker is unavailable), never a hard stall.
- **Announce the resolved target, and confirm an implicit pick that live state contradicts
  ([selection announce-and-confirm]).** After the candidate is resolved, announce the resolved
  target — its task ID and issue — before the first file edit. Whether to also **pause for
  confirmation** is a deterministic decision, not a model "noticing": pause only when the
  selection was **implicit** (no task ID/issue was named) *and* live state **contradicts** the
  auto-picked candidate. The contradiction is the same done-but-unchecked drift reconciliation
  refuses on, but the two responses are **keyed to the pick's provenance**: an **explicit** stale
  pick is reconciliation's terminal refusal above (the user named it), whereas an **implicit**
  contradicted auto-pick is surfaced *here* as the confirm pause — reachable on the composed
  path, not pre-empted by the refusal. Either response invites a *redirect* and never starts the
  contradicted candidate. An explicit request, or an implicit pick live state does **not**
  contradict, announces and proceeds without a pause; when live state is unreadable the step
  **degrades to announce-only**, never a stall it cannot justify. The **in-flight** axis is
  handled by the reconciliation refusal above, not by this confirm pause.
- Confirm the selected task ID, its `path`, and its `US#` before editing anything.
