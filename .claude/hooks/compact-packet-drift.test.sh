#!/usr/bin/env bash
# Regression tests for compact-packet-drift.sh (T1203, spec 007 US3.AC2; epic #166).
#
# The constitution-P2 pairing, both directions in one suite: an IN-SYNC control —
# the REAL repo's packet + profile — passes (no false fire), and a PLANTED drift on
# EVERY covered field fails naming exactly that field (the check fires, per field,
# never a prefix-only assertion). Profile-side drift (a row added to the profile,
# not the packet) and anchor rot (a restructured profile the extractors can no
# longer read) must also FAIL loud — a vacuous pass on unextractable input is the
# silently-dead-guard class. Plus the US3.AC3 entrypoint-declaration pins and the
# CI-wiring assertions (US3.AC2's "wired into standing verification").
#
# Each case copies the REAL .claude/PROJECT.md + .claude/PROJECT.compact.md into a
# throwaway dir, mutates one side, and runs the real check with that dir as CWD
# (the token-budget-check.test.sh idiom).
# Run: bash .claude/hooks/compact-packet-drift.test.sh
set -u
export LC_ALL=C

HOOKS="$(cd "$(dirname "$0")" && pwd)"
CHECK="$HOOKS/compact-packet-drift.sh"
REPO_ROOT="$(cd "$HOOKS/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
pass=0
fail=0

ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); printf 'FAIL %s\n' "$1" >&2; }

# run_check <dir> — run the real check with <dir> as CWD; combined output in $OUT,
# exit code in $GOT.
run_check() {
  GOT=0
  OUT="$( (cd "$1" && bash "$CHECK") 2>&1 )" || GOT=$?
}

# mkfixture <dir> — a fixture dir holding copies of the REAL profile + packet.
mkfixture() {
  mkdir -p "$1/.claude"
  cp "$REPO_ROOT/.claude/PROJECT.md" "$1/.claude/PROJECT.md"
  cp "$REPO_ROOT/.claude/PROJECT.compact.md" "$1/.claude/PROJECT.compact.md"
}

# expect_field_fail <case-label> <field> — after run_check: exit 1 AND the output
# names exactly that drifted field.
expect_field_fail() {
  if [ "$GOT" -eq 1 ]; then ok; else bad "$1 must exit 1 (got $GOT)"; fi
  if printf '%s' "$OUT" | grep -q "FAIL: field '$2'"; then
    ok
  else
    bad "$1 failure output must name field '$2'"
  fi
}

# --- A: the in-sync control — the REAL packet agrees with the REAL profile (run
#     from the repo root, the exact surface CI grades). ------------------------
run_check "$REPO_ROOT"
if [ "$GOT" -eq 0 ]; then ok; else bad "A in-sync real-tree control must pass (got $GOT): $OUT"; fi
if printf '%s' "$OUT" | grep -q 'compact-packet drift: OK'; then ok; else bad "A control must report OK"; fi

# --- B: planted PACKET drift, one case per covered scalar/set field — each
#     fails naming exactly its field. -----------------------------------------
B="$TMP/b"

mkfixture "$B"
sed -i.bak 's/^- Base branch: `main`/- Base branch: `develop`/' "$B/.claude/PROJECT.compact.md"
run_check "$B"
expect_field_fail "B base-branch drift" "base-branch"

mkfixture "$B"
sed -i.bak 's/^- Required check: `verify`/- Required check: `build`/' "$B/.claude/PROJECT.compact.md"
run_check "$B"
expect_field_fail "B required-check drift" "required-check"

mkfixture "$B"
sed -i.bak 's/^- Autonomy opt-in: `disabled`/- Autonomy opt-in: `enabled`/' "$B/.claude/PROJECT.compact.md"
run_check "$B"
expect_field_fail "B autonomy drift" "autonomy-opt-in"

mkfixture "$B"
sed -i.bak 's|^- Constitution: `memory/constitution.md`|- Constitution: `memory/rules.md`|' "$B/.claude/PROJECT.compact.md"
run_check "$B"
expect_field_fail "B constitution-path drift" "constitution-path"

