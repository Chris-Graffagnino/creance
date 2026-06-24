#!/usr/bin/env bash
# Regression tests for spec-lint.sh (spec 002 US2.AC3, task T704). Proves the
# deterministic spec-content lint FIRES on each of the three planted smells
# (empty AC, a US with zero ACs, a verbatim within-story duplicate) and does NOT
# false-fire on a clean spec — the constitution-P2 "machinery proves it is live"
# discipline, same as guard.test.sh / shell-lint.test.sh. Also pins the behaviours
# the lint's value depends on: a duplicate detected ACROSS wrapped continuation
# lines (so the lint reads whole ACs, not first lines), within-story scoping (a
# cross-story repeat is NOT a duplicate), and one diagnostic line per smell. Ends
# with the CI-wiring assertion (the silent-death backstop): the lint and this test
# must be ACTIVE `run: bash` steps in the required `verify` job.
# Needs only bash + awk; runs in <1s; wired into the `verify` CI job.
# Run: bash .claude/hooks/spec-lint.test.sh
set -u

LINT="$(cd "$(dirname "$0")" && pwd)/spec-lint.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
pass=0
fail=0

# assert_rc <want-rc> <file> <name>
assert_rc() {
  local want="$1" file="$2" name="$3" got=0
  bash "$LINT" "$file" >/dev/null 2>&1 || got=$?
  if [ "$got" -eq "$want" ]; then pass=$((pass + 1)); else
    fail=$((fail + 1)); printf 'FAIL %-54s want rc %s, got %s\n' "$name" "$want" "$got" >&2; fi
}
# assert_rule <rule-substring> <file> <name> — a diagnostic naming <rule> is printed
assert_rule() {
  local rule="$1" file="$2" name="$3"
  if bash "$LINT" "$file" 2>/dev/null | grep -q "$rule"; then pass=$((pass + 1)); else
    fail=$((fail + 1)); printf 'FAIL %-54s expected a "%s" diagnostic\n' "$name" "$rule" >&2; fi
}
# assert_no_rule <rule-substring> <file> <name> — that rule must NOT be printed
assert_no_rule() {
  local rule="$1" file="$2" name="$3"
  if bash "$LINT" "$file" 2>/dev/null | grep -q "$rule"; then
    fail=$((fail + 1)); printf 'FAIL %-54s "%s" must not fire here\n' "$name" "$rule" >&2; else
    pass=$((pass + 1)); fi
}
# assert_count <want> <file> <name> — number of diagnostic lines (one per smell)
assert_count() {
  local want="$1" file="$2" name="$3" got
  got="$(bash "$LINT" "$file" 2>/dev/null | grep -cE '[^[:space:]]')"; [ -n "$got" ] || got=0
  if [ "$got" -eq "$want" ]; then pass=$((pass + 1)); else
    fail=$((fail + 1)); printf 'FAIL %-54s want %s diagnostic line(s), got %s\n' "$name" "$want" "$got" >&2; fi
}

# --- empty-ac: an AC bullet with no criterion text (bare and trailing-space) ---
F="$TMP/empty.md"; cat > "$F" <<'SPEC'
# Spec
## User stories
### US1 — story with an empty criterion

**Acceptance Criteria**
- AC1: A perfectly good criterion.
- AC2:
- AC3:
SPEC
assert_rc      1        "$F" "empty-ac -> rc 1"
assert_rule    empty-ac "$F" "empty-ac -> named"
assert_no_rule zero-acs "$F" "empty-ac story has ACs -> not zero-acs"
assert_count   2        "$F" "two empty ACs -> two diagnostics"

# --- zero-acs: a US with no AC bullets, and a US with only the marker ---
F="$TMP/zero.md"; cat > "$F" <<'SPEC'
# Spec
## User stories
### US1 — narrative only, no criteria

As a user, I want a thing, but the criteria are missing.

### US2 — marker but no bullets

**Acceptance Criteria**
SPEC
assert_rc    1        "$F" "zero-acs -> rc 1"
assert_rule  zero-acs "$F" "zero-acs -> named"
assert_count 2        "$F" "two storyless USs -> two diagnostics"

# --- duplicate-ac: two ACs with identical text in the SAME story ---
F="$TMP/dup.md"; cat > "$F" <<'SPEC'
# Spec
## User stories
### US1 — has a verbatim duplicate

**Acceptance Criteria**
- AC1: The system records exactly one entry.
- AC2: An unrelated, distinct criterion.
- AC3: The system records exactly one entry.
SPEC
assert_rc      1            "$F" "duplicate-ac -> rc 1"
assert_rule    duplicate-ac "$F" "duplicate-ac -> named"
assert_count   1            "$F" "one duplicate pair -> one diagnostic"

# --- duplicate-ac across WRAPPED continuation lines (reads whole ACs) ---
F="$TMP/dup_wrap.md"; cat > "$F" <<'SPEC'
# Spec
## User stories
### US1 — wrapped duplicate

