- **Refresh the thread before composing "your call"** (§2.5): re-read the issue/PR
  comment thread; act on any newer unmarked owner-login steering (within the §2.5
  authority bounds), do not re-ask a `Decision needed:` the owner already answered there,
  and quote/flag any provenance-ambiguous comment in the PR body per §2.5's ambiguity
  rule.
- **UI-touching task? The [visual verification] evidence attaches in the body's
  "your call" section** — screenshots/video per §6.5, embedded so they render on the PR
  itself (the owner judges the UI by looking at it, not by reading code). On the
  degradation path, the explicit **"tests only — no visual evidence produced"** statement
  goes in the same place, with the affected surfaces listed as unverified. The concrete
  attachment mechanism (how an image reaches the PR body from this environment) comes
  from the **[environment block]**.
- **Attach the gate's evidence.** Post each §7 reviewer's saved verdict report to the PR as
  a comment — one comment per reviewer, verbatim, **including PASS results**, each
  carrying the **[comment marker]** (§2.5) — using a file
  for each body (same file-based rules as the PR body). The verdicts must be readable on the PR
  itself, not only in the session transcript: that is what lets the post-PR review shrink to
  "read the verdicts, spot-check, merge".
- **Then update the PR body so the digest's live-verdict links resolve.** A comment URL
  exists only after the comment is posted, and a comment needs the PR — so the order is
  unavoidable: open the PR → post the per-reviewer verdict comments above → **update the
  body** to point each digest link at a live verdict (a JUSTIFY item, the verdict that
  graded a touched invariant, the verdict a focus area traces to) at its just-posted
  comment URL. The update edits **only the digest's link targets** in the body; the posted
  verdict comments stay byte-for-byte **unmodified** (AC3). Near-miss entries already
  quote/link the `fail_reports` text and are unaffected. (If the runtime cannot edit a body
  after creation, degrade loudly: state in the digest that the live-verdict links point to
  the per-reviewer comments **below on this PR** rather than to per-comment URLs, and say
  why — never leave a dangling link.)
- Capture the create command's output and print it; then verify the PR's state and checks
  (including the merge-gate status).
- Report the PR link and review/check status. Before reporting, audit each claim against a
  tool/command output from this session — report only what you can point to evidence for; if
  something is not yet verified, say so explicitly. **Do not merge** unless the user has
  explicitly authorized autonomous merging this session.
