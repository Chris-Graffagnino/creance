# Design notes — why the harness is shaped this way

Companion to [`EXTRACTION.md`](EXTRACTION.md). The methodology docs say *what* each piece
does; this file says *why*, capturing the load-bearing decisions whose rationale otherwise
lives only in out-of-repo auto-memory and would be lost the moment the engine is copied to a
new repo. Read it before you delete, merge, or "simplify" anything — several pieces that look
like ceremony are scar tissue from real failures, noted inline.

---

## The one-sentence thesis

Treat an autonomous coding agent like a CI pipeline you don't trust: make every run start
identically, make the dangerous actions deterministically impossible rather than discouraged,
make a *different* context grade the work, and verify every "done" claim against an artifact
rather than the model's say-so.

---

## 1. Three layers, and the falsification test

The split is **methodology (neutral) / adapter (runtime) / profile (project)** so each axis
moves independently: a new project rewrites only the profile; a new runtime writes only an
adapter; the neutral core never changes for either.

The discipline is enforceable, not aspirational: a grep of `workflow/**` must surface **no**
mechanism, vendor, or model names — only `[role]` references. If a runtime need ever leaks
upward, the fix is a **new role** in the binding contract (append a row), never a mechanism
name in the neutral layer. The Codex CLI adapter stub (`adapters/codex-cli.md`) was written
specifically as a falsification test — binding all roles to a *second*, very different runtime
with zero edits to `workflow/**`. It passed, which is the evidence the split is real and not
just Claude-Code-shaped prose.

## 2. Maker ≠ checker

The §7 pre-PR gate dispatches the reviewers (`spec`/`constitution`/`contract` auditors) as
**read-only subagents in their own context**, and loops until every one returns PASS. The
maker may not override a FAIL. Rationale: self-critique is weak — the agent that wrote the
code shares its blind spots — and independent-context verifiers measurably outperform a
second self-review pass. The reviewers have no edit tools by construction, so "the checker
quietly fixed it" is impossible. Verdicts are saved verbatim and posted to the PR, so the gate
outcome is durable and a human review can shrink to "read the verdicts, spot-check, merge."

## 3. The explicit-context rule (born from a production failure)

No workflow step may depend on an environment variable or an inferred working directory for
*correctness*. The wrapper that starts a run resolves every value (paths, repo root, log
locations) and passes it **in the invocation's prompt text**; env vars may be set only as
redundant hints. Rationale is empirical, not stylistic: a headless triage run **ignored its
env-var path hints in production** until the launcher moved the paths into the prompt — an LLM
executor honors prompt text far more reliably than environment. The triage launcher contract
(`triage.md` §6) is the worked example. (Scar tissue: `triage.md` §4 itself resolved the
inbox path env-var-first for a while — a latent contradiction caught by the P-EC conformance
probe and fixed so the neutral doc matches the rule it states.)

## 4. The [guard] is deterministic and fails *open*

A PreToolUse hook (`guard.sh`) vetoes a fixed list of dangerous actions *before* they execute:
editing on the base branch, `git add .`, committing/pushing to base, pushing to a base refspec,
and dispatching the constitution reviewer below the strong tier. Two deliberate properties:

- **Deterministic — no model judgment in the decision.** A guard that asks the model whether
  to block is not a guard.
- **Fails open — uncertainty allows.** A guard that fails closed becomes a productivity tax
  that gets disabled. Fail-open keeps it trusted and always-on; the review gate and CI are the
  backstops for whatever slips through.

### The guard was silently dead — and unit tests didn't catch it

The single most important lesson in this codebase. Guard rule 5 (the constitution-reviewer
strong-floor) was **dead on the live driver** for a stretch: `settings.json`'s PreToolUse
matcher omitted `Agent|Task`, so subagent dispatches never reached `guard.sh` at all — while
`guard.test.sh` stayed green the whole time, because it tested the *script's logic*, not the
*wiring* that routes events to it. The probe run (P-GD.5) caught it. The fix added a
**wiring assertion** to the test suite: the matcher must route every tool the script handles,
so a routing regression now fails CI. **Takeaway for extraction:** the matcher in
`settings.json` is load-bearing; keep `Agent|Task` in it, and never assume "tests pass" means
"the hook fires."

## 5. The model table is the *only* file that names models

