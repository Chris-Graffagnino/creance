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
#   enter <branch> [--base <ref>] [--session <id>]
#                                   create an ephemeral worktree on a NEW branch off <base>
#                                   (default HEAD) and PRINT its path on stdout; --session
#                                   RECORDS the owning session's id in the provenance marker,
#                                   which is the ONLY thing that makes the workspace reapable
#                                   by `sweep` (T906);
#   exit  <path>                    remove that workspace DIRECTORY (force) and prune, LEAVING
#                                   the branch — the teardown half of the PROMOTE-on-PASS path
#                                   (the dispatcher pushes / opens the PR first, then exits);
#   discard <path>                  remove the workspace DIRECTORY (force) AND delete its
#                                   ephemeral branch — the DISCARD-on-FAIL path: the §7 gate
#                                   FAILed, so the committed work is thrown away whole;
#   sweep --session <live-id>       CRASH RECOVERY (T906): reap the workspaces a previous run
#                                   leaked. enter/exit/discard only reap on a caught in-process
#                                   failure, so a SIGKILL (or a machine sleep) between
#                                   `worktree add` and the teardown strands the temp dir, its
#                                   marker, the registration, and the ephemeral branch forever.
#                                   `sweep` reaps a worktree ONLY when all of: its parent is a
#                                   creance-ws-* dir, that parent carries the provenance MARKER,
#                                   and the marker records a `session=` DIFFERENT from <live-id>.
#                                   Everything else is left registered and on disk — a live
#                                   workspace, a marker-less/foreign worktree, and (crucially) a
#                                   marker with NO session line, whose owner cannot be PROVEN
#                                   dead. Reaping reuses discard's exact path, so the new delete
#                                   is marker-gated by construction, not by a parallel copy.
# exit and discard both REFUSE a <path> unless its parent carries the provenance MARKER that
# `enter` writes there — not merely a creance-ws-* name. A registered worktree under a look-alike
# creance-ws-* directory that `enter` did NOT create (a manual `git worktree add`, a copied/stale
# dir, another run's workspace) has no marker, so a stale/foreign/hand-made path can never
# force-remove — or delete the branch of — an unrelated (possibly dirty) worktree.
#
# WHY `sweep` KEYS ON A SESSION TOKEN AND NOT PROCESS LIVENESS (T906). The obvious "is the
# owner still running?" test — record a PID at `enter` and probe it — is WRONG here, and
# dangerously so: nothing in the repo invokes enter/exit/discard programmatically (the
# lifecycle is driven by the adapter binding from short-lived tool shells), so the PID at
# `enter` time belongs to a process that exits seconds later. A PID probe would therefore
# classify perfectly LIVE workspaces as dead and force-remove them — the exact failure DW3
# forbids. The sound signal is the loop's own mutual exclusion: backlog-loop.sh holds a lock
# for the whole run, so AT MOST ONE session is live at a time. "recorded session != the live
# session" is then precisely "created by a run that has already ended", with no clock, no
# PID table, and no recycling hazard. A marker with no session at all stays unreapable: the
# fail direction of this whole family is leak-never-destroy, and an unprovable owner is left
# alone rather than guessed dead.
#
# The promote-vs-discard DECISION is the §7 gate's, never the lifecycle's (T612): the
# dispatcher calls `exit` after a PASS (having already pushed / opened the PR) and `discard`
# after a FAIL. This script still PROMOTES nothing and carries no gate logic —
# enter/exit/discard only ever touch the EPHEMERAL workspace and its own fresh branch, NEVER
# the base branch. So an un-gated change cannot reach the base branch THROUGH this mechanism
# (constitution P4): promotion is the dispatcher's PR (a human / session-authorized merge),
# and discard only ever deletes a non-base ephemeral branch. The full adversarial falsification
# proof of that property is isolation-falsification.test.sh (T613), wired into `verify`.
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
#   # crash recovery, once at loop start, by the session that holds the loop lock:
#   bash .claude/hooks/isolated-workspace.sh sweep --session "$live_session_id"
# Exit: 0 ok · 2 usage · 1 lifecycle failure (could not create/remove the workspace). `sweep`
# is tolerant by design: a workspace it cannot reap is reported on stderr and the remaining
# orphans are still swept, with exit 1 at the end — one wedged orphan never blocks the rest.
set -u

