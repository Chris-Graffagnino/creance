// .claude/workflows/gate-loop.test.js — encoding test for US1.AC2 (T102).
//
// AC2: the gate loop builds exactly one telemetry record payload per gate run, on
// EVERY return path, with the correct `outcome`; the append is the dispatcher's job
// after the run returns, so a failed write never blocks, fails, or alters the gate.
//
// gate-loop.js is a workflow-tool script (injected globals `args`/`agent`/`parallel`/
// `log`, top-level await/return), so this harness wraps its source in an async
// function and injects stubs. Run with: node .claude/workflows/gate-loop.test.js

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import assert from 'node:assert/strict';

const src = readFileSync(join(dirname(fileURLToPath(import.meta.url)), 'gate-loop.js'), 'utf8');
// Strip the ESM export so the body is plain statements inside a function.
const body = src.replace(/^export const meta/m, 'const meta');

function runGateLoop(args, agentStub) {
  const parallel = async (fns) => Promise.all(fns.map((fn) => fn()));
  const log = () => {};
  // eslint-disable-next-line no-new-func
  const fn = new Function(
    'args',
    'agent',
    'parallel',
    'log',
    `return (async () => { ${body} })();`,
  );
  return fn(args, agentStub, parallel, log);
}

const baseArgs = { taskId: 'T102', strongModel: 'strong-row', cheapModel: 'cheap-row' };

function assertPayloadShape(t) {
  assert.equal(t.record, 'gate-run');
  assert.equal(t.task_id, 'T102');
  assert.ok(Array.isArray(t.rounds), 'rounds is an array of dispatch rounds');
  assert.equal(typeof t.fix_rounds_used, 'number');
  assert.equal(typeof t.fail_reports, 'object');
}

let testsRun = 0;
async function test(name, fn) {
  await fn();
  testsRun += 1;
  console.log(`ok - ${name}`);
}

// --- 1. PASS path carries the payload with outcome 'pass' -----------------------
await test('pass path: telemetry present, outcome=pass, one entry per auditor', async () => {
  const result = await runGateLoop(baseArgs, async (_p, opts) => ({
    verdict: 'PASS',
    report: `${opts.agentType} pass report`,
  }));
  assert.equal(result.gate, 'PASS');
  assertPayloadShape(result.telemetry);
  assert.equal(result.telemetry.outcome, 'pass');
  assert.equal(result.telemetry.fix_rounds_used, 0);
  assert.equal(result.telemetry.rounds.length, 1);
  assert.deepEqual(
    result.telemetry.rounds[0].map((e) => [e.auditor, e.tier, e.verdict]),
    [
      ['spec-auditor', 'cheap', 'PASS'],
      ['constitution-auditor', 'strong', 'PASS'],
    ],
  );
  assert.deepEqual(result.telemetry.fail_reports, {});
});

// --- 2. Report-only FAIL path: outcome 'fail', verbatim FAIL reports ------------
await test('fail path (fix:false): telemetry present, outcome=fail, verbatim reports', async () => {
  const result = await runGateLoop({ ...baseArgs, fix: false }, async (_p, opts) =>
    opts.agentType === 'spec-auditor'
      ? { verdict: 'FAIL', report: 'VERBATIM-FAIL-REPORT-XYZ' }
      : { verdict: 'PASS', report: 'fine' },
  );
  assert.equal(result.gate, 'FAIL');
  assertPayloadShape(result.telemetry);
  assert.equal(result.telemetry.outcome, 'fail');
  assert.equal(result.telemetry.fail_reports['spec-auditor:round-1'], 'VERBATIM-FAIL-REPORT-XYZ');
});

// --- 3. Non-convergence path: outcome 'non-convergence' -------------------------
await test('non-convergence path: telemetry present, outcome=non-convergence', async () => {
  const result = await runGateLoop({ ...baseArgs, maxFixRounds: 0 }, async (_p, opts) =>
    opts.agentType
      ? { verdict: 'FAIL', report: `${opts.agentType} still failing` }
      : { verdict: 'PASS', report: 'fixer ran' }, // the fix-stage agent has no agentType
  );
  assert.equal(result.gate, 'FAIL');
  assertPayloadShape(result.telemetry);
  assert.equal(result.telemetry.outcome, 'non-convergence');
});

