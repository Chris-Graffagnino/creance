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
