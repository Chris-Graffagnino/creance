# Agent-assisted onboarding

Bring a fresh checkout of this template onto the Creance harness by handing the work to your
coding agent instead of doing it by hand. This file is a **self-contained prompt**: an agent
with no prior context can execute it cold.

It is the agent rendering of the [README Quickstart](../README.md#quickstart) — **the same
fills, in the same order, with the same verification.** The Quickstart is the human rendering;
this is the agent rendering. Its numbered steps are kept the same numbers as the Quickstart on
purpose. If the two ever disagree, that is a documentation bug — fix it, do not improvise.

## How to use it

1. Open this repository in your agent (Claude Code, or any agent that can read files and run
   `bash`, `git`, and `gh`).
2. Paste **everything below the horizontal rule** into the agent as your instruction.
3. Answer the agent's interview questions about your project — especially the constitution.
   Do not let it invent answers for you.

**Prerequisites** (same as the Quickstart): `git`, `gh` (authenticated), `bash` on PATH, and
`rg` (ripgrep). **Runtime caveat:** the verification step (step 7) assumes `rg` and `bash`
are available — they are the README prerequisites. On a runtime without them, install them
first or run the equivalent checks by hand; do not skip verification.

**Target shape.** A filled, fictional worked example of every artifact you will produce lives
in [`docs/examples/`](examples/) (the "Lantern" project). Copy the *shape*, never the
contents.

**Step map (this prompt ↔ Quickstart)** — kept identical on purpose; a drift is a doc bug:

| This prompt | README Quickstart |
|---|---|
| Prepare (read-only) | step 1 — template already obtained; here, confirm + read for shape |
| Open the first issue + branch | agent-only — the harness blocks base-branch edits |
| Step 2 — Fill the profile | step 2 |
| Step 3 — Interview the constitution | step 3 |
| Step 4 — Fill the specs tree | step 4 |
| Step 5 — Adapt the adapter mechanics | step 5 |
| Step 6 — Rewrite the environment block | step 6 |
| Step 7 — Verify, then open the PR | step 7 |

---

You are onboarding **this repository** onto the **Creance** harness — a tethered-autonomy
workflow engine for coding agents (one task → one issue → one branch → one PR, with an
adversarial maker ≠ checker review gate). The repo is a fresh, unfilled copy of the template.
Your job is to fill in every project-specific artifact, then prove the result with artifacts —
not with your own assurance.

Read [`README.md`](../README.md) and skim [`docs/examples/`](examples/) before you start, so
you know the target shape.

## Three rules that override your defaults

These fall out of the harness's own design. Follow them as instructions, not as suggestions.

### Rule 1 — Interview the constitution; never ghostwrite it
`memory/constitution.md` is the project owner's **law**. The constitution auditor enforces it
**adversarially on every PR** and FAILs any diff that violates a principle. Therefore:
- **Do not draft plausible-sounding principles for the owner to rubber-stamp.** If you write
  the constitution, the auditor ends up enforcing *your* values, not the owner's.
- **Elicit and transcribe.** Ask the owner what they would refuse to ship over. Get 3–7
  concrete principles in *their* words. For each, write the failure mode a reviewer can hunt
  for (see the Lantern example for the shape).
- **Warn the owner, in writing, that whatever lands here is enforced as law** — a vague
  principle cannot be enforced; a wrong one will block good work. Get their confirmation
  before you commit it.
- The same "do not invent" rule applies to project *facts* in the profile: derive what the
  repo already tells you, ask the owner for the rest, and never guess.

### Rule 2 — Onboard *through* the harness you are installing
The harness is already armed in this checkout: a guard blocks edits on the base branch, and
the rules require an issue before the first file edit. So run onboarding **as the project's
first issue → branch → PR** — do not edit on the base branch. The probe and grep outputs from
step 7 are this PR's "verified automatically" evidence. (Skip this and your first experience
of the harness is the guard vetoing your setup edits.)

### Rule 3 — End on artifacts, not on your say-so
"Setup complete" is never reported on your word. Step 7 runs the probes and the verification
greps; you report their **output**. Anything that cannot be answered or does not pass is an
explicit **open item** in the PR, not a silent pass. This is the README's "probe before you
trust," applied to onboarding itself.

## Steps

Do them in this order — **profile facts → constitution → specs → adapter mechanics → probes**
(it matches the Quickstart, and later fills reference earlier ones).

### Prepare (read-only — safe on the base branch)
- Confirm the prerequisites are present: `git`, `gh auth status`, `bash`, `rg`. **The step-7
  verification assumes `rg` and `bash`** — on a runtime without them, install them first or run
  the equivalent checks by hand; do not skip verification.
- Confirm this is a fresh template checkout (the artifacts below still hold `<...>`
  placeholders).
- Read `README.md` and the worked example in `docs/examples/` for the target shape.

### Open the first issue and cut the branch  *(Rule 2 — before any edit)*
- Open the onboarding issue, e.g. `chore: onboard <project> to the Creance harness`.
- Cut a branch off the base branch, e.g. `chore/<issue#>-onboarding`. **Make every edit below
  on this branch**, never on the base branch.

