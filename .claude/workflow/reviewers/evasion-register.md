# Evasion register — the cumulative cheat museum the auditors consult (runtime-neutral)

A standing, append-only catalog of **observed gate evasions** — the concrete ways a maker
has satisfied a gate without doing the real work — paired with the **fence** that closed
each. Every adversarial **[reviewer]** consults it at dispatch as an explicit *"have you
checked these known patterns?"* checklist.

Why a register of worked exhibits, and not just sharper prose in each auditor spec: an
abstracted rule ("hunt for weak tests") helps the next reviewer marginally; a worked
exhibit — *here is the real escape that looked like this, here is the fence that closed
it* — helps much more, because the next escape rhymes with the last. It is also the one
place **all** auditors share a view, so a pattern one dimension caught is not re-learned
the hard way by another.

This is a **runtime-neutral** reviewer artifact: it names capabilities as bracketed
**[roles]** and cites `file:line` exemplars only — never a concrete runtime mechanism.
Project facts and the invariant checklist live in `.claude/PROJECT.md`; the constitution it
names is law.

## How the auditors use it (dispatch-time checklist)

- **Before hunting, scan the exhibits.** For each, ask: *does this diff exhibit this
  pattern?* The exhibits sharpen the hunt the auditor already runs; they do not replace its
  rubric (the acceptance criteria / the invariant checklist / the provider contracts).
- **When a finding matches an exhibit, cite the `EV-NN` id as the evidence anchor** in the
  verdict, next to the `file:line`. That ties the catch to the catalogued pattern and its
  fence, so a reader can see *which known escape* this diff re-ran — and the register's
  value is provable, not asserted.
- **The register informs; it never decides.** An exhibit never changes a gate outcome, a
  model tier, or gate semantics (round limits, veto authority, tier floors). It is an
  observation aid for the [reviewer]; the [reviewer] still grades (constitution **P5**).

## How it grows (write posture — P4)

- **Append-only, via the retrospective's propose-via-PR flow only.** On a **HUNT-RULE-GAP**
  or **INVARIANT-GAP** outcome, the retrospective's proposed PR adds the new exhibit here
  *alongside* the hunt-rule tightening or invariant row it already proposes
  (`retrospective.md` §5). A new escape becomes a new exhibit; the catalogue grows one
  incident at a time, never as a retroactive sweep.
- **Never written silently.** The register is rule-shaped, so it joins the **protected
  reviewer-spec set** the constitution's *no-silent-self-modification* principle guards
  (**P4**): every append travels issue → branch → §7 gate → PR, and the owner merges to
  apply. No gate run, prompt auto-tune, or automation edits it directly.
- **Mechanizable exhibits graduate into lints.** Where a fence can be a deterministic check,
  the exhibit names that check and the **Mechanization status** table below tracks which have
  graduated and which remain judgment-only — mirroring `.claude/PROJECT.md`'s
  invariant → enforcement table (**P3**). An exhibit that becomes fully mechanized stays in
  the register as provenance, with its lint named.

## Exhibit format

Each exhibit carries: **EV-NN — title** · **Observed** (what the gamed diff looked like) ·
**Fence** (the rule that FAILs it, with `file:line`) · **Exemplar** (the real escape, or a
*spec-derived seed* where no escape is yet logged) · **Mechanized** (the deterministic lint
it graduated into, or *judgment-only*).

## The exhibits

### EV-01 — Skipped test passed off as encoding
- **Observed:** the test that would encode a criterion exists but is skipped / pending /
  disabled, so the suite is green while the criterion's behavior is never asserted.
- **Fence:** the acceptance **[reviewer]**'s hard-FAIL rule — skipped tests do **not** count
  as an encoding test; any owned criterion without a *live* encoding test is an overall FAIL
  (`reviewers/spec-auditor.md` → "The hard-FAIL rule").
- **Exemplar:** spec-derived seed (the pattern the hard-FAIL rule already names); no logged
  Creance escape yet.
- **Mechanized:** judgment-only — the [reviewer] must read the test body; a green suite
  cannot reveal a skipped assertion.

### EV-02 — Assertion-free test
- **Observed:** a test exercises the changed path but asserts nothing meaningful (or only
  that it ran without throwing), so the suite is green with no behavior pinned.
- **Fence:** the hard-FAIL rule — "tests with no meaningful assertion" do **not** count as
  encoding (`reviewers/spec-auditor.md` → "The hard-FAIL rule").
- **Exemplar:** spec-derived seed.
- **Mechanized:** judgment-only.

### EV-03 — Loose assertion (matches anywhere, not the criterion's locus)
- **Observed:** a test asserts a needle exists *somewhere* in the artifact (whole file,
  whole row) rather than at the specific locus the criterion governs, so it stays green even
  when the real content is missing or misplaced.
- **Fence:** the hard-FAIL rule — "tests asserting something other than the criterion" do
  **not** count; the assertion must pin the criterion's stated locus
  (`reviewers/spec-auditor.md` → "The hard-FAIL rule").
- **Exemplar:** **real escape.** A probe-fingerprint encoding test asserted a fingerprint
  appeared *anywhere in a probe-result row*, passing even when the per-row Fingerprint
  *cell* was empty; tightened to grep the row's results section (`5bb6186`), then to validate
  the specific column cell (`9a1e94e`) — fence now at
  `.claude/hooks/probe-fingerprint-docs.test.sh:119`.
- **Mechanized:** partial — the fence is itself a deterministic per-cell assertion, but
  recognizing *loose-assertion* in a newly written test is judgment-only.

### EV-04 — Green suite cited as proof of coverage
- **Observed:** the maker offers "all tests pass" as evidence a criterion is met, when the
  suite is green precisely *because* the asserting test is absent.
