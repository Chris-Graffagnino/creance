#!/usr/bin/env bash
# Tests for backlog-loop-select.sh — the [backlog-loop]'s real selection binding
# (T905, spec 004 US1.AC7; neutral model: .claude/workflow/backlog-loop.md).
#
# Proves every rule of the documented selection contract against fixture tasks
# trees (never the live backlog), each case per-instance (exact stdout equality,
# never a prefix/anywhere grep — AGENTS.md falsification rule / next-task §5):
#   * lowest unchecked id wins, across MULTIPLE live tasks files;
#   * checked (`- [x]`) ids are never candidates;
#   * excluded arguments are skipped, whole-id (T90 never excludes T901);
#   * a "Blocked / owner-only tasks" bullet STARTING with an id excludes it —
#     in a tasks file AND in the profile — while a prose mention inside another
#     bullet ("- none. (T101 …)", the live profile's shape) does NOT;
#   * a `Blocked by` clause gates on EVERY referenced id being checked: bare
#     ids, en-dash and hyphen ranges, the clause wrapped across continuation
#     lines (the live T905 shape); an unknown referenced id reads UNMET (fail
#     closed); a met clause selects;
#   * a drained backlog prints nothing (exit 0); NO readable tasks file at all
#     is a LOUD exit 1 (fail closed — never misread as drained);
#   * wiring (P2): the `verify` job ACTIVELY runs this test.
# Bash only, <1s. Run: bash .claude/hooks/backlog-loop-select.test.sh
set -u

HOOKS="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HOOKS/backlog-loop-select.sh"
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

# mkroot <name> — a fresh fixture repo root; callers add specs/<dir>/tasks.md
# and .claude/PROJECT.md under it. run_select executes from inside it.
mkroot() {
  ROOT="$TMP/$1"
  mkdir -p "$ROOT/.claude" "$ROOT/specs/aaa" "$ROOT/specs/bbb"
  printf '# profile\n' > "$ROOT/.claude/PROJECT.md"
}
run_select() { # [excluded ids...] -> OUT/RC
  RC=0
  OUT="$( (cd "$ROOT" && bash "$SCRIPT" "$@") 2>/dev/null)" || RC=$?
}

# ── 1. lowest unchecked wins, across files; checked ids never selected.
mkroot c1
cat > "$ROOT/specs/aaa/tasks.md" <<'EOF'
# Tasks A
- [x] T101 [cheap] done already (US1)
- [ ] T105 [cheap] later work (US1)
EOF
cat > "$ROOT/specs/bbb/tasks.md" <<'EOF'
# Tasks B
- [ ] T103 [cheap] the lowest open task (US1)
- [ ] T110 [cheap] even later (US1)
EOF
run_select
assert_eq "lowest unchecked across files" "$OUT" "T103"
assert_eq "clean selection exits 0" "$RC" "0"

# ── 2. exclusions: args are skipped, whole-id only.
run_select T103
assert_eq "excluded id is skipped -> next lowest" "$OUT" "T105"
run_select T103 T105
assert_eq "multiple exclusions" "$OUT" "T110"
run_select T10 T1
assert_eq "whole-id: excluding T10/T1 never excludes T103" "$OUT" "T103"

# ── 3. blocked lists: a section bullet STARTING with an id excludes it (tasks
#      file and profile); a prose mention in another bullet does not.
mkroot c3
cat > "$ROOT/specs/aaa/tasks.md" <<'EOF'
# Tasks A
- [ ] T201 [cheap] blocked below (US1)
- [ ] T202 [cheap] open (US1)

## Blocked / owner-only tasks (never auto-start — surface them instead)

- T201 — owner-only credential rotation
EOF
run_select
assert_eq "tasks-file blocked bullet excludes its id" "$OUT" "T202"

mkroot c3b
cat > "$ROOT/specs/aaa/tasks.md" <<'EOF'
# Tasks A
- [ ] T201 [cheap] open (US1)
- [ ] T202 [cheap] open (US1)
EOF
cat > "$ROOT/.claude/PROJECT.md" <<'EOF'
# profile

