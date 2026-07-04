#!/usr/bin/env bash
# Tests for docs/launchers/backlog-loop.sh — the [backlog-loop]'s [scheduled run]
# entry (.claude/README.md role table; spec 004 US1). The sibling hook bindings
# (select/iterate/skeleton) have their own tests; this pins the launcher's OWN
# logic, which nothing else covers: the auth preflight and the permission-mode
# composition the PR #239 review flagged as an untested "silent success vs loud
# failure" surface.
#
# It drives the REAL launcher template (copied verbatim, only the placeholder
# config lines injected) against a stubbed `claude` and a stubbed loop skeleton,
# and proves, per case:
#   * missing auth token -> LOUD `exit=1`, `auth: <file> missing` logged, and the
#     loop is NEVER reached (no unauthenticated `claude` run) — the exact
#     regression the review fix (ca180d4) closed;
#   * missing `claude` CLI -> LOUD `exit=1`, logged, loop never reached;
#   * happy path -> the composed headless command carries
#     `--dangerously-skip-permissions` and the injected model, the token is
#     exported into the cycle, and the loop runs;
#   * a non-zero cycle propagates its exit code to the scheduler (never masked);
#   * a missing repo root -> LOUD `exit=1`, logged;
#   * the run-log dead-man line is UNCONDITIONAL — every exit path above writes one;
#   * drift guard: the placeholder config lines the injection targets still exist
#     (a renamed/removed config var fails LOUD, never silently tests placeholders);
#   * wiring (P2): the `verify` job ACTIVELY runs this test AND lints the launcher.
# Bash + coreutils only, <1s. Run: bash .claude/hooks/backlog-loop-launcher.test.sh
set -u

HOOKS="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HOOKS/../.." && pwd)"
LAUNCHER="$REPO/docs/launchers/backlog-loop.sh"
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
contains() { # <label> <haystack> <needle>
  case "$2" in *"$3"*) ok ;; *) bad "$1: '$2' lacks '$3'" ;; esac
}
absent() { # <label> <path>  — assert file does NOT exist
  if [ ! -e "$2" ]; then ok; else bad "$1: $2 should not exist"; fi
}

# The config lines the harness rewrites, anchored on `^VAR=`. If the launcher's
# config block is refactored so one no longer matches, make_launcher fails LOUD
# (below) rather than silently running the pristine placeholder value.
CONFIG_VARS="REPO_ROOT N RUNLOG MODEL TOKEN_FILE CLAUDE_BIN"

# make_launcher — copy the template, replacing each config assignment's whole
# line with a test value taken from T_<VAR>. Emits the runnable copy path.
make_launcher() { # -> prints copy path; asserts drift guard
  local copy="$TMP/launcher.sh" src="$LAUNCHER" v val
  cp "$src" "$copy"
  for v in $CONFIG_VARS; do
    if [ "$(grep -cE "^$v=" "$copy")" != "1" ]; then
      bad "drift guard: expected exactly one '^$v=' config line in the launcher"
      continue
    fi
    eval "val=\${T_$v}"
    # `|` delimiter so injected paths keep their slashes; test values carry no `|`.
    sed "s|^$v=.*|$v=\"$val\"|" "$copy" > "$copy.next" && mv "$copy.next" "$copy"
  done
  printf '%s' "$copy"
}

# A stubbed loop skeleton dropped at <repo>/.claude/hooks/backlog-loop.sh — the
# relative path the launcher runs after `cd "$REPO_ROOT"`. It records that the
# loop was reached, the composed headless command, and whether the auth token
# reached the cycle, then exits with the code staged in $STUB_DIR/loop-rc.
scaffold_repo() { # <dir>
  mkdir -p "$1/.claude/hooks"
  cat > "$1/.claude/hooks/backlog-loop.sh" <<'EOF'
#!/usr/bin/env bash
set -u
: > "$STUB_DIR/loop-invoked"
printf '%s' "${BACKLOG_LOOP_HEADLESS_CMD:-<unset>}" > "$STUB_DIR/headless-cmd"
printf '%s' "${CLAUDE_CODE_OAUTH_TOKEN:-<unset>}" > "$STUB_DIR/token-seen"
echo "stop=backlog-drained iterations=0/1"
rc=0
[ -f "$STUB_DIR/loop-rc" ] && rc="$(cat "$STUB_DIR/loop-rc")"
exit "$rc"
EOF
}

