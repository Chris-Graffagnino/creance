# Dry run — demand-loaded `workflow/next-task` cards through the Codex CLI adapter

A desk walkthrough of the neutral per-task procedure executing on the Codex CLI adapter
(`adapters/codex-cli.md`), section by section. **Method and claim:** every step below
resolves its **[roles]** through the adapter's table alone; the concrete Codex commands
shown below stay in this adapter document rather than becoming workflow instructions.
Separately, `bash .claude/hooks/neutrality-scan-coverage.test.sh` scans every tracked workflow Markdown file for the shared banned runtime-mechanism vocabulary. This is a *dry*
run: building/executing a Codex runner is an explicit non-goal; where a step would
execute, the concrete invocation is shown instead, and anything that can only be
confirmed by a live run is listed at the end under "What only a live run can prove"
(those are exactly the conformance probes).

Worked example task: `T401` (hypothetical UI-touching task line `T401 [strong] …` in the
profile's tasks file).

## Launch ([workflow] / [headless run])

Scheduler or user starts the run per the adapter's [workflow] binding — headless form,
explicit-context rule satisfied in the prompt text:

```
codex exec -m <strong-tier row> --sandbox workspace-write --approval never \
  --output-last-message run-T401-summary.md \
  "Read .claude/PROJECT.compact.md and .claude/workflow/next-task/00-foundations.md.
   Execute task T401 by following each card's Next: link without preloading other cards.
   Repo root: <abs path>. Adapter: .claude/adapters/codex-cli.md.
   Escalate to .claude/PROJECT.md only for a fact omitted from the compact packet."
```

The model/effort flags come from the adapter's model table row for the task's `[strong]`
tag (tier tags are authoritative — no judgment call). `AGENTS.md` (= this repo's
`CLAUDE.md` content) loads natively, so the standing instructions arrive without any
porting step.

## §0 Preconditions
Plain `git`/`gh` shell calls inside the sandbox: `git rev-parse --show-toplevel`,
`git status`, `gh auth status`. Routine read-only commands proceed unattended under the
[permission allowlist] binding (the sandbox boundary + `--approval never`). Nothing
role-bound beyond that; no neutral-doc edit needed.

## §1–§2 Select the task, read the context
The tasks file, spec, contract, and constitution paths all come from `PROJECT.md` —
project layer, untouched. Bulk reading goes through the [bulk-read offload] binding:

```
codex exec --sandbox read-only -m <cheap-tier offload row> --output-last-message ctx.md \
  "Brief: summarize the acceptance criteria for US4 in specs/001-bird-journal/spec.md
   and any contract under specs/001-bird-journal/contracts/ touching the heatmap."
```

Separate process = separate context; kernel read-only; returns a summary, not file dumps.

## §3 Find the issue
`gh issue list --search "T401"` — shell, same as the active adapter; the slug derivation
snippet is in `PROJECT.md` (project layer). The [environment block] consulted is the
Codex adapter's own (stdin-prompt form, UTF-8 file rule) — note the *role* in the neutral
doc resolved to a *different* concrete block with no neutral-doc change, which is the
point of the role.

## §4 Branch + [guard]
`git switch -c feat/T401-heatmap-fill`. From here the [guard] binding is live:
PreToolUse hooks veto bulk staging, base-branch commits/pushes, and base-targeting
refspecs (rules 2–4); rule 1 holds at commit time per the adapter's documented
compensating control; rule 5 will screen the constitution-reviewer dispatch in §7.

## §4.5 Plan artifact
`[strong]` task → post the plan comment via `gh issue comment T401's-issue --body-file
plan.md`. Checkpoint, not a gate — the run proceeds immediately. No role beyond shell.

## §5–§6 Implement, verify
Maker work inside `workspace-write`; the blocked-dependency rule (mock behind the
profile's named seam) and §5.5 discovered-work filing are executor instructions in the
neutral doc — runtime-independent by construction. Tests/lint/typecheck are shell. For a
UI-touching task, §6.5's [visual verification] resolves per the adapter: run the
project's screenshot tooling (network flag on for the dev server), seed fixtures, commit
evidence under `docs/visual-evidence/T401/`, and re-read the artifact with `--image` so
the "it renders" claim is checked against pixels. No display available → the literal
"tests only — no visual evidence produced" statement goes in the PR body with the
surfaces listed unverified.

## §7 Pre-PR gate
The adapter's [orchestrated run] is a stub, so the documented degradation applies: §7's
prose loop, exactly as written. Step 1 self-review is the maker's. Step 2 fans out
reviewer processes in parallel (acceptance + constitution; contract if the seam/data
model is touched):

```
codex exec --sandbox read-only --approval never -m <strong-tier row> \
  -c model_reasoning_effort="<strong-tier effort>" --ephemeral \
  --output-last-message verdicts/constitution.md \
  "Read .claude/workflow/reviewers/constitution-auditor.md and execute it against this
   branch's diff vs main. Task: T401. Profile: .claude/PROJECT.md.
   Return ONLY the verdict report."
```

(acceptance/contract run the same shape on the cheap row, task ID passed to the
acceptance reviewer.) Guard rule 5 inspects this very command — `-m`/effort present and
at-or-above the strong row, else veto. Step 3 is `codex review` on the branch. Step 4:
any FAIL → fix → re-dispatch that reviewer; two non-converging rounds → stop and surface.
Step 5: the `--output-last-message` files **are** the kept verdicts, verbatim by
construction.

## §8 Open the PR — then stop
`gh pr create --body-file pr.md` (UTF-8 per the adapter's environment block), `Closes #…`,
Discovered work / Mocked dependencies / Run economics lines — the Run economics line here
reads e.g. `tier=[strong] → <strong-tier row> @ <its effort>, no round-up` with the
resolved names from the adapter's model table. Each verdict file is
posted verbatim via `gh pr comment --body-file verdicts/<reviewer>.md`. Visual evidence
embeds via commit-SHA-pinned raw URLs. Review mode: stop, don't merge. Exit code
propagates to the scheduler per the [headless run] binding.

## Result

| Neutral section | Roles consumed | Bound by the adapter? |
|---|---|---|
| Launch | [workflow], [headless run] | yes (workflow: documented degradation — name rides in prompt text) |
| §0–§3 | [permission allowlist], [bulk-read offload], [environment block] | yes |
| §4–§4.5 | [guard] | yes (rule 1: documented commit-time degradation) |
| §5–§6.5 | [visual verification] | yes (incl. the role's own loud-degradation clause) |
| §7 | [reviewer], tiers, [code-review pass] / [security-review pass], [orchestrated run] | yes ([orchestrated run]: stub → §7 prose degradation; [security-review pass]: security-lens reviewer run) |
| §8 | [environment block], [headless run] | yes |

Every role the procedure consumes resolves through `adapters/codex-cli.md`; every gap is
a degradation that `workflow/README.md` already defines, invoked as written. **No
`workflow/**` file changed meaning, wording, or required any accommodation.**

## What only a live run can prove

The walkthrough validates the *binding*; it cannot validate the *driver*. Before this
adapter runs real work, execute its probe instantiation table
(`adapters/codex-cli.md` → "Probe instantiation", per
`workflow/conformance-probes.md`) — most critically P-GD (the hook gap boundary), P-RV
(kernel read-only + FAIL-with-evidence), P-HL (fresh-state + exit codes), and P-WF
(whether named custom prompts take arguments as documented). That checklist exists
precisely because this document alone is not evidence the binding works.
