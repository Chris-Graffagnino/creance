# Spec — Guided Sessions

> **Illustrative example — not live config.** Part of the *fictional* Lantern worked-example
> set (a filled counterpart to [`specs/000-template/spec.template.md`](../../../../../specs/000-template/spec.template.md)).
> The acceptance reviewer (`spec-auditor`) grades each task against the `US#` criteria below —
> each criterion is addressable by its `AC#:` label (`US1.AC1`, `US1.AC2`, …). See
> [`docs/examples/README.md`](../../../README.md).

## Overview

Guided Sessions lets a user play a spoken-word meditation or sleep session with synthesized
narration and receive gentle, opt-in reminders to practice. "Done" means a user can start a
session, hear narration produced through the audio seam (served from cache on replay), and —
if they opt in — get reminders that never shame them for a missed day.

## Non-goals

- No social features, leaderboards, or shareable streaks (Principle 1 forbids the streak
  mechanic outright).
- No cloud account or server-side session history in this slice — session data stays on-device
  (Principle 2). Encrypted backup is a later spec.
- No offline/on-device TTS engine yet — a single cloud `AudioSynthesisProvider` implementation
  is in scope; the seam keeps a second one cheap later.

## User stories

### US1 — Play a guided session with synthesized narration
As a listener, I want a guided meditation with spoken narration, so that I can follow along
with my eyes closed.

**Acceptance Criteria**
- AC1: All narration audio is produced through the `AudioSynthesisProvider` interface — no
  screen or component calls a vendor TTS SDK directly.
- AC2: Replaying a session whose narration text is unchanged serves audio from the
  content-hash cache: no re-synthesis and no re-billing for identical text.
- AC3: Every interactive control on the session player screen carries a non-empty
  accessibility label, and the screen meets WCAG AA contrast — the mechanical floor the
  `a11y-lint` backstop checks.
- AC4: The accessibility labels are *meaningful* and the player is fully navigable in order by
  VoiceOver/TalkBack — the label-quality judgment the lint cannot make.

### US2 — Gentle, non-shaming reminders
As a returning user, I want optional reminders to practice, so that I remember Lantern without
being made to feel guilty.

**Acceptance Criteria**
- AC1: Reminder copy contains no guilt, shame, or manufactured-urgency framing, and no
  zero-resetting streak language.
- AC2: A missed session never triggers a "streak broken" or "you failed" notification — the
  next reminder is as warm as the first.