# run_case — fresh per-case sandbox, then run the injected launcher.
#   args: token_present(y/n) claude_present(y/n) repo_exists(y/n) [loop_rc]
run_case() {
  local token_present="$1" claude_present="$2" repo_exists="$3" loop_rc="${4:-}"
  local box; box="$(mktemp -d "$TMP/case.XXXX")"
  export STUB_DIR="$box"
  rm -f "$box/loop-invoked" "$box/headless-cmd" "$box/token-seen" "$box/loop-rc"
  [ -n "$loop_rc" ] && printf '%s' "$loop_rc" > "$box/loop-rc"

  local repo="$box/repo"
  scaffold_repo "$repo"
  [ "$repo_exists" = n ] && repo="$box/does-not-exist"

  local claude="$box/claude"
  if [ "$claude_present" = y ]; then
    printf '#!/usr/bin/env bash\nexit 0\n' > "$claude"; chmod +x "$claude"
  else
    claude="$box/no-such-claude"
  fi

  local token="$box/.oauth-token"
  [ "$token_present" = y ] && printf 'tok-secret' > "$token"

  T_REPO_ROOT="$repo" T_N="1" T_RUNLOG="$box/runlog" \
    T_MODEL="test-strong-model" T_TOKEN_FILE="$token" T_CLAUDE_BIN="$claude"
  local script; script="$(make_launcher)"
  RUNLOG="$box/runlog"
  RC=0
  bash "$script" >/dev/null 2>&1 || RC=$?
  LOGLINE="$(tail -1 "$RUNLOG" 2>/dev/null || true)"
}

# ── 1. missing auth token: loud failure, loop never reached (ca180d4 regression).
run_case n y y
assert_eq "missing token -> exit 1" "$RC" "1"
contains "missing token logs an auth failure" "$LOGLINE" "auth:"
contains "missing token line marks exit=1" "$LOGLINE" "exit=1"
absent  "missing token never reaches the loop (no unauthenticated run)" "$STUB_DIR/loop-invoked"

# ── 2. missing claude CLI: loud failure, loop never reached.
run_case y n y
assert_eq "missing claude -> exit 1" "$RC" "1"
contains "missing claude is logged" "$LOGLINE" "claude CLI not found"
absent  "missing claude never reaches the loop" "$STUB_DIR/loop-invoked"

# ── 3. happy path: permission flag composed, token exported, loop runs.
run_case y y y
assert_eq "happy path -> exit 0 (stub loop drained)" "$RC" "0"
if [ -e "$STUB_DIR/loop-invoked" ]; then ok; else bad "happy path must reach the loop"; fi
HCMD="$(cat "$STUB_DIR/headless-cmd" 2>/dev/null || true)"
contains "headless cmd carries the permission bypass" "$HCMD" "--dangerously-skip-permissions"
contains "headless cmd carries the injected model" "$HCMD" "--model test-strong-model"
assert_eq "auth token is exported into the cycle" "$(cat "$STUB_DIR/token-seen" 2>/dev/null)" "tok-secret"
contains "happy-path run-log marks exit=0" "$LOGLINE" "exit=0"
contains "happy-path run-log carries the run id" "$LOGLINE" "run_id=bl-"

# ── 4. a non-zero cycle propagates to the scheduler (never masked as success).
run_case y y y 7
assert_eq "non-zero cycle exit is propagated" "$RC" "7"
contains "propagated exit is logged" "$LOGLINE" "exit=7"

# ── 5. missing repo root: loud failure, run-log line still written.
run_case y y n
assert_eq "missing repo root -> exit 1" "$RC" "1"
contains "missing repo root is logged" "$LOGLINE" "repo root missing"

# ── Wiring (P2): the `verify` job ACTIVELY runs this test AND lints the launcher.
verify_steps() { awk '/^  [A-Za-z]/ { inblk = ($0 ~ /^  verify:/) } inblk { print }' "$CI"; }
if verify_steps | grep -qE '^[[:space:]]*run:[[:space:]]+bash[[:space:]]+\.claude/hooks/backlog-loop-launcher\.test\.sh([[:space:]]|$)'; then
  ok
else
  bad "verify must RUN backlog-loop-launcher.test.sh (active run: step)"
fi
if verify_steps | grep -qE 'shell-lint\.sh[[:space:]]+docs/launchers'; then
  ok
else
  bad "verify must lint docs/launchers/*.sh (the launcher's standing portability gate)"
fi

printf 'backlog-loop-launcher.test.sh: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
