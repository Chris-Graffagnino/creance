#!/usr/bin/env bash
# backlog-loop-falsification.test.sh — the MULTI-ITERATION extension of the T613 isolation
# falsification proof (T903; spec 004 US1.AC4; model in .claude/workflow/backlog-loop.md →
# "Safety invariants").
#
# isolation-falsification.test.sh proves ONE lifecycle pass cannot land un-gated work on the
# base branch. The [backlog-loop] chains N complete next-task cycles in ONE unattended run, so
# the claim must hold ACROSS iterations: NO MERGE AND NO BASE-BRANCH WRITE OCCURS ANYWHERE IN
# AN N-ITERATION RUN, AND AN UN-GATED CHANGE FROM ANY ITERATION — WHATEVER THAT ITERATION'S
# OUTCOME — IS UNREACHABLE FROM BASE. This file drives the REAL lifecycle script (never a
# reimplementation) through N=3 sequential iterations with MIXED outcomes against one SHARED
# base repo, planting the T613 adversarial un-gated commit in EVERY iteration before the
# outcome step:
#   * iteration 1 — gate PASS → promote: `exit` (the T612 path — directory torn down, the
#     branch LEFT for the dispatcher's separate §7-gated PR, NO merge);
#   * iteration 2 — gate FAIL → discard: directory AND branch destroyed (the un-gated SHA is
#     captured BEFORE discard, so unreachability is still asserted for work whose branch no
#     longer exists);
#   * iteration 3 — gate PASS → promote again (the run continues past a FAIL — backlog-loop.md
#     "first FAIL advances").
# Per-instance assertions after EVERY iteration and at run end:
#   1. the base ref SHA is byte-identical to the seed (no base-branch write anywhere in the run);
#   2. no merge occurred: base's rev-list count is EXACTLY the seed count, and no promoted
#      branch is an ancestor of base (explicit is-ancestor exit codes — 1 expected, 0 = merged,
#      anything else = a vacuous check, itself a failure);
#   3. every planted un-gated commit is unreachable from base — including the DISCARDED
#      iteration's, whose commit object is first proven to still exist so the ancestry check
#      cannot pass vacuously on a missing object;
#   4. the terminal state is the PR queue's (backlog-loop.md "Merge authority"): promoted
#      branches EXIST un-merged awaiting a session-explicit merge; the discarded branch does NOT;
#   5. across-iteration independence: each iteration's workspace path and branch are fresh —
#      never a prior iteration's path or branch.
# Promotion stays the dispatcher's separate gated PR and merge stays session-explicit —
# nothing in this run ever merges. Bash + git only, <10s.
# Run: bash .claude/hooks/backlog-loop-falsification.test.sh
set -u

HOOKS="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HOOKS/isolated-workspace.sh"
REPO="$(cd "$HOOKS/../.." && pwd)"
CI="$REPO/.github/workflows/ci.yml"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
# Scope the lifecycle's ephemeral worktree parents into our TMP so the trap reaps them; the
# script honors ${TMPDIR:-/tmp}.
export TMPDIR="$TMP/wsroot"
mkdir -p "$TMPDIR"

pass=0
fail=0
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); printf 'FAIL %s\n' "$1" >&2; }

# new_repo <dir> — throwaway repo with one seed commit on main (the base branch).
new_repo() {
  local d="$1"
  git init -q -b main "$d"
  git -C "$d" config user.email t@example.com
  git -C "$d" config user.name test
  git -C "$d" commit -q --allow-empty -m "chore: bootstrap"
}

# valid_ws <repo> <path> <branch> — true iff <path> is a REAL isolated worktree `enter`
# created: non-empty, an existing directory, AND registered in <repo> on <branch>. Every
# iteration runs this as a SETUP GATE before its safety assertions — the same non-vacuity
# discipline as isolation-falsification.test.sh (Codex P2, PR #116): if `enter` failed, the
# base trivially stays put and the proof would "pass" without ever exercising the lifecycle.
valid_ws() { [ -n "$2" ] && [ -d "$2" ] && git -C "$1" worktree list 2>/dev/null | grep -q "\[$3\]"; }

# The lifecycle under test must exist — a missing script makes every `bash "$SCRIPT"` a no-op
# and the whole multi-iteration proof vacuous. Assert it up front.
if [ -f "$SCRIPT" ]; then ok; else bad "lifecycle script under test not found: $SCRIPT"; fi

