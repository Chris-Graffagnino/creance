#!/usr/bin/env bash
# Regression tests for announce-task-selection.sh — the runtime /next-task announce/confirm
# decision (issue #103, T614), the UX complement to reconcile-task-selection.sh (T608). The
# script reads `git log` + specs/*/tasks.md via the shared lib-tasks-drift.sh, so each case runs
# the REAL script inside a throwaway git repo (the reconcile-task-selection.test.sh idiom)
# seeded with a fixture tasks file plus fixture commits, then asserts the printed DECISION.
#
# The load-bearing case is the PAIRED harness: ONE repo whose ONE tasks file holds an open task
# (T910) AND a drifted task (T911, box `[ ]` but a [T911] commit landed). From that SAME setup:
#   * implicit T911 -> `confirm`   (done-when 2: implicit + contradicted -> pause)
#   * implicit T910 -> `proceed`   (done-when 5: implicit + consistent  -> NO false pause)
#   * explicit T911 -> `proceed`   (done-when 1: explicit never pauses, even on drift)
#   * explicit T910 -> `proceed`   (done-when 1)
# so the pause is provably (mode=implicit AND contradicted), not unconditional and not merely
# drift-triggered. Plus fail-open announce-only (done-when 4), usage guards, the share-not-
# duplicate assertion (sources lib-tasks-drift.sh, the P2 no-fork rule), and the CI-wiring
# assertion. Bash + git only, <1s; wired into the `verify` CI job (.github/workflows/ci.yml).
# Run: bash .claude/hooks/announce-task-selection.test.sh
set -u

HOOKS="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HOOKS/announce-task-selection.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
pass=0
fail=0

ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); printf 'FAIL %s\n' "$1" >&2; }

# run_decision <expected-stdout> <repo-dir> <name> [script-args...] — run with the repo as CWD
# (so the script's specs/*/tasks.md glob and `git log` resolve against the fixture) and assert
# BOTH the printed decision word AND exit 0 — the contract is "exit 0 (decision) / 2 (usage)"
# (SKILL binding), so a decision that printed the right word but exited non-zero must still FAIL.
run_decision() {
  local want="$1" dir="$2" name="$3"; shift 3
  local got rc=0
  got="$( cd "$dir" && bash "$SCRIPT" "$@" 2>/dev/null )" || rc=$?
  if [ "$got" = "$want" ] && [ "$rc" -eq 0 ]; then ok
  else bad "$name (want '$want' exit 0, got '$got' exit $rc)"; fi
}

# run_exit <expected-exit> <repo-dir> <name> [script-args...] — assert the exit code (usage).
run_exit() {
  local want="$1" dir="$2" name="$3"; shift 3
  local got=0
  ( cd "$dir" && bash "$SCRIPT" "$@" >/dev/null 2>&1 ) || got=$?
  if [ "$got" -eq "$want" ]; then ok; else bad "$name (want exit $want, got $got)"; fi
}

# new_repo <dir> — a throwaway repo with one task-id-free bootstrap commit so `git log` works;
# the caller writes the fixture tasks file (working tree) and adds task-bearing commits.
new_repo() {
  local d="$1"
  mkdir -p "$d"
  git init -q -b main "$d"
  git -C "$d" config user.email t@example.com
  git -C "$d" config user.name test
  git -C "$d" commit -q --allow-empty -m "chore: bootstrap (no task id)"
}

# ── The paired harness (done-when 1 + 2 + 5): one repo, one tasks file, two tasks. T910 is open
#    (no commit carries its id); T911 is drifted (box `[ ]` but a [T911] commit landed). The SAME
#    setup must confirm the implicit drifted pick, proceed on the implicit open pick, and proceed
#    on BOTH explicit picks — so the pause is provably mode-AND-contradiction-gated.
P="$TMP/paired"; new_repo "$P"; mkdir -p "$P/specs/feat"
printf -- '- [ ] T910 [cheap] genuinely open, no work yet (US1)\n- [ ] T911 [cheap] merged but box still unchecked (US1)\n' \
  > "$P/specs/feat/tasks.md"
git -C "$P" commit -q --allow-empty -m "feat: [T911] merged work for the drifted task"
run_decision confirm "$P" "paired: implicit + drifted T911 -> confirm (pause)" T911 implicit
run_decision proceed "$P" "paired: implicit + open T910 -> proceed (no false pause)" T910 implicit
run_decision proceed "$P" "paired: explicit + drifted T911 -> proceed (explicit never pauses)" T911 explicit
run_decision proceed "$P" "paired: explicit + open T910 -> proceed" T910 explicit

