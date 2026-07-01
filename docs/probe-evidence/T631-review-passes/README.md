# P-RP probe evidence — per-enabled-pass review-pass dispatch (T631, US8.AC6)

Live-run artifacts for the **P-RP** conformance probe
(`.claude/workflow/conformance-probes.md` → "P-RP"; instantiated in
`.claude/adapters/claude-code-probes.md`). Summarized in the adapter's probe-results table
(the dated **P-RP** row).

Each `.log` file is a **mechanical capture** — the raw `stdout`+`stderr` of a real headless
dispatch (`claude -p "<pass>" --model sonnet </dev/null`), tee-redirected (`> file 2>&1`),
**not** a hand-composed narrative. Everything below each file's `----- raw capture -----`
fence is the verbatim tool output (the header above it is the only machine-written framing).

> **Round-2 note (gate finding, addressed).** In round 1 (commit `0a90b9e`) two of the three
> available-side captures were genuine raw tool output but recorded a *non-dispatch* while the
> surrounding narrative called them clean dispatches: `code-review.log` opened "The skill
> infrastructure isn't dispatching cleanly …" and `craft-review.log` opened "The reference
> files are locked behind a permission prompt …". The spec-auditor FAILed the round for that
> mismatch. Round 2 re-ran both from a fresh worktree: **`/code-review` now dispatches cleanly**
> (a transient round-1 miss), so its log is the real mechanism output; **`engineering-craft`
> reproducibly cannot load its reference material under the headless driver**, so its log is
> recorded **loudly as DEGRADED** below and in the adapter row — not dressed up as a clean
> dispatch. AC6's available-side "actually dispatched" bar is carried by the two built-in
> passes (`/code-review`, `/security-review`) that genuinely dispatch headless.

## Why a cold-start reviewer can trust these — and what each artifact does / does not prove

AC6's bar is that the artifact lets a reviewer **confirm** real dispatch, not merely read a
claim. Two properties make that checkable, and one distinction keeps the claim honest:

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

**The honest distinction (read this before crediting the craft log).** The nonce + citations
prove the **diff was read** — the channel opened and the diff reached the model. That is
distinct from proving the pass's **full mechanism engaged**. For the two built-in passes
(`/code-review`, `/security-review`) both hold: the capture is a clean mechanism dispatch. For
the external `engineering-craft` pass, only the *diff-was-read* half holds under the headless
driver — the skill's reference material is permission-gated and does not load, so its capture
is a **degraded** pass (skill body's embedded principles, not the full reference-backed
mechanism), recorded loudly as such. Do not read the craft log as a clean dispatch.

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
`[security-review pass]`'s `sensitive-diff` condition does **not** hold. The run exercises the
two-sided availability branch with the external `engineering-craft` skill absent.

> **Modeled absence (read before crediting `absent-craft.log`).** This absent side is a
> **modeled** branch, not a real uninstall: the skill symlink is genuinely present on the
> machine, and the mechanism was made absent by **instructing the driver to treat
> `engineering-craft` as not installed** in the dispatch prompt — the log header labels it as
> such. The artifact proves the driver *emits the loud UNAVAILABLE/DEGRADED outcome* when told
> the mechanism is gone (and keeps a condition-unmet pass silent), which is the AC3 branch under
> test; it does **not** prove the adapter's resolver hit a real missing binding. A concrete,
> non-modeled reproduction is to move the `~/.claude/skills/engineering-craft` symlink aside
> before the run so the resolver genuinely fails to find it; the modeled branch is used here
> because the loud-vs-silent *reporting* behavior is what AC3/AC6 pin, and it is identical
> either way.

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
| `code-review.log` | `[code-review pass]` | enabled / `always` | **Clean dispatch.** `/code-review` (built-in) dispatched on the fixture diff — nonce echoed; all three plants cited (`:12`, `:22`, `:29–36`). Round-2 re-run: the round-1 non-dispatch was transient and is gone (capture opens straight into the review). |
| `security-review.log` | `[security-review pass]` | enabled / `sensitive-diff` | **Clean dispatch — evidenced by candidate-evaluation, not a surviving finding.** `/security-review` (built-in) dispatched — nonce echoed; **surfaced and evaluated** the credential candidate at `probe_fixture.py:12`, then correctly excluded it as a synthetic fixture placeholder (returning "No findings"). Dispatch — what AC6 requires — is evidenced by the candidate being **raised and adjudicated on the diff**, independent of the post-filter verdict; a *surviving* security finding is deliberately not exercised here (a non-synthetic plant would be needed, and must never be committed) |
| `craft-review.log` | `[craft-review pass]` | enabled / `always` | **DEGRADED — full mechanism did not engage.** `engineering-craft` is genuinely installed, but under the headless driver its reference material is permission-gated and does not load; the capture's own first line says so ("The reference files are behind a permission gate …"). Nonce echoed + all plants cited, so the **diff was read**, but this is the skill body's embedded principles, not a reference-backed dispatch — **reproducible** across round 1 and round 2. Recorded loudly per the review standard's "skip the craft layer / Note the skip" rule; **not** counted as a clean available-side dispatch. |
| `absent-craft.log` | `[craft-review pass]` (mechanism **absent** — **modeled**) | two-sided | nonce echoed; with the `engineering-craft` skill **modeled as not installed** (instructed in the prompt, not a real uninstall — see the absent-side fixture note above), the run names craft **loudly** as "⚠️ UNAVAILABLE / DEGRADED" (refusing a same-context self-pass) while the `[security-review pass]`, enabled but with `sensitive-diff` unmet, stays **silent** (no line) — the AC3 enabled-but-absent → loud branch, with the two not-run cases distinguished |

