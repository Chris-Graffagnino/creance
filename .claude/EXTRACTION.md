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

Manifest source inventory: 99 rows.

Every source file under `.claude/` is itemized exactly once below.
`hooks/extraction-manifest.test.sh` compares this table with
`git ls-files .claude` and fails CI on a stale count, a missing row, a duplicate row, an
untracked row, or an invalid category. Rows whose action starts
`Omit from extracted template;` are source-only template inputs and may be absent after
extraction.

Categories: **KEEP** (generic, copy verbatim) · **GENERICIZE** (reused but carries a
project/toolchain or instance assumption to strip) · **RESET** (replace contents with a
fresh/blank instantiation) · **TEMPLATE** (the project-specific input — ship the
`.template` form only).

| File | Category | Action |
|---|---|---|
| `DESIGN-NOTES.md` | KEEP | Companion rationale for the harness. Carry with this manifest; it explains why the load-bearing machinery exists. |
| `EXTRACTION.md` | KEEP | This manifest and extraction playbook. Carry so the next extraction has a complete inventory. |
| `MODELS.md` | GENERICIZE | The adapter's only model-naming file. Keep the table shape and semantics; replace the concrete rows with sensible defaults plus a "swap per your account" note. |
| `PROJECT.md` | TEMPLATE | Omit from extracted template; live project profile. Ship `PROJECT.template.md` for adopters to fill. |
| `PROJECT.template.md` | TEMPLATE | Fill-in-the-blanks project profile. Ship as the template's profile source. |
| `README.md` | GENERICIZE | Adapter-layer doc is generic, but examples may name this source environment. Strip project names/examples; keep the structure. |
| `adapters/claude-code-probes.md` | RESET | Probe instantiation + dated results are environment-specific. Reset to "instantiated, NOT yet executed" with placeholder launcher/scheduler rows. |
| `adapters/codex-cli-dry-run.md` | KEEP | Dry-run walkthrough for the Codex CLI adapter spec. Keep as a reference example. |
| `adapters/codex-cli.md` | KEEP | Second-adapter spec/stub — a worked example of porting to a non-Claude runtime. Keep as reference. |
| `adapters/omnigent/README.md` | KEEP | Third-adapter spec/stub (Omnigent meta-harness) — role→mechanism table, a worked example of porting to a cross-vendor runtime. Keep as reference. |
| `adapters/omnigent/MODELS.md` | KEEP | The Omnigent adapter's only tier→model table (cross-vendor reviewer resolution included). Keep as reference. |
| `adapters/omnigent/environment.md` | KEEP | The Omnigent adapter's single [environment block] + [comment marker] concrete form. Keep as reference. |
| `adapters/omnigent/pyproject.toml` | KEEP | Packaging for the `creance_omnigent` adapter glue package (stdlib-only, no runtime deps). Keep as reference; rename the package on extraction only if the whole adapter is re-flavored. |
| `adapters/omnigent/creance_omnigent/__init__.py` | KEEP | Importable adapter-glue package marker (the dotted path Omnigent loads). Keep as reference. |
| `adapters/omnigent/creance_omnigent/registry.py` | KEEP | `POLICY_REGISTRY` export — how Omnigent discovers the guard policies via `policy_modules:`. Keep as reference. |
| `adapters/omnigent/creance_omnigent/policies/__init__.py` | KEEP | Policy subpackage marker. Keep as reference. |
| `adapters/omnigent/creance_omnigent/policies/guard.py` | KEEP | The Omnigent `[guard]` / `[edit guard]` policy port — the runtime-neutral guard rules as deterministic, fail-open `tool_call` / `tool_result` policies (T618). Keep as reference; names no models (tiers resolved from `MODELS.md` at run time). |
| `adapters/omnigent/tests/test_guard.py` | KEEP | Unit tests for the Omnigent guard policy port (DENY cases, passing control, adversarial variants, fail-open). Run by CI `verify`. Keep as reference. |
| `adapters/omnigent/reviewers/spec.yaml` | KEEP | The Omnigent acceptance `[reviewer]` sub-agent — `purpose: review`, read-only, cross-vendor, binds `workflow/reviewers/spec-auditor.md` (T619). Keep as reference; names no models (tiers resolved from `MODELS.md`). |
| `adapters/omnigent/reviewers/constitution.yaml` | KEEP | The Omnigent constitution `[reviewer]` sub-agent — `purpose: review`, read-only, cross-vendor, `executor.model` pinned to `[frontier tier]` (T619, #119 AC3). Keep as reference; names no models. |
| `adapters/omnigent/reviewers/contract.yaml` | KEEP | The Omnigent contract `[reviewer]` sub-agent — `purpose: review`, read-only, cross-vendor, binds `workflow/reviewers/contract-auditor.md` (T619). Keep as reference; names no models. |
| `adapters/omnigent/tests/test_reviewers.py` | KEEP | Deterministic paired check for the Omnigent cross-vendor read-only reviewers (cross-vendor / read-only / `[frontier]`-pin; real-PASS + plant-FAIL; T619). Run by CI `verify`. Keep as reference. |
| `agents/constitution-auditor.md` | KEEP | Subagent binding. Verbatim. |
| `agents/contract-auditor.md` | KEEP | Subagent binding. Verbatim. |
| `agents/spec-auditor.md` | KEEP | Subagent binding. Verbatim. |
| `hooks/agents-residency-check.sh` | KEEP | Deterministic residency budget for the always-resident `AGENTS.md`. Verbatim. |
| `hooks/agents-residency-check.test.sh` | KEEP | Regression + CI-wiring test for the residency check. Verbatim. |
| `hooks/announce-task-selection.sh` | KEEP | Runtime [selection announce-and-confirm] decision (announce/confirm/announce-only) for /next-task. Verbatim. |
| `hooks/announce-task-selection.test.sh` | KEEP | Paired regression tests for the announce-and-confirm decision. Verbatim. |
| `hooks/auditor-liveness-docs.test.sh` | KEEP | Encoding test for the auditor-liveness corpus and wiring. Verbatim. |
| `hooks/autonomy-mode.sh` | KEEP | Deterministic [autonomy activation] binding. Verbatim. |
| `hooks/autonomy-mode.test.sh` | KEEP | Activation fail-closed/default-off regression tests. Verbatim. |
| `hooks/check-tasks-consistency.sh` | KEEP | Tasks-file consistency and drift gate. Verbatim. |
| `hooks/check-tasks-consistency.test.sh` | KEEP | Regression tests proving the tasks-file consistency gate fires and avoids false positives. Verbatim. |
| `hooks/evasion-register-docs.test.sh` | GENERICIZE | Structural + runtime-neutrality backstop for the register. Keep structural/neutrality/extraction checks; drop only instance-coupled real-escape assertions when the register is reset. |
| `hooks/extraction-manifest.test.sh` | KEEP | Completeness backstop for this cut-list. Verbatim. |
| `hooks/guard.sh` | KEEP | Deterministic [guard] implementation. Verbatim. |
| `hooks/guard.test.sh` | KEEP | Guard tests including matcher-wiring and edit-guard assertions. Verbatim. |
| `hooks/intake-docs.test.sh` | KEEP | Encoding test for intake/triage workflow docs and skill binding. Verbatim. |
| `hooks/isolated-workspace.sh` | GENERICIZE | Keep the [isolated workspace] worktree lifecycle verbatim, but the ephemeral worktree's `creance-ws-` mktemp prefix and `.creance-ws-owner` provenance-marker filename hardcode this project's name (`enter`'s `mktemp -d .../creance-ws-XXXXXX`, the marker write/read, and the `*/creance-ws-*` teardown name-guard). A verbatim clone would create `creance`-named temp dirs and marker files. On extraction, rename both to a neutral prefix (`ws-`/`harness-ws-`); update the two coupled tests below in lockstep. (Descriptive mentions of the prefix in `DESIGN-NOTES.md`, `skills/next-task/SKILL.md`, and example paths in `workflows/gate-loop.test.js` are self-contained — same this-repo flavor those KEEP files already carry — and don't break on rename.) |
| `hooks/isolated-workspace.test.sh` | GENERICIZE | Keep the lifecycle regression tests and CI-wiring assertion verbatim, but its look-alike fixtures (`creance-ws-LOOKALIKE-*`) hardcode the prefix to exercise the `*/creance-ws-*` name-guard. Rename them in lockstep with `isolated-workspace.sh` above so the extracted test matches the genericized script. |
| `hooks/isolation-falsification.test.sh` | GENERICIZE | Keep the adversarial base-unreachability proof verbatim, but its forged-marker fixture (`creance-ws-FORGED`) hardcodes the prefix to pass the `*/creance-ws-*` name filter. Rename it in lockstep with `isolated-workspace.sh` above. |
| `hooks/lib-neutrality-scan.sh` | KEEP | Shared runtime-neutral workflow-doc mechanism scanner used by the distributed docs encoding tests. Verbatim. |
| `hooks/lib-neutrality-scan.test.sh` | KEEP | Contract tests for the shared runtime-neutral workflow-doc mechanism scanner. Verbatim. |
| `hooks/lib-tasks-drift.sh` | KEEP | Shared task-drift detection library for runtime selection and CI consistency. Verbatim. |
| `hooks/maker-eval-docs.test.sh` | KEEP | Encoding test for the maker-eval corpus, the doc's fingerprint/observe-only/PR-only contract, and CI wiring. Verbatim. |
| `hooks/maker-eval-emit.sh` | KEEP | Adapter-side maker-eval record + transcript-packet emitter and triple-fingerprint capture (observe-only). Verbatim. |
| `hooks/maker-eval-emit.test.sh` | KEEP | Behavioral tests for the maker-eval emitter — fingerprint independence, record/packet fencing, silent-write, partial-run completeness. Verbatim. |
| `hooks/maker-eval-fence.sh` | KEEP | Deterministic P5 fence — asserts the maker-eval channel (records.jsonl + packets/) is read/resolved only by the eval writer and the triage reader, never a gate/tier/guard/selection path. The run binding (`skills/maker-eval/SKILL.md`) is line-scoped: it may DRIVE the writer (`maker-eval-emit`) but a channel read/resolve inside it still fires (PR #164). Plus the non-control declaration/probe-doc/test surface. Verbatim. |
| `hooks/maker-eval-fence.test.sh` | KEEP | Paired plant/pass tests for the P5 fence — fires on a planted cross-reference to either path across the four danger classes, passes on the real tree, and proves the run binding's line-scope (writer drive benign, channel read fires — PR #164). Verbatim. |
| `hooks/neutrality-scan-coverage.test.sh` | KEEP | Global backstop that scans every tracked neutral workflow markdown doc through the shared scanner. Verbatim. |
| `hooks/next-task-budget-check.sh` | KEEP | Line-budget check for the `next-task.md` accretion sink. Verbatim. |
| `hooks/next-task-budget-check.test.sh` | KEEP | Regression + CI-wiring test for the next-task budget check. Verbatim. |
| `hooks/omnigent-neutral-core.test.sh` | KEEP | Paired neutral-core-untouched check for the Omnigent adapter (mechanism-leak + model-confinement). Verbatim. |
| `hooks/pr-review-docs.test.sh` | KEEP | Encoding test for the PR-review workflow and binding. Verbatim. |
| `hooks/probe-fingerprint-docs.test.sh` | KEEP | Encoding test for probe fingerprint recording and machinery-freshness inputs. Verbatim. |
| `hooks/reconcile-inflight-selection.sh` | KEEP | Runtime in-flight (open PR/branch) selection refusal — the tracker-based half of live-state reconciliation. Verbatim. |
| `hooks/reconcile-inflight-selection.test.sh` | KEEP | Paired regression tests for in-flight selection reconciliation (`gh` mocked). Verbatim. |
| `hooks/reconcile-task-selection.sh` | KEEP | Runtime live-state reconciliation precondition. Verbatim. |
| `hooks/reconcile-task-selection.test.sh` | KEEP | Paired regression tests for selection reconciliation. Verbatim. |
| `hooks/retrospective-docs.test.sh` | KEEP | Encoding test for retrospective workflow/binding invariants. Verbatim. |
| `hooks/reviewer-roster.test.sh` | KEEP | Drift backstop for the §7 reviewer roster and read-only agent bindings. Verbatim. |
| `hooks/shell-lint.sh` | KEEP | Shell syntax/portability checker used by CI and the edit guard. Verbatim. |
| `hooks/shell-lint.test.sh` | KEEP | Regression tests for the shell portability checker. Verbatim. |
| `hooks/spec-lint.sh` | KEEP | Deterministic spec-content lint over `specs/*/spec.md` (the mechanizable spec-quality smells). Verbatim. |
| `hooks/spec-lint.test.sh` | KEEP | Regression + CI-wiring tests for the spec-content lint. Verbatim. |
| `hooks/telemetry-docs.test.sh` | KEEP | Encoding test for telemetry docs and neutral-boundary constraints. Verbatim. |
| `hooks/triage-freshness-docs.test.sh` | KEEP | Encoding test for PROBES-STALE / GUARD-SILENT machinery freshness surfacing. Verbatim. |
| `hooks/triage-maker-eval-docs.test.sh` | KEEP | Encoding test for the triage "Maker eval" differential-regression surfacing (US2.AC2 — threshold, packet link, MAKER-EVAL-STALE / JUDGE-CHANGED / INSTRUMENT-CHANGED / JUDGE-MISCALIBRATED, empty states). Verbatim. |
| `settings.json` | GENERICIZE | Keep the guard hook wiring exactly; replace this repo's permission/toolchain allowlist with template placeholders. |
| `skills/auditor-liveness/SKILL.md` | KEEP | Claude adapter binding for auditor-liveness runs. Verbatim. |
| `skills/constitution-check/SKILL.md` | KEEP | Claude adapter binding for the constitution check. Verbatim. |
| `skills/intake/SKILL.md` | KEEP | Claude adapter binding for intake. Verbatim. |
| `skills/maker-eval/SKILL.md` | KEEP | Claude adapter binding for maker-eval runs — drives the writer (`maker-eval-emit.sh`) and the pinned judge, defines the two triggers (maker-behavior fingerprint change + weekly schedule), observe-only. Portable; verbatim. |
| `skills/next-task/SKILL.md` | KEEP | Adapter binding + the single [environment block]. Verbatim, but see §3 note on the env block's bash+PowerShell assumption. |
| `skills/pr-review/SKILL.md` | KEEP | Claude adapter binding for PR review. Verbatim. |
| `skills/retrospective/SKILL.md` | KEEP | Claude adapter binding for retrospectives. Verbatim. |
| `skills/triage/SKILL.md` | KEEP | Claude adapter binding for triage. Verbatim. |
| `workflow/README.md` | KEEP | The binding contract — the spine. Verbatim. |
| `workflow/auditor-liveness.md` | KEEP | Runtime-neutral auditor-liveness methodology. Verbatim. |
| `workflow/conformance-probes.md` | KEEP | Neutral probe checklist. Verbatim. |
| `workflow/constitution-check.md` | KEEP | Pre-PR compliance gate. Verbatim. |
| `workflow/gate-loop.md` | KEEP | §7 gate as pseudocode. Verbatim. |
| `workflow/intake.md` | KEEP | Runtime-neutral intake workflow. Verbatim. |
| `workflow/maker-eval.md` | KEEP | Runtime-neutral maker-eval methodology (the maker analog of auditor-liveness). Verbatim. |
| `workflow/next-task.md` | KEEP | Per-task loop. Verbatim. |
| `workflow/pr-review.md` | KEEP | Runtime-neutral PR-review workflow. Verbatim. |
| `workflow/retrospective.md` | KEEP | Runtime-neutral retrospective workflow. Verbatim. |
| `workflow/reviewers/auditor-liveness-corpus.md` | KEEP | Fixture manifest for auditor-liveness. Verbatim. |
| `workflow/reviewers/constitution-auditor.md` | KEEP | Values reviewer spec. Verbatim. |
| `workflow/reviewers/contract-auditor.md` | KEEP | Architecture reviewer spec. Verbatim. |
| `workflow/reviewers/evasion-register.md` | GENERICIZE | The cumulative cheat-museum. Its **universal pattern exhibits** (the spec-derived ones — test-gaming, green-suite, vendor-leak, measurement-gains-control) are engine-level and ship verbatim. Its **real-escape exhibits** (EV-03/06/08) hardcode *this repo's* commit SHAs (`5bb6186`…) and instance test-file paths (`probe-fingerprint-docs.test.sh:119`, `reviewer-roster.test.sh`) — project facts (the one documented engine-file exception, `PROJECT.md` → "Architecture boundaries"). On extraction, **reset the real-escape exhibits to the "spec-derived seed (no escape logged yet)" form** (or move them into DESIGN-NOTES as the worked example, like `claude-code-probes.md`); keep the universal patterns + the mechanization-status scaffold. A fresh project's retrospective grows its own exemplars per incident. |
| `workflow/reviewers/maker-eval-corpus.md` | KEEP | Frozen instrument manifest for maker-eval — corpus, per-dimension lifecycle metadata, rubrics, pinned-judge spec, scoring schema, calibration pointer. Portable; verbatim. |
| `workflow/reviewers/spec-auditor.md` | KEEP | Acceptance reviewer spec. Verbatim. |
| `workflow/reviewers/spec-quality-auditor.md` | KEEP | Spec-quality reviewer spec — grades spec content one phase upstream of the acceptance reviewer (T701). Verbatim. |
| `workflow/telemetry.md` | KEEP | Runtime-neutral telemetry record and observe-only semantics. Verbatim. |
| `workflow/triage.md` | KEEP | Read-only heartbeat. Verbatim. |
| `workflows/gate-loop.js` | KEEP | [orchestrated run] adapter script. Verbatim. |
| `workflows/gate-loop.test.js` | KEEP | JS encoding tests for the gate-loop adapter script. Verbatim. |

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
4. **GENERICIZE** `README.md`, `settings.json`, `MODELS.md`, the evasion-register pair
   (`workflow/reviewers/evasion-register.md` + `hooks/evasion-register-docs.test.sh`), and the
   isolated-workspace trio (`hooks/isolated-workspace.sh` + the coupled
   `hooks/isolated-workspace.test.sh` and `hooks/isolation-falsification.test.sh`) per §2
   (strip project name, placeholder the toolchain allowlist, keep the model-table shape;
   reset the register's real-escape exhibits to spec-derived seeds and drop the matching
   DW1 test assertions; rename the `creance-ws-` mktemp prefix + `.creance-ws-owner` marker to a
   neutral prefix and move the `creance-ws-*` test fixtures in lockstep). §2's GENERICIZE rows
   are the authoritative set for this step — `hooks/extraction-manifest.test.sh` fails CI if §4
   omits one.
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

1. **The split holds — grep tests.** Four files must quote the grep needles to do their
   jobs, so the commands exclude them by name: this manifest (it states the commands),
   `adapters/claude-code-probes.md` (its instantiation table names the tokens it greps
   for), `hooks/guard.test.sh` (sealed fixture table — the recorded P-MT caveat), and
   `hooks/retrospective-docs.test.sh` (sealed P-RT telemetry fixture). The original
   probe run excluded the needle-quoting files implicitly; the commands below make that explicit. They
   use `git grep` so only *tracked* files are scanned (a gitignored `settings.local.json`
   can't false-match), and `-w` instead of `\b` (a GNU extension — under BSD/macOS regex it
   silently returns zero hits, vacuously passing the no-hits check and failing the
   exactly-one checks):
   - `git grep -Einw 'fable|opus|sonnet|haiku' -- .claude/workflow` → **no hits** (workflow
     layer names no models). Use the model-table vocabulary only — a bare `claude` would
     false-match every `.claude/` *path* reference, which is why probe P-MT greps model
     names, not vendor strings.
   - `git grep -Eilw 'fable|opus|sonnet|haiku' -- .claude ':(exclude).claude/EXTRACTION.md' ':(exclude).claude/adapters/claude-code-probes.md' ':(exclude).claude/hooks/guard.test.sh' ':(exclude).claude/hooks/retrospective-docs.test.sh'`
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