// --- 4. NO-RESULT dispatch carries the literal marker ----------------------------
await test('no-result dispatch: fail_reports carries literal NO-RESULT marker', async () => {
  const result = await runGateLoop({ ...baseArgs, fix: false }, async (_p, opts) =>
    opts.agentType === 'constitution-auditor' ? null : { verdict: 'PASS', report: 'fine' },
  );
  assert.equal(result.gate, 'FAIL');
  assert.equal(result.telemetry.outcome, 'fail');
  assert.equal(result.telemetry.fail_reports['constitution-auditor:round-1'], 'NO-RESULT');
  assert.equal(
    result.telemetry.rounds[0].find((e) => e.auditor === 'constitution-auditor').verdict,
    'NO-RESULT',
  );
});

// --- 5. A failed append cannot alter the gate result -----------------------------
await test('failed telemetry write never alters the gate outcome', async () => {
  const result = await runGateLoop(baseArgs, async () => ({ verdict: 'PASS', report: 'ok' }));
  const before = JSON.stringify(result);
  // The dispatcher appends AFTER the run returns — simulate the append failing.
  const failingAppend = () => {
    throw new Error('disk full: telemetry append failed');
  };
  let writeFailed = false;
  try {
    failingAppend(result.telemetry);
  } catch {
    writeFailed = true; // the dispatcher swallows this; the gate result is already final
  }
  assert.equal(writeFailed, true);
  assert.equal(result.gate, 'PASS');
  assert.equal(result.telemetry.outcome, 'pass');
  assert.equal(JSON.stringify(result), before, 'gate return value is byte-identical after write failure');
});

// --- 6. workspacePath set: reviewers audit the WORKSPACE diff via explicit git -C (T612) ---
// Gate-in-place's gameability guard: it is not enough that `workspacePath` is accepted — the
// reviewer prompt TEXT must actually point the auditors at that worktree's committed diff.
await test('workspacePath: reviewer prompt targets the workspace diff via explicit git -C', async () => {
  const seen = [];
  const result = await runGateLoop(
    { ...baseArgs, workspacePath: '/tmp/creance-ws-abc/wt' },
    async (prompt, opts) => {
      seen.push({ prompt, agentType: opts.agentType });
      return { verdict: 'PASS', report: 'ok' };
    },
  );
  assert.equal(result.gate, 'PASS');
  const reviewerPrompts = seen.filter((s) => s.agentType); // reviewers carry agentType; the fixer does not
  assert.ok(reviewerPrompts.length >= 2, 'both unconditional reviewers dispatched');
  for (const { prompt } of reviewerPrompts) {
    assert.match(prompt, /git -C '\/tmp\/creance-ws-abc\/wt' diff main\.\.HEAD/);
    assert.match(prompt, /ISOLATED WORKSPACE/);
  }
});

// --- 7. workspacePath absent: review mode is byte-identical (main-tree diff, no git -C) ----
await test('no workspacePath: reviewer prompt is the unchanged main-tree diff', async () => {
  const seen = [];
  await runGateLoop(baseArgs, async (prompt, opts) => {
    seen.push({ prompt, agentType: opts.agentType });
    return { verdict: 'PASS', report: 'ok' };
  });
  const reviewerPrompts = seen.filter((s) => s.agentType);
  for (const { prompt } of reviewerPrompts) {
    assert.match(prompt, /git diff main\.\.HEAD/);
    assert.doesNotMatch(prompt, /git -C/);
    assert.doesNotMatch(prompt, /ISOLATED WORKSPACE/);
  }
});

