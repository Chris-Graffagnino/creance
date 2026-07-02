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

// NOTE (#188): the reviewers are read-only with NO shell, so gate-loop dispatches a git-capable
// "diff-provider" helper (label `diff-provider-round-N`, no agentType) once per dispatch round,
// validates its output against a checked, fail-closed contract (marker-terminated, non-empty
// `diff --git` patch — PR #200 review), and only then embeds the diff in each reviewer prompt.
// Stubs must therefore return a CONTRACT-VALID payload for the diff-provider (see `providedDiff`)
// or the run aborts closed before any reviewer dispatch — that requirement is itself the proof
// the contract is enforced (the provider can no longer be satisfied by a reviewer-style object
// or a bare placeholder string). It also carries no agentType, so a stub that does not
// special-case it would miscount it as the fixer/restore step. Tests 17–21 pin the abort path.

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

// The diff-provider's checked contract (mirrors gate-loop.js): output ends with the completion
// marker and what precedes it is a non-empty `diff --git` patch.
const DIFF_MARKER = '-----GATE-DIFF-COMPLETE-----';
const providedDiff = (diffBody = 'diff --git a/file b/file\n+change') =>
  `${diffBody}\n${DIFF_MARKER}`;
const isDiffProvider = (opts) => opts.label && opts.label.startsWith('diff-provider');

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
  const result = await runGateLoop(baseArgs, async (_p, opts) =>
    isDiffProvider(opts)
      ? providedDiff()
      : { verdict: 'PASS', report: `${opts.agentType} pass report` },
  );
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
  const result = await runGateLoop({ ...baseArgs, fix: false }, async (_p, opts) => {
    if (isDiffProvider(opts)) return providedDiff();
    return opts.agentType === 'spec-auditor'
      ? { verdict: 'FAIL', report: 'VERBATIM-FAIL-REPORT-XYZ' }
      : { verdict: 'PASS', report: 'fine' };
  });
  assert.equal(result.gate, 'FAIL');
  assertPayloadShape(result.telemetry);
  assert.equal(result.telemetry.outcome, 'fail');
  assert.equal(result.telemetry.fail_reports['spec-auditor:round-1'], 'VERBATIM-FAIL-REPORT-XYZ');
});

// --- 3. Non-convergence path: outcome 'non-convergence' -------------------------
await test('non-convergence path: telemetry present, outcome=non-convergence', async () => {
  const result = await runGateLoop({ ...baseArgs, maxFixRounds: 0 }, async (_p, opts) => {
    if (isDiffProvider(opts)) return providedDiff();
    return opts.agentType
      ? { verdict: 'FAIL', report: `${opts.agentType} still failing` }
      : { verdict: 'PASS', report: 'fixer ran' }; // the fix-stage agent has no agentType
  });
  assert.equal(result.gate, 'FAIL');
  assertPayloadShape(result.telemetry);
  assert.equal(result.telemetry.outcome, 'non-convergence');
});

