#!/usr/bin/env bash
# Regression tests for harness-manifest-fence.sh — the deterministic P5 fence over the
# generated harness manifest (T637, issue #233; the maker-eval-fence.test.sh idiom).
# The fence scans the tracked tree for the lock artifact's token (`HARNESS.lock`) and
# FAILs when it appears outside the generator/declaration/test allowlist. Each case
# runs the REAL fence against a throwaway git repo holding one planted fixture file,
# then asserts the exit code — proving the fence FIRES on a planted reference from a
# gate/tier/guard/selection/autonomy surface (never prose-only, constitution P2), does
# NOT false-fire on the sanctioned surfaces or the real tree, line-scopes CI (benign
# check/test wiring passes; a step that parses the lock fires), and fails CLOSED on an
# unlistable tree. Bash + git only, <5s; wired into the `verify` CI job.
# Run: bash .claude/hooks/harness-manifest-fence.test.sh
set -u

DIR="$(cd "$(dirname "$0")" && pwd)"
FENCE="$DIR/harness-manifest-fence.sh"
REPO_ROOT="$(cd "$DIR/../.." && pwd)"
CI="$REPO_ROOT/.github/workflows/ci.yml"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
pass=0
fail=0

# run_fence <expected-exit> <root> <name> [<must-contain>] — run the REAL fence with
# HARNESS_MANIFEST_FENCE_ROOT pointed at <root> and assert exit code (+ output text).
run_fence() {
  local want="$1" root="$2" name="$3" needle="${4:-}" got=0
  HARNESS_MANIFEST_FENCE_ROOT="$root" bash "$FENCE" > "$TMP/out" 2>&1 || got=$?
  if [ "$got" -ne "$want" ]; then
    fail=$((fail + 1))
    printf 'FAIL %-70s want exit %s, got %s\n' "$name" "$want" "$got" >&2
    return
  fi
  if [ -n "$needle" ] && ! grep -qF "$needle" "$TMP/out"; then
    fail=$((fail + 1))
    printf 'FAIL %-70s output does not contain %s\n' "$name" "$needle" >&2
    return
  fi
  pass=$((pass + 1))
}

# mkfix <dir> <relpath> <line> — a throwaway git repo holding ONE fixture file at
# <relpath> containing <line>, staged (the fence reads `git ls-files`, the index).
mkfix() {
  local d="$1" rel="$2" line="$3"
  mkdir -p "$d/$(dirname "$rel")"
  printf '%s\n' "$line" > "$d/$rel"
  git init -q -b main "$d"
  git -C "$d" config user.email t@example.com
  git -C "$d" config user.name test
  git -C "$d" add "$rel"
}

# addfix <dir> <relpath> <line> — one more staged fixture file in an existing repo.
addfix() {
  local d="$1" rel="$2" line="$3"
  mkdir -p "$d/$(dirname "$rel")"
  printf '%s\n' "$line" > "$d/$rel"
  git -C "$d" add "$rel"
}

REF='decide_gate() { jq .autonomy .claude/HARNESS.lock.json; }'

# --- the fence FIRES on a reference from each control-authority surface class ----
mkfix "$TMP/a" ".claude/hooks/autonomy-mode.sh" "$REF"
run_fence 1 "$TMP/a" "fires: an autonomy hook reading the lock" \
  "P5 FENCE VIOLATION: .claude/hooks/autonomy-mode.sh"

mkfix "$TMP/b" ".claude/workflows/gate-loop.js" "const lock = require('.claude/HARNESS.lock.json')"
run_fence 1 "$TMP/b" "fires: the gate script reading the lock"

mkfix "$TMP/c" ".claude/hooks/reconcile-task-selection.sh" "$REF"
run_fence 1 "$TMP/c" "fires: a selection hook reading the lock"

mkfix "$TMP/d" ".claude/MODELS.md" 'Tier rows are compiled into `.claude/HARNESS.lock.json`.'
run_fence 1 "$TMP/d" "fires: the model table (a tier surface) naming the lock"

mkfix "$TMP/e" ".claude/skills/next-task/SKILL.md" 'Read `.claude/HARNESS.lock.json` to pick the branch.'
run_fence 1 "$TMP/e" "fires: a workflow binding reading the lock"

# The basename-stem token also catches relative/renamed reference forms.
mkfix "$TMP/f" ".claude/hooks/guard.sh" 'cat "$ROOT/../HARNESS.lock.json"'
run_fence 1 "$TMP/f" "fires: a relative-path reference from the guard"

