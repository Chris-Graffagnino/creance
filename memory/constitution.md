# Project Constitution — Creance

The non-negotiable principles for the Creance repo itself (the harness template
developing itself). If any feature, convenience, or stakeholder request violates one of
these, the default answer is **no**. These principles break ties when a decision is unclear. Each
principle is mirrored as a checkable rule in `.claude/PROJECT.md` → "Invariant
checklist", and the constitution auditor
(`.claude/workflow/reviewers/constitution-auditor.md`) enforces this file as law.

## Core Principles

### 1. The engine stays runtime-neutral
The workflow layer (`.claude/workflow/**`) names capabilities as bracketed **[roles]**
only — never a concrete tool, CLI flag, vendor, or model ID. The one exception is `git`:
as the harness's assumed universal VCS substrate it may be named directly in neutral docs
(e.g. `git rev-parse --show-toplevel` to denote the repo root) and is not a violation.
The banned, *runtime-specific* mechanisms — `gh` and other vendor CLIs, model IDs, and
runtime-only tokens — live exclusively in `.claude/adapters/` and skill bindings, and
project facts live exclusively in `.claude/PROJECT.md`. A Claude-Code-specific (or any
runtime-specific) instruction inside `workflow/**`, or a project fact baked into an
engine file, never ships.

### 2. No silently dead guards
Enforcement machinery must be proven live, not assumed live. Any change to guard
behavior ships in the same diff with a matching `guard.test.sh` case, including wiring
assertions that would catch matcher drift in `settings.json`. Machinery that cannot
demonstrate it still fires (the DESIGN-NOTES "the guard was silently dead" class) is
treated as broken, not as probably-fine.

### 3. Determinism over model judgment
Where a rule can be enforced by a deterministic check — a test, a lint, a CI
consistency step — that check must exist. Engine text that depends on a model
"noticing" something a deterministic check could enforce is a defect: either add the
backstop or explicitly justify its absence. Model judgment is the fallback layer, never
the load-bearing one.

### 4. The harness never modifies itself silently
Every change to reviewer specs, invariants, guards, or this constitution lands as a
human-reviewed PR with an evidence trail — never as an automatic rewrite, prompt
auto-tuning, or side effect of a gate run (spec 001 non-goals). Feedback loops may
*propose* tightening; only a reviewed merge may *apply* it.

### 5. Telemetry observes; it never decides
Gate telemetry and retrospective records are append-only observations. They never
affect gate outcomes, never reassign model tiers, and never alter gate semantics
(round limits, veto authority, tier floors). A measurement channel that gains control
authority has violated this principle, whatever the convenience.
