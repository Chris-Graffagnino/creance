#!/usr/bin/env bash
# Tests for autonomy-mode.sh — the [autonomy activation] check (T610 / epic #81).
#
# Proves the activation decision is DEFAULT-OFF and FAILS CLOSED, and that the
# machinery is wired (P2 "machinery proves it is live", same discipline as
# guard.test.sh / reconcile-task-selection.test.sh):
#   * default-off:    no opt-in + no authorization -> review (done-when (a).1);
#   * the two engage signals (config opt-in, in-session authorization);
#   * fail-closed:     unreadable/absent profile, non-`enabled` value, ambiguous
#                      duplicate declaration, and any token that only LOOKS like the
#                      declaration (longer-identifier suffix, commented-out line,
#                      heading, prose mention) -> review (never autonomous);
#   * usage guards;
#   * wiring:          the `verify` job ACTIVELY runs both the check and this test (an
#                      active `run:` step, not a mention in a comment); the neutral model
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

# Fixtures. A genuine declaration is the canonical code-span shape (PROJECT.md → Autonomy:
# the key inside backticks, on its own bullet line); dup/garbled use that shape so they
# still exercise the cardinality and value guards rather than the code-span anchor.
printf 'foo\nbar\n'                                            > "$TMP/none.md"
printf '%s\n' '- **mode** `autonomy-opt-in: disabled` (default)' > "$TMP/disabled.md"
printf '%s\n' '- **mode** `autonomy-opt-in: enabled`'           > "$TMP/enabled.md"
printf '%s\n' '- `autonomy-opt-in: enabled`' '- `autonomy-opt-in: enabled`' > "$TMP/dup.md"
printf '%s\n' '- `autonomy-opt-in: maybe`'                     > "$TMP/garbled.md"
# "Looks like a declaration but is not one" (Codex review + constitution audit, PR #107).
# Each must resolve to review: a longer identifier whose suffix is the key (bare and in a
# code span), a commented-out declaration (HTML + heading forms — the operator's natural
# "turn it off" gesture), and prose mentions (key name in a code span; the token in prose).
printf '%s\n' 'xautonomy-opt-in: enabled'                      > "$TMP/superstring.md"
printf '%s\n' '- `xautonomy-opt-in: enabled`'                  > "$TMP/superstring-span.md"
printf '%s\n' '<!-- `autonomy-opt-in: enabled` -->'            > "$TMP/commented-html.md"
printf '%s\n' '# `autonomy-opt-in: enabled`'                   > "$TMP/commented-hash.md"
printf '%s\n' '(see `autonomy-opt-in` — set it to enabled)'    > "$TMP/prose-keyname.md"
printf '%s\n' 'docs say autonomy-opt-in: enabled turns it on'  > "$TMP/prose-mention.md"

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
# A token that merely LOOKS like the declaration must never flip OPEN (Codex review +
# constitution audit, PR #107). The unanchored grep lifted the key straight out of
# `xautonomy-opt-in: enabled`; a left-only anchor still honored a commented-out line — the
# canonical code-span + comment-strip rejects both, plus prose, in either direction.
decision "fail-closed: superstring key"       review --profile "$TMP/superstring.md"
decision "fail-closed: superstring in span"   review --profile "$TMP/superstring-span.md"
decision "fail-closed: commented-out (html)"  review --profile "$TMP/commented-html.md"
decision "fail-closed: commented-out (hash)"  review --profile "$TMP/commented-hash.md"
decision "fail-closed: prose key name"        review --profile "$TMP/prose-keyname.md"
decision "fail-closed: prose mention"         review --profile "$TMP/prose-mention.md"

# A non-fail-open spot check: an unreadable profile must NEVER read as autonomous.
got=$(bash "$SCRIPT" --profile "$TMP/does-not-exist.md" 2>/dev/null)
if [ "$got" != "autonomous" ]; then ok; else bad "fail-open leak: absent profile read as autonomous"; fi

# Usage guards.
rc "unknown flag -> exit 2"        2 --bogus
rc "--profile w/o value -> exit 2" 2 --profile
rc "valid call -> exit 0"          0 --profile "$TMP/none.md"

# Wiring (P2): the check + this test must be RUN by the required `verify` job, or the
# machinery is silently dead. A bare filename grep over the whole file is too loose
# (Codex review, PR #107; same class as the residency/budget wiring fix, #92): a
# commented-out, disabled, or moved-to-another-job copy of the step would still satisfy
# it — and the explanatory comment block above these steps names both filenames — while
# `verify` no longer runs the gate. So scope to the `verify` job's body and require an
# ACTIVE `run: bash <script>` step, exactly as the residency/budget tests do.
# Lines belonging to the `verify:` job: from its 2-space-indented key to the next
# 2-space-indented job key (or EOF). No awk interval syntax (portable to BSD awk).
verify_steps() { awk '/^  [A-Za-z]/ { inblk = ($0 ~ /^  verify:/) } inblk { print }' "$CI"; }
# 0 iff an active (uncommented) `run: bash <path>` step invokes $1 within verify.
runs_in_verify() { verify_steps | grep -qE "^[[:space:]]*run:[[:space:]]+bash[[:space:]]+$1([[:space:]]|\$)"; }
if runs_in_verify '\.claude/hooks/autonomy-mode\.sh'; then ok; else bad "verify must RUN autonomy-mode.sh (active run: step)"; fi
if runs_in_verify '\.claude/hooks/autonomy-mode\.test\.sh'; then ok; else bad "verify must RUN autonomy-mode.test.sh (active run: step)"; fi

# Mechanism <-> model drift backstop: the neutral role the check binds, and the
# profile opt-in key it reads, must both exist (else the check is decoupled from its model).
if grep -qF '[isolated workspace]' "$MODEL"; then ok; else bad "workflow/README.md missing the [isolated workspace] role"; fi
if grep -qE 'autonomy-opt-in:' "$PROFILE"; then ok; else bad "PROJECT.md missing the autonomy-opt-in key the check reads"; fi
# The profile default must be review (disabled), never enabled-by-default.
if [ "$(bash "$SCRIPT" --profile "$PROFILE")" = "review" ]; then ok; else bad "shipped PROJECT.md must default to review mode"; fi

printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
