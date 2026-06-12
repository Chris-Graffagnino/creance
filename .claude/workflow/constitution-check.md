# constitution-check — the gate that cannot be skipped (runtime-neutral)

Run this against the current diff (`git diff main..HEAD`) before any PR.

> Runtime-neutral: project facts come from `.claude/PROJECT.md`. This is the same checklist
> the constitution **[reviewer]** applies; run it inline as a self-check, or delegate to the
> reviewer for maker≠checker independence.

## Read the rules first (every run)
1. `.claude/PROJECT.md` → **"Invariant checklist"** (the concrete, checkable rules and their
   FAIL/JUSTIFY dispositions) and **"Architecture boundaries"**. This is the operative list.
2. The constitution named in `PROJECT.md` → "Paths" (e.g. `memory/constitution.md`) — the
   principles behind the invariants. **Law.**

Do not re-derive or soften the rules; apply them as written. If `.claude/PROJECT.md` is
missing, grade against the constitution alone and say so.

## Evaluate
For every item in the invariant checklist, find its concrete failure mode in the diff and the
files it touches (not the abstract principle). Translate each rule into a search: e.g. a "must
never decrement/reset" rule → look for the state mutation that could go down; a "no PII/egress"
rule → trace every new network/SDK/upload/analytics call; a "remains user-correctable" rule →
confirm the override/edit path survives; a banned word → grep user-facing strings.

## Verdicts
Output a verdict per item:
- **PASS** — the diff upholds the invariant.
- **JUSTIFY** — the diff trips a rule the checklist marks JUSTIFY; the deviation must be
  documented (e.g. in `plan.md`) with a rationale.
- **FAIL** — the diff breaks a rule the checklist marks FAIL. **Any FAIL blocks the PR.**

## Output format
A short table: item → verdict → one-line evidence (`file:line`). End with an overall
**PASS / JUSTIFY / FAIL** and, if not PASS, the exact blocking items.