## Blocked / owner-only tasks (never auto-start — surface them instead)
- T201 — waiting on the owner

## Next section
EOF
run_select
assert_eq "profile blocked bullet excludes its id" "$OUT" "T202"

mkroot c3c
cat > "$ROOT/specs/aaa/tasks.md" <<'EOF'
# Tasks A
- [ ] T101 [cheap] open (US1)

## Blocked / owner-only tasks (never auto-start — surface them instead)

- none. (T101 carries an owner-overridable design default — see the note.)
EOF
run_select
assert_eq "prose mention in a 'none' bullet does NOT block" "$OUT" "T101"

# ── 4. dependencies: `Blocked by` gates on every referenced id being checked.
mkroot c4
cat > "$ROOT/specs/aaa/tasks.md" <<'EOF'
# Tasks A
- [x] T301 [cheap] landed (US1)
- [x] T302 [cheap] landed (US1)
- [ ] T303 [cheap] needs both, en-dash range wrapped across lines. Blocked by
      T301–T302 (US1)
- [ ] T304 [cheap] open fallback (US1)
EOF
run_select
assert_eq "met en-dash range (wrapped continuation line) selects" "$OUT" "T303"

mkroot c4b
cat > "$ROOT/specs/aaa/tasks.md" <<'EOF'
# Tasks A
- [x] T301 [cheap] landed (US1)
- [ ] T302 [cheap] the LOWEST id, but its range dep is unmet. Blocked by T301-T310 (US1)
- [ ] T310 [cheap] the open dependency itself (US1)
EOF
run_select
assert_eq "unmet hyphen range skips the lowest id to its open dependency" "$OUT" "T310"

mkroot c4c
cat > "$ROOT/specs/aaa/tasks.md" <<'EOF'
# Tasks A
- [x] T301 [cheap] landed (US1)
- [ ] T303 [cheap] bare-id dep met. Blocked by T301 (US1)
EOF
run_select
assert_eq "met bare-id dependency selects" "$OUT" "T303"

mkroot c4d
cat > "$ROOT/specs/aaa/tasks.md" <<'EOF'
# Tasks A
- [ ] T303 [cheap] dep on an id that exists NOWHERE. Blocked by T999 (US1)
- [ ] T304 [cheap] open fallback (US1)
EOF
run_select
assert_eq "unknown referenced id reads UNMET (fail closed)" "$OUT" "T304"

# ── 5. drained backlog: nothing on stdout, exit 0 (stop condition (b) is the
#      loop's to declare — the selector just reports no candidate).
mkroot c5
cat > "$ROOT/specs/aaa/tasks.md" <<'EOF'
# Tasks A
- [x] T101 [cheap] done (US1)
EOF
run_select
assert_eq "drained: empty stdout" "$OUT" ""
assert_eq "drained: exit 0" "$RC" "0"

# ── 6. NO readable tasks file at all: LOUD exit 1 — a selector that cannot see
#      the backlog fails closed, never reports a drained backlog it never read.
mkroot c6
rm -rf "$ROOT/specs"
run_select
assert_eq "no tasks files: loud exit 1" "$RC" "1"
assert_eq "no tasks files: nothing on stdout" "$OUT" ""

# ── Wiring (P2): the `verify` job ACTIVELY runs this test.
verify_steps() { awk '/^  [A-Za-z]/ { inblk = ($0 ~ /^  verify:/) } inblk { print }' "$CI"; }
if verify_steps | grep -qE '^[[:space:]]*run:[[:space:]]+bash[[:space:]]+\.claude/hooks/backlog-loop-select\.test\.sh([[:space:]]|$)'; then
  ok
else
  bad "verify must RUN backlog-loop-select.test.sh (active run: step)"
fi

printf 'backlog-loop-select.test.sh: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