**Acceptance Criteria**
- AC1: The reviewer reads the full current spec
      and not merely the diff under review.
- AC2: The reviewer reads the full current spec
      and not merely the diff under review.
SPEC
assert_rc   1            "$F" "wrapped duplicate -> rc 1"
assert_rule duplicate-ac "$F" "wrapped duplicate -> named (continuation joined)"

# --- duplicate-ac is WITHIN-story: a cross-story repeat must NOT fire ---
F="$TMP/cross.md"; cat > "$F" <<'SPEC'
# Spec
## User stories
### US1 — first story

**Acceptance Criteria**
- AC1: A criterion that recurs in another story.

### US2 — second story

**Acceptance Criteria**
- AC1: A criterion that recurs in another story.
SPEC
assert_rc      0            "$F" "cross-story repeat -> rc 0"
assert_no_rule duplicate-ac "$F" "cross-story repeat -> not a duplicate"

# --- near-duplicate (distinct text) must NOT fire ---
F="$TMP/near.md"; cat > "$F" <<'SPEC'
# Spec
## User stories
### US1 — near but distinct

**Acceptance Criteria**
- AC1: The system stores data.
- AC2: The system stores data securely.
SPEC
assert_rc      0            "$F" "near-duplicate -> rc 0"
assert_no_rule duplicate-ac "$F" "near-duplicate -> not flagged"

# --- clean multi-story spec (wrapped ACs, multiple USs): zero diagnostics ---
F="$TMP/clean.md"; cat > "$F" <<'SPEC'
# Spec — Clean
## Overview
Prose that is not a user story.
## Non-goals
- A non-AC bullet outside any story.
## User stories
### US1 — first

**Acceptance Criteria**
- AC1: A criterion whose text wraps onto
      a second, indented line.
- AC2: A second, distinct criterion.

### US2 — second

**Acceptance Criteria**
- AC1: Only one criterion here, and it is fine.
SPEC
assert_rc    0 "$F" "clean spec -> rc 0"
assert_count 0 "$F" "clean spec -> zero diagnostics"

# --- all three smells in one file: one diagnostic line each ---
F="$TMP/multi.md"; cat > "$F" <<'SPEC'
# Spec
## User stories
### US1 — empty and duplicate

**Acceptance Criteria**
- AC1: Shared criterion text.
- AC2:
- AC3: Shared criterion text.

### US2 — zero ACs

As a user, I want a thing.
SPEC
assert_rc    1 "$F" "three smells -> rc 1"
assert_count 3 "$F" "empty + duplicate + zero-acs -> three diagnostics"

# --- a missing file argument is skipped, not an error (cf. shell-lint.sh) ---
assert_rc 0 "$TMP/does-not-exist.md" "missing file arg -> rc 0 (skipped)"

# --- the lint must not false-fire on the REAL live specs (CI runs it on them).
#     Lint ALL live specs in ONE multi-arg invocation (the glob is unquoted so it
#     word-splits into one path per file); require >=1 match so this can never pass
#     vacuously on an empty glob (the EV-04 "green-because-skipped" trap). ---
REPO="$(cd "$(dirname "$0")" && pwd)/../.."
live_count=$(ls "$REPO"/specs/*/spec.md 2>/dev/null | grep -c .)
live_rc=0
bash "$LINT" "$REPO"/specs/*/spec.md >/dev/null 2>&1 || live_rc=$?
if [ "$live_count" -ge 1 ] && [ "$live_rc" -eq 0 ]; then pass=$((pass + 1)); else
  fail=$((fail + 1)); printf 'FAIL %-54s %s spec(s), want rc 0, got %s\n' "live specs -> no false positive" "$live_count" "$live_rc" >&2; fi

# --- CI wiring (the silent-death backstop): the lint and this test are only live
#     if the REQUIRED `verify` job actually RUNS them. Scope to the verify job body
#     and require an ACTIVE `run: bash <script>` step (cf. agents-residency-check.test.sh).
CI="$(cd "$(dirname "$0")" && pwd)/../../.github/workflows/ci.yml"
verify_steps() { awk '/^  [A-Za-z]/ { inblk = ($0 ~ /^  verify:/) } inblk { print }' "$CI"; }
runs_in_verify() { verify_steps | grep -qE "^[[:space:]]*run:[[:space:]]+bash[[:space:]]+$1([[:space:]]|\$)"; }
if runs_in_verify '\.claude/hooks/spec-lint\.sh'; then pass=$((pass + 1)); else
  fail=$((fail + 1)); printf 'FAIL %-54s verify must RUN spec-lint.sh (active run: step)\n' "wiring: lint is an active verify step" >&2; fi
if runs_in_verify '\.claude/hooks/spec-lint\.test\.sh'; then pass=$((pass + 1)); else
  fail=$((fail + 1)); printf 'FAIL %-54s verify must RUN spec-lint.test.sh (active run: step)\n' "wiring: test is an active verify step" >&2; fi

printf 'spec-lint.test.sh: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