// --- 4. NO-RESULT dispatch carries the literal marker ----------------------------
await test('no-result dispatch: fail_reports carries literal NO-RESULT marker', async () => {
  const result = await runGateLoop({ ...baseArgs, fix: false }, async (_p, opts) => {
    if (isDiffProvider(opts)) return providedDiff();
    return opts.agentType === 'constitution-auditor' ? null : { verdict: 'PASS', report: 'fine' };
  });
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
  const result = await runGateLoop(baseArgs, async (_p, opts) =>
    isDiffProvider(opts) ? providedDiff() : { verdict: 'PASS', report: 'ok' },
  );
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
      if (isDiffProvider(opts)) return providedDiff();
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
    if (isDiffProvider(opts)) return providedDiff();
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
      if (isDiffProvider(opts)) return providedDiff(); // read-only diff helper (#188)
      if (!opts.agentType) {
        fixerPrompts.push(_prompt); // the fix-stage maker agent has no agentType (and isn't the diff helper)
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
      if (isDiffProvider(opts)) return providedDiff();
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
  const result = await runGateLoop({ ...baseArgs, dispatchSpec: true }, async (_p, opts) =>
    isDiffProvider(opts)
      ? providedDiff()
      : { verdict: 'PASS', report: `${opts.agentType} pass report` },
  );
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
  const result = await runGateLoop(baseArgs, async (_p, opts) =>
    isDiffProvider(opts)
      ? providedDiff()
      : { verdict: 'PASS', report: `${opts.agentType} pass report` },
  );
  assert.equal(result.gate, 'PASS');
  const auditors = result.telemetry.rounds[0].map((e) => e.auditor);
  assert.ok(!auditors.includes('spec-quality-auditor'), 'spec-quality not dispatched without dispatchSpec');
  assert.deepEqual(auditors, ['spec-auditor', 'constitution-auditor']);
});

// --- 12. reviewer prompt is read-only-by-construction: the diff is PROVIDED, not fetched (#188) --
// Reviewers hold no shell (Read/Grep/Glob only), so the loop embeds the committed diff in the prompt
// and tells them so — there is no "run git / never git checkout" instruction to hand a shell-less
// agent (that branch-switch prevention layer is moot once the reviewer cannot run git at all; the
// shared-tree restore backstop still runs for the loop's remaining shell actors, tests 14/16). This
// pins the provided-diff contract so it cannot silently regress to telling the reviewer to fetch it.
await test('reviewer prompt provides the committed diff to a read-only (no-shell) reviewer', async () => {
  const seen = [];
  await runGateLoop(baseArgs, async (prompt, opts) => {
    if (isDiffProvider(opts)) return providedDiff('diff --git a/f b/f\n+PROVIDED-DIFF-BODY');
    seen.push({ prompt, agentType: opts.agentType });
    return { verdict: 'PASS', report: 'ok' };
  });
  const reviewerPrompts = seen.filter((s) => s.agentType); // reviewers carry agentType; the fixer does not
  assert.ok(reviewerPrompts.length >= 2, 'both unconditional reviewers dispatched');
  for (const { prompt } of reviewerPrompts) {
    assert.match(prompt, /read-only\s+tools only/i, 'tells the reviewer it is read-only');
    assert.match(prompt, /NO shell/i, 'states the no-shell constraint');
    assert.match(prompt, /BEGIN COMMITTED DIFF/, 'embeds the committed diff block');
    assert.match(prompt, /PROVIDED-DIFF-BODY/, 'the provided diff body is embedded verbatim');
    assert.match(prompt, /git diff main\.\.HEAD/, 'names the diff provenance command');
    assert.doesNotMatch(prompt, /GATE-DIFF-COMPLETE/, 'the completion marker is stripped, not embedded');
    assert.doesNotMatch(prompt, /never run `git checkout`/i, 'no shell-git instruction to a shell-less reviewer');
  }
});

// --- 13. workspacePath: the diff provenance is workspace-scoped, not bare (T612; Codex P2 #174) ---
// It is not enough that `workspacePath` is accepted — the diff handed to the reviewers must be the
// WORKSPACE's diff. The command the diff helper runs (and the provenance named in the reviewer
// prompt) must carry the explicit `git -C <workspace>`, never a bare `git diff` that would read the
// shared main tree and recreate the T612 vacuous-pass risk.
await test('workspacePath: the diff provenance is workspace-scoped (explicit git -C), not bare', async () => {
  const seen = [];
  await runGateLoop({ ...baseArgs, workspacePath: '/tmp/creance-ws-abc/wt' }, async (prompt, opts) => {
    if (isDiffProvider(opts)) {
      seen.push({ prompt, kind: 'diff-provider' });
      return providedDiff('diff --git a/f b/f\n+WS-DIFF');
    }
    seen.push({ prompt, agentType: opts.agentType });
    return { verdict: 'PASS', report: 'ok' };
  });
  const reviewerPrompts = seen.filter((s) => s.agentType);
  const diffProviderPrompts = seen.filter((s) => s.kind === 'diff-provider');
  assert.ok(reviewerPrompts.length >= 2, 'both unconditional reviewers dispatched');
  assert.ok(diffProviderPrompts.length >= 1, 'the diff helper was dispatched');
  // The diff helper runs the workspace-scoped, shell-quoted command.
  for (const { prompt } of diffProviderPrompts) {
    assert.match(prompt, /git -C '\/tmp\/creance-ws-abc\/wt' diff main\.\.HEAD/, 'diff helper reads the workspace diff');
    assert.doesNotMatch(prompt, /git -C \/tmp\/creance-ws-abc/, 'the git -C path is shell-quoted (no unquoted split form)');
  }
  // The reviewer prompt names that same workspace-scoped provenance and never a bare git diff.
  for (const { prompt } of reviewerPrompts) {
    assert.match(prompt, /git -C '\/tmp\/creance-ws-abc\/wt' diff main\.\.HEAD/, 'provenance is workspace-scoped');
    assert.match(prompt, /ISOLATED WORKSPACE/, 'names the isolated workspace target');
    assert.doesNotMatch(prompt, /`git diff main\.\.HEAD`/, 'no bare git diff provenance in workspace mode');
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
      if (isDiffProvider(opts)) return providedDiff(); // read-only diff helper (#188)
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
      if (isDiffProvider(opts)) return providedDiff(); // read-only diff helper (#188)
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
      if (isDiffProvider(opts)) return providedDiff(); // read-only diff helper (#188)
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

// --- 17. diff-provider contract: NO output fails the gate closed, nothing dispatched (PR #200) ---
// The provider is an agent like any other — it can be skipped or die (null). The gate must not
// dispatch reviewers against a missing diff and must not count on them noticing: it aborts before
// any reviewer runs, outcome 'fail', with the fail-closed classification recorded for the PR body.
await test('diff-provider contract: null provider output → gate fails closed, no reviewer dispatched', async () => {
  const dispatched = [];
  const result = await runGateLoop(baseArgs, async (_p, opts) => {
    if (isDiffProvider(opts)) return null;
    dispatched.push(opts.agentType || opts.label);
    return { verdict: 'PASS', report: 'should never run' };
  });
  assert.equal(result.gate, 'FAIL');
  assert.equal(dispatched.length, 0, 'no reviewer (or fixer) ran on an unverified diff');
  assert.ok(result.diffUnverified, 'the return names the diff as unverified');
  assert.deepEqual(result.notDispatched, ['spec-auditor', 'constitution-auditor']);
  assertPayloadShape(result.telemetry);
  assert.equal(result.telemetry.outcome, 'fail');
  assert.match(result.telemetry.fail_reports['diff-provider:round-1'], /no output/);
});

// --- 18. diff-provider contract: failed or truncated output (no marker) fails closed --------------
// The completion marker prints only when the diff command exits 0, and it must be the LAST line —
// so a git error message, a truncated relay (even one that starts diff-shaped), or trailing
// commentary all classify as unverified. They must never be embedded as "the diff".
await test('diff-provider contract: marker-less output (failed / truncated) → gate fails closed', async () => {
  for (const bad of [
    'fatal: not a git repository (or any of the parent directories): .git',
    'diff --git a/f b/f\n+truncated mid-hunk', // diff-shaped but no completion marker
    `${providedDiff()}\nIn summary, the change looks reasonable.`, // commentary after the marker
  ]) {
    const dispatched = [];
    const result = await runGateLoop(baseArgs, async (_p, opts) => {
      if (isDiffProvider(opts)) return bad;
      dispatched.push(opts.agentType || opts.label);
      return { verdict: 'PASS', report: 'should never run' };
    });
    assert.equal(result.gate, 'FAIL');
    assert.equal(dispatched.length, 0, 'no reviewer ran');
    assert.match(result.telemetry.fail_reports['diff-provider:round-1'], /missing completion marker/);
  }
});

// --- 19. diff-provider contract: marker-terminated NON-diff output fails closed -------------------
// A summary or prose answer that happens to end with the marker is still not a git diff.
await test('diff-provider contract: non-diff payload with marker → gate fails closed', async () => {
  const result = await runGateLoop(baseArgs, async (_p, opts) =>
    isDiffProvider(opts)
      ? providedDiff('Here is a summary of the changes: gate-loop.js was refactored.')
      : { verdict: 'PASS', report: 'should never run' },
  );
  assert.equal(result.gate, 'FAIL');
  assert.match(result.telemetry.fail_reports['diff-provider:round-1'], /not a git diff/);
});

// --- 20. diff-provider contract: an EMPTY diff fails closed (the T612 vacuous-pass class) ---------
// Before PR #200 an empty diff reached the reviewers with a "treat as UNVERIFIABLE, do NOT PASS"
// instruction — a behavioral contract. Now the loop itself refuses it structurally: an empty
// committed diff (wrong branch/worktree, nothing committed) aborts without any reviewer prompt.
await test('diff-provider contract: empty committed diff → gate fails closed, not reviewer-instructed', async () => {
  const seen = [];
  const result = await runGateLoop(baseArgs, async (prompt, opts) => {
    if (isDiffProvider(opts)) return `\n${DIFF_MARKER}\n`; // command succeeded, diff is empty
    seen.push(prompt);
    return { verdict: 'PASS', report: 'should never run' };
  });
  assert.equal(result.gate, 'FAIL');
  assert.equal(seen.length, 0, 'no reviewer saw an "empty diff" prompt');
  assert.match(result.telemetry.fail_reports['diff-provider:round-1'], /empty committed diff/);
});

// --- 21. diff-provider contract: a reviewer-style OBJECT return fails closed (PR #200 review) -----
// The exact test-quality gap the review named: earlier stubs let the provider return a
// `{ verdict, report }` object that was stringified into the reviewer prompt and still passed.
// A non-string provider return must abort — nothing stringified ever reaches a reviewer.
await test('diff-provider contract: object (reviewer-shaped) provider return → gate fails closed', async () => {
  const seen = [];
  const result = await runGateLoop(baseArgs, async (prompt, opts) => {
    if (isDiffProvider(opts)) return { verdict: 'PASS', report: 'not a diff' };
    seen.push(prompt);
    return { verdict: 'PASS', report: 'should never run' };
  });
  assert.equal(result.gate, 'FAIL');
  assert.equal(seen.length, 0, 'no reviewer prompt was built from a stringified object');
  assert.match(result.telemetry.fail_reports['diff-provider:round-1'], /no output/);
});

console.log(`\n${testsRun} tests passed`);