Tiers are an **ordinal ladder** (`frontier > strong > cheap`); a task tag is a *minimum
capability requirement*, not a model name. Every doc, skill, agent, and hook references tiers;
`MODELS.md` alone resolves a tier to a concrete model (+ optional effort dial). Consequence: a
model swap is a one-line edit with zero re-tagging, and a grep for model vocabulary across the
whole tree must hit exactly one binding file. The agents carry **no model pin** — an omitted
dispatch model silently inherits the session's model, which for the constitution reviewer on a
cheap session would be a forbidden downgrade; that's precisely why guard rule 5 makes the
absence of an explicit model a veto.

## 6. The constitution reviewer has a strong-tier *floor*

It never downgrades, even when the task itself runs cheap. The constitution is the product
thesis treated as law; the cheapest place to lose a project is shipping a values/constitution
violation unattended. So the one check that protects the thesis is pinned at-or-above strong —
deterministically, via guard rule 5, not via instruction-following.

## 7. Probe before you trust

`conformance-probes.md` is one verifiable probe per role — because **a binding that reads
correctly can still not work on a real driver.** This isn't theoretical: when the probes were
finally executed against the *active, production-trusted* adapter, **two probes failed live**
(the dead guard matcher in §4, and the env-var-first launcher in §3) despite both reading
correctly on paper. The rule: never trust a binding on a new runtime, or after a mechanism
changes, until its probes pass. The extraction's verification step (`EXTRACTION.md` §5) is a
direct application.

## 8. The dead-man switch

`/triage` is a read-only daily heartbeat that writes a state snapshot to an out-of-repo inbox.
But a heartbeat can only report runs that *happen* — if the scheduler stops firing or the
headless run dies before writing, nothing inside the workflow can flag it. So detection lives
one level down, in the **launcher** (`triage.md` §6 contract): one run-log line per attempt,
appended *after* the agent exits (so the last line always describes a completed attempt),
unconditional (try/finally — even a crash writes `exit=1`), with the inbox header's "next run
expected" date making staleness self-describing to a reader who checks nothing else. The
launcher is out-of-repo and per-platform; the contract is what every rewrite must honor.

## 9. One task → one issue → one branch → one PR; review mode by default

Each task runs in its own fresh context (a headless run, not a continued chat) because a task
must fit one context window without compaction — the **repo + issue + PR + profile +
constitution are authoritative; the conversation is disposable.** State is checkpointed to
disk continuously (commit, PR, issue comments) so an interrupted task is recoverable from disk
alone. The default is to open the PR and **stop** — autonomous merge only on explicit
authorization.

## 10. PR bodies separate "verified automatically" from "your call"

So a non-developer owner reviews only what they can judge. Every "verified automatically"
claim must cite evidence from the run (a command output, CI result, or a posted reviewer
verdict) — an explicit anti-fabrication rule, because an unverified "it works" is worse than a
flagged "untested." Every "your call" item ends with a `Decision needed:` / `Recommendation:`
pair so the owner sees exactly what they're deciding.

## 11. Context residency — frequency-weighted placement

Orthogonal to §1's axis-of-change split, the files form a tiered cache by **frequency of
use**, and every piece of guidance must live at the cheapest tier that serves it:

- **Always resident (L1):** `AGENTS.md` (imported by `CLAUDE.md` into every session) and
  skill frontmatter descriptions. Only rules that apply to *every turn* belong here.
