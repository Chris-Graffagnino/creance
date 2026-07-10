## 3. Find the issue (before the first file edit)
- **Target the right repo.** The profile's Identity section states the repo model; for a
  fork, issues/PRs live on your `origin`, not the upstream (a bare CLI call may resolve to
  the empty upstream). Derive the slug once **per the profile** and target that slug
  explicitly on every call. CLI invocation specifics (PATH fallbacks) come from the
  **[environment block]**.
- **An issue is pre-created for every task.** Locate it (search the issue tracker for the task
  ID in the title). **Use that existing issue** — do NOT open a duplicate.
- Only if none exists, create one titled `<type>: [<task-id>] <description>` with a body
  covering description, acceptance criteria traced to the `US#`, testing guidelines, and the
  task reference. Write multi-line bodies from a file, not an inline string — inline
  multi-line text is unreliable across environments (concrete form per the
  **[environment block]**).

## 4. Branch
- From an up-to-date base branch: `git switch -c <type>/<task-id>-<short-description>`.
- Never commit to the base branch. Never `git add .` — stage specific files only. (The
  **[guard]** enforces both deterministically where available.)
- **Isolated autonomous mode (§0.5):** instead of switching the main tree, **enter** the
  **[isolated workspace]** for this branch and run every later step inside it. Its end-of-run
  fate is driven by the §7 gate outcome, not a blanket teardown: **promote** it on a PASS,
  **discard** it on a FAIL (§8). Review mode uses the plain `git switch -c` above.

## 4.5 Plan artifact ([strong tier] and above — a checkpoint, not a gate)
Before the first file edit on a **[strong tier]** or **[frontier tier]** task (tagged, or
untagged-but-judged-strong per "Model & usage economy"), post a short plan as a comment on
the task's issue (multi-line body via a file, per the **[environment block]**; carrying
the **[comment marker]** per §2.5, like every engine-posted comment):
- **Approach** — a few sentences on the intended shape of the change.
- **Files to touch** — the expected list.
- **Test plan** — which tests will encode which acceptance criteria.
Then **proceed immediately. This is a checkpoint artifact, not an approval gate** —
autonomous runs do not pause on it and no reply is awaited. Its value: an alignment point
the owner can audit asynchronously; deterministic scaffolding that converges output shape
across models; and a durable recovery source for the resume protocol (the plan survives
context loss because it lives on the issue). **[cheap tier]** tasks skip it.

Next: [§5 Implement and §5.5 discovered work](05-implement.md)
