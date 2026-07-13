#!/usr/bin/env bash
# Regression tests for harness-manifest.py — the generated harness manifest's
# generator + staleness gate (T637, issue #233). Two-sided falsification (constitution
# P2/P3): a planted drift in EACH covered surface — reviewer roster, review-pass set,
# guard-rule list, edit-time checker map, autonomy opt-in — independently flips the
# check red NAMING that surface's manifest field (per-surface assertions, never a
# single match anywhere), and a clean control passes; plus generator determinism
# (byte-identical repeated runs), fail-loud on a missing lock and on anchor rot, the
# regeneration command named in every staleness failure, and the CI wiring for all
# four steps (check, these tests, the P5 fence, its tests). Each case runs the REAL
# generator against a throwaway fixture tree holding copies of the real source files
# (the generator resolves paths relative to CWD). Bash + python3, <5s; wired into the
# `verify` CI job (.github/workflows/ci.yml).
# Run: bash .claude/hooks/harness-manifest.test.sh
set -u

DIR="$(cd "$(dirname "$0")" && pwd)"
GEN="$DIR/harness-manifest.py"
REPO_ROOT="$(cd "$DIR/../.." && pwd)"
CI="$REPO_ROOT/.github/workflows/ci.yml"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
pass=0
fail=0

ok() { pass=$((pass + 1)); }
bad() {
  fail=$((fail + 1))
  printf 'FAIL %s\n' "$1" >&2
}

SOURCES=".claude/PROJECT.md .claude/MODELS.md .claude/README.md .claude/workflow/README.md .claude/workflow/gate-loop.md memory/constitution.md"

# mkfixture <dir> — a throwaway tree holding copies of the REAL source files in their
# real relative layout (so a fixture edit can never touch the repo's own files).
mkfixture() {
  local d="$1" s
  for s in $SOURCES; do
    mkdir -p "$d/$(dirname "$s")"
    cp "$REPO_ROOT/$s" "$d/$s"
  done
}

# edit_fixture <file> <sed-script> — portable in-place edit (no `sed -i`: BSD/GNU
# divergence), failing the test run loud if the edit matched nothing.
edit_fixture() {
  local f="$1" script="$2"
  sed "$script" "$f" > "$f.tmp" || exit 1
  if cmp -s "$f" "$f.tmp"; then
    bad "fixture edit matched nothing: $script on $f"
  fi
  mv "$f.tmp" "$f"
}

# run_gen <dir> <mode> — run the real generator from <dir>; stdout+stderr to $TMP/out.
run_gen() { ( cd "$1" && python3 "$GEN" "$2" ) > "$TMP/out" 2>&1; }

# expect <want-exit> <got-exit> <must-contain> <name> — exit code + output assertion
# ("" skips the content check).
expect() {
  local want="$1" got="$2" needle="$3" name="$4"
  if [ "$got" -ne "$want" ]; then
    bad "$name: want exit $want, got $got ($(head -3 "$TMP/out" | tr '\n' ' '))"
    return
  fi
  if [ -n "$needle" ] && ! grep -qF "$needle" "$TMP/out"; then
    bad "$name: output does not contain '$needle'"
    return
  fi
  ok
}

# --- control: a clean fixture writes, then checks green -------------------------
F="$TMP/clean"; mkfixture "$F"
got=0; run_gen "$F" --write || got=$?
expect 0 "$got" "wrote" "control: --write succeeds on a clean fixture"
got=0; run_gen "$F" --check || got=$?
expect 0 "$got" "OK" "control: --check passes on a freshly written lock"

# --- determinism: two runs on a clean tree are byte-identical -------------------
cp "$F/.claude/HARNESS.lock.json" "$TMP/first.json"
got=0; run_gen "$F" --write || got=$?
if [ "$got" -eq 0 ] && cmp -s "$TMP/first.json" "$F/.claude/HARNESS.lock.json"; then
  ok
else
  bad "determinism: repeated --write runs are not byte-identical"
fi

# --- the lock carries an explicit schema_version --------------------------------
if grep -q '"schema_version": 1' "$F/.claude/HARNESS.lock.json"; then
  ok
else
  bad "lock: no explicit schema_version"
fi

# --- multi-role binding rows: every bracketed role in a row's bold cell reaches
#     adapter_bindings.roles, not only the first match (PR #283 review finding) ---
for role in '[strong tier]' '[cheap tier]' '[security-review pass]'; do
  if python3 -c "
import json, sys
roles = json.load(open('$TMP/clean/.claude/HARNESS.lock.json'))['adapter_bindings']['roles']
sys.exit(0 if '$role' in roles else 1)
"; then
    ok
  else
    bad "adapter bindings: combined-row role $role missing from adapter_bindings.roles"
  fi
done

# --- missing lock fails loud, naming the regeneration command -------------------
F="$TMP/missing"; mkfixture "$F"
got=0; run_gen "$F" --check || got=$?
expect 1 "$got" "python3 .claude/hooks/harness-manifest.py --write" \
  "missing lock: --check fails naming the regeneration command"

