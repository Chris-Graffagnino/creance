# Model table — Claude Code adapter

This is the **only file in this adapter that names models**. Everything else —
`workflow/**`, `PROJECT.md`, the skills, the agents, the hooks — references capability
**tiers**; this table resolves a tier to a concrete model (and an effort level, where the
runtime exposes a dial). Swapping a model for its successor is a one-line edit here, with
zero re-tagging anywhere else. This table is **per-adapter**: every adapter carries
exactly one of its own (the Codex CLI spec's table in `adapters/codex-cli.md` is the
worked second example) — the harness is not bound to this adapter's vendor.

The rows below are a **sensible default at extraction time — swap per your account**
(available models, plan, runtime): edit the Model column only; nothing else in the harness
re-tags. Keep the three-tier shape and the ordinal order.

| Tier (ordinal, highest first) | Model | Effort |
|---|---|---|
| **[frontier tier]** | `fable` | high |
| **[strong tier]** | `opus` | — (no dial: column ignored) |
| **[cheap tier]** | `sonnet` (`haiku` acceptable for [bulk-read offload]) | — |

How a consumer resolves a tier (semantics in `workflow/README.md` → binding contract):

- **A tier tag is a minimum.** Resolve to that tier's row; if the row's model is
  unavailable in the current environment, round **up** to the nearest tier above — never
  down. Only when nothing at-or-above exists may a run drop below its tag, and it must say
  so loudly in the PR (the degradation rules in `workflow/README.md`).
- **Headless [workflow] runs** pass the resolved model as the model flag:
  `claude -p "/<workflow> <args>" --model <model>`.
- **[reviewer] dispatch** passes the resolved model **explicitly on every dispatch** (the
  Agent tool's `model` parameter). The agent files carry **no model pin of their own** — an
  omitted parameter silently inherits the session's model, which for the constitution
  [reviewer] on a cheap-tier session would be a forbidden downgrade.
- **Floor:** the constitution [reviewer] is always dispatched at-or-above the
  **[strong tier]** row, even when the task itself runs cheap (the per-stage tier map in
  `workflow/next-task.md`).
- **[bulk-read offload]** spawns the `Explore` subagent on the [cheap tier] row's model.
- **Effort** is set where Claude Code exposes a dial (session-level model selection for
  models that support effort levels); there is no per-dispatch effort parameter. Where no
  dial applies, ignore the column — the tier still resolves (the "degrades gracefully"
  rule in `workflow/README.md`).
