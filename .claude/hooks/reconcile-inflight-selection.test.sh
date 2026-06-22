#!/usr/bin/env bash
# Regression tests for reconcile-inflight-selection.sh — the IN-FLIGHT half of /next-task
# live-state reconciliation (#105, T615), the tracker-based companion to the git-only merged
# half (reconcile-task-selection.sh, #80/T608). The check reads the tracker via `gh`, so each
# case injects a STUB gh on the script's `GH` seam and feeds it canned PR/issue/branch fixtures
# (the reconcile-task-selection.test.sh idiom, adapted: a mocked tracker instead of a throwaway
# git repo), then asserts the exit code.
#
# The load-bearing case is the PAIRED harness (done-when 1 + 2): ONE mocked tracker state holds
# an in-flight task (T615 — open PR AND a branch) AND a genuinely-open task (T616 — no PR, no
# branch). The SAME fixtures must REFUSE T615 (exit 3) AND SELECT T616 (exit 0), so "no false
# positive" cannot be met by a check that never fires (or that flags every candidate). Each
# in-flight ARM is also exercised alone (PR-only, branch-only) since done-when 1 says
# "PR/branch". Plus whole-id anchoring; the targeted-query lock (the PR scan narrows server-side
# with `--search "<id> in:title"` rather than a --limit-capped enumeration that could miss a
# conflicting PR past the window — Codex P2, #129); the fail-open paths (done-when 4: gh errors
# AND gh absent); usage guards; and the end-to-end wiring proof (the verify job ACTIVELY runs
# this test, SKILL.md binds the script, and next-task.md routes the in-flight axis as a [role]).
# Bash + a stub only, <1s; wired into the `verify` CI job.
# Run: bash .claude/hooks/reconcile-inflight-selection.test.sh
set -u

HOOKS="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HOOKS/reconcile-inflight-selection.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
pass=0
fail=0

ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); printf 'FAIL %s\n' "$1" >&2; }

# A stub `gh` that serves canned fixtures the test points it at via env, dispatching on the
# subcommand: `pr list` -> $STUB_PRS, `issue list` -> $STUB_ISSUES, `api …/branches` ->
# $STUB_BRANCHES. STUB_FAIL=1 makes every call exit non-zero (the "tracker unavailable" path).
# An unset fixture is empty success — exactly what real gh returns for "nothing matched".
STUB="$TMP/gh"
cat > "$STUB" <<'STUB_EOF'
#!/usr/bin/env bash
[ -n "${STUB_ARGV:-}" ] && printf '%s\n' "$*" >> "$STUB_ARGV"
[ "${STUB_FAIL:-0}" = "1" ] && exit 1
case "$1 $2" in
  "pr list")    [ -n "${STUB_PRS:-}" ]    && cat "$STUB_PRS" ;;
  "issue list") [ -n "${STUB_ISSUES:-}" ] && cat "$STUB_ISSUES" ;;
esac
[ "$1" = "api" ] && [ -n "${STUB_BRANCHES:-}" ] && cat "$STUB_BRANCHES"
exit 0
STUB_EOF
chmod +x "$STUB"

# run_inflight <expected-exit> <name> <task-id> — run the real script with the stub gh on the
# GH seam, carrying whatever STUB_* fixtures the caller exported.
run_inflight() {
  local want="$1" name="$2" id="$3"
  local got=0
  GH="$STUB" bash "$SCRIPT" "$id" >/dev/null 2>&1 || got=$?
  if [ "$got" -eq "$want" ]; then ok; else bad "$name (want exit $want, got $got)"; fi
}

