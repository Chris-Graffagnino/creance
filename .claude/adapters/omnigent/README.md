# Omnigent adapter — spec/stub (skeleton)

**Status: specification + role bindings only — NOT wired to run.** The active adapter
remains Claude Code (`.claude/README.md`); the Codex CLI adapter (`adapters/codex-cli.md`)
is the spec'd second example. This document is the **third** falsification test of the
binding contract (`workflow/README.md`): if every `[role]` binds to a real Omnigent
mechanism (or a documented degradation) without editing one line of `workflow/**`, the
neutral-core/adapter split holds for a meta-harness runtime too.

The skeleton landed at **T617 (T616 epic · part a)**: the role→mechanism table (`#119` AC1)
and the deterministic neutral-core-untouched check (`#119` AC4). The mechanism
*implementations* land in later sub-tasks: the `[guard]` / `[edit guard]` policies
(`creance_omnigent/policies/guard.py`) are **now built and unit-tested at T618** (`#119`
AC2); the cross-vendor `[reviewer]` sub-agents (`reviewers/*.yaml`) at **T619** (AC3); and
the orchestrator `config.yaml` + conformance probes + live-driver run at **T620** (AC5 +
Done-when). The adapter is **still not wired to a live driver** — that is T620. Mechanism
facts below were verified against Omnigent's docs (sources at the end, fetched 2026-06-23);
anything not verifiable is marked **UNVERIFIED** rather than asserted.

**Reused unchanged:** `workflow/**`, `PROJECT.md`, `memory/constitution.md`, `specs/**`.
The instruction surface is *already shared*: this repo's `CLAUDE.md` is literally the line
`AGENTS.md`, and an Omnigent agent binds the same rules with `instructions:` (which takes
precedence over an inline `prompt:`). The path is **resolved relative to the config's
directory** (`docs/AGENT_YAML_SPEC.md`): from `.claude/adapters/omnigent/` the repo-root
file is `instructions: ../../../AGENTS.md` — **not** a bare `AGENTS.md`, which would resolve
to a non-existent `.claude/adapters/omnigent/AGENTS.md` and silently fail to bind. (If T620
instead roots `config.yaml` at the repo top, the path is simply `AGENTS.md`.) Either way,
zero migration for the standing rules.

## Role → mechanism table

The runtime-neutral spec of each role (inputs / outputs / constraints) lives in
`workflow/README.md` → "The binding contract"; this table is **mechanisms only**.

