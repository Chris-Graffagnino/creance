#!/usr/bin/env bash
# Regression tests for gate-diff.sh — the review-mode §7 gate HEAD-stability-verified diff
# helper (T639, #240). The script reads real git state, so each case runs the REAL script inside
# a throwaway git repo (the restore-task-branch.test.sh idiom) and asserts stdout's final marker
# line, the diff content, and the exit code.
#
# The done-when criteria (#240) drive the cases:
#   DW3 (red→green race) — the LOAD-BEARING pair. On the task branch the helper emits the task
#        branch's real diff + the completion marker (green); after a CONCURRENT session switches
#        the shared checkout to another branch the helper emits the mismatch marker and NO diff
#        (green). The RED it turns green is documented in the SAME tree: the OLD bare
#        `git diff main..HEAD && echo <completion-marker>` grades the CONCURRENT branch's diff
#        terminated by the completion marker — a wrong-diff vacuous pass. So the harness proves the
#        race really mis-grades pre-fix (not a tautology) and the helper refuses it post-fix.
#   DW2 (HEAD-stability at each re-dispatch, fails loud) — the mismatch is caught with a distinct
#        marker + a non-zero exit; a legitimate fix-round commit (HEAD advances WITH the branch tip)
#        stays stable, so the check does not false-positive on the gate's own fixes.
#   DW4 (scoped, non-regressing) — the stable control grades the real diff; an empty diff still
#        emits only the completion marker (gate-loop.js's classifier fails THAT closed, not the hook).
# Plus the fail-LOUD aborts (unreadable git / missing refs / a `git diff` that dies mid-patch),
# usage guards, and the P2 "machinery proves it is live" wiring: the markers agree with gate-loop.js,
# gate-loop.js invokes the hook, and CI runs this test. Bash + git only, <1s; wired into `verify`.
# Run: bash .claude/hooks/gate-diff.test.sh
set -u

HOOKS="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HOOKS/gate-diff.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
pass=0
fail=0

DIFF_COMPLETE='-----GATE-DIFF-COMPLETE-----'
HEAD_MISMATCH='-----GATE-HEAD-MISMATCH-----'

ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); printf 'FAIL %s\n' "$1" >&2; }

# `-- "$2"` is required: every marker starts with `-----`, which grep would otherwise parse as options.
last_line() { printf '%s\n' "$1" | tail -n1; }
has()    { printf '%s\n' "$1" | grep -qF -- "$2"; }

# run_hook <dir> <args...> — run the helper with <dir> as CWD (its bare `git` resolves against the
# fixture repo). Captures stdout into OUT and the exit code into RC.
OUT=""; RC=0
run_hook() {
  local dir="$1"; shift
  OUT="$( cd "$dir" && bash "$SCRIPT" "$@" 2>/dev/null )" && RC=0 || RC=$?
}

# new_repo <dir> — a repo on main with f="BASE", a task branch feat/x one commit ahead (f="WORK",
# so the diff is non-empty), and a SECOND branch chore/other one commit ahead of main (f="OTHER")
# standing in for a concurrent session's work. Left checked out ON feat/x — the gate's start state.
new_repo() {
  local d="$1"
  mkdir -p "$d"
  git init -q -b main "$d"
  git -C "$d" config user.email t@example.com
  git -C "$d" config user.name test
  printf 'BASE\n' > "$d/f"
  git -C "$d" add f
  git -C "$d" commit -q -m "chore: base content on main"
  git -C "$d" switch -q -c feat/x
  printf 'WORK\n' > "$d/f"
  git -C "$d" add f
  git -C "$d" commit -q -m "feat: [T999] the maker's work on the task branch"
  git -C "$d" switch -q -c chore/other main
  printf 'OTHER\n' > "$d/f"
  git -C "$d" add f
  git -C "$d" commit -q -m "chore: a concurrent session's unrelated work"
  git -C "$d" switch -q feat/x
}

# ── DW4 / stable control: on the task branch the helper emits the REAL diff + completion marker,
#    exit 0, and NEVER the mismatch marker. (A stable HEAD grades the true diff — no false refusal.)
D="$TMP/main"; new_repo "$D"
run_hook "$D" feat/x
[ "$RC" -eq 0 ] && ok || bad "stable: exit 0 on the task branch (got $RC)"
[ "$(last_line "$OUT")" = "$DIFF_COMPLETE" ] && ok || bad "stable: stdout ends with the completion marker"
has "$OUT" 'WORK' && ok || bad "stable: emits the task branch's real diff (WORK)"
has "$OUT" "$HEAD_MISMATCH" && bad "stable: must NOT emit the mismatch marker on a stable HEAD" || ok

