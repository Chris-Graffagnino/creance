/* global args, agent, parallel, log */
// .claude/workflows/gate-loop.js — the Claude Code binding of the [orchestrated run]
// role. The runtime-neutral spec is .claude/workflow/gate-loop.md (next-task §7 as
// code). This script owns §7 steps 2/4/5 — parallel reviewer fan-out, fix-and-
// re-dispatch, the non-convergence stop, verbatim verdict retention. The maker's
// self-review (§7.1), /code-review (§7.3), and posting the verdicts to the PR (§8)
// stay with the invoker. Invoke it on a task branch with the work COMMITTED — the
// reviewers audit the committed diff (`git diff main..HEAD`), which the loop obtains and
// hands to them in the dispatch prompt because their bindings grant no shell to run `git`
// themselves (read-only by construction, #188). Under an engaged isolated autonomous run
// (next-task §0.5/§4), pass `workspacePath` so the reviewers and the fixer audit the
// committed diff of the [isolated workspace] at that path instead of the main working
// tree (gate-in-place, T612) — the path is passed EXPLICITLY, never inferred from CWD
// (the explicit-context rule). Omit it for review mode and the gate is byte-identical.
//
// Every return path carries `telemetry`: the gate-run record payload defined by
// workflow/telemetry.md, minus the timestamp/repo envelope and the introducing-commit
// ref (this runtime has no clock or filesystem). The DISPATCHER appends it to the
// telemetry stream after the run returns — stamping timestamp/repo and `commit` (the
// audited HEAD) then — so a failed write can never block, fail, or alter the gate
// (telemetry observes; it never decides).
//
// Models are NEVER named here: .claude/MODELS.md is the adapter's only model-naming
// file. The invoker resolves the tier rows and passes them in `args`:
//   taskId           (required) task/issue ID the acceptance reviewer grades against
//   strongModel      (required) MODELS.md [strong tier] row — the constitution floor
//   cheapModel       (required) MODELS.md [cheap tier] row — acceptance + contract
//   dispatchContract (default false) true when the diff touches a provider
//                    interface, monetization, or the data model (§7's rule)
//   dispatchSpec     (default false) true when the diff adds, edits, or renames a
//                    specs/*/spec.md (git A/M/R; a pure deletion D does not fire)
//   maxFixRounds     (default 2) the §7 non-convergence bound
//   fix              (default true) false → one report-only fan-out, no fix stage
//   workspacePath    (optional) the [isolated workspace] path whose committed diff the
//                    reviewers + fixer audit (gate-in-place under autonomous mode, T612);
//                    absent → the main working tree (review mode, unchanged)
//   taskBranch       (optional; review mode) the task branch the dispatcher cut — passed so the
//                    fix step restores the SHARED working tree onto it before each fix/re-dispatch
//                    round (#140/T622); absent under autonomous mode (the work is isolated)

export const meta = {
  name: 'gate-loop',
  description:
    'next-task §7 pre-PR gate as code: parallel auditor fan-out, fix, re-dispatch only failures, two-round non-convergence stop, verdicts kept verbatim',
  whenToUse:
    'From /next-task §7 on a committed task branch. Requires args {taskId, strongModel, cheapModel} — the invoker resolves the models from .claude/MODELS.md.',
  phases: [
    { title: 'Dispatch', detail: 'parallel reviewer fan-out (re-dispatch: failures only)' },
    { title: 'Fix', detail: 'maker-role agent commits minimal fixes for blocking findings' },
  ],
};

// Tolerate a JSON-encoded string args (an invoker that stringifies reaches the script
// as one string); anything else unparseable falls through to the hard errors below.
let input = args;
if (typeof input === 'string') {
  try {
    input = JSON.parse(input);
  } catch {
    input = null;
  }
}

if (!input || !input.taskId) {
  throw new Error(
    'gate-loop: args.taskId is required — the acceptance reviewer cannot grade without it.',
  );
}
if (!input.strongModel || !input.cheapModel) {
  throw new Error(
    'gate-loop: args.strongModel and args.cheapModel are required. Resolve them from the ' +
      '[strong tier] / [cheap tier] rows of .claude/MODELS.md and pass them explicitly — the ' +
      'constitution floor must never depend on inherited session state.',
  );
}

const MAX_FIX_ROUNDS = input.maxFixRounds === undefined ? 2 : input.maxFixRounds;
const APPLY_FIXES = input.fix === undefined ? true : Boolean(input.fix);