| Role | Omnigent mechanism |
|------|--------------------|
| **[workflow]** | A per-agent **skill** (`skills/<name>/SKILL.md` under this adapter's config dir — Omnigent ships skills, e.g. `examples/polly/skills/cross-review/`), thin like a Claude skill binding: it names the neutral doc (`.claude/workflow/<name>.md`), tells the agent to read+execute it, and restates this table. On-demand from the session. The **scheduler/headless** path is a **degradation** (see [headless run]); the exact skill trigger-frontmatter syntax is **UNVERIFIED** — pin at T620 |
| **[reviewer]** | A sub-agent declared under `tools:` as `<name>: {type: agent, executor: {harness, model}, …}` with **`purpose: review`** and **a different vendor than the implementer** ("review is ALWAYS done by a DIFFERENT vendor", `examples/polly/config.yaml`). Read-only **by tool-scoping** — the reviewer declares **no file-mutation tools** (no write `os_env`), so it can be handed the diff + its contract but cannot edit ("reviewers report issues without editing"). Parallel = concurrent dispatches; the verdict is the sub-agent's returned message. Cross-vendor isolation is **structurally stronger** than the Claude adapter's same-runtime/different-context split. Spec files: `reviewers/*.yaml` at **T619** |
| **[frontier tier] / [strong tier] / [cheap tier]** | `executor.model` (+ `executor.harness`) per agent/sub-agent, resolved through **`MODELS.md`** (this adapter's only model-naming file). Each sub-agent picks its own harness+model, so tiers — and the cross-vendor reviewer rule — are structural. Resolution semantics (minimum, round up, never down; constitution `[reviewer]` floor pinned to `[frontier]` per AC3) live in `MODELS.md` |
| **[code-review pass]** | A `purpose: review` cross-vendor sub-agent over the branch diff with a **general** code-review brief (Omnigent's cross-vendor review is first-class — `examples/polly/skills/cross-review/`, `.github/workflows/polly-review.yml`). Not a spec-bound `[reviewer]`; the brief is general |
| **[security-review pass]** | **Degradation** (`workflow/README.md` → "No [security-review pass] mechanism"): no dedicated security subcommand — run a `purpose: review` sub-agent with a security-lens brief scoped to the profile's privacy/credential/payment invariants, same cross-vendor isolation as a `[reviewer]` |
| **[craft-review pass]** *(optional)* | A `purpose: review` sub-agent with a craft-lens brief (testing/failure-handling/boundaries/simplicity), **advisory** — findings to the PR body, no PASS/FAIL gate. Absent it, skip the craft layer and note the skip (degradation) |
| **[visual verification]** | A sub-agent with a write sandbox (`os_env` + `sandbox.write_paths`) runs the **project's own** render/screenshot tooling; evidence is committed under `docs/visual-evidence/<task-id>/` and embedded via commit-SHA-pinned raw URLs (a **repo convention**, shared across adapters — concrete form in `environment.md`). Whether Omnigent can feed the produced image back to the model (the Codex `--image` loop) is **UNVERIFIED**. Degradation clause applies verbatim: no display/device → the PR carries "tests only — no visual evidence produced" + the unverified surfaces |
| **[orchestrated run]** *(optional)* | A **Polly-shaped orchestrator** `config.yaml` (an `omnigent` executor whose `prompt`/`instructions` forbid it from writing code — "ALL coding work gets delegated") that drives the `gate-loop.md` control flow: dispatch the cross-vendor `[reviewer]` sub-agents (via `sys_session_send`), collect verdicts, re-dispatch only failures, stop after the fix-round cap. `guardrails:` enforce the structural bounds (`max_dispatches_per_turn`, restricted sub-agent `purpose`s). **Built at T620**; until then the gate runs `next-task.md` §7's prose loop (the documented degradation) |
| **[bulk-read offload]** | A `purpose: explore` / `search` sub-agent ("read-only investigation, return findings", `examples/polly/config.yaml`) on the **[cheap tier]** row — separate context, read-only by tool-scoping, returns a bounded summary |
| **[headless run]** | **Degradation.** Omnigent's primary surface is the web UI (`localhost:6767`); there is **no documented non-interactive one-shot** (the `claude -p` / `codex exec` analog). The scheduler path drives `omnigent run <config>` with the workflow name + arguments + repo root written **into the prompt/config text** (the explicit-context rule, which the contract requires anyway). Non-interactive exit-code propagation is **UNVERIFIED** — pin at T620 |
| **[guard]** | A deterministic **`tool_call` policy** — `type: function`, `handler:` a dotted path into `creance_omnigent/policies/guard.py`, discovered via `policy_modules:` + a `POLICY_REGISTRY` export, attachable server-wide / per-agent / per-session. The policy receives `event["type"] == "tool_call"` with `target` (e.g. `sys_os_shell`, `sys_os_edit`) + `data.arguments`, and returns `{"result": "DENY", "reason": …}` on a banned action, abstaining (`None`) otherwise (the port never force-`ALLOW`s — abstaining lets the chain + `[permission allowlist]` decide). Several rules **could delegate to builtins** at wiring time: `omnigent.policies.builtins.github.github_policy` (write-branch allowlist = no commit/push to base; `shell_tools: ["sys_os_shell"]`), `…builtins.block_working_dir_changes`, `…builtins.cost.cost_budget` (a spend cap the harness currently lacks) — but the T618 port ships **self-contained custom code** for every rule so the unit tests run without Omnigent installed; the builtins are an optional T620 wiring optimisation. **Fail-open is forced in the port** (the framework's on-error default is **UNDOCUMENTED / UNVERIFIED** — see "The [guard] binding"). Rules **implemented + unit-tested at T618** (`creance_omnigent/policies/guard.py`; `tests/test_guard.py`) |
| **[edit guard]** | A policy on the edit tools (`sys_os_edit` / `sys_os_write`) that reruns the profile's configured checker on the touched file and returns `DENY` (fix-forward feedback) when the edit raises diagnostics **above the file's committed baseline**, allowing an edit no worse than before; **fails open** when no checker maps to the type. **Implemented + unit-tested at T618.** **Phase caveat (discovered at T618):** `docs/POLICIES.md` documents the `tool_call` and `request` phases but **no `tool_result` phase**, so the README's original `tool_result` binding is **UNVERIFIED**. The delta logic is phase-independent, so the port's evaluator is **phase-tolerant** — it runs on an edit-tool event and is *meaningful* once the file reflects the edit (a post-write firing); if only a pre-write phase exists the on-disk file is unchanged, the delta is 0, and it degrades to **fail-open** (no false reject). The exact firing phase + the edit-argument key carrying the path are pinned on the live driver at **T620** |
| **[isolated workspace]** *(optional)* | **Native.** Per-dispatch **git worktrees** (each Polly delegation runs in a fresh worktree) + OS/cloud sandboxes (`environment.md`). Gate **PASS → promote** (open the PR through the §7-gated path) / **FAIL → discard** the worktree. Activation is **off by default and fails closed to review** (the autonomous-mode decision; the config-opt-in read is adapter-side — `workflow/README.md` → "Isolation and the guard's fail-open posture"). Promotion is a **PR, not a merge** — the human merges ("the PR is the deliverable and the human merges it — you never merge", `examples/polly/config.yaml`; `guardrails.gate_pushes`). Wiring + the P-IW probe at **T620** |
| **[permission allowlist]** | The policy/guardrails layer: policies that **ALLOW** routine actions without prompting (the inverse of the `ask_on_os_tools` builtin), plus `guardrails:` such as `max_dispatches_per_turn` and `gate_pushes`. Matched mechanically by the policy engine; the list lives in this adapter's config, never in `workflow/**` |
| **[environment block]** | `environment.md` — this adapter's single copy (CLI invocation, install, sandboxes, tracker/marker forms) |
| **[comment marker]** | The footer line defined once in `environment.md` → "The [comment marker] concrete form", appended to every engine-posted issue/PR comment body; recognition anchored to the comment's final non-empty line |

## Model table
`MODELS.md` — the adapter's **only** model-naming surface (the neutral-core check below
proves no model vocabulary leaks elsewhere). Tiers everywhere else are `[roles]`.

## The [guard] binding (policy port — one documented uncertainty)

Omnigent's policy engine is a clean home for the guard rules: a policy is a deterministic
function over a `tool_call` event returning `ALLOW` / `DENY` / `ASK` (or `None` to abstain),
which is exactly the `[guard]`'s "allow, or a deterministic VETO" shape. The six rules map
as the Codex adapter's do, with two differences in Omnigent's favour and **one caveat**:

| Guard rule | Enforcement |
|---|---|
| 1 — file edit on base branch | `tool_call` policy on `sys_os_edit` / `sys_os_write` targets — **reachable at edit time** (Omnigent fires policies on edit-tool calls, closing the Codex `apply_patch` gap) |
| 2 — bulk staging (`git add .`/`-A`/`--all`) | `tool_call` policy on `sys_os_shell` — direct port; or `github_policy` |
| 3 — commit/push on base branch | `github_policy` write-branch allowlist + the custom `sys_os_shell` policy |
| 4 — push refspec targeting base | custom `sys_os_shell` policy (parse the refspec) |
| 5 — constitution reviewer below strong | the reviewer dispatch is itself a tool call carrying `args.model`; the policy reads it and vetoes a below-floor/absent resolution, ranking against `MODELS.md` at enforcement time |
| 6 — self-colliding in-place substitution | custom `sys_os_shell` policy — content-aware, reads the full command |

- **Caveat (on-raise posture — resolved at T618; framework default still pinned at T620):**
  `docs/POLICIES.md` does **not** document whether a policy that *raises* is treated as
  fail-open or fail-closed. The `[guard]` contract mandates **fail-open**, so the port does
  **not** rely on the framework default: every registered entry point wraps its logic so any
  internal exception/uncertainty returns `None` (abstain), and `tests/test_guard.py`
  (`TestFailOpen`) asserts it — a forced internal raise on a would-be-DENY event still
  abstains. The framework-level on-error default is independently pinned on the live driver
  at T620.
- **Phase caveat (the `tool_result` question — discovered + handled at T618):** the README's
  `[edit guard]` row originally bound a **`tool_result` policy**, but `docs/POLICIES.md`
  documents only `tool_call` and `request` phases. The T618 port makes the edit-guard
  evaluator **phase-tolerant** (the baseline-vs-current delta is phase-independent) and
  records the firing phase as UNVERIFIED → pinned at T620; see the `[edit guard]` row above.
- **Phase-0 risk resolved (the `#119` open question).** Does `omnigent claude` (the
  `claude-sdk` harness) load this repo's `.claude/settings.json` PreToolUse hooks? **AGENTS.md
  rides natively** (`instructions: ../../../AGENTS.md` from the adapter config dir — see
  "Reused unchanged" above), so the standing rules travel. Whether the
  Claude-Code *hook wiring* is bridged is **UNVERIFIED** — Omnigent has its **own** policy
  engine, so the conforming path is the **policy port above** (T618), independent of any hook
  bridge. If a live T620 probe shows the hooks do load, `guard.sh` riding inside
  `omnigent claude` is an *optional* cross-harness upgrade, not a requirement. Either way
  AC1's graceful-degradation clause is satisfied — this is the documented resolution.

## The [reviewer] / [orchestrated run] binding (cross-vendor, Polly-shaped)

The upstream Polly orchestrator is structurally Creance's review-mode `/next-task`: it
delegates each task to an implementer sub-agent in its own worktree, routes the diff to a
**different-vendor** reviewer, and leaves the merge to the human. The §7 gate maps directly:

- The orchestrator (`config.yaml`, T620) is an `omnigent`-executor agent whose
  `instructions: ../../../AGENTS.md` (the repo-root file; see "Reused unchanged") + prompt
  forbid direct coding and encode the `gate-loop.md`
  loop. It dispatches the three `reviewers/*.yaml` sub-agents (T619) — each `purpose: review`,
  each a vendor **other** than the implementer's, each handed only the diff + its contract
  and **no write tools**. A reviewer that returns no verdict counts as **failing, never
  passed** (`gate-loop.md`). The constitution reviewer's `executor.model` is pinned to
  `[frontier]` (AC3), so its tier floor is **structural**, not runtime-checked.
- Until `config.yaml` exists (T620), the gate is the `next-task.md` §7 **prose loop**, run
  exactly as written — the contract's documented `[orchestrated run]` degradation.

## Degradations summary (per `workflow/README.md` → "degrades gracefully")

| Role | Degradation |
|---|---|
| [headless run] | No documented non-interactive one-shot; procedure + args ride in the `omnigent run` prompt/config text (explicit-context); exit-code propagation UNVERIFIED |
| [workflow] | Skills cover on-demand triggering; the scheduler path inherits [headless run]'s degradation; trigger-frontmatter syntax UNVERIFIED |
| [security-review pass] | No dedicated mechanism; security-lens `purpose: review` sub-agent (contract's clause) |
| [craft-review pass] | Optional; advisory `purpose: review` sub-agent, or skipped + noted |
| [orchestrated run] | Stub until `config.yaml` (T620); §7 prose loop meanwhile |
| [guard] on-error posture | Framework fail-open/closed default UNVERIFIED; the port forces fail-open + a T618 test (`TestFailOpen`) |
| [edit guard] firing phase | `tool_result` phase not in `docs/POLICIES.md` (only `tool_call`/`request`); phase-tolerant evaluator, exact phase + edit-arg path key pinned at T620 |
| [visual verification] | Image-feedback-to-model UNVERIFIED; the role's "tests only…" clause otherwise unchanged |
| Everything else | Bound natively (often more strongly — OS-sandboxed reviewers, native worktrees, cross-vendor review) |

## Conformance probes
Deferred to **T620** (`#119` AC5): `omnigent-probes.md` instantiates
`workflow/conformance-probes.md` for this adapter and records dated PASS/FAIL with
fingerprints on a real driver. A binding that reads correctly can still fail on a live
driver (the Claude adapter's own probe run caught two live failures), so this adapter is
**not trusted until T620 probes it**.

## Sources
Verified 2026-06-23 against `github.com/omnigent-ai/omnigent@main` (Apache-2.0):
`docs/POLICIES.md` (policy event/return shape, `policy_modules` / `POLICY_REGISTRY`,
builtins incl. `github_policy` / `cost_budget` / `block_working_dir_changes`),
`docs/AGENT_YAML_SPEC.md` (`executor.harness` / `executor.model`, sub-agent `type: agent`,
`instructions:`, `os_env` / `sandbox`), `examples/polly/config.yaml` (the cross-vendor rule,
`purpose` types, worktree-per-dispatch, "you never merge", `guardrails`), `README.md` (CLI,
install, sandboxes, harness identifiers). Facts marked **UNVERIFIED** could not be confirmed
from those pages and must be pinned during wiring (T618/T620), never assumed.