# ── DW3 (load-bearing, GREEN half): a concurrent session switches the shared checkout to
#    chore/other between dispatch and fan-out. The helper detects the drift — mismatch marker, exit
#    3 — and emits NEITHER the completion marker NOR the concurrent branch's diff (OTHER).
git -C "$D" switch -q chore/other
run_hook "$D" feat/x
[ "$RC" -eq 3 ] && ok || bad "drift: exit 3 on a concurrent branch switch (got $RC)"
[ "$(last_line "$OUT")" = "$HEAD_MISMATCH" ] && ok || bad "drift: stdout ends with the mismatch marker"
has "$OUT" "$DIFF_COMPLETE" && bad "drift: must NOT emit the completion marker (no vacuous pass)" || ok
has "$OUT" 'OTHER' && bad "drift: must NOT emit the concurrent branch's diff (OTHER)" || ok

# ── DW3 (load-bearing, RED half — documents the pre-fix bug in the SAME drifted tree): the OLD
#    behavior the helper replaces was a bare `git diff main..HEAD && echo <completion-marker>`. On
#    the drifted tree ($D is on chore/other) it grades the CONCURRENT branch's diff (OTHER) AND
#    terminates it with the completion marker — a wrong-diff vacuous pass. This is the exact failure
#    the helper turns into a refusal above, proving the race is real, not a harness tautology.
OLD_OUT="$( cd "$D" && git diff main..HEAD && printf '%s\n' "$DIFF_COMPLETE" )"
has "$OLD_OUT" 'OTHER' && ok || bad "red-doc: the old bare command graded the WRONG branch's diff (OTHER)"
[ "$(last_line "$OLD_OUT")" = "$DIFF_COMPLETE" ] && ok \
  || bad "red-doc: the old bare command emitted the completion marker on a wrong diff (vacuous pass)"

# ── DW2: a legitimate fix-round commit advances HEAD AND the branch tip together, so the helper
#    stays stable (no false refusal) and emits the UPDATED diff — the check fires at each
#    re-dispatch without penalizing the gate's own fixes.
git -C "$D" switch -q feat/x
printf 'FIX\n' >> "$D/f"
git -C "$D" add f
git -C "$D" commit -q -m "fix: [T999] address gate findings (round 1)"
run_hook "$D" feat/x
[ "$RC" -eq 0 ] && ok || bad "post-fix: still stable after a fix-round commit (exit 0, got $RC)"
[ "$(last_line "$OUT")" = "$DIFF_COMPLETE" ] && ok || bad "post-fix: completion marker after a fix commit"
has "$OUT" 'FIX' && ok || bad "post-fix: emits the updated diff including the fix"

# ── Fail loud (the diff command dies mid-patch): the completion marker must crown ONLY a diff that
#    `git diff` produced cleanly. A GIT_EXTERNAL_DIFF driver that emits a partial patch then exits
#    non-zero makes `git diff` write output AND exit non-zero — a truncated patch. The helper must
#    refuse (mismatch marker, exit 1) and NEVER print the completion marker over that partial patch;
#    otherwise reviewers grade an incomplete diff as verified. (Codex P2 + craft finding, PR #245.)
#    RED on the pre-fix hook: the bare `git diff` continued to the unconditional completion marker,
#    so RC=0 and the last line was the completion marker over the partial patch.
DIEDIFF="$TMP/diediff.sh"
printf '#!/usr/bin/env bash\nprintf "diff --git a/f b/f\\n@@ partial hunk @@\\n"\nexit 1\n' > "$DIEDIFF"
chmod +x "$DIEDIFF"
OUT="$( cd "$D" && GIT_EXTERNAL_DIFF="$DIEDIFF" bash "$SCRIPT" feat/x 2>/dev/null )" && RC=0 || RC=$?
[ "$RC" -eq 1 ] && ok || bad "diff-fail: a diff command that dies mid-patch exits 1 (got $RC)"
has "$OUT" '@@ partial hunk @@' && ok || bad "diff-fail: the partial patch reached stdout (a real mid-patch failure, not a pre-output abort)"
[ "$(last_line "$OUT")" = "$HEAD_MISMATCH" ] && ok || bad "diff-fail: stdout ends with the mismatch marker when git diff fails"
has "$OUT" "$DIFF_COMPLETE" && bad "diff-fail: must NOT crown a truncated patch with the completion marker" || ok