# ── Fixtures. ONE tracker state: T615 is in flight (open PR #200 + branch feat/105-…, its
#    mapped issue is #105); T616 is genuinely open (no PR carries [T616], its issue #119 has no
#    branch). printf with literal tabs => the @tsv shape the script parses.
printf '200\tfeat: [T615] in-flight work\thttps://gh/x/y/pull/200\n' > "$TMP/prs.tsv"
printf '105\tfeat: [T615] refuse in-flight candidates\n119\tfeat: [T616] omnigent adapter\n' > "$TMP/issues.tsv"
printf 'main\nfeat/105-inflight-refusal\n' > "$TMP/branches.txt"

# ── The paired harness (done-when 1 + 2): the SAME mocked tracker refuses the in-flight task
#    and selects the genuinely-open one.
export STUB_PRS="$TMP/prs.tsv" STUB_ISSUES="$TMP/issues.tsv" STUB_BRANCHES="$TMP/branches.txt"
run_inflight 3 "paired: in-flight T615 (open PR + branch) is REFUSED" T615
run_inflight 0 "paired: genuinely-open T616 (no PR, no branch) is SELECTED (no false positive)" T616

# ── PR-only arm (done-when 1, "PR"): an open PR carries [T615] but no branch is bound to its
#    issue — refuse on the PR signal alone.
printf 'main\nfeat/119-omnigent\n' > "$TMP/branches-nopr105.txt"
STUB_BRANCHES="$TMP/branches-nopr105.txt" run_inflight 3 "PR-only: open PR [T615], no matching branch -> REFUSE" T615

# ── Branch-only arm (done-when 1, "branch"): no open PR carries [T615], but its issue #105 has
#    a branch pushed before any PR — the real "started, not yet PR'd" window. Refuse on the
#    branch signal alone.
printf '300\tfeat: [T616] unrelated open pr\thttps://gh/x/y/pull/300\n' > "$TMP/prs-nopr615.tsv"
STUB_PRS="$TMP/prs-nopr615.tsv" run_inflight 3 "branch-only: branch feat/105-… , no PR [T615] -> REFUSE" T615

# ── Whole-id / delimiter anchoring: a [T61] PR and a /1054- branch must NOT make T615 look
#    in-flight (mirrors the merged half's bracket-anchored match).
printf '400\tfix: [T61] a lower task\thttps://gh/x/y/pull/400\n' > "$TMP/prs-substr.tsv"
printf 'main\nfeat/1054-unrelated\n' > "$TMP/branches-substr.txt"
printf '105\tfeat: [T615] refuse in-flight candidates\n' > "$TMP/issues-615.tsv"
STUB_PRS="$TMP/prs-substr.tsv" STUB_ISSUES="$TMP/issues-615.tsv" STUB_BRANCHES="$TMP/branches-substr.txt" \
  run_inflight 0 "anchoring: [T61] PR + /1054- branch do not trip T615" T615

# ── Targeted PR query (Codex P2, #129): the pr-list call must narrow server-side with
#    `--search "<id> in:title"`, not enumerate a --limit-capped list of unrelated open PRs — in
#    a repo with more open PRs than the window, a conflicting [<id>] PR past it would be missed
#    and the task wrongly marked selectable (duplicate in-flight work). The stub serves fixtures
#    regardless of flags, so the QUERY SHAPE is asserted from recorded argv, locking the fix
#    against a silent revert to a bare capped list.
argv="$TMP/argv.log"
STUB_ARGV="$argv" GH="$STUB" bash "$SCRIPT" T615 >/dev/null 2>&1
if grep -Eq 'pr list .*--search T615 in:title' "$argv"; then ok
else bad "Codex P2 #129: PR query not narrowed by --search \"T615 in:title\" (a capped --limit list can miss the conflicting PR)"; fi

