#!/usr/bin/env bash
# isolated-workspace.sh — the [isolated workspace] role's WORKSPACE LIFECYCLE binding for
# the Claude Code adapter (T611 / epic #81 part b; model in .claude/workflow/README.md →
# "[isolated workspace]", rationale in DESIGN-NOTES §14).
#
# The deterministic [autonomy activation] check (autonomy-mode.sh, T610) decides WHETHER an
# autonomous run is engaged; this script provides the WHERE — the ephemeral git worktree an
# engaged autonomous run executes inside, entered before the work and torn down after. It is
# a pair of pure lifecycle primitives:
#
#   enter <branch> [--base <ref>]   create an ephemeral worktree on a NEW branch off <base>
#                                   (default HEAD) and PRINT its path on stdout;
#   exit  <path>                    remove that workspace DIRECTORY (force) and prune; REFUSES
#                                   a <path> that is not one of THIS lifecycle's own
#                                   creance-ws-* workspaces, so a stale/foreign path can never
#                                   force-remove an unrelated (possibly dirty) worktree.
#
# Two boundaries this script deliberately does NOT cross — they are T612 (gate-in-place):
#   * it never PROMOTES. Nothing here writes the base branch: `enter` creates a fresh branch,
#     and `exit` removes only the workspace DIRECTORY. The committed work's fate — promote on
#     a §7 gate PASS vs discard on FAIL — is the gate's decision, not the lifecycle's, so the
#     branch is left in place by `exit`.
#   * it carries no gate logic.
# An un-gated change therefore cannot reach the base branch THROUGH this mechanism
# (constitution P4); the falsification proof of that property, wired into `verify`, is T613.
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
#   ... do the autonomous task inside "$path" ...
#   bash .claude/hooks/isolated-workspace.sh exit "$path"
# Exit: 0 ok · 2 usage · 1 lifecycle failure (could not create/remove the workspace).
set -u

usage() {
  echo "usage: $(basename "$0") enter <branch> [--base <ref>]" >&2
  echo "       $(basename "$0") exit  <path>" >&2
  exit 2
}

# fail <msg> — loud, non-zero, and crucially NO path on stdout (the caller aborts; it must
# never read a stale/empty path as a workspace and never fall back to the base branch).
fail() { echo "isolated-workspace: $*" >&2; exit 1; }

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
    # OWNERSHIP GUARD — refuse to tear down anything that is not one of THIS lifecycle's own
    # ephemeral workspaces. `enter` only ever prints <tmp>/creance-ws-XXXXXX/wt, so a path it
    # produced always has a */creance-ws-* parent. `git worktree remove --force` discards even
    # a DIRTY worktree, so a stale, corrupted, or hand-supplied path pointing at an unrelated
    # worktree would otherwise delete real local work — validate ownership BEFORE the forced
    # remove, not after.
    parent=$(dirname "$path")
    case "$parent" in
      */creance-ws-*) : ;;
      *) fail "refusing to exit '$path' — not an isolated-workspace ephemeral worktree (its parent is not a */creance-ws-* temp dir)" ;;
    esac
    # Remove the workspace DIRECTORY only (force: it may carry uncommitted or committed work —
    # discarding the working tree is the point). The branch is intentionally left untouched:
    # promoting or deleting it is the gate's decision (T612), never the lifecycle's.
    if ! git worktree remove --force "$path" >/dev/null 2>&1; then
      fail "git worktree remove failed for '$path' (not a registered worktree?)"
    fi
    # Best-effort cleanup of OUR ephemeral parent dir (ownership already proven above), then
    # prune stale worktree metadata.
    rmdir "$parent" 2>/dev/null || true
    git worktree prune >/dev/null 2>&1 || true
    ;;
  *)
    usage
    ;;
esac
exit 0
