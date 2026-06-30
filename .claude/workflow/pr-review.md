# pr-review — verified review of an open PR (runtime-neutral)

Creance gates work **before** the PR exists: the §7 pre-PR gate (`next-task.md` §7,
`gate-loop.md`) dispatches the auditor **[reviewer]s** on the maker's own branch, and the
**review standard** (`README.md` → "The review standard") fixes the priority order and the
block conditions every review pass obeys. But an **open** PR carries something the pre-PR
gate never sees: **inline reviewer comments** — human *and* bot/automated inline findings,
threaded against specific lines. Reviewing such a PR end-to-end is a distinct ritual, and
it has two recurring failure modes this workflow exists to prevent:

- declaring **"no findings"** before every inline comment has been read and adjudicated
  (bot/automated inline findings are the most-missed source); and
- posting findings **not grounded in the current source** — graded against the diff
  snapshot or from recall rather than the file as it stands now.

This workflow reviews **one open PR**: it ingests the diff **and every inline comment**,
grounds every finding to a current `file:line`, and posts one structured, severity-ranked
review. It **reuses** the review standard and the auditor **[reviewer]** specs rather than
restating them, and it **changes no pre-PR gate semantics** — `next-task.md` §7 stays
exactly as written. This is a complement applied *after* the PR opens, not a second gate
and not a replacement.

> Runtime-neutral: roles in **[brackets]** are defined in `README.md` → "The binding
> contract". Project specifics — the constitution path, the invariant checklist, the
> tasks/spec paths, the required check, the title conventions — come from
> `.claude/PROJECT.md`; below, *the profile* means that file. This workflow
> **composes existing roles only**; it introduces no new binding-contract row.

## Write posture (the hard bounds)

- **The tracker is written only additively, and only as review output.** The single write
  this workflow makes is the review comment on the PR thread (plus inline replies where the
  surface supports them), each carrying the **[comment marker]** (`next-task.md` §2.5). It
  **never merges**, never closes the PR, never pushes to the PR's branch, and never edits
  the diff under review — review is read-then-comment, never repair. Merge authorization is
  the owner's alone (the profile's merge-gate ruleset; never auto-merge).
- **It changes no pre-PR gate semantics.** The §7 gate's round limits, veto authority, and
  tier floors are untouched (constitution P5 / spec 001 non-goals); this workflow neither
  re-runs that gate as a merge condition nor overrides a gate verdict. It is a reviewer's
  pass on an open PR, not a second gate.