# ── Surfacing (done-when 1, "surfacing the conflict"): a refusal must PRINT the conflicting
#    PR/branch, not merely exit 3. Re-uses the paired fixtures (exports restored after the
#    anchoring prefix override) — PR arm prints the PR, branch-only arm prints the branch.
msg="$( GH="$STUB" bash "$SCRIPT" T615 2>&1 )"
case "$msg" in *"open PR:"*200*) ok ;; *) bad "surfacing: PR refusal does not surface the conflicting PR (got: $msg)" ;; esac
msg="$( GH="$STUB" STUB_PRS="$TMP/prs-nopr615.tsv" bash "$SCRIPT" T615 2>&1 )"
case "$msg" in *"open branch:"*feat/105-inflight-refusal*) ok ;; *) bad "surfacing: branch refusal does not surface the conflicting branch (got: $msg)" ;; esac

# ── Fail-open (done-when 4): the tracker is unavailable. gh ERRORS (auth/network) and gh ABSENT
#    both degrade to selectable WITH a surfaced warning, never a hard stall.
STUB_FAIL=1 run_inflight 0 "fail-open: gh errors -> selectable (degrade to merged-only)" T615
warn="$( GH="$STUB" STUB_FAIL=1 bash "$SCRIPT" T615 2>&1 )"
case "$warn" in *fail-open*) ok ;; *) bad "fail-open: gh errors missing surfaced warning (got: $warn)" ;; esac
( GH="$TMP/nonexistent-gh" bash "$SCRIPT" T615 >/dev/null 2>&1 ); \
  [ "$?" -eq 0 ] && ok || bad "fail-open: gh absent should exit 0"
warn="$( GH="$TMP/nonexistent-gh" bash "$SCRIPT" T615 2>&1 )"
case "$warn" in *fail-open*) ok ;; *) bad "fail-open: gh absent missing surfaced warning (got: $warn)" ;; esac

# ── Usage guards: no argument and a non-task argument both exit 2.
unset STUB_PRS STUB_ISSUES STUB_BRANCHES
run_inflight 2 "usage: no argument exits 2" ""
got=0; ( GH="$STUB" bash "$SCRIPT" >/dev/null 2>&1 ) || got=$?
[ "$got" -eq 2 ] && ok || bad "usage: zero args exits 2 (got $got)"
run_inflight 2 "usage: a non-task argument exits 2" not-a-task

# ── Wiring (P2): the precondition must be proven LIVE end-to-end, else its machinery is the
#    silently-dead-machinery class. Three links, mirroring isolated-workspace.test.sh:
#    (a) the required `verify` job ACTIVELY runs this test — a bare-filename grep is too loose
#        (a commented-out/moved copy satisfies it, the #92 / PR #107 lesson), so scope to the
#        verify job body and require an active `run: bash <path>` step;
#    (b) the adapter SKILL.md binds the concrete reconcile-inflight-selection.sh into /next-task
#        (the in-flight axis actually runs "at selection", not just inside this test);
#    (c) the neutral next-task.md routes the in-flight axis as a tracker [role] read — proving
#        the path is wired while keeping the script name out of workflow/** (the P1 boundary).
CI="$HOOKS/../../.github/workflows/ci.yml"
BINDING="$HOOKS/../../.claude/skills/next-task/SKILL.md"
NEUTRAL="$HOOKS/../../.claude/workflow/next-task.md"
verify_steps() { awk '/^  [A-Za-z]/ { inblk = ($0 ~ /^  verify:/) } inblk { print }' "$CI"; }
if verify_steps | grep -qE '^[[:space:]]*run:[[:space:]]+bash[[:space:]]+\.claude/hooks/reconcile-inflight-selection\.test\.sh([[:space:]]|$)'; then ok
else bad "wiring (a): verify job does not ACTIVELY run reconcile-inflight-selection.test.sh"; fi
if grep -qF 'reconcile-inflight-selection.sh' "$BINDING"; then ok
else bad "wiring (b): SKILL.md does not bind reconcile-inflight-selection.sh into the /next-task path"; fi
if grep -qF 'tracker [role]' "$NEUTRAL"; then ok
else bad "wiring (c): next-task.md does not route the in-flight axis as a tracker [role] read"; fi

printf 'reconcile-inflight-selection.test.sh: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