- **One discovery step (L2):** skill bodies that defer to `workflow/*.md` ("read that file
  now and execute it") — loaded only when the skill fires.
- **Per-task fetch (L3):** the profile, specs, contracts, and constitution — read per
  `workflow/next-task.md` §2.
- **Below L1 — deterministic code:** anything expressible as a check goes in the guard
  (§4) instead of the prompt. "Never push to main" costs zero resident tokens because it
  is a veto, not an instruction.

The failure mode this prevents is invisible: the template invites filling `AGENTS.md`
placeholders, and an adopter who pastes a full procedure manual or style guide into it
taxes every session of every task. A deterministic CI check
(`hooks/agents-residency-check.sh`, in the `verify` job) now backstops the *blunt* form of
this — it FAILs if `AGENTS.md` grows past a line ceiling — but the *subtler* form (inlining
a procedure that still fits under the ceiling) stays a judgment call, and bloated resident
context degrades model accuracy on every turn. The `AGENTS.md`
"Discovered Work" section (a summary plus a pointer to `next-task.md` §5.5) is the worked
example of the intended pattern: the per-turn rule stays resident, the full procedure
lives one fetch away.

## 12. The reviewer roster is one table with derived mirrors, not three hand-synced lists

The §7 gate's reviewer set — *membership, tier, and dispatch-condition* — is declared once,
as the roster table in `workflow/gate-loop.md`. Two other sites restate it: the §7 prose
procedure in `next-task.md` (the degradation path used when no [orchestrated run] exists)
and the `reviewers` array in `workflows/gate-loop.js` (the executable adapter). Those two
are **derived mirrors**, not independent copies — each says so in place — and a CI-wired
bash test (`hooks/reviewer-roster.test.sh`, in the `verify` job) FAILs the moment any site
disagrees with a hardcoded canonical set.

It reads like triplicated cruft: three places saying the same thing, plus a test whose only
job is to assert they still match. Leave it. The three forms exist for three different
readers — the runtime-neutral methodology (the roster *is* the source of truth), the
human-readable §7 procedure, and running code — and none can be dropped without losing a
consumer. Before the roster existed they were hand-synced with **nothing checking
agreement**, so a reviewer quietly dropped from one site, or a tier/condition that drifted,
sailed through CI. That is exactly the "silently dead machinery" failure this codebase has
already lived through once (the dead guard matcher, §4) and that the constitution names as a
first-class hazard (**P2**). The drift test converts "a reviewer fell out of the gate" from
a model-noticing risk into a deterministic check, and — like `guard.test.sh` — it ships in
the same PR as the thing it guards.

So the redundancy is load-bearing: **one source of truth + derived mirrors + an independent
drift oracle.** Collapsing it back into three hand-edited lists, or deleting the test as "it
only checks the obvious," re-opens the silent-drift hole the roster was built to close. Two
constraints keep the roster itself honest: it names only spec-paths, tiers, and conditions —
never a model (**P1**); and its dispatch-conditions are restricted to two deterministic
values (`always`, `dispatch-contract`), so no model judgment ever lands on the gate's
load-bearing path (**P3**).

---

## 13. Two governance checks, opposite fail directions — the [guard] fails open, [autonomy activation] fails closed

`guard.sh` fails **open**: on any uncertainty it allows the action. That is correct for review
mode, where a human merge is the wall — a guard that blocked on doubt would tax every edit until
someone disabled it (§4). The `[isolated workspace]` role (T610, epic #81) adds a *second*
deterministic governance check, `autonomy-mode.sh`, and it fails the **opposite** way — **closed
to review** on any uncertainty (unreadable profile, ambiguous/duplicate opt-in, a non-`enabled`
value).

The inversion is deliberate, not an inconsistency. The two checks guard different directions of
the same wall:
- The **guard** decides *may this edit/commit proceed*. Failing open keeps work moving; the wall
  to the base branch is elsewhere (a human merge, or — under autonomy — the §7 gate).
- The **activation check** decides *is the human-out-of-the-loop path even on*. Failing open here
  would silently switch autonomy **on**, the one thing a blast wall must never do. So it defaults
  off and fails closed: absent a clear, explicit signal = review mode.

This is why isolation does **not** require retuning the guard's fail-open posture under autonomy
(the design question the epic carried for intake). The guard can keep failing open *inside* an
ephemeral workspace because nothing there reaches the base branch except a §7 gate PASS —
promotion is the gate's, never a direct write (P4). The wall moved from the guard to the
workspace + gate; the guard's posture is unchanged. A future maintainer "harmonizing" the two
checks to one fail direction would break exactly this: a fail-closed guard re-creates the
productivity tax, and a fail-open activation check silently enables autonomy.

---

## 14. The isolated workspace is a lifecycle, split from the gate that fills it

T610 defined the `[isolated workspace]` model and the default-off `[autonomy activation]` check
(§13); T611 binds the *mechanism* — `hooks/isolated-workspace.sh`, a pair of worktree primitives
(`enter <branch>` → an ephemeral git worktree on a fresh branch, path printed on stdout; `exit
<path>` → tear the workspace directory down) — and wires the activation read into the autonomous
`next-task` path (§0.5/§4). Three decisions are load-bearing and easy to "simplify" wrongly:

- **`enter` fails *loud* — the inverse of the guard.** If a workspace can't be created, `enter`
  exits non-zero with **no path on stdout**, and the caller's contract is to **abort** the
  autonomous run — never fall back to editing the main tree on the base branch. A fail-open
  `enter` (or a caller that reads an empty path as "just work here") would run un-isolated
  autonomous work, exactly what isolation prevents. Same fail-direction logic as `autonomy-mode.sh`
  (§13): the parts that decide *whether* and *where* autonomy runs fail safe; only the guard
  (which decides whether a single edit proceeds) fails open.
- **`exit` removes the workspace *directory*, never the branch.** The committed work's fate —
  promote on a §7 PASS, discard on a FAIL — is the **gate's** call (T612), not the lifecycle's.
  So `exit` is a pure directory teardown; T612's discard path *is* `exit`, its promote path is
  "push/PR first, then `exit`." A lifecycle that deleted the branch would be silently making the
  gate's promote/discard decision.
- **The lifecycle ships *without* the gate that consumes it (T611 vs T612).** T611 wires only
  enter/exit + the activation read; the §7 gate reading the workspace diff and the promote/discard
  path are T612, the falsification proof is T613. The intermediate state is *safe by
  construction*: with no promotion code, an autonomous run executes in a worktree but still ends at
  the review-mode PR, so nothing reaches the base branch outside the normal §7-gated human path.
  The split keeps each PR reviewable (the Phase 8/9 epic-splitting precedent) without ever shipping
  a half-built promotion path.

---

## Things that look like cruft but are not — quick index

| Looks droppable | Why it stays |
|---|---|
| `Agent\|Task` in the settings matcher | Without it, guard rule 5 is silently dead (§4). |
| The constitution reviewer's strong floor | The one check that protects the product thesis; pinned deterministically (§6). |
| Agents having no `model:` pin | Forces explicit per-dispatch models; the omission is itself a guard veto (§5). |
| The dated probe *results* | Evidence the "probe before you trust" thesis caught real bugs (§7). Keep as the worked example even after resetting the live table. |
| The launcher's run-log-after-exit ordering | The dead-man switch only works if the last line is always a *completed* attempt (§8). |
| Passing paths in prompt text *and* env | The explicit-context rule — prompt text is the carrier, env is a redundant hint (§3). |
| The Codex CLI stub | The falsification test that proves the layer split is real (§1). |
| The reviewer roster's three sites + its drift test | One source of truth + two derived mirrors + an independent drift oracle; collapsing it back into hand-synced lists re-opens the silent-drift hole the roster closed (§12). |
| `fetch-depth: 0` on the CI checkout | Without it the #69 checkbox-drift gate (`check-tasks-consistency.sh` rule 3) is silently dead in CI: `actions/checkout` fetches one commit — on a PR the merge commit — so `git log` sees no `[T###]` and the gate passes vacuously (§4 silent-death class). `check-tasks-consistency.test.sh`'s CI-wiring assertion FAILs if it is dropped. |
| The [edit guard]'s *delta* baseline, and `shell-lint.sh` running BOTH at edit time and over all hooks in CI | The delta (vs. the committed `HEAD` blob, not "any current failure") keeps a file with a pre-existing failure editable, so guard rule 7 taxes only *new* breakage and stays trusted (§4 fail-open ethos); collapsing it to "block on any current failure" re-creates the productivity tax that gets guards disabled, and its `guard.test.sh` delta case FAILs. The CI sweep is the *second* consumer of the same checker — it catches a non-portable hook the edit guard never saw (it predates the guard, or was edited on a runtime without the hook), the passes-locally-fails-CI class (#79/#97). |
| `lib-tasks-drift.sh` as a separate file two scripts source | One drift definition, two consumers — the CI gate (`check-tasks-consistency.sh` rule 3, #69) and the runtime selection precondition (`reconcile-task-selection.sh`, #80/T608). Inlining it back into either forks the "done-but-unchecked" logic the gate and the selector must agree on — the same hand-synced-duplication hole the reviewer roster closed (§12). `reconcile-task-selection.test.sh` asserts both still source it, so a re-fork FAILs CI. |
| `autonomy-mode.sh` failing *closed* while `guard.sh` fails *open* | Opposite fail directions are intentional, not a bug to reconcile: the guard decides "may this edit proceed" (fail open keeps work moving, the wall is elsewhere); the activation check decides "is the human-out-of-the-loop path on" (fail open would silently enable autonomy). Harmonizing them to one direction re-opens one of the two holes (§13). |
| `isolated-workspace.sh exit` leaving the branch behind (and `enter` failing loud, not falling back) | `exit` removes the workspace *directory* only; promoting vs discarding the committed work is the §7 gate's call (T612), not the lifecycle's — an `exit` that deleted the branch would silently make that decision. And `enter` must fail loud with no path so the caller aborts rather than running un-isolated on the base branch (§14). |