usage() {
  echo "usage: $(basename "$0") enter   <branch> [--base <ref>] [--session <id>]" >&2
  echo "       $(basename "$0") exit    <path>" >&2
  echo "       $(basename "$0") discard <path>" >&2
  echo "       $(basename "$0") sweep   --session <live-id>" >&2
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

# marker_field <parent> <key> — echo the value `enter` RECORDED under <key> in this workspace's
# provenance marker (its `<key>=` line), or return non-zero if the key is absent. ONE reader for
# every marker field (`branch`, `session`), never two that could drift — the same single-definition
# discipline assert_owned follows. `discard` reads `branch` to delete THIS recorded identity — the
# branch enter created — never the worktree's CURRENT HEAD: if the worktree were switched to
# another branch after enter (`git switch`), resolving HEAD would force-delete that unrelated
# branch and orphan the ephemeral one (Codex P2, PR #114). `sweep` reads `session` to tell a dead
# run's leftovers from a live run's workspace. Pure-bash read (no external tool); callers run
# assert_owned (or the sweep's own marker test) first, so the marker file is present.
marker_field() {
  local line key="$2"
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      "$key"=*) printf '%s\n' "${line#"$key"=}"; return 0 ;;
    esac
  done < "$1/.creance-ws-owner"
  return 1
}

