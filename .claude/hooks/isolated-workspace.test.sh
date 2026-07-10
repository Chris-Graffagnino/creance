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
#                   untouched (the no-un-gated-path-to-main slice; the full adversarial
#                   falsification proof is isolation-falsification.test.sh, T613) — done-when 3;
#   * boundary:     exit removes the DIRECTORY but leaves the branch — `exit` is the PROMOTE
#                   path's teardown (the dispatcher pushed/PR'd first), so the branch must
#                   survive; throwing it away on a FAIL is the separate `discard` verb;
#   * discard:      discard (the §7 gate's FAIL decision, T612) removes the workspace dir AND
#                   deletes its ephemeral branch, leaving the BASE ref untouched — the
#                   discard-on-FAIL path;
#   * branch id:    discard deletes the branch enter RECORDED in the marker, not the worktree's
#                   CURRENT HEAD — a post-enter `git switch` cannot misdirect the branch -D onto
#                   an unrelated branch and orphan the ephemeral one (Codex P2, PR #114);
#   * fail-safe:    enter outside a repo / on an existing branch FAILS LOUD with NO path on
#                   stdout, so the caller aborts rather than reading a phantom workspace and
#                   never falls back to the base branch — done-when 5;
#   * ownership:    exit AND discard REFUSE a registered worktree that this lifecycle did not
#                   create (its parent is not a creance-ws-* temp dir) and leave it intact, so a
#                   stale or foreign path can never force-remove — or delete the branch of —
#                   unrelated local work (Codex P2, #111; discard extends the guard, T612);
#   * provenance:   exit AND discard also refuse a registered worktree whose parent only LOOKS
#                   like ours — it matches creance-ws-* but lacks the marker enter writes (a manual
#                   `git worktree add`, a copied/stale dir, another run's workspace) — so the name
#                   pattern alone is never mistaken for ownership before a forced remove / branch
#                   delete (Codex P2, #114);
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
NEUTRAL="$REPO/.claude/workflow/next-task/01-preconditions.md"
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
# Boundary: exit removes the DIRECTORY but leaves the branch — `exit` is the promote path's
# teardown (the dispatcher pushed/PR'd first), so the branch must survive. Discarding it on a
# FAIL is the separate `discard` verb, exercised next.
if git -C "$R" show-ref --verify --quiet refs/heads/ws-1; then ok; else bad "boundary: exit deleted the branch (that is discard's job, not exit's)"; fi

# ── discard (T612): the §7 gate's FAIL decision — tear the dir down AND delete the branch ──
# enter -> commit work -> discard leaves the BASE ref untouched, the workspace dir gone, the
# worktree de-registered, AND the ephemeral branch deleted (the whole change is thrown away).
RD="$TMP/repo-discard"; new_repo "$RD"
dbase_before=$(git -C "$RD" rev-parse main)
wsd=$( cd "$RD" && bash "$SCRIPT" enter ws-d --base main 2>/dev/null )
echo discardme > "$wsd/scratch"
git -C "$wsd" add scratch
git -C "$wsd" commit -q -m "work that the gate will FAIL"
( cd "$RD" && bash "$SCRIPT" discard "$wsd" ) >/dev/null 2>&1; drc=$?
if [ "$drc" = "0" ]; then ok; else bad "discard: returned rc=$drc want 0"; fi
if [ ! -d "$wsd" ]; then ok; else bad "discard: workspace directory still present"; fi
if git -C "$RD" worktree list 2>/dev/null | grep -q '\[ws-d\]'; then bad "discard: worktree still registered"; else ok; fi
# The ephemeral branch is GONE — this is what distinguishes discard from exit.
if git -C "$RD" show-ref --verify --quiet refs/heads/ws-d; then bad "discard: ephemeral branch ws-d survived (discard must delete it)"; else ok; fi
# The BASE ref is byte-identical — discard never writes the base branch (P4).
if [ "$(git -C "$RD" rev-parse main)" = "$dbase_before" ]; then ok; else bad "discard: base ref moved"; fi

# ── Branch identity (T612 · Codex P2, PR #114): discard deletes the branch `enter` RECORDED in the
# provenance marker, NEVER the worktree's CURRENT HEAD. If the workspace is switched to another
# branch after enter (`git switch`), discard must still delete the enter-created ephemeral branch
# and leave the switched-to, unrelated branch intact — resolving HEAD instead would force-delete
# the unrelated branch and orphan the ephemeral one. Falsifies the pre-fix HEAD-resolving discard. ──
RBS="$TMP/repo-branch-switch"; new_repo "$RBS"
bsbase_before=$(git -C "$RBS" rev-parse main)
wsbs=$( cd "$RBS" && bash "$SCRIPT" enter ws-orig --base main 2>/dev/null )
git -C "$wsbs" branch other-branch                 # an unrelated branch the lifecycle did NOT create
git -C "$wsbs" switch -q other-branch              # move the workspace HEAD off the ephemeral branch
( cd "$RBS" && bash "$SCRIPT" discard "$wsbs" ) >/dev/null 2>&1; bsrc=$?
if [ "$bsrc" = "0" ]; then ok; else bad "branch-switch discard: returned rc=$bsrc want 0"; fi
# The enter-created ephemeral branch is GONE — discard deleted the recorded identity, not HEAD.
if git -C "$RBS" show-ref --verify --quiet refs/heads/ws-orig; then bad "branch-switch: enter-created branch ws-orig survived (orphaned — discard followed HEAD, not the marker)"; else ok; fi
# The switched-to, unrelated branch SURVIVES — discard never deletes a branch it did not create.
if git -C "$RBS" show-ref --verify --quiet refs/heads/other-branch; then ok; else bad "branch-switch: discard force-deleted the unrelated switched-to branch other-branch"; fi
# Base ref untouched throughout (P4).
if [ "$(git -C "$RBS" rev-parse main)" = "$bsbase_before" ]; then ok; else bad "branch-switch: base ref moved"; fi

