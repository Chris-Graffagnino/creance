# P-RP probe evidence — per-enabled-pass review-pass dispatch (T631, US8.AC6)

Live-run artifacts for the **P-RP** conformance probe
(`.claude/workflow/conformance-probes.md` → "P-RP"; instantiated in
`.claude/adapters/claude-code-probes.md`). Each log is the captured output of a **real**
headless dispatch (`claude -p "<pass>" --model sonnet`) of an enabled review pass, so a
cold-start reviewer can confirm the pass was **actually dispatched** — not a self-asserted
`dispatched: yes`. Summarized in the adapter's probe-results table (the dated **P-RP** row).

## Fixture (available side)

A throwaway git worktree on the fixture branch `fix/probe-t631-avail` (off `main`), one
commit adding `probe_fixture.py` with three planted defects, one per lens:

- **code lens** — an off-by-one (`range(n + 1)` reads one past the window → `IndexError`);
- **security lens** — a credential-shaped string in source (a **sensitive-diff**);
- **craft lens** — a new public function shipped with **no covering test** (a dimension-6
  test-adequacy gap).

The worktree + fixture branch are **deleted after the run** (fixtures, never live state — the
probe leaves the repo as found). The fixture never reached `origin` or `main`.

> **Redaction note.** The security-lens plant used a Stripe-live-key-*format* placeholder so
> `/security-review` had a credential candidate to surface. In these committed logs that
> token is replaced with `sk_live_REDACTED_SYNTHETIC_PLACEHOLDER` so no secret-shaped string
> lands in `origin` history (it would trip push-protection / secret scanners and normalize
> committing `sk_live_` strings — the exact risk the craft pass flagged live). The redaction
> touches only the literal value; every `file:line` dispatch reference is intact.

## Logs

| Log | Pass | Enabled / condition | What it evidences |
|---|---|---|---|
| `code-review.log` | `[code-review pass]` | enabled / `always` | `/code-review` dispatched on the fixture diff |
| `security-review.log` | `[security-review pass]` | enabled / `sensitive-diff` | `/security-review` dispatched (reviewed the credential candidate at `probe_fixture.py:8`) |
| `craft-review.log` | `[craft-review pass]` | enabled / `always` | `engineering-craft review` dispatched (craft-lens findings on the fixture) |
| `absent-craft.log` | `[craft-review pass]` (mechanism **absent**) | two-sided | with the `engineering-craft` skill treated as **not installed**, the run names craft **loudly** as unavailable/degraded while a condition-gated pass stays silent — the AC3 enabled-but-absent → loud branch |

## Reproduce

From a clean `main`:

```
git worktree add -b fix/probe-t631-avail <tmp> main
# add probe_fixture.py with the three plants; commit in the worktree
( cd <tmp> && claude -p "/code-review"            --model sonnet </dev/null )
( cd <tmp> && claude -p "/security-review"        --model sonnet </dev/null )
( cd <tmp> && claude -p "/engineering-craft review" --model sonnet </dev/null )
git worktree remove --force <tmp> && git branch -D fix/probe-t631-avail
```

Guard fingerprint at run time: `guard=f358a87 wiring=c81604e`.
