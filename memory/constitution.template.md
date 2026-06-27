# Project Constitution — <PROJECT NAME>

> Copy this file to `memory/constitution.md` and rewrite it for your project. Keep it
> short: 3–7 principles you would refuse a feature over. The constitution auditor
> (`.claude/workflow/reviewers/constitution-auditor.md`) enforces this file as **law** —
> a diff that violates a principle is FAILED in the pre-PR gate, not negotiated. Each
> principle should be concrete enough that a reviewer can hunt for its *failure mode*;
> mirror each one as a checkable rule in `.claude/PROJECT.md` → "Invariant checklist".
>
> **Worked example:** [`docs/examples/lantern/constitution.md`](../docs/examples/lantern/constitution.md)
> is a fully filled version of this file (the fictional "Lantern" project).

The non-negotiable principles for this project. If any feature, growth tactic, or
stakeholder request violates one of these, the default answer is **no**. These break
ties when a decision is unclear.

## Core Principles

### 1. <Principle name>
<What it demands, in product terms. What ships and what never ships. A worked example of
the shape (from this template's source project): "We never punish absence, never display
shame-coded messaging, and never use consecutive-day streaks that reset to zero. Momentum
mechanics may only *fill in* and celebrate; they may never 'break'.">

### 2. <Principle name>
<...>

### 3. <Principle name>
<...>

<!-- Add 4/5/... as needed. Fewer, harder principles beat many soft ones: every one of
     these is enforced adversarially on every PR, so each must be worth blocking a ship
     over. -->
