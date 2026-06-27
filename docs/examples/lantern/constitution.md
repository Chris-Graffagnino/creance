# Project Constitution — Lantern

> **Illustrative example — not live config.** Lantern is a *fictional* privacy-first
> sleep & meditation app, included only to show what a filled `memory/constitution.md`
> looks like. See [`docs/examples/README.md`](../README.md) for the whole set. Copy the
> *shape*, never these contents.

The non-negotiable principles for Lantern. If any feature, growth tactic, or stakeholder
request violates one of these, the default answer is **no**. These principles break ties
when a decision is unclear. Each principle is mirrored as a checkable rule in
[`PROJECT.md`](PROJECT.md) → "Invariant checklist", and the constitution auditor
(`.claude/workflow/reviewers/constitution-auditor.md`) enforces this file as law.

## Core Principles

### 1. We never shame the user into practicing
Reminders, empty states, and re-engagement copy may *invite* and *celebrate*; they may
never guilt, shame, or manufacture urgency. We never ship consecutive-day streaks that
reset to zero, "you broke your streak" messaging, red loss-framed counters, or
notifications that imply the user has failed. A missed session is silent — the next
reminder is as warm as the first. (Failure mode to hunt: loss-framed or
absence-punishing copy in any user-visible string.)

### 2. Session data stays on the device and is never sold
What a person listens to, when they sleep, and how long they meditate is among the most
intimate data we hold. Session records never leave the device except as an
end-to-end-encrypted backup the user explicitly opts into, and we never embed a
third-party analytics, advertising, or attribution SDK — there is no "anonymized
telemetry" exception. (Failure mode to hunt: any analytics/ad/attribution dependency, or
any session field sent to a non-E2EE destination.)

### 3. All generated audio goes through one seam, cached by content hash
Every text-to-speech / guided-narration call routes through the `AudioSynthesisProvider`
interface — no screen or component calls a vendor TTS SDK directly, so the vendor stays
swappable and cost is controlled at one choke point. Identical narration text is served
from a content-hash cache and never re-synthesized or re-billed. (Failure mode to hunt: a
vendor SDK imported outside the provider adapter, or a synthesis path that can re-bill for
text already generated.)

### 4. An inaccessible session screen does not ship
Guided practice is for everyone, including users who cannot see the screen. Every session
surface carries complete VoiceOver/TalkBack labeling and meets WCAG AA contrast; a screen
that fails either blocks the release. (Failure mode to hunt: an interactive control with
no accessibility label, or text/background contrast below AA on a session surface.)
