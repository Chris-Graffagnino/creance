#!/usr/bin/env bash
# Regression tests for maker-eval-fence.sh — the deterministic P5 fence over the
# maker-eval channel (T804, #161, spec 003 US2.AC3). The fence scans the tracked tree
# for the eval channel's path/IO tokens and FAILs if any appear outside the writer/
# reader allowlist. So each case runs the REAL fence against a throwaway git repo (the
# check-tasks-consistency.test.sh idiom) holding one planted fixture file, then asserts
# the exit code. This is the constitution-P2 backstop: the fence ships with the test
# proving it FIRES on a planted cross-reference to EITHER path (US2.AC3) AND does not
# false-fire on the real tree or on the sanctioned writer/reader/test surface. It also
# proves the run binding (skills/maker-eval/SKILL.md) is LINE-SCOPED — a writer drive (case n)
# or fingerprint recompute (case t) is benign, but a channel READ/RESOLVE in it still fires:
# a record-path/packet/seam token (cases p/q/r) OR the emitter's channel-reading `complete`
# subcommand, one-line (case s) or WRAPPED across a shell line-continuation (case s2), closing the
# whole-file-allowlist gap PR #164 found. Bash + git only, <1s; wired into the
# `verify` CI job (.github/workflows/ci.yml).
# Run: bash .claude/hooks/maker-eval-fence.test.sh
set -u

DIR="$(cd "$(dirname "$0")" && pwd)"
FENCE="$DIR/maker-eval-fence.sh"
REPO_ROOT="$(cd "$DIR/../.." && pwd)"
CI="$REPO_ROOT/.github/workflows/ci.yml"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
pass=0
fail=0