# ─────────────────────────────────────────────────────────────────────────────────────────
# The shared base repo. Unlike T613's one-repo-per-case, the WHOLE RUN executes against ONE
# base — that is the multi-iteration claim: iteration k's outcome must not disturb the base
# any prior or later iteration also runs against.
# ─────────────────────────────────────────────────────────────────────────────────────────
R="$TMP/loop-repo"; new_repo "$R"
base0=$(git -C "$R" rev-parse main)
count0=$(git -C "$R" rev-list --count main)

# Per-iteration records, captured BEFORE each outcome step (index 0 unused; pre-seeded so
# every element is set under `set -u` even if an iteration's setup gate fails).
WS=("" "" "" "")
BR=("" "" "" "")
SHA=("" "" "" "")

# assert_base_intact <label> — the no-base-write / no-merge core, run after EVERY iteration
# and at run end: the base ref SHA must be byte-identical to the seed AND base's history must
# have gained no commit (exact rev-list count — a merge, fast-forward, or direct commit on
# base changes at least one of the two).
assert_base_intact() {
  if [ "$(git -C "$R" rev-parse main)" = "$base0" ]; then ok; else bad "$1: base ref SHA changed (a base-branch write occurred during the run)"; fi
  if [ "$(git -C "$R" rev-list --count main)" = "$count0" ]; then ok; else bad "$1: base rev-list count changed (base history gained a commit — a merge/write occurred)"; fi
}

# assert_not_ancestor <label> <commit-ish> <what> — <commit-ish> must NOT be an ancestor of
# base. Explicit exit codes: 1 = not an ancestor (the safe state), 0 = reachable from base
# (the violation), anything else = the check itself errored (a vacuous pass is a failure).
assert_not_ancestor() {
  git -C "$R" merge-base --is-ancestor "$2" main 2>/dev/null; rc=$?
  if [ "$rc" = "1" ]; then ok
  elif [ "$rc" = "0" ]; then bad "$1: $3 ($2) is reachable from base — un-gated/un-merged work landed on the base branch"
  else bad "$1: is-ancestor check for $3 ($2) errored (rc=$rc) — the unreachability assertion would be vacuous"; fi
}

# run_iteration <i> <branch> <promote|discard> — one COMPLETE lifecycle iteration of the loop
# against the shared base repo: enter → plant the T613 adversarial un-gated commit → the
# outcome step (promote = `exit`, the T612 teardown that LEAVES the branch for the separate
# gated PR; discard = the gate-FAIL path, directory + branch destroyed). Records the workspace
# path, branch, and un-gated SHA in WS/BR/SHA — the SHA before the outcome step, so a
# discarded iteration's work is still individually assertable at run end — then runs the
# per-iteration safety assertions.
run_iteration() {
  local i="$1" branch="$2" outcome="$3" ws sha k rc
  ws=$( cd "$R" && bash "$SCRIPT" enter "$branch" --base main 2>/dev/null )
  if valid_ws "$R" "$ws" "$branch"; then
    ok                                                # setup gate: a real isolated worktree exists
  else
    bad "iteration $i setup: enter did not create an isolated worktree on $branch (got '$ws') — cannot run this iteration's proof"
    return
  fi
  # across-iteration independence: iteration i's workspace is FRESH — never a prior
  # iteration's path or branch (one pairwise assertion per prior iteration).
  k=1
  while [ "$k" -lt "$i" ]; do
    if [ "$ws" != "${WS[$k]}" ]; then ok; else bad "iteration $i: workspace path reuses iteration $k's path '$ws'"; fi
    if [ "$branch" != "${BR[$k]}" ]; then ok; else bad "iteration $i: branch reuses iteration $k's branch '$branch'"; fi
    k=$((k + 1))
  done
  # the T613 adversarial move, EVERY iteration: an un-gated commit inside the workspace.
  echo "ungated-$i" > "$ws/ungated-change-$i"
  if git -C "$ws" add "ungated-change-$i" && git -C "$ws" commit -q -m "iteration $i: un-gated change committed inside the isolated workspace"; then ok; else bad "iteration $i setup: could not commit the un-gated change inside the workspace"; fi
  sha=$(git -C "$ws" rev-parse HEAD)
  if [ -n "$sha" ] && [ "$sha" != "$base0" ]; then ok; else bad "iteration $i setup: no distinct un-gated commit to contain (got '$sha')"; fi
  WS[$i]="$ws"; BR[$i]="$branch"; SHA[$i]="$sha"
  case "$outcome" in
    promote)
      # gate PASS → promote: the T612 path — `exit` tears down the DIRECTORY, leaves the
      # branch for the dispatcher's separate gated PR, and merges NOTHING.
      ( cd "$R" && bash "$SCRIPT" exit "$ws" ) >/dev/null 2>&1; rc=$?
      if [ "$rc" = "0" ] && [ ! -d "$ws" ]; then ok; else bad "iteration $i: exit (promote teardown) failed (rc=$rc) or left the workspace directory"; fi
      if git -C "$R" show-ref --verify --quiet "refs/heads/$branch"; then ok; else bad "iteration $i: promoted branch $branch is gone (exit must LEAVE it for the PR)"; fi
      ;;
    discard)
      # gate FAIL → discard: directory AND branch destroyed — the work is thrown away whole.
      ( cd "$R" && bash "$SCRIPT" discard "$ws" ) >/dev/null 2>&1; rc=$?
      if [ "$rc" = "0" ] && [ ! -d "$ws" ]; then ok; else bad "iteration $i: discard failed (rc=$rc) or left the workspace directory"; fi
      if git -C "$R" show-ref --verify --quiet "refs/heads/$branch"; then bad "iteration $i: discarded branch $branch survived discard"; else ok; fi
      ;;
  esac
  # the per-iteration invariants: base untouched, this iteration's un-gated work contained.
  assert_base_intact "iteration $i"
  assert_not_ancestor "iteration $i" "$sha" "the planted un-gated commit"
}