// --- 8. workspacePath set: the FIXER is told to work inside the workspace too ---------------
// The fixer commits the diff the reviewers re-audit, so it must operate in the same worktree —
// wiring WORKSPACE into the reviewer prompt but not the fixer would silently fix the main tree.
await test('workspacePath: the fixer is directed into the workspace', async () => {
  const fixerPrompts = [];
  let specCalls = 0;
  await runGateLoop(
    { ...baseArgs, workspacePath: '/tmp/creance-ws-xyz/wt', maxFixRounds: 1 },
    async (_prompt, opts) => {
      if (!opts.agentType) {
        fixerPrompts.push(_prompt); // the fix-stage maker agent has no agentType
        return { verdict: 'PASS', report: 'fixer ran' };
      }
      if (opts.agentType === 'spec-auditor') {
        specCalls += 1;
        return specCalls === 1
          ? { verdict: 'FAIL', report: 'needs a fix' } // round 1 FAIL → triggers the fix stage
          : { verdict: 'PASS', report: 'ok now' }; // round 2 PASS
      }
      return { verdict: 'PASS', report: 'ok' };
    },
  );
  assert.equal(fixerPrompts.length, 1, 'exactly one fix round ran');
  assert.match(fixerPrompts[0], /ISOLATED WORKSPACE at \/tmp\/creance-ws-xyz\/wt/);
  assert.match(fixerPrompts[0], /git -C '\/tmp\/creance-ws-xyz\/wt' diff main\.\.HEAD/);
});

// --- 9. workspacePath with a space: the generated git -C command stays a single arg (T612) ----
// A valid workspace temp path may contain spaces or shell metacharacters; embedded unquoted it
// would split `git -C /tmp/with space/... diff` into a malformed command and the reviewers/fixer
// could not audit the isolated diff (Codex P2, PR #114). The path must be shell-quoted in diffCmd —
// in EVERY generated command: each reviewer prompt and the fixer prompt (a round-1 FAIL→fix→round-2
// PASS exercises the fixer too).
await test('workspacePath with a space: git -C path is shell-quoted into one argument', async () => {
  const seen = [];
  let specCalls = 0;
  await runGateLoop(
    { ...baseArgs, workspacePath: '/tmp/with space/creance-ws-abc/wt', maxFixRounds: 1 },
    async (prompt, opts) => {
      seen.push({ prompt, agentType: opts.agentType });
      if (!opts.agentType) return { verdict: 'PASS', report: 'fixer ran' }; // fixer has no agentType
      if (opts.agentType === 'spec-auditor') {
        specCalls += 1;
        return specCalls === 1
          ? { verdict: 'FAIL', report: 'needs a fix' } // round-1 FAIL → triggers the fix stage
          : { verdict: 'PASS', report: 'ok now' }; // round-2 PASS
      }
      return { verdict: 'PASS', report: 'ok' };
    },
  );
  // The single-quoted form keeps the spaced path one argument in every generated command —
  // reviewer prompts AND the fixer prompt (both read diffCmd).
  const quoted = /git -C '\/tmp\/with space\/creance-ws-abc\/wt' diff main\.\.HEAD/;
  assert.ok(
    seen.some((s) => !s.agentType && quoted.test(s.prompt)),
    'the fixer prompt carries the shell-quoted git -C command',
  );
  assert.ok(
    seen.filter((s) => s.agentType && quoted.test(s.prompt)).length >= 2,
    'both reviewers carry the shell-quoted git -C command',
  );
  for (const { prompt } of seen) {
    // never the unquoted split form `git -C /tmp/with space/...`
    assert.doesNotMatch(prompt, /git -C \/tmp\/with space/);
  }
});

// --- 10. dispatchSpec set: the spec-quality reviewer joins the round at strong (T703) ----
// US2.AC1: a diff that adds/edits/renames a specs/*/spec.md flips dispatchSpec, and the
// gate dispatches the spec-quality reviewer alongside the always-reviewers, on the STRONG
// tier (its [strong tier] floor — the spec is the cheapest place to lose a project). The
// agentType is stubbed, so this proves the wiring independent of T706's agent binding.
await test('dispatchSpec: spec-quality-auditor dispatched at strong on a spec-touching diff', async () => {
  const result = await runGateLoop({ ...baseArgs, dispatchSpec: true }, async (_p, opts) => ({
    verdict: 'PASS',
    report: `${opts.agentType} pass report`,
  }));
  assert.equal(result.gate, 'PASS');
  assert.deepEqual(
    result.telemetry.rounds[0].map((e) => [e.auditor, e.tier]),
    [
      ['spec-auditor', 'cheap'],
      ['constitution-auditor', 'strong'],
      ['spec-quality-auditor', 'strong'],
    ],
  );
});