### Step 2 — Fill the profile (`.claude/PROJECT.md`)
- `cp .claude/PROJECT.template.md .claude/PROJECT.md`, then fill **every** `<...>`: identity
  and repo model, paths, task/branch conventions, blocked tasks, CI/merge gate, architecture
  boundaries, the invariant checklist, and the invariant→enforcement mapping.
- Shape: [`docs/examples/lantern/PROJECT.md`](examples/lantern/PROJECT.md).

### Step 3 — Interview the constitution (`memory/constitution.md`)  *(Rule 1)*
- Start from `memory/constitution.template.md`. Run the Rule 1 interview — elicit, do not
  ghostwrite — and transcribe the owner's principles, each with a huntable failure mode.
- Mirror each principle as a checkable rule in `.claude/PROJECT.md` → "Invariant checklist."
- Shape: [`docs/examples/lantern/constitution.md`](examples/lantern/constitution.md).

### Step 4 — Fill the specs tree (`specs/001-<feature>/`)
- Copy `specs/000-template/` to `specs/001-<feature>/`; rename `spec.template.md` → `spec.md`
  and `tasks.template.md` → `tasks.md`. **Keep the `.template.md` suffix on the originals** —
  it keeps the skeleton out of the engine's `specs/*/tasks.md` glob, so its placeholder tasks
  are never selectable.
- Fill the spec with `US#` acceptance criteria, a tier-tagged task backlog, the
  criterion-ownership mapping, and provider contracts if you have swappable seams.
- Shape: [`docs/examples/lantern/specs/001-guided-sessions/`](examples/lantern/specs/001-guided-sessions/).

### Step 5 — Adapt the adapter mechanics
- Fill the `<...>` placeholders in `AGENTS.md` (verification commands, architecture
  guardrails, etc.).
- Add your toolchain's commands to `.claude/settings.json` → `permissions.allow` (e.g.
  `Bash(npm test:*)`) and to `.github/workflows/ci.yml`.

### Step 6 — Rewrite the environment block (`.claude/skills/next-task/SKILL.md`)
- Rewrite the `[environment block]` ("This environment's concrete forms") for your OS/shell.
  The shipped one is a Windows PowerShell 5.1 worked example; a macOS/Linux translation to
  copy from is
  [`docs/examples/environment-block-macos-linux.md`](examples/environment-block-macos-linux.md).
- It must stay the **single** environment block — translate it in place; do not add a second.

### Step 7 — Verify on artifacts, then open the PR  *(Rule 3)*
Run all of these and capture their output:
- **Conformance probes** — instantiate and run every probe in
  [`.claude/adapters/claude-code-probes.md`](../.claude/adapters/claude-code-probes.md) for
  this fresh repo. Treat the harness as untrusted until they pass.
- **`.claude/EXTRACTION.md` §5 checks** — run **every** check in
  [`.claude/EXTRACTION.md` §5](../.claude/EXTRACTION.md) (the model-vocabulary,
  environment-block, and skill-invocation neutrality greps, plus
  `bash .claude/hooks/guard.test.sh`). They prove the engine/profile split still holds and the
  guard is wired, not just present. Run the greps as written there — they are the source of
  truth, so this prompt points at them rather than copying them.
- **Residual-placeholder grep** — confirm no canonical fill markers remain in the artifacts
  you filled:
  ```
  rg -n '<\.\.\.>|<PROJECT NAME>' AGENTS.md .claude/PROJECT.md memory/constitution.md specs/ -g '!*.template.md' -g '!specs/000-template/**'
  ```
  A clean (empty) run means the two canonical markers (`<...>`, `<PROJECT NAME>`) are gone
  from the files onboarding fills. The skeleton templates (`*.template.md`,
  `specs/000-template/`) keep their placeholders by design and are excluded, and the scope is
  the fill targets only — so engine docs that merely *mention* `<...>` do not pollute the
  result. This narrow pattern is a first net, not a complete one: also eyeball each filled
  file against its `docs/examples/lantern/` counterpart for any remaining
  `<descriptive placeholder>` (e.g. `<one-line description>`, `<language / framework>`) the
  pattern does not catch. Format notation that legitimately stays — `<task-id>`, `<type>`,
  `<triage inbox dir>` — is expected and is not a residual.

Then commit your work and open the PR against the base branch:
- **Commit the filled artifacts first.** `git add` the specific files you filled (the profile,
  constitution, specs tree, `AGENTS.md`, `.claude/settings.json`, the CI workflow, the
  environment block) and commit them on your onboarding branch — use `git add <files>`, never
  `git add .`. Without commits the branch has nothing to open a PR from, and you are left with
  an orphaned onboarding issue.
- Title it per your filled convention (e.g. `chore: onboard <project> …`); pass the body via a
  file or heredoc, never literal `\n`.
- The body **must** carry the fields `AGENTS.md` requires: `Closes #<issue-number>` for the
  onboarding issue you opened above, and a **`Discovered work`** line naming any issues you
  filed (or "none").
- Put the probe results and the grep / `guard.test.sh` output under **"verified
  automatically."**
- List **anything** that could not be run, did not pass, or you could not answer (an
  unprovisioned probe, a failing grep, a constitution principle the owner has not confirmed)
  as an explicit **open item** under **"your call."** Do not report onboarding complete on
  your own assurance.
- **Stop at the PR.** Do not merge — the owner reviews and merges.
