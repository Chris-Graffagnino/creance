# Spec — <FEATURE NAME>

> Skeleton. Copy `specs/000-template/` to `specs/001-<feature>/`, rename
> `spec.template.md` → `spec.md` and `tasks.template.md` → `tasks.md`, fill them in, and
> point `.claude/PROJECT.md` → "Paths" at the result. The `.template.md` suffix keeps the
> skeletons out of the engine's `specs/*/spec.md` / `specs/*/tasks.md` fallback globs, so
> a kept-around template dir can never be selected as a real spec or backlog. The acceptance [reviewer]
> (`spec-auditor`) grades each task against the `US#` acceptance criteria below — bullets
> are addressable as `US1.AC1`, `US1.AC2`, … (the nth bullet under that story), so write
> them as independently checkable statements.
>
> **Worked example:** [`docs/examples/lantern/specs/001-guided-sessions/spec.md`](../../docs/examples/lantern/specs/001-guided-sessions/spec.md)
> is a fully filled version of this file (the fictional "Lantern" project).

## Overview

<One paragraph: what this feature is, who it serves, what "done" means.>

## Non-goals

- <Explicitly out of scope, so reviewers can flag scope creep.>

## User stories

### US1 — <story title>
<As a <user>, I want <capability>, so that <outcome>.>

**Acceptance Criteria**
- <AC1 — a single, testable statement>
- <AC2 — ...>

### US2 — <story title>
<...>

**Acceptance Criteria**
- <AC1 — ...>