# run_fence <expected-exit> <root> <name> — run the REAL fence with MAKER_EVAL_FENCE_ROOT
# pointed at <root> and assert its exit code.
run_fence() {
  local want="$1" root="$2" name="$3" got=0
  MAKER_EVAL_FENCE_ROOT="$root" bash "$FENCE" >/dev/null 2>&1 || got=$?
  if [ "$got" -eq "$want" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL %-62s want exit %s, got %s\n' "$name" "$want" "$got" >&2
  fi
}

# mkfix <dir> <relpath> <line> — a throwaway git repo holding ONE fixture file at
# <relpath> containing <line>. git add (no commit needed — the fence reads `git
# ls-files`, the index). The lone file is what determines the fence verdict.
mkfix() {
  local d="$1" rel="$2" line="$3"
  mkdir -p "$d/$(dirname "$rel")"
  printf '%s\n' "$line" > "$d/$rel"
  git init -q -b main "$d"
  git -C "$d" config user.email t@example.com
  git -C "$d" config user.name test
  git -C "$d" add -A
}

# ── PASSES on the real tree (US2.AC3: "passes on the real tree") ────────────────
run_fence 0 "$REPO_ROOT" "PASSES: the real tracked tree"

# ── FIRES on a planted cross-reference to EITHER path, across all four danger
#    classes the AC names (gate / tier / guard / selection) ───────────────────────

# (a) records.jsonl (the eval-RECORD path) planted in a GUARD path.
A="$TMP/plant-records-guard"; mkfix "$A" ".claude/hooks/guard.sh" 'cat "$chan/records.jsonl"   # planted cross-reference'
run_fence 1 "$A" "FIRES: records.jsonl planted in guard.sh (guard path)"

# (b) packets (the transcript-PACKET storage) planted across danger classes — and in all
#     three reference forms, since the dir is matched as a path segment, not just `packets/`:
#     a trailing slash; no trailing slash (`$channel/packets`); and the quote-wrapped pathlib
#     form (`… / "packets"`). Matching only `packets/` let the latter two evade (PR #162 Codex P2).
B="$TMP/plant-packets-gate"; mkfix "$B" ".claude/workflows/gate-loop.js" 'const p = "packets/" + runId + "/" + taskId; // planted'
run_fence 1 "$B" "FIRES: packets/ (trailing slash) planted in gate-loop.js (gate path)"
B_NS="$TMP/plant-packets-noslash"; mkfix "$B_NS" ".claude/hooks/guard.sh" 'probe="$channel/packets"   # no trailing slash — planted'
run_fence 1 "$B_NS" "FIRES: \$channel/packets (no trailing slash) planted in guard.sh (guard path)"
B_PL="$TMP/plant-packets-pathlib"; mkfix "$B_PL" ".claude/hooks/reconcile-task-selection.sh" 'target = Path(channel) / "packets"  # pathlib, quote-wrapped — planted'
run_fence 1 "$B_PL" "FIRES: quote-wrapped \"packets\" planted in reconcile-task-selection.sh (selection)"

# (c) the MAKER_EVAL_DIR access seam planted in a SELECTION path.
C="$TMP/plant-seam-selection"; mkfix "$C" ".claude/hooks/reconcile-task-selection.sh" 'eval_dir="${MAKER_EVAL_DIR:-}"  # planted'
run_fence 1 "$C" "FIRES: MAKER_EVAL_DIR planted in reconcile-task-selection.sh (selection)"

# (d) the channel dir name planted in a TIER path (the model table).
D="$TMP/plant-dir-tier"; mkfix "$D" ".claude/MODELS.md" 'resolve tier from ~/.claude/triage/creance-maker-eval/records.jsonl'
run_fence 1 "$D" "FIRES: creance-maker-eval dir planted in MODELS.md (tier path)"

# (e) invoking the writer planted in next-task.md (the gate+selection hub).
E="$TMP/plant-emit-nexttask"; mkfix "$E" ".claude/workflow/next-task.md" 'then call maker-eval-emit to fold the score into selection'
run_fence 1 "$E" "FIRES: maker-eval-emit invocation planted in next-task.md"

# (f) reading the eval-record path planted in CI ITSELF. CI is a gate (it decides the
#     merge), so a workflow step that reads records.jsonl to gate on it is a P5 breach.
#     The old whole-file allowlist masked this (PR #162 craft/Codex finding); ci.yml is
#     now scanned line-by-line, so the planted step survives the benign filter and fires.
F_CI="$TMP/plant-ci-gate"; mkfix "$F_CI" ".github/workflows/ci.yml" '        run: cat "$HOME/.claude/triage/creance-maker-eval/records.jsonl"  # gate on it'
run_fence 1 "$F_CI" "FIRES: records.jsonl read planted in ci.yml (CI gate surface)"

# (g) a channel token in a NON-allowlisted skill still FIRES — the skill allowlist is the
#     EXACT maker-eval run binding (skills/maker-eval/SKILL.md), never skills/**. next-task is
#     the gate+selection hub, so invoking the writer there to fold a score in is a P5 breach
#     (T805 widened the allowlist by exactly one skill — this proves it did not widen to all).
G_SKILL="$TMP/plant-skill-nonallow"; mkfix "$G_SKILL" ".claude/skills/next-task/SKILL.md" 'then call maker-eval-emit to fold the score into selection'
run_fence 1 "$G_SKILL" "FIRES: maker-eval-emit planted in a non-allowlisted skill (next-task)"

# ── does NOT false-fire on the sanctioned surface ───────────────────────────────

# (h) the eval WRITER may carry the tokens (it IS the channel writer).
F="$TMP/allow-writer"; mkfix "$F" ".claude/hooks/maker-eval-emit.sh" 'printf "%s" "$channel/records.jsonl"  # the writer'
run_fence 0 "$F" "no false fire: records.jsonl in the allowlisted writer"

# (i) the triage READER may carry the tokens.
G="$TMP/allow-reader"; mkfix "$G" ".claude/skills/triage/SKILL.md" 'Read `<channel>/records.jsonl` and the `packets/` subtree.'
run_fence 0 "$G" "no false fire: tokens in the allowlisted triage reader"

# (j) a *.test.sh harness may carry the tokens (tests exercise the channel; no authority).
#     This also proves the plant in cases (a)-(g) had to land in a NON-test file to fire.
H="$TMP/allow-test"; mkfix "$H" ".claude/hooks/guard.test.sh" 'echo "fixture: records.jsonl packets/ MAKER_EVAL_DIR"'
run_fence 0 "$H" "no false fire: tokens in a *.test.sh harness"

# (k) ci.yml is now scanned, but its sanctioned surface must NOT false-fire: a comment
#     naming the tokens cannot execute, so it is benign.
J="$TMP/allow-ci-comment"; mkfix "$J" ".github/workflows/ci.yml" '      # scans for records.jsonl / packets/ (the maker-eval channel)'
run_fence 0 "$J" "no false fire: ci.yml comment naming the channel tokens"

# (l) ...and a step that merely RUNS a maker-eval *.test.sh harness carries no control
#     authority, so it is benign too — this is the wiring ci.yml is allowlisted for.
K="$TMP/allow-ci-wiring"; mkfix "$K" ".github/workflows/ci.yml" '        run: bash .claude/hooks/maker-eval-emit.test.sh'
run_fence 0 "$K" "no false fire: ci.yml step running a maker-eval *.test.sh"

# (m) the path-segment match must NOT catch the bare English plural "packets" in prose —
#     a non-allowlisted doc may discuss "transcript packets" without referencing the dir
#     (real tree: workflow/maker-eval.md, reviewers/maker-eval-corpus.md, spec.md all do).
L="$TMP/allow-prose"; mkfix "$L" ".claude/workflow/some-neutral-doc.md" 'the eval-record path and its transcript packets are observed, never gated.'
run_fence 0 "$L" "no false fire: bare word \"packets\" in prose (not a path segment)"

# (n) the eval RUN binding (skills/maker-eval/SKILL.md) DRIVES the writer, so a writer
#     invocation there is benign. The binding is LINE-SCOPED, not whole-file allowlisted
#     (PR #164), so the writer-invocation line drops out and must not false-fire (T805, US2.AC1).
N="$TMP/allow-run-binding"; mkfix "$N" ".claude/skills/maker-eval/SKILL.md" 'Append via: bash .claude/hooks/maker-eval-emit.sh record --run-id "$id" --task "$t".'
run_fence 0 "$N" "no false fire: maker-eval-emit (writer drive) in the line-scoped run binding"

# (o) the P-ME probe instantiation (adapters/claude-code-probes.md) names the writer + the
#     record path by its NATURE (a conformance-probe doc, no control authority) — allowlisted
#     Tier 2, must not false-fire (T805, US2.AC4).
O="$TMP/allow-probe-doc"; mkfix "$O" ".claude/adapters/claude-code-probes.md" 'P-ME: invoke maker-eval-emit; assert a record lands in records.jsonl with the fingerprint.'
run_fence 0 "$O" "no false fire: tokens in the allowlisted P-ME probe instantiation"

# ── the RUN binding is LINE-SCOPED, not whole-file trusted: it may DRIVE the writer (case n)
#    or recompute the fingerprint (case t) but a channel READ/RESOLVE inside it still FIRES —
#    reading the record path or the packet store, resolving the channel seam, or invoking the
#    emitter's `complete` READ subcommand (one-line or wrapped across a line-continuation), is
#    the triage reader's/writer's job, never the run
#    binding's (spec 003 US2.AC3). The old whole-file allowlist let any of these pass, so a
#    future edit reading eval records "to choose a tier" from the binding bypassed the P5 fence
#    (PR #164 craft/Codex). These are the negative fixtures proving the line-scope closes it. ──

# (p) reading the eval-RECORD path planted in the run binding FIRES — the exact "read
#     records.jsonl to choose a tier" escape both reviewers named (not a writer drive).
P_REC="$TMP/binding-reads-records"; mkfix "$P_REC" ".claude/skills/maker-eval/SKILL.md" 'Then `cat "$chan/records.jsonl"` to choose the maker tier.  # planted read'
run_fence 1 "$P_REC" "FIRES: records.jsonl READ planted in the run binding (not a writer drive)"

# (q) reading the transcript-PACKET store planted in the run binding FIRES.
Q_PKT="$TMP/binding-reads-packets"; mkfix "$Q_PKT" ".claude/skills/maker-eval/SKILL.md" 'Read `$channel/packets/$id/report` back into the gate.  # planted packet read'
run_fence 1 "$Q_PKT" "FIRES: packet-store read planted in the run binding"

# (r) resolving the channel SEAM (the env override) planted in the run binding FIRES — the
#     binding drives the writer; it must not resolve the channel location itself.
R_SEAM="$TMP/binding-resolves-seam"; mkfix "$R_SEAM" ".claude/skills/maker-eval/SKILL.md" 'eval_dir="${MAKER_EVAL_DIR:-}"   # planted channel resolve'
run_fence 1 "$R_SEAM" "FIRES: MAKER_EVAL_DIR seam planted in the run binding"

# (s) invoking the emitter's channel-READING subcommand (`complete`, which resolves the channel
#     and reads records.jsonl to count a run's records) planted in the run binding FIRES — it is
#     a channel read, not a writer drive. The whole-emitter line-scope this replaces let it pass
#     because it carries no explicit records.jsonl token, yet `complete` reads exactly that
#     (PR #164 Codex P2). The run binding emits records; the completeness READ is the triage reader's.
S_DONE="$TMP/binding-invokes-complete"; mkfix "$S_DONE" ".claude/skills/maker-eval/SKILL.md" 'Then `bash .claude/hooks/maker-eval-emit.sh complete --run-id "$id"` to check the run.  # planted channel read'
run_fence 1 "$S_DONE" "FIRES: maker-eval-emit complete (channel read) planted in the run binding"

# (s2) the SAME channel-reading `complete` invocation, but WRAPPED across a shell line-
#      continuation (`maker-eval-emit.sh \<newline> complete`), still FIRES — the real evasion
#      shape (P3). The per-physical-line scan saw a benign writer drive on the first line and a
#      tokenless `complete` on the next, so the wrap cleared the line-scope (PR #164 craft). The
#      fence now folds backslash-continuations into one logical line before scoping the binding,
#      so the wrapped read matches EMITTER_READ_SUBCOMMAND exactly as the one-line case (s).
S_WRAP="$TMP/binding-wraps-complete"
S_WRAP_LINE=$'bash .claude/hooks/maker-eval-emit.sh \\\n  complete --run-id "$id"  # planted wrapped channel read'
mkfix "$S_WRAP" ".claude/skills/maker-eval/SKILL.md" "$S_WRAP_LINE"
run_fence 1 "$S_WRAP" "FIRES: maker-eval-emit + complete WRAPPED across a line-continuation in the run binding"

# (t) recomputing the fingerprint (`maker-eval-emit fingerprint`) reads only the model table +
#     the maker surfaces, never the channel, so it is benign in the run binding (the binding's
#     own MAKER-EVAL-STALE detector recipe) — it must not false-fire alongside (s), proving the
#     line-scope distinguishes the emitter's read subcommand from its no-channel-I/O one.
T_FP="$TMP/binding-invokes-fingerprint"; mkfix "$T_FP" ".claude/skills/maker-eval/SKILL.md" 'Recompute via `bash .claude/hooks/maker-eval-emit.sh fingerprint` — the maker-behavior field.'
run_fence 0 "$T_FP" "no false fire: maker-eval-emit fingerprint (no channel I/O) in the run binding"

# ── fail-closed: an unscannable root is a LOUD failure, never a silent pass (P2) ─
run_fence 2 "$TMP/does-not-exist" "fail-closed: empty/unscannable root exits loud"

# ── CI wiring (the silent-death backstop, P2): the fence AND its test must run in
#    verify, else the machinery is dead while this file stays green. ───────────────
if grep -qE '(^|[[:space:]])bash[[:space:]]+[.]claude/hooks/maker-eval-fence[.]sh([[:space:]]|$)' "$CI"; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  printf 'FAIL %-62s ci.yml verify must run maker-eval-fence.sh\n' "wiring: fence runs in CI" >&2
fi
if grep -qE '(^|[[:space:]])bash[[:space:]]+[.]claude/hooks/maker-eval-fence[.]test[.]sh([[:space:]]|$)' "$CI"; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  printf 'FAIL %-62s ci.yml verify must run maker-eval-fence.test.sh\n' "wiring: fence test runs in CI" >&2
fi

printf 'maker-eval-fence.test.sh: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
