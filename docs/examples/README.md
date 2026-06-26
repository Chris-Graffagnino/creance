# Worked examples — a filled harness, end to end

Every fill-in artifact in this template ships as a **skeleton**. This directory shows what a
**filled** one looks like, so an adopter writing their own `PROJECT.md`, constitution, spec,
tasks, or contract has a concrete target to copy the *shape* from.

> **All of this is fictional and illustrative — never live config.** The example project,
> **"Lantern"** (a privacy-first sleep & meditation app), does not exist. Nothing here is read
> by the engine: the live profile is `.claude/PROJECT.md`, the live law is
> `memory/constitution.md`, and the live backlog is `specs/*/tasks.md`. Copy the **shape**, not
> the contents.

## What's here

| Example | Filled counterpart of | Shows |
|---|---|---|
| [`lantern/PROJECT.md`](lantern/PROJECT.md) | [`.claude/PROJECT.template.md`](../../.claude/PROJECT.template.md) | every required heading; an invariant→enforcement mapping with both a **judgment-only** row and a **deterministic-backstop** row; an architecture boundary with a **banned vendor**; a **blocked/owner-only** task |
| [`lantern/constitution.md`](lantern/constitution.md) | [`memory/constitution.template.md`](../../memory/constitution.template.md) | 4 enforceable, failure-mode-hunting principles — one with a deterministic backstop, one judgment-only |
| [`lantern/specs/001-guided-sessions/spec.md`](lantern/specs/001-guided-sessions/spec.md) | [`specs/000-template/spec.template.md`](../../specs/000-template/spec.template.md) | two user stories in `US#.AC#` form, written as independently checkable statements |
| [`lantern/specs/001-guided-sessions/tasks.md`](lantern/specs/001-guided-sessions/tasks.md) | [`specs/000-template/tasks.template.md`](../../specs/000-template/tasks.template.md) | tier-tagged tasks, the criterion-ownership mapping, and a blocked owner-only task |
| [`lantern/specs/001-guided-sessions/contracts/audio-synthesis-provider.md`](lantern/specs/001-guided-sessions/contracts/audio-synthesis-provider.md) | [`specs/000-template/contracts/example-provider.md`](../../specs/000-template/contracts/example-provider.md) | a swappable provider seam whose name matches a boundary in the example `PROJECT.md` |
| [`environment-block-macos-linux.md`](environment-block-macos-linux.md) | the Windows `[environment block]` in [`.claude/skills/next-task/SKILL.md`](../../.claude/skills/next-task/SKILL.md) | the macOS/Linux translation of the single live environment block — **an example to copy from, not a second live block** |

## How the example hangs together

The fiction is internally consistent on purpose, so it doubles as a model of the
cross-references the auditors check:

- The spec's `US1`/`US2` are the stories the `tasks.md` lines map to, and every acceptance
  criterion is owned by exactly one task (the criterion-ownership table).
- The `AudioSynthesisProvider` contract names the same seam the example `PROJECT.md` lists under
  "Architecture boundaries".
- Each constitution principle reappears as a checkable rule in the `PROJECT.md` invariant
  checklist — including the deterministic-backstop one (no analytics SDK) and the judgment-only
  one (no shame-coded copy).

## A note on neutrality

The set carries **no `MODELS.md`** and names **no concrete model** — it refers to capability
tiers as **roles** (`[strong]`, `[cheap]`) only, exactly as the real profile does. That keeps
the single-source-of-models property intact: across the whole repo, model names live only in
`.claude/MODELS.md`.
