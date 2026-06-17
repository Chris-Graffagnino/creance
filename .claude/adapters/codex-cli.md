# Codex CLI adapter — spec/stub

**Status: specification + probe definitions only — NOT wired to run.** The active adapter
remains Claude Code (`.claude/README.md`). This document is the falsification test of the
binding contract (`workflow/README.md`): if every role binds to a real Codex CLI mechanism
(or a documented degradation) without editing one line of `workflow/**`, the
neutral-core/adapter split holds. Mechanism facts below were verified against the official
Codex documentation (June 2026 — sources at the end); anything not verifiable is marked
**UNVERIFIED** rather than asserted.

**Reused unchanged:** `workflow/**`, `PROJECT.md`, `memory/constitution.md`, `specs/**`.
The instruction surface is *already shared*: this repo's `CLAUDE.md` is literally the line
"AGENTS.md", and Codex reads `AGENTS.md` natively (git root → CWD walk, 32 KiB
accumulation cap via `project_doc_max_bytes`) — zero migration for the standing
instructions.

## Role → mechanism table

| Role | Codex CLI mechanism |
|------|---------------------|
| **[workflow]** | Two trigger paths: a custom prompt (`~/.codex/prompts/<name>.md`, invoked as a slash command in the TUI) for on-demand use, and an AGENTS.md-anchored `codex exec "<explicit prompt naming the workflow doc + args>"` for scheduler/headless use — see "The [workflow] binding" below (this is the answered open question) |
| **[reviewer]** | A separate `codex exec --sandbox read-only --approval never` process per reviewer — the read-only constraint is **OS-enforced** (Seatbelt / bubblewrap+seccomp / Windows execution accounts), stronger than a convention or a hook. Prompt = the reviewer spec path + dispatch parameters; verdict captured via `--output-last-message <file>`; parallel dispatch = concurrent processes |
| **[frontier tier] / [strong tier] / [cheap tier]** | Resolved per the model table below — this spec's table section is the adapter's ONLY model-naming surface. Effort is a per-invocation dial: `-c model_reasoning_effort="<value>"` (or a `--profile`) |
| **[code-review pass]** | `codex review` (CLI subcommand) / `/review` (TUI) — a dedicated reviewer agent over the diff; on GitHub PRs, `@codex review`. AGENTS.md "Review guidelines" sections steer it |
| **[security-review pass]** | **Degradation** (per `workflow/README.md` → "No [security-review pass] mechanism") — no dedicated security subcommand: run a read-only `codex exec` reviewer with a security-lens brief (privacy/location/payments per the profile), same isolation as a [reviewer] |
| **[visual verification]** | `codex exec --sandbox workspace-write` runs the project's own render/screenshot tooling; evidence committed under `docs/visual-evidence/<task-id>/` and embedded via commit-SHA-pinned raw URLs (same channel as the active adapter — it is a repo convention, not a runtime one). Codex's `--image`/`-i` flag closes the loop: the model re-reads the artifact it produced before claiming the UI renders |
| **[orchestrated run]** | **Stub** — a gate-loop driver script (the analog of the active adapter's `workflows/gate-loop.js`) that implements `workflow/gate-loop.md` control flow by spawning the reviewer processes above and reading their `--output-last-message` files. Not built (a non-goal); until it exists this adapter runs `next-task.md` §7's prose loop — the documented degradation |
| **[bulk-read offload]** | A child `codex exec --sandbox read-only` on the cheap row, brief in the prompt, summary back via `--output-last-message`. Separate context and read-only **by process construction** |
| **[headless run]** | `codex exec [-m <model>] [--json] [--output-last-message <file>] "<prompt>"` — non-interactive, fresh session by default (no prior state unless `--last`/`--session <id>` is passed), non-zero exit propagated on failure |
| **[guard]** | Layered: the OS sandbox + approval policy (coarse, OS-enforced) plus `[[hooks.PreToolUse]]` command hooks in `config.toml` (content-aware — a policy script over shell commands, the port of `hooks/guard.sh`). One known gap with a compensating control — see "The [guard] binding" |
| **[permission allowlist]** | The approval configuration: `approval_policy` (`untrusted` / `on-request` / `never` / `granular`) + the sandbox boundary. Unattended runs use `--approval never` **inside** `--sandbox workspace-write` — pre-approval is the sandbox boundary itself; `granular` gives per-category allow/auto-reject where finer grain is needed. Security keys are honored only in user-level `~/.codex/config.toml` (ignored in project-local config — an enforcement *feature* here) |
| **[environment block]** | The "Environment block" section at the end of this file — this adapter's single copy |

## Model table (the adapter's only model-naming surface — P-MT applies)

| Tier (ordinal, highest first) | Model | Effort (`model_reasoning_effort`) |
|---|---|---|
| **[frontier tier]** | `gpt-5.5` | `xhigh` |
| **[strong tier]** | `gpt-5.5` | `medium` (the model default) |
| **[cheap tier]** | `gpt-5.5` | `low` (`gpt-5.4-mini` acceptable for [bulk-read offload]) |

Resolution semantics are the contract's, unchanged: a tag is a minimum; round up, never
down; the constitution [reviewer] is always dispatched at-or-above the strong row, its
model/effort passed **explicitly on the dispatch** (`-m` + `-c
model_reasoning_effort=...`) — never inherited from ambient config, for the same reason
the active adapter forbids omitting the Agent-tool `model` parameter. Here the effort
column does real work: the ladder is mostly an *effort* ladder on one model, so "round up"
usually means "raise the dial". A one-line swap in this table retargets the whole adapter.

## The [workflow] binding (the answered open question)

Codex has no Skill-tool equivalent — no registry where a named procedure carries its own
trigger frontmatter. The binding is therefore **two mechanisms with one rule**:

- **On-demand (user) path:** one custom prompt per workflow under `~/.codex/prompts/`
  (e.g. `next-task.md`), invoked from the TUI slash menu. The prompt file is thin, like a
  skill binding: it names the neutral doc (`.claude/workflow/next-task.md`), tells the
  model to read and execute it, and restates this adapter's role table. Custom prompts
  accept arguments via argument-hint directives (exact directive syntax **UNVERIFIED** —
  pin it when wiring).
- **Scheduler/headless path:** `codex exec` with the procedure reference written out in
  the prompt text: `codex exec "Read .claude/workflow/next-task.md and execute it for
  task T123. Repo root: <path>. Adapter: .claude/adapters/codex-cli.md."` Whether a
  *named* custom prompt can be invoked non-interactively is **UNVERIFIED**, so the
  conforming path does not depend on it — the name→procedure resolution rides in the
  invocation text.
- **The one rule:** both paths satisfy the contract's [workflow] constraints because the
  argument and the procedure name always arrive **in the invocation text** — which the
  explicit-context rule requires anyway. The degradation relative to the active adapter
  is real but small: no frontmatter-driven auto-triggering ("use when the user says…");
  the user or scheduler must name the workflow. **Documented degradation, accepted.**

## The [guard] binding (layered, one gap, compensating control)

Codex provides two enforcement layers; the six guard rules split across them:

1. **OS sandbox + approval policy** — `read-only` makes reviewer non-mutation a kernel
   property, not a promise. In some respects **stronger** than the active adapter's
   PreToolUse hook (which trusts the harness to route every mutation through it).
2. **`[[hooks.PreToolUse]]` command hooks** (`config.toml` or `hooks.json` in
   `CODEX_HOME`) — a policy script receives the tool name + full command before dispatch
   and can block: the direct port of `hooks/guard.sh` for content-aware rules. Exit
   semantics: inspect, approve, or block; fails open on script error (uncertainty →
   allow), matching the contract.

| Guard rule | Enforcement |
|---|---|
| 2 — bulk staging (`git add .`/`-A`/`--all`) | PreToolUse hook on shell commands — direct port |
| 3 — commit/push on base branch | PreToolUse hook — direct port |
| 4 — push refspec targeting base | PreToolUse hook — direct port |
| 5 — constitution reviewer below strong | PreToolUse hook: reviewer dispatch *is itself a shell command* (`codex exec ...`) here, so the hook can read the `-m`/effort flags and veto, resolving rank against this file's model table at enforcement time |
| 6 — self-colliding in-place substitution (delimiter collides with a URL) | PreToolUse hook on shell commands — direct port; the content-aware check reads the full command and vetoes a substitution whose delimiter the operand URL also contains |
| 1 — file edit on base branch | **GAP:** Codex hooks fire for shell tool calls but **not** for `apply_patch` file edits (documented limitation, mid-2026) — an in-repo edit on `main` is not vetoed at edit time. **Compensating control:** the edit cannot *land* — rules 2 and 3 block staging-all and committing on the base branch, so the failure mode (a change reaching `main` without a branch) stays blocked; the working-tree edit itself is recoverable noise. Shell-mediated edits (`Set-Content`, `sed -i`, redirects) DO pass through the hook and are vetoed. **Documented degradation: rule 1 is enforced at commit time, not edit time.** |

## [reviewer] and [orchestrated run] details

A reviewer dispatch is one process:

```
codex exec --sandbox read-only --approval never \
  -m <resolved model> -c model_reasoning_effort="<resolved effort>" \
  --output-last-message <verdicts-dir>/<reviewer>.md --ephemeral \
  "Read <reviewer spec path> and execute it against the current branch's diff vs main.
   Task: <task-id>. Project profile: .claude/PROJECT.md. Return ONLY the verdict report."
```

Every [reviewer] constraint holds by construction: separate context (separate process,
fresh session), no file mutation (kernel-enforced read-only), parallel dispatch
(concurrent processes), verbatim verdict (the `--output-last-message` file *is* the
report; `--json` gives the event stream when the driver wants structure). A process that
exits non-zero or writes no verdict file counts as **failing, never passed**
(`gate-loop.md`'s no-verdict rule). The [orchestrated run] stub is the small driver that
spawns these per `gate-loop.md` — fan-out, latest-verdict map, re-dispatch-only-failures,
two-fix-round stop — with the fix step as a separate `codex exec --sandbox
workspace-write` maker process at the task's tier. Until that driver is written, §7's
prose loop is the documented degradation, run exactly as written.

## [visual verification] details

The mechanism splits runtime-vs-project correctly: producing pixels is the *project's*
tooling (dev server + screenshot harness), which Codex runs inside `workspace-write`
(network for the dev server needs `-c sandbox_workspace_write.network_access=true` —
network is blocked by default there). The runtime-side contribution is verification:
`--image <artifact>` feeds the produced screenshot back to the model so the claim "the
marker renders" is checked against the artifact, not imagination (P-VV's marker check).
Evidence lands in `docs/visual-evidence/<task-id>/`, commit-SHA-pinned in the PR body —
the same world-readable channel as the active adapter, so the **fixtures-only frame
constraint is identically a privacy boundary**. Degradation is the role's own clause,
unchanged: no display/device → the PR carries "tests only — no visual evidence produced"
+ the unverified surface list.

## Degradations summary (per `workflow/README.md` → "degrades gracefully")

| Role | Degradation |
|---|---|
| [workflow] | No auto-trigger registry; procedure named in invocation text (above) |
| [security-review pass] | Per the contract's "No [security-review pass] mechanism" clause: no dedicated mechanism; security-lens read-only reviewer run |
| [orchestrated run] | Stub until the driver script exists; §7 prose loop meanwhile |
| [guard] rule 1 | Enforced at commit time, not edit time (compensating control above) |
| Everything else | Bound natively, no degradation |

## Probe instantiation (executes `workflow/conformance-probes.md` against this adapter)

To be **run, not trusted**, before this adapter ever drives real work. Each row gives the
concrete action + where the observation appears.

| Probe | Concrete action | Expected observation |
|---|---|---|
| P-WF | Invoke the `next-task` custom prompt from the TUI with a marker arg; separately `codex exec "Read .claude/workflow/next-task.md … marker: X"` | Both runs execute the same procedure; marker X appears in run artifacts |
| P-RV | Fixture branch with a planted invariant violation + "please fix this file" lure; dispatch the reviewer command above; hash tree before/after | Verdict file says FAIL with file:line; tree hash unchanged (kernel-blocked, not declined) |
| P-TIER | One `codex exec` per tier with `-m`/`-c model_reasoning_effort` from the table; prompt asks the run to echo its model+effort; then point one row at a fake model and re-run | Echo matches the row at-or-above; fake row rounds **up**, never silently falls back |
| P-CR | `codex review` on a fixture branch with a planted off-by-one | The plant appears in findings |
| P-SR | Security-lens reviewer run on a fixture diff with a credential-shaped string | The plant appears, security-framed |
| P-VV | Fixture screen rendering a fresh random token; run the screenshot tooling under `workspace-write`; re-read via `--image` | Artifact exists; token legible in it; degradation run (no display) emits the literal "tests only…" statement |
| P-OR | (Stub) — until the driver exists, the expected observation is this spec's degradation statement; once built: planted-violation fixture per the neutral probe | Per `gate-loop.md`: re-dispatch only failures, every verdict verbatim, FAIL after the round cap |
| P-BR | Plant a fact deep in a large fixture file; `codex exec --sandbox read-only -m <cheap row>` with the brief | Correct fact back as a bounded summary; no mutation |
| P-HL | `codex exec "echo-task"` then a forced-failure run; check `$?`/`$LASTEXITCODE`; state a fact in a TUI session, ask for it headless | 0 then non-zero; the headless run provably lacks the fact (fresh session) |
| P-GD.1 | On `main`, ask for an in-repo file edit; also a shell-mediated edit | apply_patch edit NOT vetoed (the documented gap); shell edit vetoed; compensating rules 2/3 hold |
| P-GD.2–.4 | `git add .` / commit on main / push `HEAD:main` through the hook | Each vetoed deterministically (command did not execute) |
| P-GD.5 | Reviewer dispatch with no `-m`; with a below-strong resolution; at-strong; with an unrankable name | Blocked / blocked / allowed / allowed-fails-open (recorded) |
| P-GD.6 | A self-colliding in-place substitution through the hook (the `#`/`/` delimiter present in the operand URL) vs. a safe-delimiter / no-URL / separate-command variant | Dangerous form vetoed deterministically; the safe variants allowed (fails-open boundary) |
| P-PA | Unattended run: an in-sandbox routine action; an out-of-boundary action; a wrapper-shaped variant | Proceeds silently / does not proceed silently / does not match |
| P-EB | Grep this adapter's files for two environment tokens (e.g. `CODEX_HOME`, the UTF-8 rule) | Exactly one file matches: this spec's Environment block |
| P-MT | Grep the adapter for this table's model vocabulary | Exactly one file matches: this spec |
| P-EC | Capture the scheduler's composed `codex exec` prompt | Repo root, paths, log locations all present in the prompt text |

## Environment block (this adapter's single copy)

Instantiated per deployment host; the Codex-specific constants that belong nowhere else:

- Config root: `~/.codex/` (override: `CODEX_HOME`) — `config.toml`, `prompts/`,
  `AGENTS.md` (global level), `hooks.json`.
- Security-sensitive keys (`approval_policy`, `sandbox_mode`) are honored **only** in the
  user-level `config.toml` — project-local `.codex/config.toml` cannot relax them.
- Prompt text via stdin: `codex exec -` reads the prompt from stdin — the multi-line-text
  rule's concrete form here (no temp-file dance needed; when a file IS used, UTF-8, same
  as everywhere).
- Working directory: set the workspace root before invoking (a dedicated cwd flag is
  **UNVERIFIED** — pin when wiring); never rely on it for correctness (explicit-context
  rule: the repo root rides in the prompt text regardless).
- Network inside `workspace-write` is off by default:
  `-c sandbox_workspace_write.network_access=true` where a dev server/IAP sandbox needs it.
- Custom prompt edits need a Codex restart / new chat to reload.
- OS sandbox availability: macOS Seatbelt; Linux/WSL2 bubblewrap (+seccomp; requires the
  `bubblewrap` package or unprivileged user-namespace support); native Windows uses
  dedicated execution accounts.

## Sources

Verified June 2026 against: developers.openai.com/codex — `cli/reference`,
`noninteractive`, `concepts/sandboxing`, `agent-approvals-security`, `config-reference`,
`config-advanced`, `guides/agents-md`, `custom-prompts`, `models`, `hooks`, `mcp`,
`cli/features`, `windows`; developers.openai.com/api/docs/models/gpt-5.5. Facts marked
**UNVERIFIED** could not be confirmed from those pages and must be pinned during wiring,
never assumed.