# --- per-surface planted drift: each surface INDEPENDENTLY flips the check red,
#     naming that surface's manifest field (and the regeneration command) ----------
# plant_case <name> <field> <file> <sed-script>
plant_case() {
  local name="$1" field="$2" file="$3" script="$4"
  local d="$TMP/drift-$field"
  mkfixture "$d"
  run_gen "$d" --write || { bad "$name: fixture --write failed"; return; }
  edit_fixture "$d/$file" "$script"
  local got=0; run_gen "$d" --check || got=$?
  expect 1 "$got" "field '$field' drifted" "$name"
  if grep -qF "python3 .claude/hooks/harness-manifest.py --write" "$TMP/out"; then
    ok
  else
    bad "$name: staleness failure does not name the regeneration command"
  fi
}

plant_case "drift: reviewer-roster tier change fails naming reviewer_roster" \
  "reviewer_roster" ".claude/workflow/gate-loop.md" \
  's#constitution-auditor.md` | strong | `always`#constitution-auditor.md` | cheap | `always`#'

plant_case "drift: review-pass condition change fails naming review_passes" \
  "review_passes" ".claude/PROJECT.md" \
  's#| true | sensitive-diff |#| true | always |#'

plant_case "drift: guard-rule text change fails naming guard_rules" \
  "guard_rules" ".claude/workflow/README.md" \
  's#Staging the entire tree at once#Staging the entire tree at will#'

plant_case "drift: edit-time checker change fails naming edit_time_checks" \
  "edit_time_checks" ".claude/PROJECT.md" \
  '/^- `\*\.sh`/ s#hooks/shell-lint\.sh#hooks/other-lint.sh#'

plant_case "drift: autonomy opt-in flip fails naming autonomy" \
  "autonomy" ".claude/PROJECT.md" \
  's#`autonomy-opt-in: disabled`#`autonomy-opt-in: enabled`#'

# --- anchor rot fails LOUD (never a silently empty field): renaming a source
#     section makes the GENERATOR itself fail naming the unextractable field ------
F="$TMP/anchor-rot"; mkfixture "$F"
run_gen "$F" --write || bad "anchor-rot: fixture --write failed"
edit_fixture "$F/.claude/PROJECT.md" 's@^## Review passes$@## Renamed passes@'
got=0; run_gen "$F" --check || got=$?
expect 1 "$got" "could not extract 'review-passes'" \
  "anchor rot: a renamed source section fails loud naming the field"

# --- a failed regeneration preserves the committed lock (PR #283 review finding):
#     --write must not truncate the existing artifact before generation succeeds ----
F="$TMP/write-fail"; mkfixture "$F"
run_gen "$F" --write || bad "write-fail: fixture --write failed"
cp "$F/.claude/HARNESS.lock.json" "$TMP/pre-fail.json"
edit_fixture "$F/.claude/PROJECT.md" 's@^## Review passes$@## Renamed passes@'
got=0; run_gen "$F" --write || got=$?
if [ "$got" -ne 0 ] && cmp -s "$TMP/pre-fail.json" "$F/.claude/HARNESS.lock.json"; then
  ok
else
  bad "write-fail: a failed --write must leave the existing lock byte-identical (exit $got)"
fi

# --- a stale lock with a valid non-object JSON root (e.g. [] or null) gets the
#     stale-manifest diagnostic + regeneration command, never a crash (PR #283) ----
for root in '[]' 'null'; do
  F="$TMP/nonobject-$(echo "$root" | tr -d '[]')"; mkfixture "$F"
  run_gen "$F" --write || bad "non-object root $root: fixture --write failed"
  printf '%s\n' "$root" > "$F/.claude/HARNESS.lock.json"
  got=0; run_gen "$F" --check || got=$?
  expect 1 "$got" "stale relative to its source-of-truth docs" \
    "non-object lock root $root: --check fails with the stale diagnostic"
  if grep -qF "python3 .claude/hooks/harness-manifest.py --write" "$TMP/out" \
    && ! grep -q "Traceback" "$TMP/out"; then
    ok
  else
    bad "non-object lock root $root: expected the regeneration command and no traceback"
  fi
done

# --- the real repo's committed lock is fresh (the same assertion CI runs) --------
got=0; run_gen "$REPO_ROOT" --check || got=$?
expect 0 "$got" "OK" "real tree: the committed lock matches its sources"

# --- CI wiring: all four steps run in verify (a check nothing runs is the
#     silently-dead-machinery class, constitution P2) ------------------------------
for step in \
  'run: python3 \.claude/hooks/harness-manifest\.py --check' \
  'run: bash \.claude/hooks/harness-manifest\.test\.sh' \
  'run: bash \.claude/hooks/harness-manifest-fence\.sh' \
  'run: bash \.claude/hooks/harness-manifest-fence\.test\.sh'
do
  if grep -qE "^ +$step[[:space:]]*$" "$CI"; then
    ok
  else
    bad "CI wiring: no active step matching '$step' in .github/workflows/ci.yml"
  fi
done

# ---------------------------------------------------------------------------------
echo "harness-manifest tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
