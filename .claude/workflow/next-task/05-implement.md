## 5. Implement (minimum scoped change)
- Before the first edit, define success criteria and the smallest safe verification path. Keep changes surgical; every line traces to the task. No speculative abstraction.
- Respect the profile's **"Architecture boundaries"**: route each capability only through its
  named interface (never a vendor SDK from UI/component code), and never use a banned
  vendor/source listed there.
- For behavior changes, add/update meaningful tests incl. negative/edge cases.
- **Falsify every new/changed test:** it counts only if shown to **fail on incorrect
  output** (mutate or withhold the behavior, confirm it goes red, and **keep that red
  run's output — the PR body cites it as evidence, §8**) AND it asserts **per-instance /
  per-row behavior, never a single match anywhere in the artifact** — forbidden vacuous
  shapes: a **prefix-only match**, a **single-fingerprint-anywhere match**. Maker-side
  only; the acceptance **[reviewer]**'s §7 hard-FAIL on vacuous assertions
  (`workflow/reviewers/spec-auditor.md`) is the unchanged backstop.
- **Blocked by an external dependency? Mock it behind the seam — never abort.** When
  progress is blocked by something outside the repo (a provider API key, an unprovisioned
  service, an owner-only credential, an unreleased upstream), do all four:
  1. scaffold a **documented mock behind the existing interface seam** — the named
     interface from the profile's "Architecture boundaries", never inline in callers;
  2. record the blockage and the mock's location as a comment on the issue (marked, per
     §2.5);
  3. continue the task against the mock;
  4. list it in the PR body under **"Mocked dependencies"** (§8).
  Swappability is preserved by construction — the real provider later replaces the mock
  without touching callers. (Distinct from the profile's *blocked/owner-only task list*:
  those tasks are never started at all, per §1; this rule is for a task already legitimately
  underway that hits an external wall.)

## 5.5 Discovered work (file it, don't fix it)
Implementing one task often uncovers others — a bug, a missing test, a stale doc, a security
risk. Capture these durably WITHOUT widening the current diff. Classify each finding at the
moment of discovery:
- **Blocks this task?** If it prevents meeting the task's acceptance criteria, it is part of
  the task: record it on the issue and handle it in scope (or stop and surface it if it
  reshapes the task).
- **Concrete, actionable, out of scope?** Search the tracker for an existing issue first (no
  duplicates), and if none exists **file one now** — title per the issue convention, body
  self-contained (file/line evidence, enough context for a cold start) plus a "Discovered
  while working #N" line. When the bug's origin is traceable with bounded effort
  (`git log -S`/`-G`, `git blame`, linked PRs), add a one-line **provenance** note —
  `introduced by` / `made visible by` / `carried forward by` `<commit/PR>` — with an
  explicit confidence label: `clear`, `likely`, or `unknown`. **Say `unknown` rather than
  guessing**, consistent with §6.5's anti-fabrication posture (never report an unverified
  claim as established). Provenance is best-effort and **never a filing blocker** — an
  untraceable bug is filed with `provenance: unknown`, not held back. Filing at discovery
  time beats reconstructing from memory at PR time.
- **Vague hunch or trivial nit?** Note it in the PR body under "Out of scope, observed";
  don't spam the tracker.
- **Constitution or security finding already on the base branch?** Never optional: file it
  AND flag it prominently in the PR body.
The PR body (§8) lists what was filed under **"Discovered work"** (or "none"). The triage
[workflow] resurfaces open issues without a branch/PR every run, so a filed issue cannot be
lost — no human dispatch needed.

Next: [§6 Verify and §6.5 definition of done](06-verify.md)