# ── Whole-id match: a [T91] commit must NOT make an implicit unchecked T913 look contradicted.
S="$TMP/substr"; new_repo "$S"; mkdir -p "$S/specs/feat"
printf -- '- [ ] T913 [cheap] open task (US1)\n' > "$S/specs/feat/tasks.md"
git -C "$S" commit -q --allow-empty -m "fix: [T91] an unrelated, lower task"
run_decision proceed "$S" "substring: [T91] commit does not contradict implicit T913" T913 implicit

# ── Composed production path (craft review on PR #128, finding 1): the §1 binding runs the
#    reconcile precondition AND this announce decision, keyed to the selection's provenance.
#    Prove `confirm` is REACHABLE on the real composed path — not only on the announce hook in
#    isolation — and that an explicit stale pick is reconcile's TERMINAL refusal, not a confirm.
#    Without this, the documented "announce after reconcile clears" would make `confirm` dead:
#    reconcile exits 3 on the same drift the confirm uses, so a confirm gated behind a reconcile
#    exit 0 could never fire. run_composed mirrors the binding's documented composition exactly.
RECON="$HOOKS/reconcile-task-selection.sh"
# run_composed <expected-outcome> <repo-dir> <name> <mode> <id> — explicit: reconcile is
# authoritative (exit 3 = terminal `refuse`; else announce → `proceed`). implicit: announce
# decides (`confirm` | `proceed` | `announce-only`); reconcile is not a separate terminal gate
# because the confirm surfaces that same drift as a pause-for-redirect.
run_composed() {
  local want="$1" dir="$2" name="$3" mode="$4" id="$5"
  local outcome
  if [ "$mode" = "explicit" ]; then
    if ( cd "$dir" && bash "$RECON" "$id" >/dev/null 2>&1 ); then
      outcome="$( cd "$dir" && bash "$SCRIPT" "$id" explicit 2>/dev/null )"
    else
      outcome="refuse"
    fi
  else
    outcome="$( cd "$dir" && bash "$SCRIPT" "$id" implicit 2>/dev/null )"
  fi
  if [ "$outcome" = "$want" ]; then ok; else bad "$name (want '$want', got '$outcome')"; fi
}
run_composed confirm "$P" "composed: implicit drifted T911 -> confirm IS reachable on the real path" implicit T911
run_composed proceed "$P" "composed: implicit open T910 -> proceed" implicit T910
run_composed refuse  "$P" "composed: explicit drifted T911 -> reconcile terminal refusal (not confirm)" explicit T911
run_composed proceed "$P" "composed: explicit open T910 -> proceed" explicit T910

# ── Fail-open (done-when 4): no git state -> an implicit pick degrades to `announce-only`
#    (announce, no spurious confirm-stall), never a hard stall. A bare temp dir under $TMP is
#    outside any repo.
NOGIT="$TMP/nogit"; mkdir -p "$NOGIT/specs/feat"
printf -- '- [ ] T914 [cheap] open task (US1)\n' > "$NOGIT/specs/feat/tasks.md"
run_decision announce-only "$NOGIT" "fail-open: unreadable git state -> announce-only (implicit)" T914 implicit

# ── Usage guards: missing args, a non-task id, and a bad mode all exit 2.
run_exit 2 "$P" "usage: no arguments exits 2"
run_exit 2 "$P" "usage: a single argument exits 2" T910
run_exit 2 "$P" "usage: a non-task id exits 2" not-a-task implicit
run_exit 2 "$P" "usage: a bad mode exits 2" T910 sideways

# ── Share, not duplicate (P2): the announce decision sources the SHARED drift lib rather than
#    re-implementing detection, so it can never disagree with the reconcile refusal / CI gate.
if grep -qE 'lib-tasks-drift\.sh' "$SCRIPT"; then ok
else bad "share: announce-task-selection.sh does not source lib-tasks-drift.sh (forked drift logic?)"; fi

# ── CI wiring: ci.yml must run this test, else the decision's machinery is unproven (the
#    silently-dead-machinery class, P2 — same posture as reconcile-task-selection.test.sh).
CI="$HOOKS/../../.github/workflows/ci.yml"
if grep -qE 'announce-task-selection\.test\.sh' "$CI"; then ok
else bad "wiring: ci.yml verify does not run announce-task-selection.test.sh"; fi

printf 'announce-task-selection.test.sh: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
