#!/usr/bin/env bash
# Tests for autonomy-mode.sh — the [autonomy activation] check (T610 / epic #81).
#
# Proves the activation decision is DEFAULT-OFF and FAILS CLOSED, and that the
# machinery is wired (P2 "machinery proves it is live", same discipline as
# guard.test.sh / reconcile-task-selection.test.sh):
#   * default-off:    no opt-in + no authorization -> review (done-when (a).1);
#   * the two engage signals (config opt-in, in-session authorization);
#   * fail-closed:     unreadable/absent profile, non-`enabled` value, ambiguous
#                      duplicate declaration -> review (never autonomous);
#   * usage guards;
#   * wiring:          ci.yml runs both the check and this test; the neutral model
#                      ([isolated workspace] in workflow/README.md) and the profile
#                      opt-in key the check reads both exist (mechanism <-> model
#                      drift backstop).
set -u

HOOKS="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HOOKS/autonomy-mode.sh"
REPO="$(cd "$HOOKS/../.." && pwd)"
CI="$REPO/.github/workflows/ci.yml"
MODEL="$REPO/.claude/workflow/README.md"
PROFILE="$REPO/.claude/PROJECT.md"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
pass=0
fail=0
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); printf 'FAIL %s\n' "$1" >&2; }

# decision <label> <want-stdout> <args...>
decision() {
  local label="$1" want="$2"
  shift 2
  local out
  out=$(bash "$SCRIPT" "$@" 2>/dev/null)
  if [ "$out" = "$want" ]; then ok; else bad "$label: got '$out' want '$want'"; fi
}

# rc <label> <want-rc> <args...>
rc() {
  local label="$1" want="$2"
  shift 2
  local got=0
  bash "$SCRIPT" "$@" >/dev/null 2>&1 || got=$?
  if [ "$got" = "$want" ]; then ok; else bad "$label: got rc=$got want $want"; fi
}

# Fixtures.
printf 'foo\nbar\n'                                            > "$TMP/none.md"
printf '%s\n' '- **mode** `autonomy-opt-in: disabled` (default)' > "$TMP/disabled.md"
printf '%s\n' '- **mode** `autonomy-opt-in: enabled`'           > "$TMP/enabled.md"
printf 'autonomy-opt-in: enabled\nautonomy-opt-in: enabled\n'  > "$TMP/dup.md"
printf '%s\n' 'autonomy-opt-in: maybe'                         > "$TMP/garbled.md"

# Default-off — the load-bearing done-when (a).1 case: with neither signal, review.
decision "default-off (no key)"        review      --profile "$TMP/none.md"
decision "default-off (disabled key)"  review      --profile "$TMP/disabled.md"

# Engage signals.
decision "config opt-in -> autonomous" autonomous  --profile "$TMP/enabled.md"
decision "in-session auth -> autonomous" autonomous --session-authorized --profile "$TMP/none.md"
decision "either signal (auth + disabled profile)" autonomous --session-authorized --profile "$TMP/disabled.md"

# Fail-closed — every uncertainty resolves to review, never autonomous.
decision "fail-closed: absent profile" review      --profile "$TMP/does-not-exist.md"
decision "fail-closed: ambiguous dup"  review      --profile "$TMP/dup.md"
decision "fail-closed: garbled value"  review      --profile "$TMP/garbled.md"

# A non-fail-open spot check: an unreadable profile must NEVER read as autonomous.
got=$(bash "$SCRIPT" --profile "$TMP/does-not-exist.md" 2>/dev/null)
if [ "$got" != "autonomous" ]; then ok; else bad "fail-open leak: absent profile read as autonomous"; fi

# Usage guards.
rc "unknown flag -> exit 2"        2 --bogus
rc "--profile w/o value -> exit 2" 2 --profile
rc "valid call -> exit 0"          0 --profile "$TMP/none.md"

# Wiring (P2): the check + this test must be run by CI, or the machinery is silently dead.
if grep -qE 'autonomy-mode\.sh' "$CI"; then ok; else bad "ci.yml does not run autonomy-mode.sh"; fi
if grep -qE 'autonomy-mode\.test\.sh' "$CI"; then ok; else bad "ci.yml does not run autonomy-mode.test.sh"; fi

# Mechanism <-> model drift backstop: the neutral role the check binds, and the
# profile opt-in key it reads, must both exist (else the check is decoupled from its model).
if grep -qF '[isolated workspace]' "$MODEL"; then ok; else bad "workflow/README.md missing the [isolated workspace] role"; fi
if grep -qE 'autonomy-opt-in:' "$PROFILE"; then ok; else bad "PROJECT.md missing the autonomy-opt-in key the check reads"; fi
# The profile default must be review (disabled), never enabled-by-default.
if [ "$(bash "$SCRIPT" --profile "$PROFILE")" = "review" ]; then ok; else bad "shipped PROJECT.md must default to review mode"; fi

printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
