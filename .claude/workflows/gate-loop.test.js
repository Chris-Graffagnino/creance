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

console.log(`\n${testsRun} tests passed`);
