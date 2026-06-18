#!/usr/bin/env bash
# Regression tests for shell-lint.sh (issues #79, #97). Proves the portability
# denylist + the bash -n syntax check FIRE on planted divergences and do NOT
# false-fire on the portable forms (the P2 "machinery proves it is live"
# discipline, same as guard.test.sh). Each denylisted construct is assembled at
# runtime (a dash in $D, a brace in $B), so this file never carries either
# pattern verbatim — a standing lint of .claude/hooks/*.sh stays clean on it.
# Needs only bash; runs in <1s; wired into the `verify` CI job.
set -u

LINT="$(cd "$(dirname "$0")" && pwd)/shell-lint.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
D="-"; B="{"   # dash / open-brace, kept out of literals so this file lints clean

hdr='#!/usr/bin/env bash'

# assert_rc <want-rc> <file> <name>
assert_rc() {
  local want="$1" file="$2" name="$3" got=0
  bash "$LINT" "$file" >/dev/null 2>&1 || got=$?
  if [ "$got" -eq "$want" ]; then pass=$((pass + 1)); else
    fail=$((fail + 1)); printf 'FAIL %-52s want rc %s, got %s\n' "$name" "$want" "$got" >&2; fi
}
# assert_rule <rule-substring> <file> <name> — a diagnostic naming <rule> is printed
assert_rule() {
  local rule="$1" file="$2" name="$3"
  if bash "$LINT" "$file" 2>/dev/null | grep -q "$rule"; then pass=$((pass + 1)); else
    fail=$((fail + 1)); printf 'FAIL %-52s expected a "%s" diagnostic\n' "$name" "$rule" >&2; fi
}
# assert_no_rule <rule-substring> <file> <name> — that rule must NOT be printed
assert_no_rule() {
  local rule="$1" file="$2" name="$3"
  if bash "$LINT" "$file" 2>/dev/null | grep -q "$rule"; then
    fail=$((fail + 1)); printf 'FAIL %-52s "%s" must not fire here\n' "$name" "$rule" >&2; else
    pass=$((pass + 1)); fi
}
# assert_count <want> <file> <name> — number of diagnostic lines (the edit guard
# counts these for its delta, so one-line-per-diagnostic is load-bearing)
assert_count() {
  local want="$1" file="$2" name="$3" got
  got="$(bash "$LINT" "$file" 2>/dev/null | grep -cE '[^[:space:]]')"; [ -n "$got" ] || got=0
  if [ "$got" -eq "$want" ]; then pass=$((pass + 1)); else
    fail=$((fail + 1)); printf 'FAIL %-52s want %s diagnostic line(s), got %s\n' "$name" "$want" "$got" >&2; fi
}

# --- yes-dash-arg: fires on a leading-dash arg, ignores a hash-leading one ---
F="$TMP/yes_dash.sh";  { printf '%s\n' "$hdr"; printf "yes '%s x' | head -n1\n" "$D"; } > "$F"
assert_rc   1            "$F" "yes-dash-arg quoted -> rc 1"
assert_rule yes-dash-arg "$F" "yes-dash-arg quoted -> named"
F="$TMP/yes_bare.sh";  { printf '%s\n' "$hdr"; printf 'yes %sn 3 | head -n1\n' "$D"; } > "$F"
assert_rule yes-dash-arg "$F" "yes-dash-arg unquoted dash flag -> named"
F="$TMP/yes_hash.sh";  { printf '%s\n' "$hdr"; printf "yes '# x' | head -n1\n"; } > "$F"
assert_rc   0            "$F" "yes hash-leading arg -> rc 0 (the fixed form)"
assert_no_rule yes-dash-arg "$F" "yes hash-leading arg -> not flagged"

# --- awk-interval: fires on a regex interval, ignores grep intervals + blocks ---
F="$TMP/awk_int.sh";   { printf '%s\n' "$hdr"; printf 'echo x | awk "/a%s2}/{print}"\n' "$B"; } > "$F"
assert_rc   1           "$F" "awk regex interval -> rc 1"
assert_rule awk-interval "$F" "awk regex interval -> named"
F="$TMP/grep_int.sh";  { printf '%s\n' "$hdr"; printf "grep -E '[0-9]%s4}' f\n" "$B"; } > "$F"
assert_rc   0           "$F" "grep ERE interval (portable) -> rc 0"
assert_no_rule awk-interval "$F" "grep ERE interval -> not flagged as awk"
F="$TMP/awk_block.sh"; { printf '%s\n' "$hdr"; printf "awk '%s print %s1 %s' f\n" "$B" '$' '}'; } > "$F"
assert_rc   0           "$F" "valid awk action block (no interval) -> rc 0"

# --- syntax (bash -n) ---
F="$TMP/syntax.sh";    { printf '%s\n' "$hdr"; printf 'if [ -z ]\n'; } > "$F"
assert_rc   1      "$F" "unterminated if -> rc 1"
assert_rule syntax "$F" "unterminated if -> syntax diagnostic"

# --- clean file: no diagnostics ---
F="$TMP/clean.sh";     { printf '%s\n' "$hdr"; printf 'echo ok\n'; } > "$F"
assert_rc    0 "$F" "clean file -> rc 0"
assert_count 0 "$F" "clean file -> zero diagnostics"

# --- multiple diagnostics: one diagnostic line each (delta-counting contract) ---
F="$TMP/multi.sh";     { printf '%s\n' "$hdr"; printf "yes '%s x' | head -n1\n" "$D"; printf 'echo y | awk "/b%s3}/{print}"\n' "$B"; } > "$F"
assert_rc    1 "$F" "two portability issues -> rc 1"
assert_count 2 "$F" "two portability issues -> two diagnostic lines"

# --- a missing file argument is skipped, not an error ---
assert_rc 0 "$TMP/does-not-exist.sh" "missing file arg -> rc 0 (skipped)"

printf 'shell-lint.test.sh: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