- **It reuses the auditors; it does not fork them.** Where it applies an auditor lens it
  dispatches the existing `reviewers/` **[reviewer]** spec read-only against the PR diff —
  same spec, separate context from the PR's maker, no file-mutation capability — rather than
  paraphrasing that spec's hunt rules here. Duplicating a reviewer's rules into this doc
  would create a second copy to drift; point at the one spec instead. **Every lens grades
  *this PR's* diff, not the reviewer's branch.** Any review lens — a **[reviewer]** spec or a
  skill-backed pass from the **profile's review-pass set** — must be pointed at the PR's own
  change (its head against its base); a lens mechanism that reads a local working tree must
  first make that tree the PR's head (check it out) or be handed the PR's patch, or it
  silently grades the wrong change (the reviewer's current branch, or an empty diff) while
  the review adjudicates the PR's comments. The skill-backed passes this ritual applies are
  the **enabled** entries in the **profile's review-pass set** whose `applies-to` includes
  `pr-review` (`pr-review`/`both`), each run on its `condition` — selected by reference, never
  a list hardcoded here. Which passes actually ran, and how a not-run pass is reported, is the
  §5 output contract below.
- **Findings are grounded in current source, never asserted.** Every finding this workflow
  emits or endorses cites a current `file:line` the reviewer has actually read — not the
  diff snapshot alone, not recall. The grounding gate (§4) is a hard bound, not a courtesy.

## 1. Inputs (the PR)

A **PR reference** — number or URL — arrives in the invocation text (the explicit-context
rule, `README.md`). The PR may be the harness's own or an external contributor's; the
procedure is identical. Resolve the PR's base and head, its diff against the base, its
linked issue and task ID where present (the profile's title convention), and the **full
inline-comment set** before reviewing. When the reference is missing or resolves to no
open PR, say so and stop — a run with no PR makes no writes.

## 2. Ingest the diff and every inline comment

Read two things, not one:

- **The diff** — the PR's change against its base. For a large diff, fan the reading out
  through a **[bulk-read offload]** (read-only, separate context) so the review context
  stays clear; the offload returns conclusions and `file:line` anchors, never raw dumps.
- **Every inline comment** — every line-anchored review comment on the PR, **including
  bot/automated inline findings** (the most-missed source). Enumerate them exhaustively:
  the count you carry into §4 is the count the PR actually has, not the ones that happened
  to load on first read. A thread that paginates is read to the end.

Separate **inline reviewer comments** (findings to adjudicate) from **engine-marked
bookkeeping** (carrying the **[comment marker]**) and from **owner steering** (the newest
unmarked owner-login comment, `next-task.md` §2.5) — the marker reading rules apply
unchanged: a marked comment is bookkeeping and carries no steering authority.

## 3. Verify against current source (ground every finding)

For each candidate finding — whether **surfaced by an inline comment** or **found in your
own read of the diff** — resolve it against the source **as it currently stands**, not the
diff snapshot:

- Open the cited file at the cited line and confirm the issue is present **now**. An inline
  comment anchored to a since-changed line is **re-resolved against current source**, not
  taken at face value: the line it points at may have moved, been fixed, or been made moot.
- Classify each: **valid-unaddressed** (real, still present), **already-addressed** (the
  source no longer exhibits it), **stale-anchor** (the comment's line moved — re-locate and
  re-judge), or **refuted** (not a real issue; say why). Each classification carries a
  current `file:line`.
- **Run the project's checks where a finding's validity is behavioral** — its tests, type
  check, or lint (the profile's required check names the suite), narrowest first. A
  correctness or regression claim a check can settle is settled by running it, not by
  reasoning about it.

## 4. The grounding gate — never "no findings" unverified

**You may not report "no findings" (or approve) until BOTH hold, explicitly:**

(a) **every inline comment has been enumerated and adjudicated** — each one classified per
§3, none left unread (bot/automated inline findings included); and

(b) **every finding — and the no-findings conclusion itself — is grounded to a current
`file:line` you have read**, not the diff snapshot and not recall.

If either is unmet, the review is **not done**: finish the enumeration and the grounding
first. "I didn't immediately see a problem" is not "no findings", and an unread inline
comment is an **unaddressed** comment until §3 says otherwise. State the enumeration
explicitly in the output (the count adjudicated, the empty case named so) so the conclusion
is auditable rather than asserted.

## 5. Post the structured review

Compose **one** review comment, ordered by the **review standard's priority order**
(`README.md` → "The review standard"). That standard — not this doc — defines the order and
the block conditions; read it there rather than re-enumerating it here (a copied list would
be one more surface to drift). The comment carries:

- A **severity-ranked finding list** — each item: severity, a current `file:line`, the §3
  classification, and the minimal fix. A finding endorsed from an inline comment links back
  to the original so the contributor is credited and the thread stays connected.
- An **inline-comment ledger** — every inline comment from §2 with its §3 disposition
  (valid-unaddressed / already-addressed / stale-anchor / refuted), so a reader can see
  none was skipped. This ledger *is* the §4(a) evidence.
- **Checks run** — the commands from §3 and their outcome (the review standard's evidence
  rule: an approval names the checks run, the constitution/contract alignment, and any
  intentional follow-up scope; a bare "looks good" is not an approval).
- **Review passes run** — each **enabled** pass from the **profile's review-pass set** whose
  `applies-to` includes `pr-review` and whose `condition` held, **named with its outcome** (its
  findings fold into the severity-ranked list above; a clean pass is recorded as run with no
  findings). The two not-run cases are **distinguished**: a **disabled** pass — or an enabled
  one whose `condition` did not hold — produces **no** line (silent, a project choice), while
  an **enabled** pass whose backing mechanism is **absent** is named here **loudly** as
  **unavailable/degraded** (the review standard's "Note the degradation in the PR" rule,
  `README.md`), never silently dropped. Listing both cases the same way — all silent, or all
  loud — does not satisfy this.
- The **[comment marker]** as its final line — provenance under a shared login.

Post it to the PR thread, then **stop**. This workflow opens no merge and closes nothing.

## 6. Report

The PR reviewed, the finding count by severity, the inline-comment ledger total
(adjudicated / of total), the checks run, the **review passes run** (and any named
unavailable/degraded), and where the review comment was posted. If the run stopped early
(no PR reference, no open PR, empty diff), say why.