mkfixture "$B"
sed -i.bak 's|creance-telemetry\.jsonl|other-telemetry.jsonl|' "$B/.claude/PROJECT.compact.md"
run_check "$B"
expect_field_fail "B telemetry-path drift" "telemetry-path"

mkfixture "$B"
sed -i.bak 's|`specs/008-fast-lane-workflow/spec.md`|`specs/009-imaginary/spec.md`|' "$B/.claude/PROJECT.compact.md"
run_check "$B"
expect_field_fail "B spec-paths drift" "spec-paths"
if printf '%s' "$OUT" | grep -q 'specs/008-fast-lane-workflow/spec.md'; then
  ok
else
  bad "B spec-paths failure must name the missing path"
fi

mkfixture "$B"
sed -i.bak 's|`specs/008-fast-lane-workflow/tasks.md`|`specs/009-imaginary/tasks.md`|' "$B/.claude/PROJECT.compact.md"
run_check "$B"
expect_field_fail "B tasks-paths drift" "tasks-paths"

mkfixture "$B"
sed -i.bak 's|`<type>: \[<task-id>\] <description>`|`<kind>: [<task-id>] <description>`|' "$B/.claude/PROJECT.compact.md"
run_check "$B"
expect_field_fail "B title-conventions drift" "title-conventions"

mkfixture "$B"
sed -i.bak 's|`<type>/<issue#>-<short-slug>`|`<type>/<short-slug>`|' "$B/.claude/PROJECT.compact.md"
run_check "$B"
expect_field_fail "B branch-convention drift" "branch-convention"

mkfixture "$B"
sed -i.bak 's|^- none (detail|- T999 imaginary blocked task (detail|' "$B/.claude/PROJECT.compact.md"
run_check "$B"
expect_field_fail "B blocked-tasks drift" "blocked-tasks"

mkfixture "$B"
sed -i.bak 's/^| `\[security-review pass\]` | true | sensitive-diff | both |/| `[security-review pass]` | false | sensitive-diff | both |/' "$B/.claude/PROJECT.compact.md"
run_check "$B"
expect_field_fail "B review-passes drift" "review-passes"

mkfixture "$B"
sed -i.bak 's|`\*\.sh` → `.claude/hooks/shell-lint.sh`|`*.sh` → `.claude/hooks/other-lint.sh`|' "$B/.claude/PROJECT.compact.md"
run_check "$B"
expect_field_fail "B checker-map drift" "checker-map"

# a dropped judgment-only invariant bullet changes the count but not the backstop
# set — invariant-count must fire on its own.
mkfixture "$B"
sed -i.bak '/^- Telemetry observes, never decides (P5)/d' "$B/.claude/PROJECT.compact.md"
run_check "$B"
expect_field_fail "B invariant-count drift" "invariant-count"

mkfixture "$B"
sed -i.bak 's|`agents-residency-check.sh`|`agents-residency-check-renamed.sh`|' "$B/.claude/PROJECT.compact.md"
run_check "$B"
expect_field_fail "B invariant-backstops drift" "invariant-backstops"
if printf '%s' "$OUT" | grep -q 'agents-residency-check.sh'; then
  ok
else
  bad "B invariant-backstops failure must name the drifted script"
fi

# --- C: PROFILE-side drift — the profile moves, the packet stays: a new
#     checker-map row and a new enforcement-mapping row appear only in the
#     profile copy. The check must fail; a summary that only tracks packet edits
#     would pass vacuously. ----------------------------------------------------
C="$TMP/c"
mkfixture "$C"
printf -- '- `*.py` → `.claude/hooks/py-lint.sh`\n' >> "$TMP/c-row.txt"
sed -i.bak '/^- `\*\.sh` → `\.claude\/hooks\/shell-lint\.sh`/r '"$TMP/c-row.txt" "$C/.claude/PROJECT.md"
run_check "$C"
expect_field_fail "C profile-side checker-map row" "checker-map"