### Degradation disclosure — `[craft-review pass]` under the headless driver

Stated plainly here so no cold-start reviewer mistakes the craft capture for a clean dispatch
(the round-1 gate finding was exactly such a mismatch — a genuine raw capture whose surrounding
claim contradicted its own first line):

- **What degraded:** the `engineering-craft` external skill's **reference material** could not
  be loaded under `claude -p … </dev/null` — it sits behind a permission grant the
  non-interactive invocation is not given. The skill is genuinely installed
  (`~/.claude/skills/engineering-craft` is a real symlink), so this is a *driver* limitation,
  not a missing install.
- **Reproducible, not transient:** both the round-1 run (commit `0a90b9e`) and the round-2
  re-run hit the identical "locked behind a permission prompt" / "reference files are behind a
  permission gate" wall. Contrast `/code-review`, where a round-1 non-dispatch cleared on
  re-run — that one was transient, so its log is now a clean mechanism dispatch.
- **The probe headline is `DEGRADED`, not a bare `PASS`.** Per the neutral contract's Result
  taxonomy (`conformance-probes.md` → "P-RP" → "Result taxonomy"), a run in which an enabled
  applicable pass is present-but-can't-fully-engage is scored **DEGRADED** — clean-dispatched
  where the driver can engage the mechanism, loud-and-disclosed where it can't — precisely so
  the results row can **never** certify an all-clean configuration while an enabled pass didn't
  cleanly fire (the risk a bare `PASS` would carry into a downstream staleness / trust read).
  The adapter's P-RP row records `DEGRADED` for exactly this reason. The headless craft
  degradation is the contract's **documented, expected** degraded-available-side outcome, not an
  unverified branch.
- **AC6 is still satisfied by that honest DEGRADED recording.** AC6's available-side requirement
  is that an enabled, *available* pass be evidenced as **actually dispatched**, and that the run
  **record per-pass dispatch honestly** (including the two-sided availability distinction). The
  two **built-in** passes (`/code-review`, `/security-review`) supply the actually-dispatched
  evidence — both dispatch cleanly headless (see their logs). The external craft pass's
  full-mechanism dispatch is the one this driver cannot evidence, and the review standard's own
  rule for that case (`.claude/workflow/README.md` → "No [craft-review pass] mechanism → skip
  the craft layer … Note the skip in the PR. Do **not** fake it as a same-context self-pass") is
  to name the degradation loudly — which is what the craft log's header, this section, and the
  adapter's P-RP results row all now do. A DEGRADED-but-honest recording is the discipline AC6
  asks for, not a shortfall against it.
- **What the craft capture still contributes:** the nonce echo + fixture-line citations are a
  non-forgeable record that the **diff reached the model** on that dispatch; it is kept as a
  degraded/advisory craft artifact, clearly labeled, not as a clean pass.

## Reproduce

From a clean `main` (`<nonce>` is a fresh random token; embed it in each fixture's docstring):

```
git worktree add -b fix/probe-t631-avail <tmp> main
# add probe_fixture.py: nonce in the docstring + the three plants; commit in the worktree
( cd <tmp> && claude -p "/code-review. Also quote the Probe marker verbatim."      --model sonnet </dev/null ) > code-review.raw    2>&1
( cd <tmp> && claude -p "/security-review. Also quote the Probe marker verbatim."  --model sonnet </dev/null ) > security-review.raw 2>&1
# craft DEGRADES under this headless recipe — its reference material is permission-gated, so this capture is a degraded pass, NOT a clean dispatch; a clean craft dispatch needs an interactive / permission-granted context (see "Degradation disclosure" above)
( cd <tmp> && claude -p "Run an engineering-craft review … quote the Probe marker" --model sonnet </dev/null ) > craft-review.raw    2>&1
git worktree remove --force <tmp> && git branch -D fix/probe-t631-avail
# absent side: a non-sensitive fixture on fix/probe-t631-absent, engineering-craft treated as absent
```

Confirm each capture echoes `<nonce>` and cites the plants at their fixture line numbers, then
redact only the literal credential value before committing.

Guard fingerprint at run time: `guard=f358a87 wiring=c81604e`.
