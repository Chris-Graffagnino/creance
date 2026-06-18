#!/usr/bin/env bash
# Tests for isolated-workspace.sh — the [isolated workspace] role's worktree lifecycle
# binding (T611 / epic #81 part b).
#
# Proves the lifecycle primitives behave AND that the wiring is live (P2 "machinery proves
# it is live", same discipline as guard.test.sh / autonomy-mode.test.sh):
#   * enter:        creates an ephemeral worktree on a NON-base branch and PRINTS its path
#                   on stdout (explicit-context) — done-when 1;
#   * exit:         removes that workspace directory; the worktree de-registers — done-when 1;
#   * no main write: enter -> commit work in the workspace -> exit leaves the BASE ref
#                   untouched (the no-un-gated-path-to-main slice; the full falsification
#                   proof is T613) — done-when 3;
#   * boundary:     exit removes the DIRECTORY but leaves the branch (committed work's fate is
#                   the gate's, T612 — exit must not silently discard it);
#   * fail-safe:    enter outside a repo / on an existing branch FAILS LOUD with NO path on
#                   stdout, so the caller aborts rather than reading a phantom workspace and
#                   never falls back to the base branch — done-when 5;
#   * usage guards;
#   * wiring (P2):  the `verify` job ACTIVELY runs this test (an active `run:` step, not a
#                   mention in a comment); and the mechanism<->model drift backstop — the
#                   neutral role, the next-task activation wiring, and the adapter binding of
#                   BOTH mechanisms all exist — done-when 4.
# Bash + git only, <1s. Run: bash .claude/hooks/isolated-workspace.test.sh
set -u

HOOKS="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HOOKS/isolated-workspace.sh"
REPO="$(cd "$HOOKS/../.." && pwd)"
CI="$REPO/.github/workflows/ci.yml"
MODEL="$REPO/.claude/workflow/README.md"
NEUTRAL="$REPO/.claude/workflow/next-task.md"
BINDING="$REPO/.claude/skills/next-task/SKILL.md"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
# Scope the script's ephemeral worktree parents (creance-ws-*) into our TMP so the trap
# reaps them; the script honors ${TMPDIR:-/tmp}.
export TMPDIR="$TMP/wsroot"
mkdir -p "$TMPDIR"

pass=0
fail=0
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); printf 'FAIL %s\n' "$1" >&2; }

# new_repo <dir> — throwaway repo with one seed commit on main.
new_repo() {
  local d="$1"
  git init -q -b main "$d"
  git -C "$d" config user.email t@example.com
  git -C "$d" config user.name test
  git -C "$d" commit -q --allow-empty -m "chore: bootstrap"
}

# rc <label> <want-rc> <args...> — run the script from a neutral CWD, assert exit code.
rc() {
  local label="$1" want="$2"
  shift 2
  local got=0
  ( cd "$TMP" && bash "$SCRIPT" "$@" ) >/dev/null 2>&1 || got=$?
  if [ "$got" = "$want" ]; then ok; else bad "$label: got rc=$got want $want"; fi
}

# ── Lifecycle: enter -> work -> exit, with the base ref watched throughout ──
R="$TMP/repo"; new_repo "$R"
base_before=$(git -C "$R" rev-parse main)

ws=$( cd "$R" && bash "$SCRIPT" enter ws-1 --base main 2>/dev/null )
# enter prints a usable path (done-when 1, explicit-context).
if [ -n "$ws" ] && [ -d "$ws" ]; then ok; else bad "enter: no usable workspace path printed (got '$ws')"; fi
# the workspace is a separate working tree on the NON-base branch ws-1.
if [ "$(git -C "$ws" branch --show-current 2>/dev/null)" = "ws-1" ]; then ok; else bad "enter: workspace not on branch ws-1"; fi
# it is a registered worktree (match the branch tag, not the path — macOS resolves /var->/private/var).
if git -C "$R" worktree list 2>/dev/null | grep -q '\[ws-1\]'; then ok; else bad "enter: worktree not registered"; fi

# Do work inside the workspace; the BASE ref must not move (done-when 3).
echo isolated > "$ws/newfile"
git -C "$ws" add newfile
git -C "$ws" commit -q -m "work inside the isolated workspace"
if [ "$(git -C "$R" rev-parse main)" = "$base_before" ]; then ok; else bad "no-write: base ref moved while working in the workspace"; fi