# Ownership (T612): discard REFUSES a registered worktree this lifecycle did not create (its
# parent is not creance-ws-*) — it must neither force-remove the dir NOR delete the branch of
# unrelated, possibly dirty, local work. Mirrors exit's ownership case for the new verb.
RDO="$TMP/repo-discard-own"; new_repo "$RDO"
dforeign="$TMP/discard-foreign-wt"                 # NOT under a creance-ws-* parent
git -C "$RDO" worktree add -q -b discard-foreign "$dforeign" >/dev/null 2>&1
echo dirty > "$dforeign/uncommitted"               # unrelated work that MUST survive
out=$( cd "$RDO" && bash "$SCRIPT" discard "$dforeign" 2>/dev/null ); got=$?
if [ "$got" = "1" ]; then ok; else bad "discard ownership: non-owned worktree must fail loud (got rc=$got)"; fi
if [ -d "$dforeign" ]; then ok; else bad "discard ownership: force-removed a non-owned worktree directory"; fi
if git -C "$RDO" show-ref --verify --quiet refs/heads/discard-foreign; then ok; else bad "discard ownership: deleted a non-owned worktree's branch (unrelated work lost)"; fi

# ── Provenance, not just the name (T612 · Codex P2, PR #114): the foreign-parent ownership tests
# above refuse paths whose parent FAILS the creance-ws-* pattern. These PASS the pattern but carry
# NO provenance marker — a registered worktree under a look-alike creance-ws-* dir that this
# lifecycle's enter did not create (a manual `git worktree add`, a copied/stale dir, another run's
# workspace). The name alone is not ownership, so exit AND discard must REFUSE before any forced
# remove or branch -D. Two INDEPENDENT look-alikes (one per verb) so each verb's falsification is
# order-independent — in particular discard's must prove the branch is NOT force-deleted, the worst
# consequence Codex named. Both falsify the pre-marker guard, which accepted them on the name alone. ──
RP="$TMP/repo-prov"; new_repo "$RP"
# (a) exit refuses its own markerless look-alike and leaves the directory intact.
exit_la="$TMPDIR/creance-ws-LOOKALIKE-X/wt"        # matches */creance-ws-* but enter did NOT make it
mkdir -p "$(dirname "$exit_la")"
git -C "$RP" worktree add -q -b lookalike-exit "$exit_la" >/dev/null 2>&1
echo dirty > "$exit_la/uncommitted"                # unrelated work that MUST survive the refusal
( cd "$RP" && bash "$SCRIPT" exit "$exit_la" ) >/dev/null 2>&1; got=$?
if [ "$got" = "1" ]; then ok; else bad "provenance: exit on a markerless creance-ws-* look-alike must fail loud (got rc=$got)"; fi
if [ -d "$exit_la" ]; then ok; else bad "provenance: exit force-removed a markerless look-alike worktree"; fi
# (b) discard refuses its OWN markerless look-alike — the dir AND its (unmerged) branch MUST
# survive; the pre-marker guard would have removed the dir and then `git branch -D`'d the branch.
disc_la="$TMPDIR/creance-ws-LOOKALIKE-Y/wt"
mkdir -p "$(dirname "$disc_la")"
git -C "$RP" worktree add -q -b lookalike-discard "$disc_la" >/dev/null 2>&1
echo dirty > "$disc_la/uncommitted"
( cd "$RP" && bash "$SCRIPT" discard "$disc_la" ) >/dev/null 2>&1; got=$?
if [ "$got" = "1" ]; then ok; else bad "provenance: discard on a markerless look-alike must fail loud (got rc=$got)"; fi
if [ -d "$disc_la" ]; then ok; else bad "provenance: discard force-removed a markerless look-alike worktree"; fi
if git -C "$RP" show-ref --verify --quiet refs/heads/lookalike-discard; then ok; else bad "provenance: discard deleted a markerless look-alike's branch (unmerged work lost)"; fi

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
# (d) exit on a REGISTERED worktree this lifecycle did NOT create (its parent is not a
# creance-ws-* temp dir) must REFUSE before the forced remove — `git worktree remove --force`
# would otherwise discard unrelated, possibly DIRTY, local work (Codex P2, PR #111). This is
# the ownership case (c)'s unregistered path does not cover.
R3="$TMP/repo3"; new_repo "$R3"
foreign="$TMP/foreign-wt"                 # NOT under a creance-ws-* parent
git -C "$R3" worktree add -q -b foreign-branch "$foreign" >/dev/null 2>&1
echo dirty > "$foreign/uncommitted"       # unrelated, uncommitted work that MUST survive
out=$( cd "$R3" && bash "$SCRIPT" exit "$foreign" 2>/dev/null ); got=$?
if [ "$got" = "1" ]; then ok; else bad "ownership: exit on a non-owned registered worktree must fail loud (got rc=$got)"; fi
if [ -d "$foreign" ]; then ok; else bad "ownership: exit force-removed a non-owned worktree directory (unrelated work lost)"; fi
if git -C "$R3" worktree list 2>/dev/null | grep -q '\[foreign-branch\]'; then ok; else bad "ownership: exit de-registered a non-owned worktree"; fi

# ── Usage guards (exit 2, before any git work) ──
rc "no args -> usage"              2
rc "enter w/o branch -> usage"     2 enter
rc "enter --base w/o value"        2 enter b --base
rc "exit w/o path -> usage"        2 exit
rc "discard w/o path -> usage"     2 discard
rc "discard extra arg -> usage"    2 discard p extra
rc "unknown subcommand -> usage"   2 frobnicate

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