mkfixture "$C"
printf '| A brand-new invariant | judgment | none yet — judgment-only |\n' > "$TMP/c-inv.txt"
sed -i.bak '/^| Maker-eval is observe-only/r '"$TMP/c-inv.txt" "$C/.claude/PROJECT.md"
run_check "$C"
expect_field_fail "C profile-side invariant row" "invariant-count"

# --- D: anchor rot fails LOUD, never a vacuous pass — a profile whose "## Paths"
#     heading was renamed yields zero extracted spec paths. --------------------
D="$TMP/d"
mkfixture "$D"
sed -i.bak 's/^## Paths$/## Locations/' "$D/.claude/PROJECT.md"
run_check "$D"
if [ "$GOT" -eq 1 ]; then ok; else bad "D renamed profile section must FAIL loud (got $GOT)"; fi
if printf '%s' "$OUT" | grep -q "could not extract"; then ok; else bad "D failure must say the extraction anchor rotted"; fi

# --- E: a missing packet (and a missing profile) FAIL loud naming the repair
#     target — the check never passes on absence. ------------------------------
E="$TMP/e"
mkfixture "$E"
rm "$E/.claude/PROJECT.compact.md"
run_check "$E"
if [ "$GOT" -eq 1 ] && printf '%s' "$OUT" | grep -q 'PROJECT.compact.md not found'; then
  ok
else
  bad "E missing packet must FAIL naming it (got $GOT)"
fi
mkfixture "$E"
rm "$E/.claude/PROJECT.md"
run_check "$E"
if [ "$GOT" -eq 1 ] && printf '%s' "$OUT" | grep -q 'PROJECT.md not found'; then
  ok
else
  bad "E missing profile must FAIL naming it (got $GOT)"
fi

# --- F: US3.AC3 — the workflow entrypoints' declared read sets name the packet
#     as the DEFAULT profile read and the full profile as an EXPLICIT escalation.
for skill in next-task pr-review triage intake; do
  sk="$REPO_ROOT/.claude/skills/$skill/SKILL.md"
  if grep -q 'PROJECT\.compact\.md' "$sk"; then
    ok
  else
    bad "F entrypoint $skill must name .claude/PROJECT.compact.md as the default profile read"
  fi
  if grep -qi 'escalat' "$sk"; then
    ok
  else
    bad "F entrypoint $skill must name the full-profile escalation explicitly"
  fi
done

# --- G: CI wiring (US3.AC2's "wired into standing verification, wiring
#     asserted"): the verify job actively RUNS the check and this test (the
#     token-budget-check.test.sh idiom, verify-job scope). ---------------------
CI="$REPO_ROOT/.github/workflows/ci.yml"
verify_steps() { awk '/^  [A-Za-z]/ { inblk = ($0 ~ /^  verify:/) } inblk { print }' "$CI"; }
if verify_steps | grep -qE '^[[:space:]]*run:[[:space:]]+bash[[:space:]]+\.claude/hooks/compact-packet-drift\.sh([[:space:]]|$)'; then
  ok
else
  bad "wiring: verify must RUN compact-packet-drift.sh (active run: step)"
fi
if verify_steps | grep -qE '^[[:space:]]*run:[[:space:]]+bash[[:space:]]+\.claude/hooks/compact-packet-drift\.test\.sh([[:space:]]|$)'; then
  ok
else
  bad "wiring: verify must RUN compact-packet-drift.test.sh (active run: step)"
fi

# --- H: the budget gate is ACTIVE (US3.AC1's same-diff activation): the
#     registry row for compact-packet gates, not defers. -----------------------
if grep -qE '^\| `compact-packet` \| `total` \| `[0-9]+` \| `active` \|' "$REPO_ROOT/.claude/context-budgets.md"; then
  ok
else
  bad "H the compact-packet budget row must be gating 'active' (US3.AC1)"
fi

printf 'compact-packet-drift.test.sh: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
