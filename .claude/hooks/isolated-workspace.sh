#!/usr/bin/env bash
# isolated-workspace.sh — the [isolated workspace] role's WORKSPACE LIFECYCLE binding for
# the Claude Code adapter (T611 enter/exit + T612 discard; epic #81; model in
# .claude/workflow/README.md → "[isolated workspace]", rationale in DESIGN-NOTES §14).
#
# The deterministic [autonomy activation] check (autonomy-mode.sh, T610) decides WHETHER an
# autonomous run is engaged; this script provides the WHERE — the ephemeral git worktree an
# engaged autonomous run executes inside, entered before the work and (per the §7 gate
# outcome) torn down after. Three lifecycle primitives:
#
#   enter <branch> [--base <ref>]   create an ephemeral worktree on a NEW branch off <base>
#                                   (default HEAD) and PRINT its path on stdout;
#   exit  <path>                    remove that workspace DIRECTORY (force) and prune, LEAVING
#                                   the branch — the teardown half of the PROMOTE-on-PASS path
#                                   (the dispatcher pushes / opens the PR first, then exits);
#   discard <path>                  remove the workspace DIRECTORY (force) AND delete its
#                                   ephemeral branch — the DISCARD-on-FAIL path: the §7 gate
#                                   FAILed, so the committed work is thrown away whole.
# exit and discard both REFUSE a <path> unless its parent carries the provenance MARKER that
# `enter` writes there — not merely a creance-ws-* name. A registered worktree under a look-alike
# creance-ws-* directory that `enter` did NOT create (a manual `git worktree add`, a copied/stale
# dir, another run's workspace) has no marker, so a stale/foreign/hand-made path can never
# force-remove — or delete the branch of — an unrelated (possibly dirty) worktree.
#
# The promote-vs-discard DECISION is the §7 gate's, never the lifecycle's (T612): the
# dispatcher calls `exit` after a PASS (having already pushed / opened the PR) and `discard`
# after a FAIL. This script still PROMOTES nothing and carries no gate logic —
# enter/exit/discard only ever touch the EPHEMERAL workspace and its own fresh branch, NEVER
# the base branch. So an un-gated change cannot reach the base branch THROUGH this mechanism
# (constitution P4): promotion is the dispatcher's PR (a human / session-authorized merge),
# and discard only ever deletes a non-base ephemeral branch. The full falsification proof of
# that property, wired into `verify`, is T613.
#
# explicit-context rule (workflow/README.md): `enter` RETURNS the workspace path on stdout;
# the caller passes it forward (to the work, and to `exit`) explicitly — the path is never
# rediscovered from an env var or an inferred CWD.
#
# FAIL DIRECTION — like autonomy-mode.sh, the inverse of guard.sh's fail-open: `enter` FAILS
# LOUD (non-zero, no path on stdout) on any error. The caller's contract is to ABORT the
# autonomous run on a non-zero `enter`, NEVER to fall back to operating on the base branch /
# main working tree — a silent fallback would run un-isolated autonomous work, the one thing
# isolation exists to prevent.
#
# Run from the repo root:
#   path=$(bash .claude/hooks/isolated-workspace.sh enter <branch> [--base <ref>]) || abort
#   ... do the autonomous task inside "$path", then run the §7 gate against it ...
#   # gate PASS → promote: push / open the PR, THEN
#   bash .claude/hooks/isolated-workspace.sh exit "$path"
#   # gate FAIL → discard (no push, no PR):
#   bash .claude/hooks/isolated-workspace.sh discard "$path"
# Exit: 0 ok · 2 usage · 1 lifecycle failure (could not create/remove the workspace).
set -u

usage() {
  echo "usage: $(basename "$0") enter   <branch> [--base <ref>]" >&2
  echo "       $(basename "$0") exit    <path>" >&2
  echo "       $(basename "$0") discard <path>" >&2
  exit 2
}

# fail <msg> — loud, non-zero, and crucially NO path on stdout (the caller aborts; it must
# never read a stale/empty path as a workspace and never fall back to the base branch).
fail() { echo "isolated-workspace: $*" >&2; exit 1; }

# assert_owned <path> — the ONE ownership guard, shared by exit and discard (a single
# definition, never two that could drift). `enter` prints <tmp>/creance-ws-XXXXXX/wt AND writes a
# provenance MARKER (.creance-ws-owner) into that parent. Both teardown verbs run a forced
# `git worktree remove` (and discard additionally deletes the branch), which would destroy even
# a DIRTY worktree's work, so a stale, corrupted, hand-made, or another run's path must be refused
# BEFORE any destructive step. The */creance-ws-* name is only a cheap first filter (and a clear
# message); the load-bearing check is the MARKER, because the name alone is forgeable — a manual
# `git worktree add` under a creance-ws-* dir, or another lifecycle's look-alike worktree, would
# otherwise pass and (via discard) have its branch force-deleted (Codex P2, PR #114). Called in the
# main shell (never in a command substitution) so its `fail` exits the script, not just a subshell.
assert_owned() {
  local parent
  parent=$(dirname "$1")
  case "$parent" in
    */creance-ws-*) : ;;
    *) fail "refusing to tear down '$1' — not an isolated-workspace ephemeral worktree (its parent is not a */creance-ws-* temp dir)" ;;
  esac
  [ -f "$parent/.creance-ws-owner" ] \
    || fail "refusing to tear down '$1' — no isolated-workspace provenance marker in '$parent' (a creance-ws-* look-alike this lifecycle's enter did not create, or an already-torn-down workspace)"
}

[ "$#" -ge 1 ] || usage
cmd="$1"
shift