# discard_workspace <path> — THE discard path: ownership guard, forced worktree removal, parent
# cleanup, then delete the ephemeral branch `enter` recorded. Extracted (T906) so the `discard`
# verb and the crash-recovery `sweep` share ONE delete implementation — the sweep cannot acquire
# a weaker guard than discard's, because it does not have its own. Calls `fail` on every error
# path (so the `discard` verb aborts exactly as before); `sweep` runs it in a subshell to contain
# that exit and keep sweeping the remaining orphans.
discard_workspace() {
  local path="$1" parent branch
  # Same ownership guard as exit — a stale/foreign path must never get its branch deleted.
  assert_owned "$path"
  # The branch to delete is the one `enter` RECORDED in the provenance marker — NOT the
  # worktree's current HEAD. A post-enter `git switch` would otherwise make HEAD resolve to an
  # unrelated branch, so discard would force-delete THAT and orphan the ephemeral one (Codex P2,
  # PR #114). assert_owned already proved the marker exists; read the enter-written identity.
  parent=$(dirname "$path")
  branch=$(marker_field "$parent" branch) \
    || fail "provenance marker in '$parent' records no enter-created branch — refusing to guess which ref to delete (a pre-marker workspace?)"
  [ -n "$branch" ] || fail "empty recorded branch in '$parent' — refusing to delete an unnamed ref"
  # DISCARD = exit's teardown + delete the ephemeral branch. The gate FAILed, so the whole
  # committed change is thrown away. Remove the worktree first (so the branch is no longer
  # checked out anywhere), then force-delete the recorded branch.
  if ! git worktree remove --force "$path" >/dev/null 2>&1; then
    fail "git worktree remove failed for '$path' (not a registered worktree?)"
  fi
  rm -f "$parent/.creance-ws-owner" 2>/dev/null || true   # drop the marker so the parent rmdir's cleanly
  rmdir "$parent" 2>/dev/null || true
  git worktree prune >/dev/null 2>&1 || true
  # -D (force): the ephemeral branch is unmerged by definition (the gate FAILed). git refuses
  # to delete a branch still checked out in a live worktree, so this can never touch the base
  # branch checked out in the main tree — and `$branch` is the marker-recorded identity enter
  # created, not an arbitrary current HEAD. The base branch is never named or touched here.
  if ! git branch -D "$branch" >/dev/null 2>&1; then
    fail "removed the workspace dir but could not delete its branch '$branch' — delete it manually"
  fi
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
    session=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --base) [ "$#" -ge 2 ] || usage; base="$2"; shift 2 ;;
        --session) [ "$#" -ge 2 ] || usage; session="$2"; shift 2 ;;
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
    # deleted (Codex P2, PR #114). It also RECORDS the ephemeral branch (`branch=<name>`) so discard
    # deletes the branch enter created, not the worktree's current HEAD (a post-enter `git switch`
    # cannot misdirect the delete — Codex P2, PR #114). Any failure path below reaps it via
    # `rm -rf "$parent"`, so the recorded branch can never outlive a failed `worktree add`.
    # `session=` (T906) is written ONLY when the caller supplied one, and is what makes this
    # workspace reapable by `sweep` after a crash. Omitted -> the marker records no owner, and
    # sweep leaves the workspace alone forever rather than guessing its owner is dead; every
    # marker written before T906 is therefore still safe by construction.
    {
      printf '%s\nbranch=%s\n' \
        'isolated-workspace ephemeral worktree parent — safe to remove via exit/discard' "$branch"
      [ -z "$session" ] || printf 'session=%s\n' "$session"
    } > "$parent/.creance-ws-owner" \
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
    discard_workspace "$path"
    ;;
  sweep)
    # CRASH RECOVERY (T906). Reap ONLY the workspaces a run that has already ended left behind.
    # --session is REQUIRED and must be the LIVE session's id: the caller is the loop, which
    # holds its run lock for the whole run, so exactly one live id exists at a time (the header's
    # "WHY sweep KEYS ON A SESSION TOKEN" note). Nothing is inferred — no default, no env read.
    live=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --session) [ "$#" -ge 2 ] || usage; live="$2"; shift 2 ;;
        *) usage ;;
      esac
    done
    [ -n "$live" ] || usage
    git rev-parse --git-dir >/dev/null 2>&1 \
      || fail "not inside a git repository — cannot sweep isolated workspaces"
    # Snapshot the registrations BEFORE reaping: each discard_workspace runs `git worktree prune`,
    # so iterating the live output while mutating it would skip entries.
    registered=$(git worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p')
    reaped=0
    stuck=0
    while IFS= read -r path; do
      [ -n "$path" ] || continue
      parent=$(dirname "$path")
      # The SAME three-part gate discard enforces, evaluated before anything destructive:
      #   1. the cheap name filter,
      #   2. the load-bearing provenance MARKER (a marker-less/foreign worktree is never ours),
      #   3. a RECORDED session that is not the live one.
      # Any miss leaves the worktree registered and on disk, untouched.
      case "$parent" in */creance-ws-*) : ;; *) continue ;; esac
      [ -f "$parent/.creance-ws-owner" ] || continue
      recorded=$(marker_field "$parent" session) || continue  # no session line -> owner unprovable
      [ -n "$recorded" ] || continue
      [ "$recorded" != "$live" ] || continue                  # the live session's own workspace
      # Read the recorded branch BEFORE reaping (the reap deletes the marker), so the report names
      # WHICH workspace went — an operator reading a run log needs the identity, not just a count.
      recorded_branch=$(marker_field "$parent" branch) || recorded_branch="<unrecorded>"
      # Subshell: discard_workspace `fail`s (exits) on any error path, and one wedged orphan must
      # not abort the sweep of the rest. The failure is already on stderr; count it and continue.
      if ( discard_workspace "$path" ); then
        reaped=$((reaped + 1))
        printf 'isolated-workspace: swept orphaned workspace %s (branch %s, session %s)\n' \
          "$path" "$recorded_branch" "$recorded"
      else
        stuck=$((stuck + 1))
      fi
    done <<EOF
$registered
EOF
    printf 'isolated-workspace: sweep complete — %d reaped, %d could not be reaped (live session %s)\n' \
      "$reaped" "$stuck" "$live"
    [ "$stuck" -eq 0 ] || exit 1
    ;;
  *)
    usage
    ;;
esac
exit 0
