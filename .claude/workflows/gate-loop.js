/* global args, agent, parallel, log */
// .claude/workflows/gate-loop.js — the Claude Code binding of the [orchestrated run]
// role. The runtime-neutral spec is .claude/workflow/gate-loop.md (next-task §7 as
// code). This script owns §7 steps 2/4/5 — parallel reviewer fan-out, fix-and-
// re-dispatch, the non-convergence stop, verbatim verdict retention. The maker's
// self-review (§7.1), /code-review (§7.3), and posting the verdicts to the PR (§8)
// stay with the invoker. Invoke it on a task branch with the work COMMITTED — the
// reviewers audit the committed diff (`git diff main..HEAD`), which the loop obtains and
// hands to them in the dispatch prompt because their bindings grant no shell to run `git`
// themselves (read-only by construction, #188); the obtained diff must pass a checked,
// fail-closed contract before any reviewer sees it (`classifyProvidedDiff` — PR #200 review).
// Under an engaged isolated autonomous run
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
//   workspacePath    the [isolated workspace] path whose committed diff the reviewers + fixer
//                    audit (gate-in-place under autonomous mode, T612). One of workspacePath /
//                    taskBranch is REQUIRED (T639/#240): every dispatch audits an EXPLICIT ref,
//                    never an inferred working directory
//   taskBranch       the task branch the dispatcher cut (review mode). REQUIRED when workspacePath
//                    is absent — it is the explicit ref the review-mode diff is verified against:
//                    the fix step restores the SHARED tree onto it before each fix/re-dispatch
//                    round (#140/T622), AND the diff-provider refuses to grade unless the shared
//                    tree's HEAD still matches it (T639/#240). Absent under autonomous mode

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
// T639/#240 — an explicit audited ref is required for EVERY dispatch, review mode included. The
// reviewers must never grade an inferred working directory whose HEAD a concurrent session can move
// between dispatch and fan-out (the #240 shared-tree race). Autonomous runs pass workspacePath (an
// isolated worktree, T612); review runs pass taskBranch (the ref the diff is verified against).
// Absent both, there is no explicit ref to audit — fail before any dispatch rather than read a
// stray HEAD. This removes the pre-T639 inferred-CWD default.
if (!input.workspacePath && !input.taskBranch) {
  throw new Error(
    'gate-loop: an explicit audited ref is required — pass workspacePath (isolated autonomous run) ' +
      'or taskBranch (review mode). The inferred working-directory default is removed (T639/#240): a ' +
      'dispatch must never audit an unspecified tree whose HEAD a concurrent session can switch.',
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

// Where the committed diff under review is read, as an EXPLICIT ref (T639/#240) — never an inferred
// CWD. Under an engaged isolated autonomous run the invoker passes `workspacePath` and the diff is
// read from THAT worktree via an explicit `git -C <path>` (gate-in-place, T612). In review mode the
// invoker passes `taskBranch` and the diff-provider goes through the HEAD-stability hook (see
// `provideDiff`), which emits `git diff main..HEAD` ONLY while the shared tree's HEAD still matches
// that branch. `diffCmd` below is the provenance shown to the reviewers/fixer; the path is
// shell-quoted so a space/metacharacter cannot malform the generated command.
const WORKSPACE = input.workspacePath;
const TASK_BRANCH = input.taskBranch; // review-mode explicit audited ref: fix-round restore target (#140/T622) + HEAD-stability ref (T639/#240); absent under autonomous mode
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
//
// The helper's output is NOT trusted blindly (PR #200 review): what it returns is what the
// reviewers audit, so a failure message, summary, or truncated patch fed through as "the diff"
// would let the gate pass without the reviewers ever seeing the real change. In WORKSPACE
// (autonomous) mode the provider runs `diffCmd && echo <marker>` — the marker prints ONLY when the
// diff command exits 0. In REVIEW mode it runs the HEAD-stability hook `.claude/hooks/gate-diff.sh
// <taskBranch>` (T639/#240): the hook emits the committed diff + the completion marker ONLY while
// the shared tree's HEAD still matches the task branch, and otherwise a diagnostic + the
// HEAD-mismatch marker and no diff — so a concurrent session's branch switch fails the gate loud
// instead of the reviewers grading the wrong diff. `classifyProvidedDiff` below enforces the
// checked, fail-closed contract on either marker.
const DIFF_COMPLETE_MARKER = '-----GATE-DIFF-COMPLETE-----';
// Emitted by gate-diff.sh (review mode) when the shared tree drifted off the task branch (or git is
// unreadable). MUST stay byte-identical to the hook's literal — gate-diff.test.sh pins the agreement.
const HEAD_MISMATCH_MARKER = '-----GATE-HEAD-MISMATCH-----';

// The command the diff-provider runs this round. WORKSPACE (autonomous) mode is byte-identical to
// pre-T639 (the isolated worktree is immune to a shared-tree switch by construction — T612 unchanged);
// REVIEW mode delegates to the HEAD-stability hook, which owns the verify-then-diff atomically.
const providerCommand = WORKSPACE
  ? `${diffCmd} && echo '${DIFF_COMPLETE_MARKER}'`
  : `bash .claude/hooks/gate-diff.sh ${shellQuote(TASK_BRANCH)}`;
const providerMarkerNote = WORKSPACE
  ? `The last line of your message must be the ${DIFF_COMPLETE_MARKER} line the command ` +
    `prints on success. If the command fails, return its error output instead, WITHOUT that line.`
  : `On success the command's last line is ${DIFF_COMPLETE_MARKER}; if a concurrent session has ` +
    `moved the shared working tree off the task branch (or git state is unreadable) it instead ` +
    `prints a diagnostic ending in ${HEAD_MISMATCH_MARKER} and no diff. Return whatever it prints, verbatim.`;
const provideDiff = (round) =>
  agent(
    `Output the committed diff under review for the pre-PR gate, and NOTHING else. Run exactly ` +
      `this and return its complete output verbatim as your final message — no summary, no ` +
      `commentary, no code fence:\n\n    ${providerCommand}\n\n` +
      `${providerMarkerNote} Make NO change to any file or branch — this is a read-only step.`,
    { label: `diff-provider-round-${round}`, phase: 'Dispatch' },
  );

// The checked contract on the provider's output (fail-closed; PR #200 review). Only output that
// is verifiably the committed diff may reach a reviewer prompt: it must END with the completion
// marker (the command prints it only after the diff command exits 0 — a failed run, a truncated
// relay, or trailing commentary loses it; only the LAST line is checked, so a diff that itself
// contains the marker text cannot confuse it), and what precedes the marker must be a non-empty
// git diff (`diff --git ` opens every non-empty patch). Anything else — no output, an error
// message, a summary, a non-diff payload, or an empty diff (nothing to audit: wrong branch or
// worktree, the T612 vacuous-pass class) — classifies as unverified.
const classifyProvidedDiff = (raw) => {
  if (typeof raw !== 'string' || raw.trim() === '') {
    return { ok: false, why: 'no output — the diff-provider returned nothing usable' };
  }
  const lines = raw.trim().split('\n');
  const lastLine = lines[lines.length - 1].trim();
  // T639/#240 — the review-mode HEAD-stability hook (gate-diff.sh) emits this marker when the shared
  // working tree drifted off the task branch (a concurrent session switched it) or git is unreadable.
  // Fail the gate CLOSED and LOUD with the hook's diagnostic — never grade the wrong/absent diff.
  if (lastLine === HEAD_MISMATCH_MARKER) {
    const detail = lines.slice(0, -1).join('\n').trim();
    return {
      ok: false,
      why:
        'HEAD-stability check failed — the audited working tree is no longer on the expected task ' +
        'branch (a concurrent session switched the shared checkout); refusing to grade the wrong diff' +
        (detail ? `: ${detail}` : ''),
    };
  }
  if (lastLine !== DIFF_COMPLETE_MARKER) {
    return {
      ok: false,
      why:
        'missing completion marker — the diff command failed, or its output was truncated ' +
        'or followed by commentary',
    };
  }
  const diff = lines.slice(0, -1).join('\n').trim();
  if (diff === '') {
    return {
      ok: false,
      why: 'empty committed diff — nothing to audit (wrong branch or worktree?); a PASS would be vacuous',
    };
  }
  if (!diff.startsWith('diff --git ')) {
    return { ok: false, why: 'output is not a git diff' };
  }
  return { ok: true, diff };
};

// A reviewer's dispatch prompt, built around the provided diff. The reviewer audits the embedded
// diff (it has no shell to produce one) and uses Read/Grep/Glob for the current files it touches.
// `diffCmd` is named as provenance so the audited tree (main vs the isolated workspace) is explicit.
// The diff has already passed `classifyProvidedDiff` — non-empty, diff-shaped, marker-verified —
// so an invalid or empty provider payload can never reach this template: the loop fails closed
// without dispatching first (the T612 vacuous-pass class is closed structurally, not by asking
// the reviewer to notice).
const reviewerPromptFor = (diff) =>
  `Task under review: ${input.taskId}. Audit ${diffTarget} per your spec. You have read-only ` +
  `tools only (Read/Grep/Glob) and NO shell, so the committed diff under review is provided below ` +
  `— audit it, and use Read/Grep/Glob to inspect the current files it touches and their ` +
  `surrounding code. Set 'verdict' to your overall verdict and put your full verdict report, ` +
  `verbatim, in 'report'.\n\n` +
  `----- BEGIN COMMITTED DIFF (${diffCmd}) -----\n` +
  `${diff}\n` +
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

// T642 (#214) — resolve the roster reviewer agent types BEFORE the grading loop. The reviewers are
// dispatched by custom agent type (`agentType: r.key`, below); the runtime resolves those types from
// the DISPATCHER SESSION's registry (the session root's `.claude/agents/`), NOT from `workspacePath`
// — so a dispatcher rooted outside the repo cannot resolve them. Every reviewer dispatch then returns
// NO-RESULT, and the loop, correctly refusing to pass on no-result, would otherwise burn the WHOLE
// `max-fix-rounds` budget grading nothing (the incident: 9x NO-RESULT across 3 rounds, outcome
// `non-convergence`, zero grading). `workspacePath` scopes the DIFF explicitly but has no agent-type
// equivalent, so this deterministic preflight is the missing explicit-context backstop.
//
// It probes each DISTINCT roster agent type with a trivial, read-only dispatch: a type that resolves
// returns something (non-null); an unresolvable type returns null — the same NO-RESULT the full
// fan-out would get, but paid ONCE, before round 1, at zero fix-round cost (`parallel` reports a
// throwing/erroring dispatch as null too, so a runtime that throws on an unknown type is caught here
// just the same). If ANY type is unresolvable, abort BEFORE any reviewer dispatch — and before the
// diff is even produced — with a diagnostic DERIVED from the actual unresolved set that names the
// failure mode; a run whose types all resolve proceeds to the loop unchanged (two-sided — never
// "always abort"). Fail-closed exactly like the diff-provider contract below: no reviewer dispatched,
// outcome `fail`, the classification recorded in `fail_reports` keyed to this pre-dispatch check.
const probeTypes = [...new Set(reviewers.map((r) => r.key))];
const probeResults = await parallel(
  probeTypes.map(
    (key) => () =>
      agent(
        'Pre-PR gate preflight: reply with exactly the word READY and NOTHING else. Do NOT read ' +
          'any file, run any command, or take any action — this dispatch only confirms your ' +
          'reviewer role is resolvable before the gate dispatches it for real.',
        { label: `preflight:${key}`, phase: 'Dispatch', agentType: key },
      ),
  ),
);
const unresolvedTypes = probeTypes.filter((_key, i) => probeResults[i] == null);
if (unresolvedTypes.length > 0) {
  const diagnostic =
    `gate-loop preflight: the reviewer agent type(s) ${unresolvedTypes.join(', ')} did not ` +
    'resolve — dispatching them returns no result. Reviewer agent types resolve from the dispatcher ' +
    "session's registry (the session root's .claude/agents/), NOT from workspacePath, so this " +
    'session is almost certainly rooted OUTSIDE THE REPO where those reviewer roles live ' +
    '(workspacePath scopes the committed diff, but agent-type resolution is not workspace-scoped). ' +
    'Aborting before any reviewer dispatch — zero fix rounds consumed — instead of fanning out to ' +
    `NO-RESULT across ${MAX_FIX_ROUNDS + 1} rounds and burning the fix budget grading nothing. ` +
    'Re-dispatch the [orchestrated run] from a session rooted in the repo, or fall back to the ' +
    '§7 prose gate.';
  failReports.preflight = diagnostic;
  return {
    gate: 'FAIL',
    // The roster types that did not resolve — derived from the probe, never hardcoded.
    preflightUnresolved: unresolvedTypes,
    // No reviewer was dispatched — an undispatched reviewer is never a pass (the same
    // no-verdict-is-not-a-pass rule as the diff-provider abort and NO-RESULT).
    notDispatched: reviewers.map((r) => r.key),
    verdicts,
    fixRoundsUsed: 0,
    telemetry: telemetry('fail'),
  };
}

while (true) {
  log(
    `Gate dispatch ${fixRoundsUsed + 1}/${MAX_FIX_ROUNDS + 1}: ${pending.map((r) => r.key).join(', ')}`,
  );
  // Obtain the committed diff for THIS round (it changes after a fix commit) and hand it to the
  // read-only reviewers, which cannot fetch it themselves (#188). The provider's output must pass
  // the checked contract first: an unverified payload is never embedded — the gate FAILs closed
  // WITHOUT dispatching, rather than let reviewers grade a failure message, a summary, or a
  // truncated patch as if it were the real committed diff (PR #200 review).
  const provided = classifyProvidedDiff(await provideDiff(fixRoundsUsed + 1));
  if (!provided.ok) {
    failReports[`diff-provider:round-${fixRoundsUsed + 1}`] = provided.why;
    return {
      gate: 'FAIL',
      diffUnverified: provided.why,
      // Never dispatched this round — they hold no verdict, and an undispatched reviewer is
      // never a pass (the same no-verdict-is-not-a-pass rule as NO-RESULT).
      notDispatched: pending.map((r) => r.key),
      verdicts,
      fixRoundsUsed,
      telemetry: telemetry('fail'),
    };
  }
  const reviewerPrompt = reviewerPromptFor(provided.diff);
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
