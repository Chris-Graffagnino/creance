## 6. Verify (narrow → broad)
- Run the changed file's tests first, then the type-checker and linter.
- Run the full suite only once the diff is stable; log-and-summarize its output.

## 6.5 Definition of done
Engineering quality must be machine-verifiable, not taken on trust (see the profile's
**reviewer profile** — e.g. when the owner is not a developer, lean harder on this). A task is
not done until:
- **CI is green** — the profile's **required check**. A red check blocks merge via the
  profile's **merge-gate ruleset**. **Never bypass it.**
- **Behavioral changes ship tests** encoding the acceptance criteria AND every touched item
  from the profile's **invariant checklist**.
- **Constitution-critical files carry a scoped coverage threshold** per the profile's
  **coverage policy**, so coverage can't silently regress.
- **UI-touching tasks carry [visual verification] evidence.** Any task touching
  user-visible UI must attach machine-generated evidence of the running app to the PR —
  screenshots; video/animated capture for animation or transition work — produced by the
  runtime actually rendering the app, never described from the model's imagination
  (tests are code-shaped evidence; this is the evidence a non-developer owner can judge).
  The frame carries **fixtures only** — the evidence channel is typically public and
  permanent, so never real or imported user content or real locations; seed
  user-content-bearing screens with synthetic data first.
  If the runtime cannot produce it (tooling flake, headless run without a display/device),
  **degrade loudly, never silently**: the PR states **"tests only — no visual evidence
  produced"** and lists the affected surfaces as unverified — the flake surfaces as
  *unverified*; it neither blocks the pipeline nor passes silently.
- **The PR body separates "verified automatically" (engineering) from "your call"
  (product/values)** so a non-developer reviews only what they can judge. **Every claim
  under "verified automatically" must point to evidence from this run** — a command output,
  CI result, or reviewer verdict you can cite (reviewer verdicts are posted on the PR per
  §8, so the citation is checkable from the PR itself). Anything not actually verified goes
  under "your call" or is explicitly labeled unverified; never report it as done.
  Symmetrically, **every "your call" item ends with a one-line `Decision needed:` … /
  `Recommendation:` … pair** — purely-informational items state
  `Decision needed: none (informational)` — so the owner sees exactly what they are
  deciding instead of inferring it from an observation. A decision-ready item meets
  three further conditions, so a one-word reply is always enough to proceed:
  - **Exhaust autonomous work first.** Surface an item only when no autonomous work on
    it remains. If the engine can still narrow the question — run a test, check a doc,
    prepare the reversible default behind its seam (the §5 blocked-dependency instinct,
    generalized to decision items) — it does that first and surfaces the *narrowed*
    question, never a half-prepared one that forces the owner to do the analysis or
    bounce it back.
  - **Enumerate the exact choices and each one's consequence** (typically 2–3: the
    recommendation, the main alternative, and reject/defer), so the owner answers in a
    word instead of asking "what are my options?". Every offered choice must be fully
    answerable through the comment channel within §2.5's authority bounds — that valve
    is one-way, so **a merge/land is never an offered choice**. Where the natural intent
    is "ship it," the item states that answering applies the decision while merging still
    requires session authorization, so the one-word answer is always fully actionable and
    never partially obeyed. Purely-informational items keep the
    `Decision needed: none (informational)` form.
  - **Refresh the item's world-state immediately before surfacing it** — re-verify it is
    still live: not already resolved, and not made moot by a newer commit. (The
    thread-side half — already answered or settled on the issue/PR thread — is §2.5's
    "don't re-ask" and thread-refresh rules; this condition owns only the world-state
    half and does not restate them.)