# ── DW4: a stable branch with NO commits ahead of base emits only the completion marker (empty
#    diff). The helper does not itself block an empty diff — gate-loop.js's classifier fails THAT
#    closed as a vacuous grade; here we only prove the helper emits a clean empty-diff + marker.
E="$TMP/empty"; new_repo "$E"
git -C "$E" switch -q -c empty main
run_hook "$E" empty
[ "$RC" -eq 0 ] && ok || bad "empty: stable branch with no commits ahead exits 0 (got $RC)"
[ "$(last_line "$OUT")" = "$DIFF_COMPLETE" ] && ok || bad "empty: completion marker even on an empty diff"
body="$(printf '%s\n' "$OUT" | sed '$d')"
[ -z "$(printf '%s' "$body" | tr -d '[:space:]')" ] && ok || bad "empty: no diff body precedes the marker"

# ── Fail loud (unreadable git): outside any repo → abort, exit 1, mismatch marker (never a silent
#    exit 0 that would hand the gate an empty/absent diff to grade).
NOGIT="$TMP/nogit"; mkdir -p "$NOGIT"
run_hook "$NOGIT" feat/x
[ "$RC" -eq 1 ] && ok || bad "abort: unreadable git state exits 1 (got $RC)"
[ "$(last_line "$OUT")" = "$HEAD_MISMATCH" ] && ok || bad "abort: mismatch marker on unreadable git"

# ── Fail loud (missing task branch / base ref): exit 1 rather than grading a wrong/absent diff.
run_hook "$D" no/such-branch
[ "$RC" -eq 1 ] && ok || bad "abort: a nonexistent task branch exits 1 (got $RC)"
run_hook "$D" feat/x no-such-base
[ "$RC" -eq 1 ] && ok || bad "abort: an unresolvable base ref exits 1 (got $RC)"

# ── Usage guards: no argument, an empty argument, and too many arguments each exit 2.
run_hook "$D"; [ "$RC" -eq 2 ] && ok || bad "usage: no argument exits 2 (got $RC)"
run_hook "$D" ""; [ "$RC" -eq 2 ] && ok || bad "usage: an empty argument exits 2 (got $RC)"
run_hook "$D" a b c; [ "$RC" -eq 2 ] && ok || bad "usage: too many arguments exit 2 (got $RC)"

# ── Self-consistency: the helper carries the two marker literals the gate classifier keys on.
grep -qF -- "$DIFF_COMPLETE" "$SCRIPT" && ok || bad "self: gate-diff.sh carries the completion marker literal"
grep -qF -- "$HEAD_MISMATCH" "$SCRIPT" && ok || bad "self: gate-diff.sh carries the mismatch marker literal"

# ── Codex P2 (PR #245) — the diff is pinned to the VERIFIED $branch_sha, never live HEAD, so a
#    concurrent checkout switch in the TOCTOU window AFTER the stability check cannot swap the graded
#    patch. That race is not deterministically reproducible, so pin the property at the source: the
#    emission must diff the captured SHA, and must NOT re-resolve live HEAD.
grep -qE 'git diff "\$base\.\.\$branch_sha"' "$SCRIPT" && ok || bad "pin: the emitted diff targets the verified \$branch_sha"
grep -qE 'git diff "\$base\.\.HEAD"' "$SCRIPT" && bad "pin: must NOT emit the diff against live HEAD (TOCTOU race, #240)" || ok

# ── Wiring (P2 "machinery proves it is live"): the markers AGREE with gate-loop.js, gate-loop.js
#    INVOKES the hook (else it is dead machinery), and CI RUNS this test (else its own proof is dead).
GLJS="$HOOKS/../workflows/gate-loop.js"
grep -qF -- "$DIFF_COMPLETE" "$GLJS" && ok || bad "wiring: gate-loop.js shares the completion marker literal"
grep -qF -- "$HEAD_MISMATCH" "$GLJS" && ok || bad "wiring: gate-loop.js shares the mismatch marker literal"
grep -qE 'gate-diff\.sh' "$GLJS" && ok || bad "wiring: gate-loop.js invokes gate-diff.sh"
CI="$HOOKS/../../.github/workflows/ci.yml"
grep -qE 'gate-diff\.test\.sh' "$CI" && ok || bad "wiring: ci.yml verify runs gate-diff.test.sh"

printf 'gate-diff.test.sh: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
