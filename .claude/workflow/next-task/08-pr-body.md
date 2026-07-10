## 8. Open the PR — then STOP
**Review mode (default)** runs the bullets below and stops at the PR for a human merge.
**Under an engaged isolated autonomous run (§0.5), the terminal step is driven by the §7 gate
outcome:**
- **Gate PASS → promote.** The work is preserved and opened as a PR through the bullets below
  (the *same* §7-gated path), then the **[isolated workspace]** is torn down. Promotion is a
  **PR, not a merge** — do **not** merge unless the user authorized autonomous merging this
  session (§2.5: merge authorization is session-explicit only).
- **Gate FAIL → discard.** The **[isolated workspace]** is **discarded** — torn down together
  with its branch — and **no PR is opened**. The base branch is untouched. (This is the one
  place an autonomous run diverges from review mode, which would surface a FAIL in a PR body;
  with no human in the loop there is no one to read it, so failed work is thrown away whole.)

Promotion is **only ever** the §7 gate's PASS; the isolation mechanism never writes the base
branch directly (P4). The numbered bullets below are the promote path (and all of review mode):

- Commit your work on the branch FIRST (the §7 reviewers review `git diff main..HEAD`, empty
  until you commit). Stage specific files; never `git add .`.
- Open the PR against the base branch, titled `<type>: [<task-id>] <description>`.
- **Lead the body with a risk-ranked digest of what the §7 gate found** — the human
  reviewer's entry point, placed **first**, ahead of "verified automatically" and "your
  call", so scarce review time targets the riskiest parts of the diff instead of
  re-deriving them from raw verdicts. The digest is composed **only** from the §7 gate's
  outputs — the **[reviewer]** verdicts posted on the PR (the per-reviewer comments below)
  and the gate-run record (`telemetry.md`) — **never** from maker self-assessment: every
  digest line **links to or quotes the verdict text it came from**, and a claim with no
  verdict source does not belong in the digest. In risk order it carries:
  - **Near-misses** — anything a reviewer **FAILed then cleared** after a fix this run,
    whether it ended **PASS or JUSTIFY** (a FAIL→JUSTIFY reviewer is a near-miss *and* a
    JUSTIFY item, listed under both — the FAIL report is the near-miss evidence, the final
    JUSTIFY is the documented deviation). The per-reviewer comment carries only the latest
    (PASS/JUSTIFY) verdict, so each near-miss instead quotes or links the verbatim FAIL
    report text retained in the gate-run record's `fail_reports` (`telemetry.md`; the
    telemetry record is US1's; §7.5). State the empty case explicitly (e.g. "none — the
    gate passed first try") rather than omitting it.
  - **JUSTIFY items** — every reviewer verdict of JUSTIFY **quoted verbatim**, with the
    documented deviation (a JUSTIFY clears the gate only with its deviation recorded here).
  - **Invariants the diff touched** — the profile's invariant-checklist items the change
    intersects, each pointing to the verdict that graded it.
  - **1–3 recommended human focus areas** — the riskiest spots for a human to read, each
    with a `file:line` reference and each tracing to one of the sources above (a near-miss,
    a JUSTIFY, or a touched invariant) — never a maker opinion no verdict backs.
  The digest **leads and links down to** the verbatim per-reviewer verdict comments
  ("Attach the gate's evidence" below), which remain on the PR **unmodified** — the digest
  summarizes and points; it never replaces, edits, or restates a verdict in place of it.
  A live-verdict comment link only resolves once that comment exists, so the digest's
  links to live verdicts are filled in by the body-update step below — composing the body
  before the comments are posted would leave them dangling. (A near-miss instead
  quotes/links the `fail_reports` text, which exists before the PR, so it needs no update.)
- **Pass the body via a file, never inline.** Inline bodies with embedded quotes/parens
  are unreliable across environments, and the temp `.md` must reach the CLI as UTF-8 —
  both concrete forms come from the **[environment block]**. The body must contain
  `Closes #<issue-number>`, a **"Discovered work"** line listing the issues filed under
  §5.5 (or "none"), a **"Mocked dependencies"** line whenever §5's blocked-dependency rule
  fired (which seam, the issue comment recording it, and — for each mocked seam — the `US#`
  acceptance criteria whose verification currently runs **against the mock rather than the
  real dependency**, listed as **live-unverified**; mock-verified is reported as
  mock-verified, never as done — the same degrade-loudly posture §6.5 applies to absent
  visual evidence, so the criterion neither blocks the pipeline nor passes silently), and a
  **"Run economics"** line — the tier, model, and effort that actually ran this task, plus
  any round-up/degradation applied (over time this is the evidence for re-tuning tier
  tags). Its **"verified automatically"** section cites the reviewer-verdict comments (next
  bullet) as its evidence for gate claims — never restated maker summaries — and carries
  the §5 red→green falsification evidence per new/changed test ("no tests changed" if none). Every **"your call"** item meets
  §6.5's decision-ready contract — the **Decision needed / Recommendation** pair, autonomous
  work exhausted, the exact comment-answerable choices enumerated (merge never among them;
  purely-informational items keep the `Decision needed: none (informational)` form, no
  choices), and the world-state refresh — composed alongside the §2.5 thread refresh below.
