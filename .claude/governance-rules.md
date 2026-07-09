# Governance rules — the deterministic-check accounting (spec 007 US6)

This registry accounts for the governance-rule candidate set from epic #166 slice 5
(spec `007-workflow-context-economy` US6; landed by T1206/#252): which rules are
**encoded** as deterministic checks, which are **cited** from coverage another story
owns, and which stay **prose** with an explicit constitution-P3 justification — never
silently dropped, never re-implemented where coverage already exists.

`.claude/hooks/governance-coverage-check.sh` parses the table below and FAILs standing
verification when an accounted row stops being true — an `encoded-*` row whose check
file is missing, whose anchor no longer appears in it, or whose wiring no longer runs
it, or a `prose-P3` row without its justification section here. Its failures always
name the file to repair (US6.AC3). That keeps this registry from becoming the
hand-maintained summary class spec 007 exists to prevent (P2).

## The accounted rules

| rule | status | check | anchor | wiring |
|---|---|---|---|---|
| `merge-not-pre-approved` | `encoded-carried` | `.claude/hooks/guard.test.sh` | `settings #165: no gh pr merge pre-approval` | `.github/workflows/ci.yml` |
| `budget-checks-wired` | `encoded-cited` | `.claude/hooks/token-budget-check.sh` | `--require-counter` | `.github/workflows/ci.yml` |
| `pr-creation-after-documented-review` | `prose-P3` | — | — | — |

Column semantics (the coverage check parses exactly these): **check** — the file
carrying the deterministic implementation; **anchor** — a literal string that must
appear in that file (the carried test-case name, or the flag the citation depends on);
**wiring** — the standing-verification file that must reference the check file's
basename, so "asserted still running" is a grep, not a promise. `encoded-carried` =
implemented by an earlier task and asserted live here; `encoded-cited` = implemented
AND proven by another story's own tests — this registry only verifies the citation
still resolves; `prose-P3` = not deterministically encodable, justified below.

## `merge-not-pre-approved` (carried: T623/#165; audited + extended: T1206/#252)

**Rule.** No `[permission allowlist]` entry may pre-approve a merge command in default
review mode — merge authorization is session-explicit, so the allowlist prompt is the
deterministic wall between a run and an unauthorized merge.

**Carried implementation.** The T623 regression in `.claude/hooks/guard.test.sh`
(case `settings #165: no gh pr merge pre-approval`) replays Claude Code's prefix match
over every `Bash(...)`/`PowerShell(...)` allow spec in the committed
`.claude/settings.json` and FAILs if any would authorize a merge command — catching a
literal re-add and an over-broad prefix alike. It runs in `verify` (ci.yml runs
`guard.test.sh`); this registry's coverage check asserts both the case and the wiring
stay present.

**T1206 audit record.** One concrete gap found and closed; the rest of the surface is
walled elsewhere or out of reach:

- **Gap (closed):** the replay's only representative command was `gh pr merge`, but the
  GitHub **API merge route** (`gh api --method PUT repos/…/pulls/N/merge`) is a merge
  command with no guard backstop — an over-broad `Bash(gh api:*)` or `Bash(gh:*)` allow
  would have pre-approved promptless merges the replay could not see. (This #252 record
  originally judged the committed allowlist's `gh api --method GET:*` "method-scoped and
  safe" — **T641/#254 later proved it is not**; see the T641 bullet below.) The T623 block now
  replays the API-merge representatives (`--method PUT` and `-X PUT` spellings), flags
  any `gh api` spec naming a merge endpoint directly (a literal one-shot PUT-merge spec
  shares no prefix with a representative), and ships two-sided detector cases (planted
  violating specs detected; benign controls not).
- **Gap (closed) — T641/#254:** `Bash(gh api --method GET:*)` (and its PowerShell twin) was
  itself merge-authorizing. Claude's `Bash(pre:*)` ≡ `Bash(pre *)` word boundary makes the
  entry auto-approve `gh api --method GET repos/…/pulls/N/merge --method PUT`, whose last-wins
  pflag method is **PUT** → a promptless merge. It named no `merge` token, so the #252 clauses
  above missed it — and the `:782` detector control encoded it as SAFE. Closed both ways
  (owner's recorded Option 2 + narrow): (1) **both twins were dropped** from
  `.claude/settings.json` — no `:*` `gh api` form can be safely pre-approved, so the raw
  `gh api --method GET` reads the `pr-review` / `review-response` skills use for inline PR
  comments now **prompt** on an interactive run or route through the GitHub MCP server (their
  SKILL.md guidance was corrected to drop the now-disproven "write-incapable entry" reasoning);
  and (2) `approves_merge` was **extended** to flag any `gh api …:*` wildcard that pins no
  positional endpoint (only `gh api`, optionally a `--method`/`-X` method flag), so any future
  re-add of such a spec fails the sweep. Two-sided cases ship in `guard.test.sh` (fires on
  `gh api --method GET:*` / `-X GET:*`; a fully-pinned non-`:*` GET spec stays a passing
  control).
- **`git merge` pre-approval — considered, not a gap:** landing a local merge requires a
  push to the base branch, and guard rules 3/4 deterministically veto any `git push`
  from `main` or any refspec targeting `main`, from any branch, including the `git -C`
  / `cd &&` evasions (`guard.test.sh` r3/r4 cases). The wall holds downstream of the
  allowlist.
- **`git pull` — considered, not a gap:** a merge of the remote into the local branch —
  the sanctioned §0 update path; it cannot land unreviewed work on the remote base, and
  the landing walls above are unaffected.
- **`settings.local.json` — documented boundary:** untracked and machine-local, so CI
  cannot audit it; the committed `settings.json` is the audited artifact. A local
  pre-approval is the owner acting on their own machine — the same authority that could
  merge by hand.
- **Representative, not exhaustive — documented boundary:** the replay proves specific
  merge spellings are not authorized; a hypothetical endpoint alias that names no
  `merge` token would sit outside the sweep. Same posture as T623 itself: extend the
  representative list when an audit finds a live spelling.

## `budget-checks-wired` (cited: US1.AC2, owned by T1201/#247)

**Rule.** The compact-context/token-budget checks run in standing verification.

**Coverage.** Owned by spec 007 **US1.AC2**: `verify` runs
`token-budget-check.sh --require-counter` plus its test suite, and
`token-budget-check.test.sh` itself asserts that wiring (its section J). Cited here,
not re-encoded — this registry's coverage check only verifies the citation resolves
(the check file exists, still carries `--require-counter`, and ci.yml still runs it);
the two-sided budget proofs live with T1201 and are not duplicated.

## `pr-creation-after-documented-review` (prose, P3-justified)

**Rule.** A PR is created only after verification results and the required review
passes are documented.

### P3 justification — pr-creation-after-documented-review

This candidate is **procedural, not deterministically encodable**: it constrains the
*ordering of actions inside an agent session* (verify → review → document → create),
and no repository state a CI check can witness proves that ordering at the moment it
matters — CI runs only *after* the PR exists. A PR-body lint could check documentation
*presence*, but presence is not precedence: a body pasted after creation, or written
before any verification ran, would pass it identically, making the check a vacuous
encoding (the class US6.AC1 forbids claiming). The rule therefore stays prose, carried
by the per-task procedure's §7 pre-PR gate and §8 PR-body evidence standard
(`workflow/next-task.md`), with two honest backstops short of encoding: the §7 gate's
reviewer verdicts are posted on the PR itself (checkable after the fact), and the
gate-run telemetry records each dispatch (observe-only, P5 — it witnesses, it never
gates). Model judgment is the fallback layer here because it is the only layer with
visibility into the ordering; per constitution P3, that absence of a deterministic
backstop is hereby explicit, not silent.

## Resident-prose accounting (US6.AC2)

Per encoded rule, the resident prompt prose points at the deterministic check instead
of restating the procedure. Audit at landing (T1206): **no resident surface restated
either encoded rule's procedure** — `AGENTS.md`'s "Autonomy and Merge Rules" carries
the per-turn *conduct* rules (which must stay resident) and now a one-line pointer at
the deterministic backstop and this registry; the full rationale lives here and in the
`guard.test.sh` block comment, nowhere resident. The budget rule was born encoded
(T1201) and never had resident prose; its documentation home is
`.claude/context-budgets.md`.
