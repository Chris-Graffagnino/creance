#!/usr/bin/env bash
# Tests for backlog-loop-iterate.sh — the [backlog-loop]'s real iteration
# binding (T905, spec 004 US1.AC7; neutral model: .claude/workflow/backlog-loop.md).
#
# Proves, against a STUB headless command (the seam the launcher binds to the
# real headless CLI), each case per-instance (exact stdout equality):
#   * explicit context: the composed prompt names the task explicitly
#     (`/next-task <id>`) and carries the outcome-marker contract;
#   * outcome transport: each grammar form (pass <pr-ref> / fail-discard /
#     refused / aborted) is read from the run's own return and passed through
#     verbatim; the LAST marker line wins; surrounding whitespace is trimmed
#     without touching the pass form's interior spacing;
#   * fail closed: a missing marker, an unrecognized outcome (a bare `pass`
#     with no PR ref included), or a non-zero run exit prints `aborted` —
#     never a guessed pass;
#   * usage guards: a missing/malformed task id or a missing seam is a loud
#     exit 2 (the skeleton reads non-zero as `aborted`, so even a
#     misconfigured binding fails closed);
#   * wiring (P2): the `verify` job ACTIVELY runs this test.
# Bash only, <1s. Run: bash .claude/hooks/backlog-loop-iterate.test.sh
set -u

HOOKS="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HOOKS/backlog-loop-iterate.sh"
REPO="$(cd "$HOOKS/../.." && pwd)"
CI="$REPO/.github/workflows/ci.yml"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
pass=0
fail=0
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); printf 'FAIL %s\n' "$1" >&2; }

assert_eq() { # <label> <got> <want>
  if [ "$2" = "$3" ]; then ok; else bad "$1: got '$2' want '$3'"; fi
}

# Stub headless command: logs the received prompt verbatim, then prints the
# canned transcript in $TMP/reply (exit code from $TMP/rc when present).
cat > "$TMP/headless.sh" <<'EOF'
#!/usr/bin/env bash
set -u
printf '%s' "$1" > "$STUB_DIR/prompt.log"
cat "$STUB_DIR/reply" 2>/dev/null
rc=0
[ -f "$STUB_DIR/rc" ] && rc="$(cat "$STUB_DIR/rc")"
exit "$rc"
EOF
export STUB_DIR="$TMP"

run_iter() { # <task-id...> -> OUT/RC
  RC=0
  OUT="$(BACKLOG_LOOP_HEADLESS_CMD="bash $TMP/headless.sh" bash "$SCRIPT" "$@" 2>/dev/null)" || RC=$?
}
set_reply() { printf '%s\n' "$1" > "$TMP/reply"; rm -f "$TMP/rc"; }

# ── 1. explicit context: the prompt names the task and the marker contract.
set_reply 'BACKLOG-LOOP-OUTCOME: refused'
run_iter T123
if grep -qF '/next-task T123' "$TMP/prompt.log"; then ok; else bad "prompt must name the task explicitly (/next-task T123)"; fi
if grep -qF 'BACKLOG-LOOP-OUTCOME: pass <pr-ref>' "$TMP/prompt.log"; then ok; else bad "prompt must state the outcome-marker contract"; fi
if grep -qF 'never merge' "$TMP/prompt.log"; then ok; else bad "prompt must restate the no-merge bound"; fi

# ── 2. outcome transport: each grammar form passes through verbatim.
set_reply 'chatter...
BACKLOG-LOOP-OUTCOME: pass PR#41'
run_iter T101
assert_eq "pass form passes through with its PR ref" "$OUT" "pass PR#41"
assert_eq "clean transport exits 0" "$RC" "0"

set_reply 'BACKLOG-LOOP-OUTCOME: fail-discard'
run_iter T101
assert_eq "fail-discard passes through" "$OUT" "fail-discard"

set_reply 'BACKLOG-LOOP-OUTCOME: refused'
run_iter T101
assert_eq "refused passes through" "$OUT" "refused"

set_reply 'BACKLOG-LOOP-OUTCOME: aborted'
run_iter T101
assert_eq "aborted passes through" "$OUT" "aborted"

set_reply 'BACKLOG-LOOP-OUTCOME: fail-discard
later correction...
BACKLOG-LOOP-OUTCOME: pass PR#7'
run_iter T101
assert_eq "the LAST marker line wins" "$OUT" "pass PR#7"

set_reply 'BACKLOG-LOOP-OUTCOME:    refused   '
run_iter T101
assert_eq "surrounding whitespace is trimmed" "$OUT" "refused"

set_reply 'BACKLOG-LOOP-OUTCOME: pass https://example.test/pr/9 (squash pending)'
run_iter T101
assert_eq "pass keeps interior spacing of its ref text" "$OUT" "pass https://example.test/pr/9 (squash pending)"

set_reply 'BACKLOG-LOOP-OUTCOME: pass PR#12
Recapping the contract I was given:
  BACKLOG-LOOP-OUTCOME: pass <pr-ref>     (the §7 gate passed...)
  BACKLOG-LOOP-OUTCOME: aborted           (a lifecycle check failed closed)'
run_iter T101
assert_eq "an echoed (indented) contract never overrides the real marker" "$OUT" "pass PR#12"

set_reply 'BACKLOG-LOOP-OUTCOME: pass <pr-ref>'
run_iter T101
assert_eq "the contract's own placeholder shape is never a real pass" "$OUT" "aborted"

# ── 3. fail closed: missing marker / unrecognized outcome / non-zero run exit.
set_reply 'the run said many things but never the marker'
run_iter T101
assert_eq "missing marker -> aborted" "$OUT" "aborted"
assert_eq "missing marker still exits 0 (the outcome IS the signal)" "$RC" "0"

set_reply 'BACKLOG-LOOP-OUTCOME: pass'
run_iter T101
assert_eq "bare pass with no PR ref -> aborted (never a guessed pass)" "$OUT" "aborted"

set_reply 'BACKLOG-LOOP-OUTCOME: maybe-later'
run_iter T101
assert_eq "unrecognized outcome -> aborted" "$OUT" "aborted"

set_reply 'BACKLOG-LOOP-OUTCOME: pass PR#41'
printf '3\n' > "$TMP/rc"
run_iter T101
assert_eq "non-zero run exit -> aborted, even with a pass marker" "$OUT" "aborted"
rm -f "$TMP/rc"

# ── 4. usage guards: loud exit 2, nothing usable on stdout.
run_iter
assert_eq "no task id -> exit 2" "$RC" "2"
run_iter banana
assert_eq "non-task-id argument -> exit 2" "$RC" "2"
run_iter T12 extra
assert_eq "extra arguments -> exit 2" "$RC" "2"
RC=0
OUT="$(BACKLOG_LOOP_HEADLESS_CMD="" bash "$SCRIPT" T101 2>/dev/null)" || RC=$?
assert_eq "missing headless seam -> exit 2 (no silent default)" "$RC" "2"

# ── Wiring (P2): the `verify` job ACTIVELY runs this test.
verify_steps() { awk '/^  [A-Za-z]/ { inblk = ($0 ~ /^  verify:/) } inblk { print }' "$CI"; }
if verify_steps | grep -qE '^[[:space:]]*run:[[:space:]]+bash[[:space:]]+\.claude/hooks/backlog-loop-iterate\.test\.sh([[:space:]]|$)'; then
  ok
else
  bad "verify must RUN backlog-loop-iterate.test.sh (active run: step)"
fi

printf 'backlog-loop-iterate.test.sh: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
