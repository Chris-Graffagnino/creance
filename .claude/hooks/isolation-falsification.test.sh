#!/usr/bin/env bash
# isolation-falsification.test.sh — the FULL falsification proof that an un-gated change
# cannot reach the base branch through the isolated-workspace lifecycle (T613 / epic #81
# part d; model in .claude/workflow/README.md → "[isolated workspace]", rationale in
# DESIGN-NOTES §14).
#
# isolated-workspace.test.sh proves the lifecycle PRIMITIVES behave, including a happy-path
# SLICE (enter→work→exit leaves the base ref untouched) and deliberately defers "the FULL
# falsification proof" here. This file is that proof: it states the single security claim —
# AN UN-GATED CHANGE CANNOT REACH THE BASE BRANCH THROUGH THE LIFECYCLE — and ADVERSARIALLY
# tries to make it false, asserting each attempt fails. It guards the wall (constitution P4:
# "the isolation mechanism never writes the base branch directly"; the discard path "deletes
# only the ephemeral creance-ws-* branch, never the base branch").
#
# Where the slice asks "does each verb behave?", this asks "can ANY path an autonomous run
# could take land un-gated work on the base branch? Prove no.":
#   * DW1 promote-teardown isolation: enter→commit→exit leaves the base ref byte-identical AND
#     the committed (un-gated) change is NOT reachable from base — the lifecycle never merges
#     un-gated work into base; promotion is the dispatcher's SEPARATE §7-gated PR (T612 §8).
#   * DW2 discard destroys the work: enter→commit→discard (the gate-FAIL path) leaves the base
#     ref byte-identical, the ephemeral branch gone, AND the commit unreachable from EVERY ref —
#     gate-FAILed work is thrown away whole, not parked somewhere base could later reach.
#   * DW3 forged-marker base safety: a FORGED provenance marker that records the BASE branch as
#     the ephemeral branch cannot make discard delete/clobber base — base survives byte-identical
#     (git refuses to delete a checked-out branch; the script never names the base ref). Encodes
#     as a standing test the property T612's review verified by hand (Codex P2, PR #114).
#   * DW4 negative space — the wall has no door: the lifecycle dispatches ONLY enter/exit/discard
#     and the script source carries no base-ref-writing operation (no merge, no push, no
#     unconditional/base-literal branch delete; the only `branch -D` operand is the
#     marker-recorded ephemeral branch). A source backstop behind the behavioral proofs above.
#   * wiring (P2): the `verify` job ACTIVELY runs this test (an active run: step, not a comment),
#     and the live counterpart — the P-IW conformance probe that the isolation tier FIRES on a
#     real driver — is documented in the neutral registry + the adapter instantiation.
# Bash + git only, <1s. Run: bash .claude/hooks/isolation-falsification.test.sh
set -u

HOOKS="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HOOKS/isolated-workspace.sh"
REPO="$(cd "$HOOKS/../.." && pwd)"
CI="$REPO/.github/workflows/ci.yml"
NEUTRAL_PROBES="$REPO/.claude/workflow/conformance-probes.md"
ADAPTER_PROBES="$REPO/.claude/adapters/claude-code-probes.md"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
# Scope the script's ephemeral worktree parents (creance-ws-*) into our TMP so the trap reaps
# them; the script honors ${TMPDIR:-/tmp}.
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

# ─────────────────────────────────────────────────────────────────────────────────────────
# DW1 — promote-teardown isolation. enter→commit an un-gated change→exit. The base ref must be
# byte-identical throughout, and after exit the committed change must NOT be reachable from
# base: `exit` is the PROMOTE path's teardown, and promotion is the dispatcher's separate
# §7-gated PR — the lifecycle itself never folds un-gated work into base.
# ─────────────────────────────────────────────────────────────────────────────────────────
R1="$TMP/r1"; new_repo "$R1"
base1=$(git -C "$R1" rev-parse main)
ws1=$( cd "$R1" && bash "$SCRIPT" enter ws-promote --base main 2>/dev/null )
echo ungated > "$ws1/ungated-change"
git -C "$ws1" add ungated-change
git -C "$ws1" commit -q -m "un-gated change committed inside the isolated workspace"
wscommit1=$(git -C "$ws1" rev-parse HEAD)
# base must not move while we commit in the workspace.
if [ "$(git -C "$R1" rev-parse main)" = "$base1" ]; then ok; else bad "DW1: base ref moved while committing in the workspace"; fi
# the un-gated commit is real and distinct from base (sanity: the change exists to be contained).
if [ "$wscommit1" != "$base1" ]; then ok; else bad "DW1: workspace commit equals base — nothing was actually committed to contain"; fi
( cd "$R1" && bash "$SCRIPT" exit "$ws1" ) >/dev/null 2>&1
# after exit: base byte-identical AND the un-gated commit is NOT an ancestor of base.
if [ "$(git -C "$R1" rev-parse main)" = "$base1" ]; then ok; else bad "DW1: base ref moved across exit"; fi
if git -C "$R1" merge-base --is-ancestor "$wscommit1" main 2>/dev/null; then
  bad "DW1: the un-gated workspace commit reached base through exit (promotion must be a separate gated PR, not a lifecycle write)"
