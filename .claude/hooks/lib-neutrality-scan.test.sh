#!/usr/bin/env bash
# Contract tests for lib-neutrality-scan.sh (#122 review follow-up).
# Proves the shared scanner catches every banned mechanism class, preserves the
# `git` and `.claude/` exemptions, and fails loud on invalid inputs.
set -u

DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib-neutrality-scan.sh
. "$DIR/lib-neutrality-scan.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0
case_id=0

ok() { pass=$((pass + 1)); }
bad() {
  fail=$((fail + 1))
  printf 'FAIL %s\n' "$1" >&2
}

fixture() {
  case_id=$((case_id + 1))
  printf '%s/fixture-%s.md' "$TMP" "$case_id"
}

assert_leak() {
  local name="$1" body="$2" want="$3" file got
  file="$(fixture)"
  printf '%b' "$body" > "$file"
  got="$(neutral_mechanism_leaks "$file")"
  if printf '%s' "$got" | grep -qF -- "$want"; then
    ok
  else
    bad "$name: expected '$want' in scan output, got '${got:-<empty>}'"
  fi
}

assert_clean() {
  local name="$1" body="$2" file got rc
  file="$(fixture)"
  printf '%b' "$body" > "$file"
  got="$(neutral_mechanism_leaks "$file")"
  rc=$?
  if [ "$rc" -eq 0 ] && [ -z "$got" ]; then
    ok
  else
    bad "$name: expected clean scan, got rc=$rc output='${got:-<empty>}'"
  fi
}

assert_scan_error() {
  local name="$1" file="$2" got err rc
  err="$TMP/error-$case_id"
  got="$(neutral_mechanism_leaks "$file" 2>"$err")"
  rc=$?
  if [ "$rc" -ne 0 ] \
    && printf '%s' "$got" | grep -qF -- 'NEUTRALITY_SCAN_ERROR' \
    && grep -qF -- 'FAIL:' "$err"; then
    ok
  else
    bad "$name: expected loud scan failure, got rc=$rc stdout='${got:-<empty>}' stderr='$(cat "$err" 2>/dev/null)'"
  fi
}

assert_leak "bare gh token" "Use gh for tracker reads." "gh"
assert_leak "line-wrapped GitHub CLI phrase" "GitHub\nCLI\n" "GitHub CLI"
assert_leak "non-adjacent GitHub CLI phrase" "Read GitHub state via its CLI." "GitHub state via its CLI"
assert_leak "bare claude token" "The claude runtime is named." "claude"
assert_leak "opus model token" "Use opus." "opus"
assert_leak "sonnet model token" "Use sonnet." "sonnet"
assert_leak "fable model token" "Use fable." "fable"
assert_leak "haiku model token" "Use haiku." "haiku"
assert_leak "model flag token" "Pass --model explicitly." "--model"
assert_leak "json flag token" "Request --json output." "--json"
assert_leak "hook token" "Wire PreToolUse." "PreToolUse"
assert_leak "settings file token" "Read settings.json." "settings.json"

# Omnigent adapter vocabulary (T617) — same shared scanner, no fork.
assert_leak "omnigent runtime token" "Drive omnigent run config.yaml." "omnigent"
assert_leak "polly orchestrator token" "Shape it like the polly orchestrator." "polly"
assert_leak "policy_modules key" "Register under policy_modules." "policy_modules"
assert_leak "POLICY_REGISTRY export" "Export a POLICY_REGISTRY list." "POLICY_REGISTRY"
assert_leak "openai-agents harness" "Run the openai-agents harness." "openai-agents"
assert_leak "sys_os_shell tool" "Policy on sys_os_shell." "sys_os_shell"
assert_leak "sys_os_edit tool" "Policy on sys_os_edit." "sys_os_edit"
assert_leak "sys_os_write tool" "Policy on sys_os_write." "sys_os_write"
assert_leak "sys_os_read tool" "Policy on sys_os_read." "sys_os_read"
assert_leak "sys_session_send tool" "Dispatch via sys_session_send." "sys_session_send"
assert_leak "executor.harness key" "Set executor.harness." "executor.harness"
assert_leak "executor.model key" "Set executor.model." "executor.model"

assert_clean "git stays exempt" "Run git rev-parse --show-toplevel."
assert_clean ".claude profile pointer stays exempt" "Read .claude/workflow/README.md."

assert_scan_error "missing file fails loud" "$TMP/missing.md"
empty="$(fixture)"
: > "$empty"
assert_scan_error "empty file fails loud" "$empty"

err="$TMP/error-no-args"
got="$(neutral_mechanism_leaks 2>"$err")"
rc=$?
if [ "$rc" -ne 0 ] \
  && printf '%s' "$got" | grep -qF -- 'NEUTRALITY_SCAN_ERROR' \
  && grep -qF -- 'FAIL:' "$err"; then
  ok
else
  bad "no file args fail loud: expected rc!=0 plus diagnostics, got rc=$rc stdout='${got:-<empty>}' stderr='$(cat "$err" 2>/dev/null)'"
fi

printf 'lib-neutrality-scan.test.sh: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
