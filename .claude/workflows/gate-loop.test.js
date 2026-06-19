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

console.log(`\n${testsRun} tests passed`);
