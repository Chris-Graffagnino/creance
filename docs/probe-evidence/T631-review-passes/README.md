# P-RP probe evidence — per-enabled-pass review-pass dispatch (T631, US8.AC6)

Live-run artifacts for the **P-RP** conformance probe
(`.claude/workflow/conformance-probes.md` → "P-RP"; instantiated in
`.claude/adapters/claude-code-probes.md`). Summarized in the adapter's probe-results table
(the dated **P-RP** row).

Each `.log` file is a **mechanical capture** — the raw `stdout`+`stderr` of a real headless
dispatch (`claude -p "<pass>" --model sonnet </dev/null`), tee-redirected (`> file 2>&1`),
**not** a hand-composed narrative. Everything below each file's `----- raw capture -----`
fence is the verbatim tool output (the header above it is the only machine-written framing).

## Why a cold-start reviewer can trust these are real dispatches

AC6's bar is that the artifact lets a reviewer **confirm** real dispatch, not merely read a
claim. Two properties make that checkable here:

1. **A run-time nonce the tool echoes back.** Each fixture embeds a freshly generated marker
   string — for this run, `PROBE-00DA47F7556C` (`openssl rand`, produced at probe time). The
   dispatched pass is asked to quote it, and every capture echoes it verbatim. A narrated log
   authored ahead of time could not contain a token that did not exist until the fixture was
   built — this mirrors **P-VV**'s random-token pattern
   (`conformance-probes.md` → "P-VV"), the repo's established way to prove real rendering
   rather than description.
2. **Verbatim per-file:line citations against the *actual* fixture.** The captures cite the
   plants at the line numbers they occupy in the committed fixture
   (`probe_fixture.py:12` credential, `:22` off-by-one, `:29–36` untested `running_max`) — the
   channel demonstrably read the diff, not a template.

## Fixture (available side)

A throwaway git worktree on the fixture branch `fix/probe-t631-avail` (off `main`), one
commit adding `probe_fixture.py` (the nonce in its module docstring) with three planted
defects, one per lens:

- **code lens** — an off-by-one (`range(n + 1)` reads one past the window → `IndexError`),
  at `probe_fixture.py:22`;
- **security lens** — a credential-shaped string in source (a **sensitive-diff**), at
  `probe_fixture.py:12`;
- **craft lens** — a new public function (`running_max`) shipped with **no covering test** (a
  test-adequacy gap), at `probe_fixture.py:29–36`.

## Fixture (absent side)

A second throwaway worktree on `fix/probe-t631-absent` (off `main`) adding a **non-sensitive**
`probe_absent_fixture.py` (a pure `add(a, b)` — no credential/privacy/payment surface), so the
`[security-review pass]`'s `sensitive-diff` condition does **not** hold. The run is driven with
the external `engineering-craft` skill treated as **not installed**, exercising the two-sided
availability branch.

Both worktrees + fixture branches are **deleted after the run** (fixtures, never live state —
the probe leaves the repo as found; `git worktree list` shows only the main tree afterward).
Neither fixture reached `origin` or `main`.

> **Redaction note.** The security-lens plant used a Stripe-live-key-*format* value so
> `/security-review` had a credential candidate to surface. In these committed logs that
> literal value is replaced with `sk_live_REDACTED_SYNTHETIC_PLACEHOLDER` so no secret-shaped
> string lands in `origin` history (it would trip push-protection / secret scanners and
> normalize committing `sk_live_` strings — the exact risk the code-review and craft passes
> flagged live). The redaction touches **only** the literal value; every `file:line`
> reference, the run-time nonce, and all prose are byte-verbatim otherwise.

## Logs

| Log | Pass | Enabled / condition | What the capture evidences |
|---|---|---|---|
| `code-review.log` | `[code-review pass]` | enabled / `always` | `/code-review` dispatched on the fixture diff — nonce echoed; all three plants cited (`:12`, `:22`, `:29–36`) |
| `security-review.log` | `[security-review pass]` | enabled / `sensitive-diff` | `/security-review` dispatched — nonce echoed; reviewed the credential candidate at `probe_fixture.py:12` (then correctly excluded it as a synthetic fixture placeholder — **dispatch** is what AC6 requires, independent of the post-filter verdict) |
| `craft-review.log` | `[craft-review pass]` | enabled / `always` | `engineering-craft review` dispatched — nonce echoed; craft-lens findings, advisory (PR-body framed, no PASS/FAIL gate) |
| `absent-craft.log` | `[craft-review pass]` (mechanism **absent**) | two-sided | nonce echoed; with the `engineering-craft` skill treated as **not installed**, the run names craft **loudly** as "⚠️ UNAVAILABLE / DEGRADED" (refusing a same-context self-pass) while the `[security-review pass]`, enabled but with `sensitive-diff` unmet, stays **silent** (no line) — the AC3 enabled-but-absent → loud branch, with the two not-run cases distinguished |

## Reproduce

From a clean `main` (`<nonce>` is a fresh random token; embed it in each fixture's docstring):

```
git worktree add -b fix/probe-t631-avail <tmp> main
# add probe_fixture.py: nonce in the docstring + the three plants; commit in the worktree
( cd <tmp> && claude -p "/code-review. Also quote the Probe marker verbatim."      --model sonnet </dev/null ) > code-review.raw    2>&1
( cd <tmp> && claude -p "/security-review. Also quote the Probe marker verbatim."  --model sonnet </dev/null ) > security-review.raw 2>&1
( cd <tmp> && claude -p "Run an engineering-craft review … quote the Probe marker" --model sonnet </dev/null ) > craft-review.raw    2>&1
git worktree remove --force <tmp> && git branch -D fix/probe-t631-avail
# absent side: a non-sensitive fixture on fix/probe-t631-absent, engineering-craft treated as absent
```

Confirm each capture echoes `<nonce>` and cites the plants at their fixture line numbers, then
redact only the literal credential value before committing.

Guard fingerprint at run time: `guard=f358a87 wiring=c81604e`.
