# Project Profile — Lantern

> **Illustrative example — not live config.** Lantern is a *fictional* privacy-first sleep
> & meditation app, included only to show what a filled `.claude/PROJECT.md` looks like (a
> worked counterpart to [`.claude/PROJECT.template.md`](../../../.claude/PROJECT.template.md)).
> Paths below describe Lantern's *own* repo layout (`memory/`, `specs/`, …) as if it were a
> real project; in this example tree those files live beside this one. See
> [`docs/examples/README.md`](../README.md) for the whole set. Copy the *shape*, never these
> contents.

## Identity
- **Project:** Lantern — a privacy-first sleep & meditation app (on-device session data,
  guided audio narration).
- **Repo model:** direct. Issues/PRs live on `origin`; derive the slug at runtime
  (e.g. `gh repo view --json nameWithOwner -q .nameWithOwner`), never hardcode it.
- **Base branch:** main

## Paths
- **Constitution (law):** `memory/constitution.md`
- **Spec (acceptance criteria):** `specs/001-guided-sessions/spec.md`
- **Tasks (backlog):** `specs/001-guided-sessions/tasks.md`
- **Contracts dir:** `specs/001-guided-sessions/contracts/`
- **Architecture guardrails:** this file → "Architecture boundaries".
- **Telemetry:** default — out-of-repo beside the triage inbox:
  `<triage inbox dir>/lantern-telemetry.jsonl`.
- **Maker-eval records:** none (Lantern does not run a maker eval).

## Finding things in this repo
The engine mandates search-first; these bounded `rg` recipes mine the `specs/` tree by the
artifact you need. Each uses only a path convention from **Paths** above.
- **A story's acceptance criteria** — `rg -n "US1" specs/*/spec.md`
- **A task line by ID** — `rg -n "T101" specs/*/tasks.md`
- **A contract by capability / seam** — `rg -n "AudioSynthesis" specs/*/contracts/`
- **An invariant by keyword** — `rg -n "analytics" memory/constitution.md .claude/PROJECT.md`

## Task & branch conventions
- **Task ID format:** `T` + 3 digits, unique across all live `specs/*/tasks.md`.
- **Model tier tag:** every task line carries `[frontier]`/`[strong]`/`[cheap]` — the task's
  MINIMUM capability tier, resolved via `.claude/MODELS.md`. Untagged → executor judges,
  leaning strong.
- **Criterion ownership (multi-task stories):** `specs/001-guided-sessions/tasks.md` carries a
  "Criterion ownership" section mapping each `US#.AC<n>` to exactly one owning task.
- **Issue / PR / commit title:** `<type>: [<task-id>] <description>` for task work;
  `<type>: <description>` for repo maintenance.
- **Branch name:** `<type>/<issue#>-<short-slug>`.
- **Issue lifecycle:** create-on-demand — an issue is opened before the first file edit and
  closed by the PR (`Closes #<n>`).

## Blocked / owner-only tasks (never auto-start — surface them instead)
- **T103** — provisions the production `AudioSynthesisProvider` API key **and** chooses the
  default narrator voice (a brand/values decision). Needs an owner credential and an owner
  call; never auto-start — surface it.

## CI / merge gate / definition of done
- **Required check:** `verify` (`.github/workflows/ci.yml` — unit tests, the no-analytics
  import scan, accessibility lint).
- **Merge-gate ruleset:** `main` requires `verify` green + 1 review; never bypass.
- **Reviewer profile:** the owner is a designer, not an engineer — separate "verified
  automatically" (engineering) from "your call" (product/values) in every PR body.
- **Coverage policy:** the audio pipeline (`AudioSynthesisProvider` and its cache) carries a
  90% line threshold so cost/privacy-critical code can't silently regress.

## Architecture boundaries (the only allowed seams)
All access to these capabilities must go through the named interface — never a vendor SDK
from UI/component code. A leaked vendor type/error/option in a public surface is a FAIL.
- Guided-audio synthesis (text-to-speech) → `AudioSynthesisProvider`
  (contract: `specs/001-guided-sessions/contracts/audio-synthesis-provider.md`).
- **Banned vendors / sources:** **TrackKit Analytics** (a behavioral-analytics + ad-attribution
  SDK) — banned because it exfiltrates per-session behavioral data, violating Principle 2.
  No "anonymized" exception.

## Invariant checklist (the auditors enforce these exactly)
Concrete, checkable rules from the constitution. Each maps to a principle above.
- User-visible copy (notifications, empty states, re-engagement) uses guilt/shame/urgency
  framing, a zero-resetting streak, or loss-framed "you failed" messaging — FAIL (Principle 1).
- Any analytics/advertising/attribution SDK is added as a dependency, or a session field is
  sent to a non-E2EE destination — FAIL (Principle 2).
- A component imports a vendor TTS SDK directly instead of routing through
  `AudioSynthesisProvider`, or a synthesis path can re-bill for already-generated text — FAIL
  (Principle 3).
- A session surface ships an interactive control with no accessibility label, or text/background
  contrast below WCAG AA — FAIL (Principle 4).

### Invariant → enforcement mapping
Map EVERY checklist item to the auditor rule that hunts it and, where one exists, a
deterministic lint/test backstop. Items with no concrete hunt rule are marked
**judgment-only** explicitly.

| Invariant | Auditor rule | Deterministic backstop (lint/test) |
|---|---|---|
| No shame/guilt/urgency copy or zero-resetting streaks (Principle 1) | constitution-auditor: hunt loss-framed/absence-punishing strings in user-visible copy | **judgment-only** — copy tone is not reliably mechanizable |
| No analytics/ad/attribution SDK; no session field to a non-E2EE sink (Principle 2) | constitution-auditor: hunt a tracking dependency or an off-device session write | `no-analytics-imports.sh` in CI `verify` — fails on any banned-SDK import (paired plant/pass) |
| Audio only through `AudioSynthesisProvider`; cache-by-hash never re-bills (Principle 3) | contract-auditor: a vendor TTS SDK called outside the seam, or a vendor type leaking a public surface | partial — an import-scope grep flags a direct vendor SDK import outside the adapter; the re-bill check is judgment-only |
| Every session control labeled; AA contrast (Principle 4) | constitution-auditor: hunt an unlabeled control on a session surface | `a11y-lint` in CI `verify` covers contrast + missing labels; subtler label *quality* stays judgment-only |

## Constitution watch (high-risk upcoming work — for triage look-ahead)
- Any new re-engagement / notification surface → re-screen against Principle 1 (shame copy).
- Any new data export, backup, or sync feature → re-screen against Principle 2 (off-device
  session data) → guard when T2xx reminder-sync work lands.
- A second audio vendor or an offline TTS path → re-screen Principle 3's seam + cache invariant.
