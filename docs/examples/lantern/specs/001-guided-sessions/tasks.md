# Tasks — Guided Sessions

> **Illustrative example — not live config.** Part of the *fictional* Lantern worked-example
> set (a filled counterpart to [`specs/000-template/tasks.template.md`](../../../../../specs/000-template/tasks.template.md)).
> Task-line format: `- [ ] T<nnn> [<tier>] <description> (US<#>)`. The
> `[frontier]`/`[strong]`/`[cheap]` tag is the task's **minimum capability tier**, resolved
> through `.claude/MODELS.md` at run time. See [`docs/examples/README.md`](../../../README.md).

## Phase 1 — Audio pipeline

- [ ] T101 [strong] Implement the `AudioSynthesisProvider` interface and a content-hash
      narration cache so identical text is never re-synthesized or re-billed (US1)
- [ ] T102 [cheap] Add accessibility labels to every session-player control and pass the
      `a11y-lint` WCAG AA contrast + missing-label check — the mechanical floor (US1)
- [ ] T104 [strong] Verify the accessibility labels are *meaningful* and the player is fully
      navigable in order by VoiceOver/TalkBack — the judgment `a11y-lint` can't make (US1)

## Phase 2 — Reminders

- [ ] T201 [strong] Build opt-in reminder scheduling with a no-shame copy guardrail — no
      guilt/urgency framing, no zero-resetting streak, no "you failed" on a missed session (US2)

## Criterion ownership (multi-task user stories)

> Each acceptance criterion is owned by exactly one task — the acceptance reviewer grades a
> task hard only on the criteria it owns; sibling criteria are `deferred-to:<task>`, not failed.

| Criterion | Owning task |
|---|---|
| US1.AC1 | T101 |
| US1.AC2 | T101 |
| US1.AC3 | T102 |
| US1.AC4 | T104 |
| US2.AC1 | T201 |
| US2.AC2 | T201 |

## Blocked / owner-only tasks (never auto-start — surface them instead)

- [ ] T103 [strong] Provision the production `AudioSynthesisProvider` API key **and** choose
      the default narrator voice — needs an owner credential and a brand/values decision, so it
      is never auto-started; surface it instead.
