# Extracting `.claude/` into a standalone harness repo

> **Provenance:** this is the carried copy (§4 step 8) inside the extracted template —
> originally written in the source project (`bird-journal-ai`, cut at `ff16689`,
> 2026-06-12). In this repo it is live documentation, not history: §2's cut-list explains
> which files are engine vs. profile, §5 is the standing conformance check after any
> harness change, and the full procedure is the playbook for the *next* extraction or
> runtime port.

**Read this first** if your job is to lift this workflow harness out of `bird-journal-ai`
into its own repository. It is the manifest the source repo's own docs don't provide: which
files are the engine, which are stained with project facts, what the engine depends on
*outside* this folder, and the order to decouple them. The *why* behind the load-bearing
decisions is in [`DESIGN-NOTES.md`](DESIGN-NOTES.md) — read that too before you "simplify"
anything, because several things that look like cruft are scar tissue from real failures.

> **Target shape: a template repo.** The deliverable is a standalone repo you start a new
> project from ("Use this template" / clone-and-fill) — *not* an installer or a submodule.
> It ships the engine + the Claude Code adapter + a fill-in-the-blanks profile + empty
> skeletons for the project-specific inputs (constitution, specs). A fresh project clones
> it, fills `PROJECT.md` + `memory/constitution.md` + `specs/`, and runs.

The source repo already documents the *concept* of this split well — read these two first,
they are 70% of the mental model and you reuse them verbatim:
- [`.claude/README.md`](README.md) → "Reuse on a new project" and "Adding a new adapter".
- [`.claude/workflow/README.md`](workflow/README.md) → "The binding contract" (the roles)
  and "How an adapter degrades gracefully".

This file is the missing 30%: the concrete cut-list and the extraction procedure.

---

## 1. The architecture in one breath

Three layers, each independently swappable (full table in `README.md`):

- **Methodology** (`workflow/**`) — runtime-neutral engine logic written against abstract
  **[roles]** in brackets. Names no tools, vendors, or models. **Reused unchanged.**
- **Adapter** (`skills/`, `agents/`, `hooks/`, `workflows/`, `settings.json`, `MODELS.md`)
  — maps each [role] to a concrete Claude Code mechanism. **Reused; genericize two files
  (see §3).**