// --- 11. dispatchSpec unset: NO spec-quality dispatch, gate runs exactly as before (T703) --
// US2.AC2: on a diff touching no spec.md the reviewer is not dispatched — the round is the
// unchanged two-member always-set. The exact-array assertion (cf. test 1) is the one-sided-
// test guard: it proves the spec-quality push is genuinely gated, not unconditionally present.
await test('no dispatchSpec: spec-quality-auditor is NOT dispatched (non-spec diff)', async () => {
  const result = await runGateLoop(baseArgs, async (_p, opts) => ({
    verdict: 'PASS',
    report: `${opts.agentType} pass report`,
  }));
  assert.equal(result.gate, 'PASS');
  const auditors = result.telemetry.rounds[0].map((e) => e.auditor);
  assert.ok(!auditors.includes('spec-quality-auditor'), 'spec-quality not dispatched without dispatchSpec');
  assert.deepEqual(auditors, ['spec-auditor', 'constitution-auditor']);
});

// --- 12. reviewer prompt carries the non-switching base-read constraint (T622, #140) -------
// The prevention layer for the shared-tree branch-switch bug: the auditors run in the maker's
// shared working tree in review mode, so the reviewer prompt must forbid branch-switching git
// and steer them to non-switching base reads. (The DETERMINISTIC backstop is the dispatcher's
// restore-task-branch step, tested in restore-task-branch.test.sh; this pins the belt-and-
// suspenders prevention so it cannot silently drop out of the prompt.)
await test('reviewer prompt forbids branch-switching and steers to non-switching base reads', async () => {
  const seen = [];
  await runGateLoop(baseArgs, async (prompt, opts) => {
    seen.push({ prompt, agentType: opts.agentType });
    return { verdict: 'PASS', report: 'ok' };
  });
  const reviewerPrompts = seen.filter((s) => s.agentType); // reviewers carry agentType; the fixer does not
  assert.ok(reviewerPrompts.length >= 2, 'both unconditional reviewers dispatched');
  for (const { prompt } of reviewerPrompts) {
    assert.match(prompt, /non-switching/i, 'instructs non-switching base reads');
    assert.match(prompt, /never run `git checkout`\/`git switch`/i, 'forbids branch-switching git');
    assert.match(prompt, /git diff main\.\.HEAD/, 'names a non-switching base read');
  }
});

// --- 13. workspacePath: the non-switching base-read EXAMPLES stay path-scoped (Codex P2 / craft, #174) -
// It is not enough that the audit TARGET is path-scoped (test 6) — the prevention text's example reads
// must be too. A bare `git diff main..HEAD` / `git show main:<path>` would steer workspace-mode
// reviewers (who run from the session CWD) back to the shared tree and recreate the T612 vacuous-pass
// risk. This pins the non-switching example reads — including `git show` — to the explicit git -C form.
await test('workspacePath: non-switching base-read examples are path-scoped, not bare', async () => {
  const seen = [];
  await runGateLoop({ ...baseArgs, workspacePath: '/tmp/creance-ws-abc/wt' }, async (prompt, opts) => {
    seen.push({ prompt, agentType: opts.agentType });
    return { verdict: 'PASS', report: 'ok' };
  });
  const reviewerPrompts = seen.filter((s) => s.agentType);
  assert.ok(reviewerPrompts.length >= 2, 'both unconditional reviewers dispatched');
  for (const { prompt } of reviewerPrompts) {
    assert.match(prompt, /git -C '\/tmp\/creance-ws-abc\/wt' diff main\.\.HEAD/, 'non-switching diff read is path-scoped');
    assert.match(prompt, /git -C '\/tmp\/creance-ws-abc\/wt' show main:<path>/, 'non-switching show read is path-scoped');
    assert.doesNotMatch(prompt, /`git diff main\.\.HEAD`/, 'no bare git diff example in workspace mode');
    assert.doesNotMatch(prompt, /`git show main:<path>`/, 'no bare git show example in workspace mode');
  }
});