- **Fence:** the acceptance **[reviewer]** must not accept a green suite as proof — it finds
  the *encoding test* for each criterion and reads its body, never trusting the aggregate
  (`reviewers/spec-auditor.md` → "How to hunt").
- **Exemplar:** spec-derived seed.
- **Mechanized:** judgment-only.

### EV-05 — Artifact created but never wired in
- **Observed:** a file, registry entry, or test the task names exists in the diff, but
  nothing imports, registers, or reaches it — dead on arrival, satisfying a "does X exist?"
  check without doing X's work.
- **Fence:** the acceptance **[reviewer]**'s Completeness check — "confirm it exists and is
  wired in (imported / registered / reachable), not just created"
  (`reviewers/spec-auditor.md` → "How to hunt"). For a test or check, *wired in* means it
  runs in the project's required check, not merely that the file is present.
- **Exemplar:** **real escape (class).** Hand-run tests sat outside the required check until
  their run was wired in — the "silently dead machinery" class: present, plausible, never
  executed (`.claude/DESIGN-NOTES.md` → "The guard was silently dead").
- **Mechanized:** partial — where *wired in* is an enumerable list (a required-check step
  set), a drift backstop can enforce it (the roster pattern, **EV-08**); recognizing an
  unwired artifact in general is judgment-only.

### EV-06 — Silently dead guard (behavior changed, test or wiring not)
- **Observed:** enforcement machinery's behavior changes but no matching guard-test case
  ships, **or** the event → guard wiring drifts so the guard never fires though its decision
  logic is still correct — the gate *looks* enforced but is not.
- **Fence:** constitution **P2** and the invariant "Guard behavior changed without a matching
  guard-test case, or wiring drift the wiring assertion would miss — FAIL"; the constitution
  **[reviewer]** FAILs a diff that touches the guard's decision logic without a matching
  guard-test case (`.claude/PROJECT.md` → "Invariant checklist";
  `reviewers/constitution-auditor.md` → "How to hunt").
- **Exemplar:** **real escape.** The event → guard matcher went silently dead while the
  guard's decision logic stayed correct, and the change "sailed through CI" with the guard
  never firing (`.claude/DESIGN-NOTES.md` → "The guard was silently dead", line 68). Fence
  now deterministic: the wiring assertion in `.claude/hooks/guard.test.sh`, run in the
  required check.
- **Mechanized:** **yes** — `guard.test.sh` (including its matcher-wiring assertion) in the
  required check.

### EV-07 — Measurement channel gains control authority
- **Observed:** telemetry, evaluation, or retrospective records — append-only *observations*
  — are read into a path that changes a gate outcome, a model-tier assignment, or gate
  semantics (round limits, veto authority, tier floors).
- **Fence:** constitution **P5** and the invariant "a change that lets telemetry or
  evaluation records influence gate outcomes, model-tier assignment, or gate semantics —
  FAIL"; the retrospective *reads* telemetry as evidence only and gains no control authority
  by reading it (`.claude/PROJECT.md` → "Invariant checklist"; `retrospective.md` §4 "Write
  posture").
- **Exemplar:** spec-derived seed — and the register itself is bound by this fence: it
  informs auditors, it never auto-tunes them.
- **Mechanized:** judgment-only.

### EV-08 — Restated rule drifts across copies
- **Observed:** one rule is duplicated across several sites; one copy is edited and the
  others silently diverge, so a check reads as enforced from one copy while another has gone
  stale — a self-inflicted variant of the silently-dead class.
- **Fence:** collapse the rule to one declarative source plus a deterministic drift backstop
  that FAILs when the copies disagree (`gate-loop.md` → "The reviewer roster (single source
  of truth)", line 45).
- **Exemplar:** **real escape (class).** The §7 reviewer set lived hand-synced in three
  places until it was collapsed to one roster table guarded by a drift test that asserts the
  sites agree (`.claude/hooks/reviewer-roster.test.sh`).
- **Mechanized:** **yes** where the copies are enumerable — the roster drift test; otherwise
  judgment-only.

### EV-09 — Vendor leaked across an interface
- **Observed:** a vendor SDK import, API URL, vendor-specific type, or error shape is
  reachable from UI / component code, or leaks into a public surface, instead of going
  through the named interface — breaking provider-swappability.
- **Fence:** the contract **[reviewer]**'s interface-boundary and swappability checks — a
  vendor name reachable from a component, or a leaked vendor-specific type / option, is a
  FAIL (`reviewers/contract-auditor.md` → "How to hunt").
- **Exemplar:** spec-derived seed — this repo declares no vendor seam yet, so the fence is
  pre-positioned for the first one added.
- **Mechanized:** judgment-only (no banned-vendor seam to lint in this repo today).

## Mechanization status (mirrors `.claude/PROJECT.md` → invariant → enforcement)

| Exhibit | Owning auditor dimension | Deterministic backstop |
|---|---|---|
| EV-01 skipped-test | acceptance (test encoding) | judgment-only |
| EV-02 assertion-free test | acceptance (test encoding) | judgment-only |
| EV-03 loose assertion | acceptance (test encoding) | partial — per-cell assertion fences exist; new-test recognition judgment-only |
| EV-04 green-suite-as-proof | acceptance (test encoding) | judgment-only |
| EV-05 unwired artifact | acceptance (completeness) | partial — drift backstop where the wiring is enumerable |
| EV-06 silently dead guard | constitution (P2) | yes — `guard.test.sh` wiring assertion in the required check |
| EV-07 measurement gains control | constitution (P5) | judgment-only |
| EV-08 restated-rule drift | constitution / contract (P2/P3) | yes (enumerable copies) — `reviewer-roster.test.sh` |
| EV-09 vendor leak | contract (swappability) | judgment-only |
