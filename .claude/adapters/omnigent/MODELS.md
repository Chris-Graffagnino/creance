# Model table — Omnigent adapter

This is the **only file in this adapter that names models.** Everything else in
`.claude/adapters/omnigent/` — `README.md`, `environment.md`, and the future
`config.yaml` / `reviewers/*.yaml` / `creance_omnigent/**` (T618–T620) — references
capability **tiers** as `[roles]`; this table resolves a tier to a concrete model (and an
effort level, where the runtime exposes a dial). Swapping a model for its successor is a
one-line edit here, with zero re-tagging anywhere else. This table is **per-adapter**: the
Claude Code adapter's table is `.claude/MODELS.md`, the Codex CLI adapter's is the table
section in `adapters/codex-cli.md` — the harness is not bound to any one vendor.

The rows below are a **sensible default — swap per your account** (the harnesses you have
credentials for, the models each exposes). Omnigent resolves a worker's available models
at run time via `sys_list_models`, and an invalid model/worker combination **fails loud at
dispatch** (`examples/polly/config.yaml`), so a wrong row surfaces immediately rather than
silently falling back. Keep the three-tier shape and the ordinal order.

## Primary tier → model (the implementer / orchestrator-brain path)

| Tier (ordinal, highest first) | Model | Harness (`executor.harness`) | Effort |
|---|---|---|---|
| **[frontier tier]** | `claude-opus-4-8` | `claude-sdk` | high (dial **UNVERIFIED** — see below) |
| **[strong tier]** | `claude-opus-4-8` | `claude-sdk` | — (no dial assumed) |
| **[cheap tier]** | `claude-haiku-4-5` | `claude-sdk` | — |

`claude-opus-4-8` on the `claude-sdk` harness is the **grounded** default — it is the brain
model the upstream Polly orchestrator resolves to (`examples/polly/config.yaml`, ~1M-token
context). Whether `claude-sdk` exposes a per-invocation reasoning-**effort** dial through
Omnigent is **UNVERIFIED**; pin it when wiring (T620). Where no dial exists, ignore the
Effort column — tier resolution is unaffected (`workflow/README.md` → "No effort dial").

## Cross-vendor reviewer resolution (used by T619; see [reviewer] in `README.md`)

Omnigent's defining property is **cross-vendor review**: "review is ALWAYS done by a
DIFFERENT vendor than the implementer" (`examples/polly/config.yaml`). So a `[reviewer]`
never resolves to the implementer's vendor. When the implementer ran on `claude-sdk`
(the primary path above), the reviewers resolve to a **different-vendor** model
**at or above** the dispatched tier:

| Reviewer | Tier floor | Cross-vendor model | Harness |
|---|---|---|---|
| acceptance / contract `[reviewer]` | **[cheap tier]**, rounded to a different vendor | `gpt-5.5` | `codex` (or `openai-agents`) |
| constitution `[reviewer]` | **[frontier tier]** (pinned — `#119` AC3) | `gpt-5.5` | `codex` (or `openai-agents`) |

The concrete `executor.harness` pins for each reviewer sub-agent are declared in
`reviewers/{spec,constitution,contract}.yaml` (**built at T619**); each carries its tier as
the `executor.model` **role token** (`[frontier tier]` / `[cheap tier]`), never a concrete
id — this table is the single source that resolves those roles. If your account has no
second vendor, cross-vendor review degrades to same-vendor-different-context review — note
the degradation loudly in the PR (`workflow/README.md` → "How an adapter degrades
gracefully"); it is a real loss of the maker≠checker *vendor* independence, not a silent
fallback.

### Harness → vendor (the single source the T619 cross-vendor check reads)

The cross-vendor rule compares **vendors**, not harnesses — `codex` and `openai-agents` are
one vendor; `claude-sdk` another. So the check needs a harness→vendor resolution and the
implementer's harness to compare against.

**Implementer / orchestrator harness:** `claude-sdk` (the primary path above). Every
`[reviewer]` must resolve to a harness whose vendor **differs** from this one.

| Harness | Vendor |
|---|---|
| `claude-sdk` | anthropic |
| `codex` | openai |
| `openai-agents` | openai |

`tests/test_reviewers.py` (the T619 deterministic check) reads **both** the implementer
line and this table at run time — nothing about vendors is hardcoded in the check, and no
vendor/model vocabulary leaks outside this file (`#119` AC4). Adding a vendor is a one-row
edit here; the reviewers and the check follow with no other change.

## How a consumer resolves a tier (semantics in `workflow/README.md` → binding contract)

- **A tier tag is a minimum.** Resolve to that tier's row; if the row's model is
  unavailable for the worker, round **up** to the nearest tier above — never down. Only
  when nothing at-or-above exists may a run drop below its tag, and it must say so loudly
  in the PR.
- **Per-dispatch, explicit.** A `[reviewer]` dispatch passes its resolved model on the
  dispatch itself (`args.model` on the orchestrator's dispatch call, backed by the
  sub-agent's `executor.model`) — never inherited from ambient config, for the same reason
  the Claude adapter forbids omitting the Agent-tool `model` parameter.
- **Floor:** the constitution `[reviewer]` is always dispatched at-or-above the
  **[strong tier]** row; this adapter pins it to **[frontier]** (`#119` AC3), which
  satisfies the floor by rounding up.
- **[bulk-read offload]** uses the **[cheap tier]** row on a `purpose: explore`/`search`
  sub-agent.

## Sources
Verified 2026-06-23 against `github.com/omnigent-ai/omnigent@main`:
`examples/polly/config.yaml` (the Polly brain model, `args.model` dispatch, `sys_list_models`,
the cross-vendor rule), `docs/AGENT_YAML_SPEC.md` (`executor.harness` / `executor.model`),
`README.md` (harness identifiers). Facts marked **UNVERIFIED** could not be confirmed from
those pages and must be pinned during wiring (T620), never assumed.