// The whole report is captured verbatim — `report` is exactly what §8 posts to the PR,
// so the gate's evidence cannot be lost or paraphrased.
const VERDICT_SCHEMA = {
  type: 'object',
  required: ['verdict', 'report'],
  properties: {
    verdict: { type: 'string', enum: ['PASS', 'JUSTIFY', 'FAIL'] },
    report: {
      type: 'string',
      description:
        'Your complete verdict report exactly as your spec defines it (item-by-item table, ' +
        'overall verdict, evidence) — verbatim markdown; it is posted to the PR unchanged.',
    },
  },
};

// Single-quote a path for safe embedding in a generated shell command. A valid workspace temp
// path may legitimately contain spaces or shell metacharacters; embedded unquoted it would split
// into multiple args and malform the `git -C <path>` command the diff-provider and fixer are told to run
// (Codex P2, PR #114). POSIX single-quoting: wrap in '…', and close/escape/reopen each embedded
// single quote ('\'') so the whole path stays one argument verbatim.
const shellQuote = (s) => `'${String(s).replace(/'/g, `'\\''`)}'`;

// Where the committed diff under review is read. Default: the main working tree (review mode).
// Under an engaged isolated autonomous run the invoker passes `workspacePath`, and the diff is
// read from THAT worktree via an explicit `git -C <path>` (gate-in-place, T612) — explicit
// context, never an inferred CWD. The path is shell-quoted so a space/metacharacter cannot
// malform the generated command.
const WORKSPACE = input.workspacePath;
const TASK_BRANCH = input.taskBranch; // review-mode fix-round restore target (#140/T622); absent under autonomous mode
const diffCmd = WORKSPACE ? `git -C ${shellQuote(WORKSPACE)} diff main..HEAD` : `git diff main..HEAD`;
const diffTarget = WORKSPACE
  ? `the committed diff of the ISOLATED WORKSPACE at ${WORKSPACE} (the autonomous run's branch, ` +
    `produced by \`${diffCmd}\` — NOT the main working tree)`
  : `the current branch's committed diff (produced by \`${diffCmd}\`)`;

// The reviewers are read-only BY CONSTRUCTION: their Claude Code bindings grant only
// Read/Grep/Glob — NO shell (#188) — so they cannot run `git` to obtain the diff themselves.
// The loop provides it. `provideDiff` dispatches a git-capable helper that runs `diffCmd`
// (workspace-scoped under an isolated run) and returns the committed diff verbatim; the loop
// embeds it in each reviewer's prompt. The helper GRADES nothing — it is not a checker — so
// maker≠checker is intact: the graders (the reviewers) hold no write capability, and a separate
// fixer owns every edit. It is re-run per dispatch round because a fix commit changes the diff.
// (The reviewers therefore never touch the working tree's branch, closing the #140/T622
// reviewer-drift vector by construction; the restore step below now guards only the loop's
// remaining shell-holding agents — this helper and the fixer — see "The loop".)
const provideDiff = (round) =>
  agent(
    `Output the committed diff under review for the pre-PR gate, and NOTHING else. Run exactly ` +
      `this and return its complete output verbatim as your final message — no summary, no ` +
      `commentary, no code fence:\n\n    ${diffCmd}\n\n` +
      `Make NO change to any file or branch — this is a read-only step.`,
    { label: `diff-provider-round-${round}`, phase: 'Dispatch' },
  );

// A reviewer's dispatch prompt, built around the provided diff. The reviewer audits the embedded
// diff (it has no shell to produce one) and uses Read/Grep/Glob for the current files it touches.
// `diffCmd` is named as provenance so the audited tree (main vs the isolated workspace) is explicit.
// An empty diff is called out loudly so a reviewer cannot PASS vacuously (the T612 class).
const reviewerPromptFor = (diff) =>
  `Task under review: ${input.taskId}. Audit ${diffTarget} per your spec. You have read-only ` +
  `tools only (Read/Grep/Glob) and NO shell, so the committed diff under review is provided below ` +
  `— audit it, and use Read/Grep/Glob to inspect the current files it touches and their ` +
  `surrounding code. Set 'verdict' to your overall verdict and put your full verdict report, ` +
  `verbatim, in 'report'.\n\n` +
  `----- BEGIN COMMITTED DIFF (${diffCmd}) -----\n` +
  `${diff && String(diff).trim() ? diff : '(empty — no committed diff was produced; treat the ' +
    'change as UNVERIFIABLE and do NOT return PASS)'}\n` +
  `----- END COMMITTED DIFF -----`;

// DERIVED FROM the reviewer roster in workflow/gate-loop.md → "The reviewer roster" — the
// single source of truth for gate membership, tier, and dispatch-condition. This array is
// the adapter-side encoding of that table: spec-auditor (cheap/always) + constitution-
// auditor (strong/always) as the unconditional set, contract-auditor (cheap) pushed only
// under the `dispatch-contract` condition, and spec-quality-auditor (strong) pushed only
// under the `dispatch-spec` condition. Do NOT edit membership/tier/condition here in
// isolation — change the roster, then mirror it here. reviewer-roster.test.sh (CI `verify`)
// FAILs if this site drifts from the roster.
//
// `tier` is the bracketed tier name the reviewer is dispatched at — it is what the
// telemetry record carries (telemetry.md: tier names, never model IDs; the model args
// are never copied into the payload).
const reviewers = [
  { key: 'spec-auditor', model: input.cheapModel, tier: 'cheap' },
  { key: 'constitution-auditor', model: input.strongModel, tier: 'strong' },
];
if (input.dispatchContract) {
  reviewers.push({ key: 'contract-auditor', model: input.cheapModel, tier: 'cheap' });
}
if (input.dispatchSpec) {
  reviewers.push({ key: 'spec-quality-auditor', model: input.strongModel, tier: 'strong' });
}

const verdicts = {}; // reviewer key → its LATEST {verdict, report}, verbatim
let pending = reviewers;
let fixRoundsUsed = 0;

// Telemetry accumulators for the `gate-run` record (workflow/telemetry.md). The loop
// only BUILDS the payload; the dispatcher appends it to the stream after the run
// returns — so a failed write structurally cannot alter the gate outcome.
const roundsHistory = []; // one entry per dispatch round: [{ auditor, tier, verdict }]
const failReports = {}; // "<auditor>:round-<n>" → verbatim FAIL report, or "NO-RESULT"

// The record minus the fields the script cannot produce (timestamp needs a clock; repo
// and `commit` — the audited HEAD — need the filesystem) — the dispatcher stamps those
// at append time, reading `commit` after the run so fix-round commits are included.
const telemetry = (outcome) => ({
  record: 'gate-run',
  task_id: input.taskId,
  rounds: roundsHistory,
  fix_rounds_used: fixRoundsUsed,
  outcome,
  fail_reports: failReports,
});

while (true) {
  log(
    `Gate dispatch ${fixRoundsUsed + 1}/${MAX_FIX_ROUNDS + 1}: ${pending.map((r) => r.key).join(', ')}`,
  );
  // Obtain the committed diff for THIS round (it changes after a fix commit) and hand it to the
  // read-only reviewers, which cannot fetch it themselves (#188).
  const diff = await provideDiff(fixRoundsUsed + 1);
  const reviewerPrompt = reviewerPromptFor(diff);
  const results = await parallel(
    pending.map(
      (r) => () =>
        agent(reviewerPrompt, {
          label: r.key,
          phase: 'Dispatch',
          agentType: r.key,
          model: r.model,
          schema: VERDICT_SCHEMA,
        }),
    ),
  );

  const roundNumber = fixRoundsUsed + 1;
  roundsHistory.push(
    pending.map((r, i) => ({
      auditor: r.key,
      tier: r.tier,
      verdict: results[i] ? results[i].verdict : 'NO-RESULT',
    })),
  );
  pending.forEach((r, i) => {
    if (!results[i]) {
      // A NO-RESULT dispatch has no report — the record carries the literal marker.
      failReports[`${r.key}:round-${roundNumber}`] = 'NO-RESULT';
    } else if (results[i].verdict === 'FAIL') {
      failReports[`${r.key}:round-${roundNumber}`] = results[i].report;
    }
  });

  pending.forEach((r, i) => {
    if (results[i]) verdicts[r.key] = results[i];
  });
  // A reviewer that returned nothing (skipped/errored dispatch) is never a pass — it
  // stays failing, gets re-dispatched, and if it never reports, the gate FAILs with it
  // listed under noVerdict.
  const failing = pending.filter((r, i) => !results[i] || results[i].verdict === 'FAIL');

  if (failing.length === 0) {
    return {
      gate: 'PASS',
      // JUSTIFY clears the gate only with the deviation documented in the PR body.
      justified: Object.keys(verdicts).filter((k) => verdicts[k].verdict === 'JUSTIFY'),
      verdicts,
      fixRoundsUsed,
      telemetry: telemetry('pass'),
    };
  }

  if (!APPLY_FIXES || fixRoundsUsed >= MAX_FIX_ROUNDS) {
    // `non-convergence` is the §7.4 stop — the fix budget ran out with a reviewer
    // still failing. A report-only run (fix: false) that fails is a plain `fail`.
    const outcome = APPLY_FIXES && fixRoundsUsed >= MAX_FIX_ROUNDS ? 'non-convergence' : 'fail';
    return {
      // Non-convergence: stop and surface in the PR body (§7.4) — the loop never
      // overrides a reviewer.
      gate: 'FAIL',
      failing: failing.map((r) => r.key),
      noVerdict: pending.filter((r, i) => !results[i]).map((r) => r.key),
      verdicts,
      fixRoundsUsed,
      telemetry: telemetry(outcome),
    };
  }

  // Review-mode fix-round restore (#140/T622; Codex P2, PR #174). We are past the PASS/stop
  // returns, so the loop is about to apply a fix and/or re-dispatch. BEFORE either, put the SHARED
  // working tree's HEAD back on the task branch. The reviewers can no longer cause this drift —
  // they are read-only by construction with no shell (#188) — but the loop still runs two
  // shell-holding agents in the shared tree: the diff-provider above and the fixer below. Either,
  // if it strayed into a `git checkout`/`git switch` despite its read-only instruction, would
  // relocate HEAD, and then the fixer would commit onto the wrong branch and the re-dispatched
  // reviewers would audit the wrong diff. This is the SAME deterministic, fail-loud restore the
  // dispatcher runs after the loop — applied here at the fix boundary so the gap is closed on every
  // fix/re-dispatch path, not only the terminal post-run step. The loop's runtime has no git, so the
  // restore is performed by a dispatched agent (the only actor here with VCS access); it makes no
  // code change and is a no-op when nothing drifted. Workspace mode isolates the work in the ephemeral
  // [isolated workspace], so there is no shared tree to restore (TASK_BRANCH is absent there).
  if (!WORKSPACE && TASK_BRANCH) {
    await agent(
      `Before the pre-PR gate for task ${input.taskId} applies any fix or re-dispatches its ` +
        `reviewers, restore the shared working tree to its task branch — a parallel read-only ` +
        `auditor in this same tree may have left HEAD relocated onto another branch. Run exactly ` +
        `this from the repo root, and nothing else (make NO code change):\n\n` +
        `    bash .claude/hooks/restore-task-branch.sh ${shellQuote(TASK_BRANCH)}\n\n` +
        `It is a no-op when nothing drifted. If it exits non-zero it could not guarantee the ` +
        `branch — STOP and report that in your final message; do not let the gate fix or re-audit ` +
        `a drifted HEAD.`,
      { label: `restore-round-${fixRoundsUsed + 1}`, phase: 'Fix' },
    );
  }

  const findings = failing.filter((r) => verdicts[r.key] && verdicts[r.key].verdict === 'FAIL');
  if (findings.length > 0) {
    log(
      `Fix round ${fixRoundsUsed + 1}: addressing FAIL findings from ${findings.map((r) => r.key).join(', ')}`,
    );
    const briefs = findings
      .map((r) => `## ${r.key} — FAIL (verbatim)\n\n${verdicts[r.key].report}`)
      .join('\n\n');
    // No model override: the fixer inherits the session model — the task's tier by
    // construction (the per-stage tier map in workflow/next-task.md).
    // The fixer works WHERE the diff is read: the [isolated workspace] worktree under
    // autonomous mode (so its commits land on the task branch the reviewers re-audit), else
    // the current task branch. Either way, never main.
    const workLocation = WORKSPACE
      ? `inside the ISOLATED WORKSPACE at ${WORKSPACE} (cd into it and work there — that ` +
        `worktree holds the task branch, NOT main; never switch to or commit on main)`
      : `on the current task branch (you are NOT on main; never switch to or commit on main)`;
    await agent(
      `You are the maker addressing blocking pre-PR gate findings for task ${input.taskId}, ` +
        `${workLocation}.\n\n` +
        `${briefs}\n\n` +
        `Apply the minimal scoped change that addresses each blocking finding — nothing ` +
        `speculative. Run the tests for whatever you change. Stage SPECIFIC files (never ` +
        `'git add .') and commit on this branch with message ` +
        `"fix: [${input.taskId}] address gate findings (round ${fixRoundsUsed + 1})". The ` +
        `reviewers re-audit the COMMITTED diff (${diffCmd}), so an uncommitted fix ` +
        `is invisible to them. If you judge a finding wrong or out of scope, leave the code ` +
        `unchanged for that finding and say why in your final message — never override the ` +
        `reviewer yourself; the gate surfaces non-convergence instead.`,
      { label: `fix-round-${fixRoundsUsed + 1}`, phase: 'Fix' },
    );
  }

  fixRoundsUsed += 1;
  pending = failing; // re-dispatch ONLY the failures
}