// --- 14. review mode + taskBranch: the loop restores the shared tree BEFORE fixing (Codex P2, #174) ---
// In review mode a parallel read-only auditor can drift the shared HEAD off the task branch; if the
// loop then fixed/re-dispatched on that HEAD the fix would miss the branch and the re-audit would read
// the wrong state. With taskBranch passed, a restore step runs the SAME tested hook before the fixer —
// closing the fix-round gap, not only the post-run step.
await test('review mode + taskBranch: a restore step runs the hook before the fixer', async () => {
  const others = []; // no agentType: the restore step and the fixer
  let specCalls = 0;
  await runGateLoop(
    { ...baseArgs, taskBranch: 'fix/140-gate-loop-restore', maxFixRounds: 1 },
    async (prompt, opts) => {
      if (!opts.agentType) {
        others.push(prompt);
        return { verdict: 'PASS', report: 'step ran' };
      }
      if (opts.agentType === 'spec-auditor') {
        specCalls += 1;
        return specCalls === 1
          ? { verdict: 'FAIL', report: 'needs a fix' } // round-1 FAIL → triggers the fix stage
          : { verdict: 'PASS', report: 'ok now' }; // round-2 PASS
      }
      return { verdict: 'PASS', report: 'ok' };
    },
  );
  assert.ok(
    others.some((p) => /restore-task-branch\.sh 'fix\/140-gate-loop-restore'/.test(p)),
    'a restore step invokes the hook with the shell-quoted task branch',
  );
  assert.ok(
    others.some((p) => /Apply the minimal scoped change/.test(p)),
    'the fixer still runs after the restore',
  );
});

// --- 15. workspace mode: NO shared-tree restore step (the work is isolated) -----------------------
// The fix-round restore is review-mode only: autonomous work lives in the ephemeral isolated
// workspace, so there is no shared tree to restore (WORKSPACE suppresses TASK_BRANCH even when both
// are passed). The fixer runs, but no restore hook is invoked.
await test('workspace mode: no shared-tree restore step even when taskBranch is also passed', async () => {
  const others = [];
  let specCalls = 0;
  await runGateLoop(
    { ...baseArgs, workspacePath: '/tmp/creance-ws-xyz/wt', taskBranch: 'fix/140-x', maxFixRounds: 1 },
    async (prompt, opts) => {
      if (!opts.agentType) {
        others.push(prompt);
        return { verdict: 'PASS', report: 'fixer ran' };
      }
      if (opts.agentType === 'spec-auditor') {
        specCalls += 1;
        return specCalls === 1 ? { verdict: 'FAIL', report: 'needs a fix' } : { verdict: 'PASS', report: 'ok now' };
      }
      return { verdict: 'PASS', report: 'ok' };
    },
  );
  assert.ok(others.length >= 1, 'the fixer ran');
  for (const p of others) assert.doesNotMatch(p, /restore-task-branch/, 'no shared-tree restore in workspace mode');
});

// --- 16. review mode + taskBranch: restore runs before a FIXER-LESS re-dispatch too (Codex P2, #174) -
// When the failing reviewers are all NO-RESULT (returned nothing) there is no FAIL finding to fix, so
// no fixer runs — but the shared tree may still have been drifted (e.g. by a sibling reviewer that
// passed). The restore must still run before the re-dispatch, or the retried reviewer would audit a
// drifted HEAD and could pass vacuously.
await test('review mode + taskBranch: restore runs before a fixer-less (NO-RESULT) re-dispatch', async () => {
  const others = [];
  let specCalls = 0;
  const result = await runGateLoop(
    { ...baseArgs, taskBranch: 'fix/140-x', maxFixRounds: 1 },
    async (prompt, opts) => {
      if (!opts.agentType) {
        others.push(prompt);
        return { verdict: 'PASS', report: 'step ran' };
      }
      if (opts.agentType === 'spec-auditor') {
        specCalls += 1;
        return specCalls === 1 ? null : { verdict: 'PASS', report: 'ok now' }; // round-1 NO-RESULT → re-dispatch, no fixer
      }
      return { verdict: 'PASS', report: 'ok' };
    },
  );
  assert.equal(result.gate, 'PASS');
  assert.ok(
    others.some((p) => /restore-task-branch\.sh 'fix\/140-x'/.test(p)),
    'a restore step runs before the fixer-less re-dispatch',
  );
  assert.ok(
    !others.some((p) => /Apply the minimal scoped change/.test(p)),
    'no fixer runs when there are no FAIL findings',
  );
});

console.log(`\n${testsRun} tests passed`);