# exit removes the workspace directory and de-registers it (done-when 1).
( cd "$R" && bash "$SCRIPT" exit "$ws" ) >/dev/null 2>&1
if [ ! -d "$ws" ]; then ok; else bad "exit: workspace directory still present"; fi
if git -C "$R" worktree list 2>/dev/null | grep -q '\[ws-1\]'; then bad "exit: worktree still registered"; else ok; fi
# Base STILL untouched after exit (done-when 3).
if [ "$(git -C "$R" rev-parse main)" = "$base_before" ]; then ok; else bad "no-write: base ref moved across exit"; fi
# Boundary: exit removes the DIRECTORY but leaves the branch — promoting/discarding the
# committed work is the gate's call (T612), so the lifecycle must not silently discard it.
if git -C "$R" show-ref --verify --quiet refs/heads/ws-1; then ok; else bad "boundary: exit deleted the branch (that is T612's decision, not the lifecycle's)"; fi

# ── Fail-safe: enter must FAIL LOUD with NO path on stdout (done-when 5) ──
# (a) outside any git repository.
OUTSIDE="$TMP/not-a-repo"; mkdir -p "$OUTSIDE"
out=$( cd "$OUTSIDE" && bash "$SCRIPT" enter foo 2>/dev/null ); got=$?
if [ "$got" = "1" ] && [ -z "$out" ]; then ok; else bad "fail-safe: enter outside a repo leaked rc=$got path='$out'"; fi
# (b) onto an already-existing branch (the fresh-branch contract).
R2="$TMP/repo2"; new_repo "$R2"; git -C "$R2" branch dup
out=$( cd "$R2" && bash "$SCRIPT" enter dup 2>/dev/null ); got=$?
if [ "$got" = "1" ] && [ -z "$out" ]; then ok; else bad "fail-safe: enter onto existing branch leaked rc=$got path='$out'"; fi
# (c) exit on a path that is not a registered worktree fails loud (not a silent success).
rc "exit non-worktree -> fail loud" 1 exit "$TMP/never-a-worktree"

# ── Usage guards (exit 2, before any git work) ──
rc "no args -> usage"            2
rc "enter w/o branch -> usage"   2 enter
rc "enter --base w/o value"      2 enter b --base
rc "exit w/o path -> usage"      2 exit
rc "unknown subcommand -> usage" 2 frobnicate

# ── Wiring (P2): the required `verify` job must ACTIVELY run this test, else the lifecycle
# is unproven-and-unwired. Bare-filename grep is too loose (a commented-out/moved copy would
# satisfy it — the #92 / PR #107 lesson), so scope to the verify job body and require an
# active `run: bash <path>` step, exactly as autonomy-mode.test.sh does. ──
verify_steps() { awk '/^  [A-Za-z]/ { inblk = ($0 ~ /^  verify:/) } inblk { print }' "$CI"; }
runs_in_verify() { verify_steps | grep -qE "^[[:space:]]*run:[[:space:]]+bash[[:space:]]+$1([[:space:]]|\$)"; }
if runs_in_verify '\.claude/hooks/isolated-workspace\.test\.sh'; then ok; else bad "verify must RUN isolated-workspace.test.sh (active run: step)"; fi

# Mechanism <-> model drift backstop (done-when 4): the role this binds, the neutral
# next-task wiring that consults the activation read, and the adapter binding of BOTH
# mechanisms must all exist — else the lifecycle is decoupled from its model/path.
if grep -qF '[isolated workspace]' "$MODEL"; then ok; else bad "workflow/README.md missing the [isolated workspace] role"; fi
if grep -qF '[autonomy activation]' "$NEUTRAL"; then ok; else bad "next-task.md does not wire the [autonomy activation] read into the path"; fi
if grep -qF 'isolated-workspace.sh' "$BINDING"; then ok; else bad "SKILL.md does not bind the [isolated workspace] lifecycle mechanism"; fi
if grep -qF 'autonomy-mode.sh' "$BINDING"; then ok; else bad "SKILL.md does not bind the [autonomy activation] read into the next-task path"; fi

printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