# ─────────────────────────────────────────────────────────────────────────────────────────
# The run: N=3 complete sequential iterations, mixed outcomes (PASS→promote, FAIL→discard,
# PASS→promote). Every stop-condition/sequencing concern is the loop model's (T902); this
# proof owns only the safety invariant the outcomes must preserve.
# ─────────────────────────────────────────────────────────────────────────────────────────
run_iteration 1 bl-iter-1-promote promote
run_iteration 2 bl-iter-2-discard discard
run_iteration 3 bl-iter-3-promote promote

# ─────────────────────────────────────────────────────────────────────────────────────────
# Run end — the whole-run terminal state (the queue of ratifiable PRs, nothing merged).
# ─────────────────────────────────────────────────────────────────────────────────────────
assert_base_intact "run end"

# Every planted un-gated commit is unreachable from base — including iteration 2's, whose
# branch no longer exists. First prove each recorded commit OBJECT still exists (a missing
# object would make is-ancestor error and the unreachability read vacuous), then assert the
# explicit not-an-ancestor exit code, one assertion pair per iteration.
i=1
while [ "$i" -le 3 ]; do
  if [ -n "${SHA[$i]}" ]; then
    if git -C "$R" cat-file -e "${SHA[$i]}^{commit}" 2>/dev/null; then ok; else bad "run end: iteration $i's un-gated commit object is gone — its unreachability check would be vacuous"; fi
    assert_not_ancestor "run end" "${SHA[$i]}" "iteration $i's planted un-gated commit"
  else
    bad "run end: iteration $i recorded no un-gated SHA (its setup failed) — the multi-iteration proof is incomplete"
  fi
  i=$((i + 1))
done

# Terminal branch state, per branch: promoted branches EXIST and are NOT ancestors of base
# (open-PR posture — merge stays session-explicit); the discarded branch does NOT exist.
for b in bl-iter-1-promote bl-iter-3-promote; do
  if git -C "$R" show-ref --verify --quiet "refs/heads/$b"; then ok; else bad "run end: promoted branch $b is gone — the PR-queue terminal state is broken"; fi
  assert_not_ancestor "run end" "refs/heads/$b" "promoted branch $b"
done
if git -C "$R" show-ref --verify --quiet refs/heads/bl-iter-2-discard; then bad "run end: discarded branch bl-iter-2-discard still exists"; else ok; fi

# ─────────────────────────────────────────────────────────────────────────────────────────
# Wiring (P2): the required `verify` job must ACTIVELY run this test, else the falsification
# proof is itself silently dead. Same verify-job-scoped active-`run:` idiom as
# isolation-falsification.test.sh (bare-filename grep is too loose — the #92 / PR #107 lesson).
# ─────────────────────────────────────────────────────────────────────────────────────────
verify_steps() { awk '/^  [A-Za-z]/ { inblk = ($0 ~ /^  verify:/) } inblk { print }' "$CI"; }
runs_in_verify() { verify_steps | grep -qE "^[[:space:]]*run:[[:space:]]+bash[[:space:]]+$1([[:space:]]|\$)"; }
if runs_in_verify '\.claude/hooks/backlog-loop-falsification\.test\.sh'; then ok; else bad "verify must RUN backlog-loop-falsification.test.sh (active run: step)"; fi

printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