else ok; fi

# ─────────────────────────────────────────────────────────────────────────────────────────
# DW2 — discard destroys the work. enter→commit→discard (the §7 gate's FAIL decision). Base
# byte-identical, the ephemeral branch gone, AND the commit unreachable from EVERY ref — a
# gate-FAILed change is thrown away whole, never parked somewhere base could later reach.
# ─────────────────────────────────────────────────────────────────────────────────────────
R2="$TMP/r2"; new_repo "$R2"
base2=$(git -C "$R2" rev-parse main)
ws2=$( cd "$R2" && bash "$SCRIPT" enter ws-fail --base main 2>/dev/null )
echo failme > "$ws2/will-be-discarded"
git -C "$ws2" add will-be-discarded
git -C "$ws2" commit -q -m "un-gated change the gate will FAIL"
wscommit2=$(git -C "$ws2" rev-parse HEAD)
( cd "$R2" && bash "$SCRIPT" discard "$ws2" ) >/dev/null 2>&1
if [ "$(git -C "$R2" rev-parse main)" = "$base2" ]; then ok; else bad "DW2: base ref moved across discard"; fi
if git -C "$R2" show-ref --verify --quiet refs/heads/ws-fail; then bad "DW2: ephemeral branch ws-fail survived discard"; else ok; fi
# unreachable from every ref: the deleted branch was its only ref, so no ref reaches it now.
if git -C "$R2" rev-list --all 2>/dev/null | grep -qF "$wscommit2"; then
  bad "DW2: the discarded commit is still reachable from a ref (work was not thrown away)"
else ok; fi

# ─────────────────────────────────────────────────────────────────────────────────────────
# DW3 — forged-marker base safety. The marker is the ownership proof; forge one that PASSES
# (a creance-ws-* parent + a .creance-ws-owner file) but RECORDS the base branch as the
# ephemeral one. discard must still be unable to delete/clobber base: git refuses to delete a
# branch checked out in the main tree, and the script names no base ref. Base survives
# byte-identical even though ownership was forged — the strongest breach attempt on the wall.
# ─────────────────────────────────────────────────────────────────────────────────────────
R3="$TMP/r3"; new_repo "$R3"
base3=$(git -C "$R3" rev-parse main)
forged_parent="$TMPDIR/creance-ws-FORGED"           # passes the */creance-ws-* name filter
forged_wt="$forged_parent/wt"
mkdir -p "$forged_parent"
# A real registered worktree (on its OWN branch — git refuses a second checkout of main), so
# discard's `git worktree remove` step succeeds and execution REACHES the branch-delete.
git -C "$R3" worktree add -q -b decoy-branch "$forged_wt" >/dev/null 2>&1
# Forge the provenance marker: ownership note + branch=main (the base, not decoy-branch).
printf '%s\nbranch=%s\n' 'forged owner marker' 'main' > "$forged_parent/.creance-ws-owner"
( cd "$R3" && bash "$SCRIPT" discard "$forged_wt" ) >/dev/null 2>&1; drc3=$?
# discard must FAIL LOUD at the base-delete (git refuses to delete the checked-out base).
if [ "$drc3" != "0" ]; then ok; else bad "DW3: discard returned 0 while told to delete the base branch — it must fail loud"; fi
# THE safety property: base survives, byte-identical, despite the forged marker.
if git -C "$R3" show-ref --verify --quiet refs/heads/main && [ "$(git -C "$R3" rev-parse main)" = "$base3" ]; then ok; else bad "DW3: a forged branch=main marker deleted/clobbered the base branch"; fi