- **Profile** (`PROJECT.md` + the project's `constitution.md` + `specs/`) — all
  project-specific facts. **Replaced by templates/skeletons.**

The whole design is falsifiable with one grep (see §5): `workflow/**` must contain **no**
mechanism, vendor, or model names — only `[role]` references.

---

## 2. The cut-list — every tracked file in `.claude/`

47 tracked files. Categories: **KEEP** (generic, copy verbatim) · **GENERICIZE** (reused
but carries a project/toolchain assumption to strip) · **RESET** (replace contents with a
fresh/blank instantiation) · **TEMPLATE** (the project-specific input — ship the
`.template` form only).

> **The table below itemizes the load-bearing dispositions, not yet all 47 files.** Surfaces
> added since the original cut — the `intake`/`pr-review`/`retrospective`/`telemetry`
> workflow docs + their skill bindings, the `hooks/*-docs.test.sh` encoding backstops +
> `check-tasks-consistency.{sh,test.sh}` + `gate-loop.test.js` — are not yet each listed; the
> category rules still apply (a neutral `workflow/**` doc or skill binding → **KEEP**; a
> `hooks/*-docs.test.sh` → **KEEP**, unless it asserts instance-specific content → then
> **GENERICIZE** it in lockstep with that content, as with the evasion-register pair below).
> Full per-file refresh + a deterministic completeness backstop tracked in **#90**.

| File | Category | Action |
|---|---|---|
| `workflow/README.md` | KEEP | The binding contract — the spine. Verbatim. |
| `workflow/next-task.md` | KEEP | Per-task loop. Verbatim. |
| `workflow/triage.md` | KEEP | Read-only heartbeat. Verbatim. |
| `workflow/constitution-check.md` | KEEP | Pre-PR compliance gate. Verbatim. |
| `workflow/gate-loop.md` | KEEP | §7 gate as pseudocode. Verbatim. |
| `workflow/conformance-probes.md` | KEEP | Neutral probe checklist. Verbatim. |
| `workflow/reviewers/spec-auditor.md` | KEEP | Acceptance reviewer spec. Verbatim. |
| `workflow/reviewers/constitution-auditor.md` | KEEP | Values reviewer spec. Verbatim. |
| `workflow/reviewers/contract-auditor.md` | KEEP | Architecture reviewer spec. Verbatim. |
| `skills/next-task/SKILL.md` | KEEP | Adapter binding + the **single [environment block]** (OS/shell/CLI concrete forms live here and nowhere else). Verbatim — but see §3 note on the env block's bash+PowerShell assumption. |
| `skills/triage/SKILL.md` | KEEP | Adapter binding. Verbatim. |
| `skills/constitution-check/SKILL.md` | KEEP | Adapter binding. Verbatim. |
| `agents/spec-auditor.md` | KEEP | Subagent (no edit tools, no model pin). Verbatim. |
| `agents/constitution-auditor.md` | KEEP | Subagent. Verbatim. |
| `agents/contract-auditor.md` | KEEP | Subagent. Verbatim. |
| `hooks/guard.sh` | KEEP | Deterministic [guard] implementation. Verbatim. |
| `hooks/guard.test.sh` | KEEP | Guard tests incl. the matcher-wiring assertion. Verbatim. |
| `workflows/gate-loop.js` | KEEP | [orchestrated run] adapter script. Verbatim. |
| `adapters/codex-cli.md` | KEEP | Second-adapter spec/stub — a worked example of porting to a non-Claude runtime. Keep as reference. |
| `adapters/codex-cli-dry-run.md` | KEEP | Its dry-run walkthrough. Keep as reference. |
| `README.md` | GENERICIZE | The adapter-layer doc is generic, but its "Reuse on a new project" steps reference `specs/001-bird-journal/` and bird-journal examples. Strip the project name; keep the structure. |
| `settings.json` | GENERICIZE | The `permissions.allow` list hardcodes a JS/React-Native toolchain (`npm`, `npx jest`, `npx tsc`, `npx prettier`). The git/`gh` rules and the **`hooks.PreToolUse` block are generic and load-bearing — keep them exactly** (the matcher must keep `Agent|Task`; see DESIGN-NOTES §"the guard was silently dead"). Replace the toolchain rules with a placeholder + a comment. |
| `MODELS.md` | GENERICIZE | The adapter's only model-naming file. The *semantics* section is generic; the actual model rows (`fable`/`opus`/`sonnet`/`haiku`) are this environment's choices. Keep the table shape; leave the rows as a sensible default with a "swap per your account" note. |
| `PROJECT.md` | TEMPLATE | Pure bird-journal facts. **Do not ship it.** Ship `PROJECT.template.md` as the only profile (it already exists and is complete). |
| `PROJECT.template.md` | TEMPLATE | The fill-in-the-blanks profile. **This is the profile the template repo ships.** Keep. |
| `adapters/claude-code-probes.md` | RESET | Carries this repo's **dated probe *results*** (the 2026-06-11 run that caught two live failures) — and the *instantiation table* (top half) is not clean either: its rows name this environment's concretes (the `BirdJournal-TriageHeartbeat` scheduler task, `triage-heartbeat.ps1`, Windows Task Scheduler steps). Reset **both halves**: drop the dated results (or move them into DESIGN-NOTES as the worked example) and genericize the instantiation rows' environment concretes to placeholders (`<scheduler-task>`, `<launcher-script>`) so a fresh project's probe run validates *its* launcher setup, not bird-journal's. End state: "instantiated, NOT yet executed — run before trusting". |
| `workflow/reviewers/evasion-register.md` | GENERICIZE | The cumulative cheat-museum. Its **universal pattern exhibits** (the spec-derived ones — test-gaming, green-suite, vendor-leak, measurement-gains-control) are engine-level and ship verbatim. Its **real-escape exhibits** (EV-03/06/08) hardcode *this repo's* commit SHAs (`5bb6186`…) and instance test-file paths (`probe-fingerprint-docs.test.sh:119`, `reviewer-roster.test.sh`) — project facts (the one documented engine-file exception, `PROJECT.md` → "Architecture boundaries"). On extraction, **reset the real-escape exhibits to the "spec-derived seed (no escape logged yet)" form** (or move them into DESIGN-NOTES as the worked example, like `claude-code-probes.md`); keep the universal patterns + the mechanization-status scaffold. A fresh project's retrospective grows its own exemplars per incident. |
| `hooks/evasion-register-docs.test.sh` | GENERICIZE | Structural + runtime-neutrality backstop for the register — **KEEP** its structural / neutrality / DW2–DW4 / extraction-hygiene checks. It also asserts the **instance** real-escape exemplar strings (the DW1 "real escape with `file:line`" check). Drop **only those** instance-coupled assertions in lockstep when the register's real-escape exhibits are reset above, so the extracted test matches the genericized register. |

**Gitignored — never travel** (machine-local; confirm your template `.gitignore` keeps them
out): `settings.local.json` (per-machine permission overrides, e.g. the Windows full-path
`gh` rule) and `launch.json` (preview/app-launch config).

---

## 3. Dependencies the engine needs that are **not** in `.claude/`

This is the part the source docs scatter and a cold session will miss. The engine reads
several things from the **repo root** and depends on two things that live **entirely
outside the repo**.

### 3a. Repo-root inputs (the Profile layer's other half) — ship skeletons

| Path | What it is | Template action |
|---|---|---|
| `memory/constitution.md` | The project's principles — "law" the constitution-auditor enforces. | Ship `memory/constitution.template.md` (a 3–5 numbered-principle skeleton with a worked example). The reviewers fail-closed without it. |
| `specs/<feature>/spec.md` | Acceptance criteria (`US#` user stories). | Ship an empty `specs/000-template/spec.template.md` skeleton (the `.template.md` suffix keeps it out of the `specs/*/spec.md` fallback glob; adopters rename on copy). |
| `specs/<feature>/tasks.md` | The backlog `next-task` drives, incl. the "Criterion ownership" map and tier tags. | Ship a `tasks.template.md` skeleton showing the task-line format + the ownership-map section (suffixed so its placeholder task IDs are never selectable via the `specs/*/tasks.md` fallback). |
| `specs/<feature>/contracts/` | Provider-interface contracts the contract-auditor reads. | Ship an empty dir + one example contract. |
| `AGENTS.md` / `CLAUDE.md` | `CLAUDE.md` just contains `AGENTS.md`; `AGENTS.md` holds the architecture guardrails `PROJECT.md` points at. | Ship a minimal `AGENTS.md` template; keep the `CLAUDE.md` → `AGENTS.md` indirection. |

`PROJECT.template.md` already names these paths and tells the filler to supply them — so the
skeletons make its instructions executable instead of aspirational.

### 3b. Out-of-repo machinery — document, provide a template, don't try to commit

These cannot live in the repo, and a cold session has **zero visibility** into them. They
must be described in the template's docs or they'll be silently dropped:

- **The heartbeat launcher.** The `/triage` dead-man switch is driven by an out-of-repo
  scheduled entry point — here, `triage-heartbeat.ps1` + a Windows Task Scheduler task
  (`BirdJournal-TriageHeartbeat`). It composes the headless invocation, writes the run log,
  and is the worked example of the explicit-context rule (passes `run log:`, `inbox:`,
  `repo root:` *in the prompt text*). Ship a **commented template launcher** (one POSIX/cron,
  one PowerShell/Task-Scheduler) under e.g. `docs/launchers/`, and point `triage.md` §6 at it.
  See DESIGN-NOTES §"the dead-man switch".
- **Headless auth.** Unattended runs read a token file (`.oauth-token`) and use
  `--dangerously-skip-permissions` (the guard hook + read-only triage contract are the
  compensating controls — documented in the probe record's P-PA row). Document the auth
  setup; commit no secrets.
- **The auto-memory system.** The design rationale for this harness currently lives in
  Claude Code's per-project auto-memory (`~/.claude/projects/<slug>/memory/*.md`) — **outside
  the repo entirely.** That is exactly why `DESIGN-NOTES.md` exists: it pulls the load-bearing
  rationale *into* the repo so it survives extraction. The memory *mechanism* is not part of
  the harness; don't try to port it.

---

## 4. Extraction procedure (ordered)

1. **Scaffold the new repo.** `git init`; create `.claude/`, `memory/`, `specs/`, root
   `AGENTS.md`/`CLAUDE.md`.
2. **Copy the KEEP files** (§2) verbatim into the new `.claude/`.
3. **Ship the TEMPLATE profile:** copy `PROJECT.template.md`; do **not** copy `PROJECT.md`.
4. **GENERICIZE** `README.md`, `settings.json`, `MODELS.md`, and the evasion-register pair
   (`workflow/reviewers/evasion-register.md` + `hooks/evasion-register-docs.test.sh`) per §2
   (strip project name, placeholder the toolchain allowlist, keep the model-table shape;
   reset the register's real-escape exhibits to spec-derived seeds and drop the matching
   DW1 test assertions).
5. **RESET** `adapters/claude-code-probes.md` to an un-run instantiation.
6. **Add the root skeletons** (§3a): `constitution.template.md`, `specs/000-template/*`,
   `AGENTS.md` template, `CLAUDE.md`.
7. **Add the out-of-repo templates** (§3b): launcher templates + an auth/setup doc under
   `docs/`.
8. **Carry these two files** (`EXTRACTION.md`, `DESIGN-NOTES.md`) into the template so the
   *next* extraction/onboarding has them.
9. **Verify** (§5).

---

## 5. Verify the extraction actually works

A binding that *reads* correctly can still be dead on a real driver — this harness learned
that the hard way (two live failures on the "production-trusted" adapter; DESIGN-NOTES
§"probe before you trust"). So don't ship on inspection alone:

1. **The split holds — grep tests.** Three files must quote the grep needles to do their
   jobs, so the commands exclude them by name: this manifest (it states the commands),
   `adapters/claude-code-probes.md` (its instantiation table names the tokens it greps
   for), and `hooks/guard.test.sh` (sealed fixture table — the recorded P-MT caveat). The
   original probe run excluded them implicitly; the commands below say so explicitly. They
   use `git grep` so only *tracked* files are scanned (a gitignored `settings.local.json`
   can't false-match), and `-w` instead of `\b` (a GNU extension — under BSD/macOS regex it
   silently returns zero hits, vacuously passing the no-hits check and failing the
   exactly-one checks):
   - `git grep -Einw 'fable|opus|sonnet|haiku' -- .claude/workflow` → **no hits** (workflow
     layer names no models). Use the model-table vocabulary only — a bare `claude` would
     false-match every `.claude/` *path* reference, which is why probe P-MT greps model
     names, not vendor strings.
   - `git grep -Eilw 'fable|opus|sonnet|haiku' -- .claude ':(exclude).claude/EXTRACTION.md' ':(exclude).claude/adapters/claude-code-probes.md' ':(exclude).claude/hooks/guard.test.sh'`
     → exactly **one** file: `MODELS.md`. (Probe P-MT.)
   - `git grep -Fil -e 'Out-File' -e '-Encoding utf8' -- .claude ':(exclude).claude/EXTRACTION.md' ':(exclude).claude/adapters/claude-code-probes.md'`
     → exactly **one** file: `skills/next-task/SKILL.md` (the [environment block]).
     (Probe P-EB.)
   - `git grep -Ein '/(code-review|security-review|run|verify)([^a-z-]|$)' -- AGENTS.md .claude/workflow`
     → **no hits** (the shared/neutral surfaces name no adapter *skill* — only **[role]**s
     like `[code-review pass]`). This guards the layering rule (`workflow/README.md` →
     binding contract; `DESIGN-NOTES.md` §1) on the two surfaces the model-vocabulary greps
     never scanned: `AGENTS.md` (shared by both runtimes — `CLAUDE.md` is `@AGENTS.md` and
     Codex reads it natively) and `.claude/workflow/`. Three deliberate choices:
     **(a)** the needle is **slash-anchored** — bare `code-review` is the legitimate role
     name `[code-review pass]` and appears throughout the neutral layer; the leading `/`
     distinguishes a Claude Code skill *invocation* from the role. **(b)** Only the four
     UI/review skills are listed: `/next-task`, `/triage`, `/constitution-check` are
     **excluded on purpose** because they collide with ordinary neutral references — the doc
     *paths* (`workflow/next-task.md`) and the §6 launcher example (`/triage inbox: …`) —
     and would false-match; the four chosen have no legitimate neutral use. **(c)** the
     `([^a-z-]|$)` right-bound stops `/run` from matching `/runtime`/`/runner` — the same
     path-false-match care P-MT takes with a bare `claude`. No `:(exclude)` clauses are
     needed: the scope (`AGENTS.md` + `.claude/workflow`) already omits every needle-quoting
     file (this manifest, the probe table, `guard.test.sh`).
2. **The guard is wired, not just present:** run `bash .claude/hooks/guard.test.sh` — it must
   pass, **including the matcher-wiring assertion** (the test that fails if `settings.json`'s
   PreToolUse matcher stops routing a tool `guard.sh` handles). This assertion exists because
   the guard was once silently dead while its unit tests stayed green (DESIGN-NOTES).
3. **Run the conformance probes:** instantiate every probe in
   `workflow/conformance-probes.md` for the fresh repo and execute them (the `claude-code-probes.md`
   table is the instantiation skeleton). Treat the harness as untrusted until they pass.

---

## 6. Do-not-break list

- **Never edit `workflow/**` to fit a runtime or project.** If a need leaks upward, the fix
  is a new *role* in the binding contract or a new *profile* field — never a mechanism/vendor
  name in the neutral layer. (Enforced by the §5 grep.)
- **Keep `settings.json`'s PreToolUse matcher intact**, `Agent|Task` included. Dropping them
  silently disables guard rule 5 (the constitution-reviewer strong-floor) — this is a
  documented past failure, not a hypothetical.
- **Don't strip the constitution-auditor's strong-tier floor**, the model table's
  "one file names models" property, or the probe records' lesson. They look like ceremony;
  they are the parts that already caught real bugs. DESIGN-NOTES explains each.
- **Don't ship secrets** (`.oauth-token`, `settings.local.json`, `launch.json`).
