/* global args, agent, parallel, log */
// .claude/workflows/gate-loop.js — the Claude Code binding of the [orchestrated run]
// role. The runtime-neutral spec is .claude/workflow/gate-loop.md (next-task §7 as
// code). This script owns §7 steps 2/4/5 — parallel reviewer fan-out, fix-and-
// re-dispatch, the non-convergence stop, verbatim verdict retention. The maker's
// self-review (§7.1), /code-review (§7.3), and posting the verdicts to the PR (§8)
// stay with the invoker. Invoke it on a task branch with the work COMMITTED — the
// reviewers audit `git diff main..HEAD`. Under an engaged isolated autonomous run
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
//   maxFixRounds     (default 2) the §7 non-convergence bound
//   fix              (default true) false → one report-only fan-out, no fix stage
//   workspacePath    (optional) the [isolated workspace] path whose committed diff the
//                    reviewers + fixer audit (gate-in-place under autonomous mode, T612);
//                    absent → the main working tree (review mode, unchanged)

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
// into multiple args and malform the `git -C <path>` command the reviewers/fixer are told to run
// (Codex P2, PR #114). POSIX single-quoting: wrap in '…', and close/escape/reopen each embedded
// single quote ('\'') so the whole path stays one argument verbatim.
const shellQuote = (s) => `'${String(s).replace(/'/g, `'\\''`)}'`;

// Where the reviewers (and the fixer) read the committed diff. Default: the main working
// tree (review mode). Under an engaged isolated autonomous run the invoker passes
// `workspacePath`, and the diff is read from THAT worktree via an explicit `git -C <path>`
// (gate-in-place, T612) — explicit context, never an inferred CWD. The `-C` form means the
// reviewer subagents audit the workspace's diff even though they run from the session CWD.
// The path is shell-quoted in the runnable command so a space/metacharacter cannot malform it.
const WORKSPACE = input.workspacePath;
const diffCmd = WORKSPACE ? `git -C ${shellQuote(WORKSPACE)} diff main..HEAD` : `git diff main..HEAD`;
const diffTarget = WORKSPACE
  ? `the committed diff of the ISOLATED WORKSPACE at ${WORKSPACE} (run \`${diffCmd}\` — ` +
    `that worktree holds the autonomous run's branch; do NOT audit the main working tree)`
  : `the current branch's committed diff (\`${diffCmd}\`)`;

const reviewerPrompt =
  `Task under review: ${input.taskId}. Audit ${diffTarget} per your spec. Set 'verdict' ` +
  `to your overall verdict and put your full verdict report, verbatim, in 'report'.`;

// DERIVED FROM the reviewer roster in workflow/gate-loop.md → "The reviewer roster" — the
// single source of truth for gate membership, tier, and dispatch-condition. This array is
// the adapter-side encoding of that table: spec-auditor (cheap/always) + constitution-
// auditor (strong/always) as the unconditional set, contract-auditor (cheap) pushed only
// under the `dispatch-contract` condition. Do NOT edit membership/tier/condition here in
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