# ─────────────────────────────────────────────────────────────────────────────────────────
# DW4 — negative space: the wall has no door. A source backstop behind the behavioral proofs:
# the lifecycle dispatches ONLY enter/exit/discard, and its source carries no base-ref-writing
# operation. Greps over the script text — brittle by nature, so it BACKS the behavioral tests
# (DW1–DW3 are the real proof), catching an obvious future regression that adds a promotion door.
# ─────────────────────────────────────────────────────────────────────────────────────────
# (a) the only dispatched subcommands are enter/exit/discard (plus usage) — no promote/merge verb.
arms=$(grep -oE '^[[:space:]]*(enter|exit|discard|push|promote|merge|land)\)' "$SCRIPT" | tr -d ' ')
if [ "$(printf '%s\n' "$arms" | sort -u | tr '\n' ' ')" = "discard) enter) exit) " ]; then ok; else bad "DW4: lifecycle case arms are not exactly enter/exit/discard (a promotion verb may have been added): got [$arms]"; fi
# (b) no merge and no push anywhere in the lifecycle — promotion is the dispatcher's job, not this script's.
if grep -qE 'git[[:space:]]+merge' "$SCRIPT"; then bad "DW4: the lifecycle script contains a git merge (it must never fold work into a branch)"; else ok; fi
if grep -qE 'git[[:space:]]+push' "$SCRIPT"; then bad "DW4: the lifecycle script contains a git push (promotion is the dispatcher's gated PR, not the lifecycle's)"; else ok; fi
# (c) the ONLY branch deletion is parameterized by the marker-recorded branch ("$branch") —
# never a base-literal — and there is no update-ref/reset that could move a base ref.
dels=$(grep -oE 'git[[:space:]]+branch[[:space:]]+-[dD][[:space:]]+[^ ]+' "$SCRIPT")
if [ "$(printf '%s\n' "$dels" | tr -s ' ')" = 'git branch -D "$branch"' ]; then ok; else bad "DW4: a branch deletion targets something other than the marker-recorded \"\$branch\": [$dels]"; fi
if grep -qE 'git[[:space:]]+(update-ref|reset)' "$SCRIPT"; then bad "DW4: the lifecycle script contains update-ref/reset (could move the base ref)"; else ok; fi

# ─────────────────────────────────────────────────────────────────────────────────────────
# Wiring (P2): the required `verify` job must ACTIVELY run this test, else the falsification
# proof is itself silently dead. Bare-filename grep is too loose (a commented-out/moved copy
# would satisfy it — the #92 / PR #107 lesson), so scope to the verify job body and require an
# active `run: bash <path>` step, exactly as isolated-workspace.test.sh does.
# ─────────────────────────────────────────────────────────────────────────────────────────
verify_steps() { awk '/^  [A-Za-z]/ { inblk = ($0 ~ /^  verify:/) } inblk { print }' "$CI"; }
runs_in_verify() { verify_steps | grep -qE "^[[:space:]]*run:[[:space:]]+bash[[:space:]]+$1([[:space:]]|\$)"; }
if runs_in_verify '\.claude/hooks/isolation-falsification\.test\.sh'; then ok; else bad "verify must RUN isolation-falsification.test.sh (active run: step)"; fi

# The live counterpart (DW5/DW6): the P-IW conformance probe — that the isolation tier FIRES on
# a real driver — must exist in the neutral registry (its coverage map included) AND be
# instantiated in the adapter. The deterministic proof above and the live probe are
# complementary: a binding that reads correctly can still be dead on a real driver
# (conformance-probes.md). Neutrality of the P-IW text is enforced by probe-fingerprint-docs.test.sh.
if grep -qF 'P-IW' "$NEUTRAL_PROBES"; then ok; else bad "conformance-probes.md is missing the P-IW isolation-tier probe"; fi
if grep -qE '^### P-IW' "$NEUTRAL_PROBES"; then ok; else bad "conformance-probes.md has no '### P-IW' probe section"; fi
if grep -qF '| [isolated workspace] + [autonomy activation] | P-IW |' "$NEUTRAL_PROBES"; then ok; else bad "conformance-probes.md coverage map is missing the P-IW row"; fi
if grep -qE '^\| P-IW ' "$ADAPTER_PROBES"; then ok; else bad "claude-code-probes.md is missing the P-IW instantiation row"; fi

printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