# The test allowlist names the two manifest harnesses exactly — an UNRELATED test
# file reading the lock still fires (tests run in the required `verify` job, so a
# glob exemption would let a future test's exit status consume the lock unfenced;
# PR #283 review finding).
mkfix "$TMP/k" ".claude/hooks/gate-reader.test.sh" 'jq .autonomy .claude/HARNESS.lock.json'
run_fence 1 "$TMP/k" "fires: an unrelated *.test.sh reading the lock (tests named, not globbed)" \
  "P5 FENCE VIOLATION: .claude/hooks/gate-reader.test.sh"

# The observe-only consumer allowance (T638/#234) is scoped to the status map BY NAME:
# a differently-named hook reading the lock is still the breach, so the allowance cannot
# be stretched into a general hooks exemption.
mkfix "$TMP/n" ".claude/hooks/status-summary.sh" 'jq .autonomy .claude/HARNESS.lock.json'
run_fence 1 "$TMP/n" "fires: a lock-reading hook that is NOT the sanctioned status map" \
  "P5 FENCE VIOLATION: .claude/hooks/status-summary.sh"

# --- the sanctioned surfaces do NOT fire ------------------------------------------
mkfix "$TMP/g" ".claude/hooks/harness-manifest.py" 'LOCK_PATH = ".claude/HARNESS.lock.json"'
addfix "$TMP/g" ".claude/HARNESS.lock.json" '{"schema_version": 1}'
addfix "$TMP/g" ".claude/EXTRACTION.md" '| `HARNESS.lock.json` | KEEP | the generated lock artifact |'
addfix "$TMP/g" "specs/001-x/tasks.md" '- [ ] T637 add `.claude/HARNESS.lock.json`'
addfix "$TMP/g" "specs/001-x/spec.md" 'AC1: `.claude/HARNESS.lock.json` exists'
addfix "$TMP/g" "specs/TASK_INDEX.md" '| T637 | strong | [ ] | | | add HARNESS.lock.json |'
addfix "$TMP/g" ".claude/hooks/harness-manifest.test.sh" 'grep schema_version .claude/HARNESS.lock.json'
# The sanctioned observe-only consumer (T638/#234): the status map reads the lock for its
# static facts and is itself P5-fenced, so it carries no control authority.
addfix "$TMP/g" ".claude/hooks/status-map.sh" 'LOCK=".claude/HARNESS.lock.json"'
addfix "$TMP/g" ".claude/hooks/status-map.test.sh" 'cat > "$d/.claude/HARNESS.lock.json"'
run_fence 0 "$TMP/g" "passes: generator + lock + cut-list + backlog/spec/index + tests + the observe-only status map"

# A token-free file is never a hit.
mkfix "$TMP/h" ".claude/hooks/guard.sh" 'echo no manifest reference here'
run_fence 0 "$TMP/h" "passes: a control-authority file with no lock reference"

# --- CI is line-scoped: the sanctioned wiring passes, a lock-parsing step fires ---
mkfix "$TMP/i" ".github/workflows/ci.yml" '#'
{
  printf '      # HARNESS.lock.json staleness wiring (comments are benign)\n'
  printf '      - name: Harness-manifest staleness check\n'
  printf '        run: python3 .claude/hooks/harness-manifest.py --check\n'
  printf '      - name: Harness-manifest tests\n'
  printf '        run: bash .claude/hooks/harness-manifest.test.sh\n'
} > "$TMP/i/.github/workflows/ci.yml"
git -C "$TMP/i" add .github/workflows/ci.yml
run_fence 0 "$TMP/i" "passes: CI's benign comment + check/test wiring lines"

printf '        run: python3 .claude/hooks/harness-manifest.py --check && jq . .claude/HARNESS.lock.json\n' \
  >> "$TMP/i/.github/workflows/ci.yml"
git -C "$TMP/i" add .github/workflows/ci.yml
run_fence 1 "$TMP/i" "fires: a CI step that parses the lock (trailing command)"

# --- fail-closed: an unlistable/empty tree exits 2, never a silent pass ----------
mkdir -p "$TMP/j"
run_fence 2 "$TMP/j" "fail-closed: an empty tree cannot be fenced"

# --- the real tree passes (no control-authority path references the lock) --------
run_fence 0 "$REPO_ROOT" "real tree: fence passes"

# --- CI wiring: the fence and these tests run in verify (constitution P2) --------
for step in \
  'run: bash \.claude/hooks/harness-manifest-fence\.sh' \
  'run: bash \.claude/hooks/harness-manifest-fence\.test\.sh'
do
  if grep -qE "^ +$step[[:space:]]*$" "$CI"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL CI wiring: no active step matching %s in ci.yml\n' "$step" >&2
  fi
done

# ---------------------------------------------------------------------------------
echo "harness-manifest-fence tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