case "$cmd" in
  enter)
    [ "$#" -ge 1 ] || usage
    branch="$1"
    shift
    base="HEAD"
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --base) [ "$#" -ge 2 ] || usage; base="$2"; shift 2 ;;
        *) usage ;;
      esac
    done
    git rev-parse --git-dir >/dev/null 2>&1 \
      || fail "not inside a git repository — cannot enter an isolated workspace"
    # A fresh ephemeral branch is the contract: refuse to reuse/clobber an existing one.
    if git show-ref --verify --quiet "refs/heads/$branch"; then
      fail "branch '$branch' already exists — enter requires a fresh branch"
    fi
    # Ephemeral location OUTSIDE the repo tree, so the main working tree stays clean and the
    # workspace is truly disposable. mktemp -d makes the parent; the worktree is a not-yet-
    # existing subdir of it (git worktree add refuses a path that already exists).
    parent=$(mktemp -d "${TMPDIR:-/tmp}/creance-ws-XXXXXX") || fail "could not allocate a workspace directory"
    dir="$parent/wt"
    # Provenance marker, written in the PARENT (never inside $dir, so it never shows up in the
    # workspace's own git status or the §7 gate's diff): proof THIS lifecycle's enter created this
    # workspace. exit/discard refuse a path whose parent lacks it, so a registered worktree under a
    # creance-ws-* look-alike enter did NOT create can never be torn down — or have its branch
    # deleted (Codex P2, PR #114). Any failure path below reaps it via `rm -rf "$parent"`.
    printf '%s\n' 'isolated-workspace ephemeral worktree parent — safe to remove via exit/discard' \
      > "$parent/.creance-ws-owner" \
      || { rm -rf "$parent" 2>/dev/null; fail "could not write the workspace provenance marker"; }
    if ! git worktree add --quiet -b "$branch" "$dir" "$base" >/dev/null 2>&1; then
      rm -rf "$parent" 2>/dev/null
      fail "git worktree add failed for branch '$branch' off '$base'"
    fi
    # explicit-context: the ONLY stdout on success is the path the caller carries forward.
    printf '%s\n' "$dir"
    ;;
  exit)
    [ "$#" -ge 1 ] || usage
    path="$1"
    shift
    [ "$#" -eq 0 ] || usage
    git rev-parse --git-dir >/dev/null 2>&1 \
      || fail "not inside a git repository — cannot exit a workspace"
    # Ownership BEFORE the forced remove (assert_owned's rationale) — never after.
    assert_owned "$path"
    # Remove the workspace DIRECTORY only (force: it may carry uncommitted or committed work —
    # discarding the working tree is the point). The branch is intentionally LEFT untouched:
    # `exit` is the teardown half of the PROMOTE path — the dispatcher has already pushed /
    # opened the PR, so the branch must survive. Throwing the branch away on a FAIL is the
    # separate `discard` verb (the gate's decision, T612), never `exit`'s.
    if ! git worktree remove --force "$path" >/dev/null 2>&1; then
      fail "git worktree remove failed for '$path' (not a registered worktree?)"
    fi
    # Best-effort cleanup of OUR ephemeral parent dir (ownership already proven above): drop the
    # provenance marker so the now-empty parent rmdir's cleanly, then prune worktree metadata.
    parent=$(dirname "$path")
    rm -f "$parent/.creance-ws-owner" 2>/dev/null || true
    rmdir "$parent" 2>/dev/null || true
    git worktree prune >/dev/null 2>&1 || true
    ;;
  discard)
    [ "$#" -ge 1 ] || usage
    path="$1"
    shift
    [ "$#" -eq 0 ] || usage
    git rev-parse --git-dir >/dev/null 2>&1 \
      || fail "not inside a git repository — cannot discard a workspace"
    # Same ownership guard as exit — a stale/foreign path must never get its branch deleted.
    assert_owned "$path"
    # Resolve the workspace's branch BEFORE removing the worktree (afterwards the path is gone
    # and the branch is unresolvable). `enter` always checks out a fresh symbolic branch, so a
    # healthy workspace has one; a detached/unresolvable HEAD is not a workspace this verb
    # created → fail loud rather than guess which ref to delete.
    branch=$(git -C "$path" symbolic-ref --quiet --short HEAD 2>/dev/null) \
      || fail "could not resolve the workspace branch for '$path' (not a registered worktree, or detached HEAD?)"
    [ -n "$branch" ] || fail "empty workspace branch for '$path' — refusing to delete an unnamed ref"
    # DISCARD = exit's teardown + delete the ephemeral branch. The gate FAILed, so the whole
    # committed change is thrown away. Remove the worktree first (so the branch is no longer
    # checked out anywhere), then force-delete the branch.
    if ! git worktree remove --force "$path" >/dev/null 2>&1; then
      fail "git worktree remove failed for '$path' (not a registered worktree?)"
    fi
    parent=$(dirname "$path")
    rm -f "$parent/.creance-ws-owner" 2>/dev/null || true   # drop the marker so the parent rmdir's cleanly
    rmdir "$parent" 2>/dev/null || true
    git worktree prune >/dev/null 2>&1 || true
    # -D (force): the ephemeral branch is unmerged by definition (the gate FAILed). git refuses
    # to delete a branch still checked out in a live worktree, so this can never touch the base
    # branch checked out in the main tree — and the ownership guard already proved the branch is
    # one of ours. The base branch is never named or touched here.
    if ! git branch -D "$branch" >/dev/null 2>&1; then
      fail "removed the workspace dir but could not delete its branch '$branch' — delete it manually"
    fi
    ;;
  *)
    usage
    ;;
esac
exit 0
