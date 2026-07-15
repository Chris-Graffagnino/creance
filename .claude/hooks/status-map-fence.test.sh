#!/usr/bin/env bash
# Regression tests for status-map-fence.sh — the deterministic P5 fence over the harness
# status map (T638, issue #234; the harness-manifest-fence.test.sh idiom).
#
# The fence scans the tracked tree for the map's command name (`status-map`) and FAILs when
# it appears outside the map/declaration/test allowlist. Each case runs the REAL fence
# against a throwaway git repo holding one planted fixture file, then asserts the exit code
# — proving the fence FIRES on a planted reference from a gate/tier/guard/selection/autonomy
# surface (never prose-only — issue #234 criterion 5 FAILs a fence with no planted-reference
# test), does NOT false-fire on the sanctioned surfaces or the real tree, line-scopes CI
# (benign test/fence wiring passes; a step that branches on the map's output fires), and
# fails CLOSED on an unlistable tree. Bash + git only, <5s; wired into the `verify` CI job.
# Run: bash .claude/hooks/status-map-fence.test.sh
set -u

DIR="$(cd "$(dirname "$0")" && pwd)"
FENCE="$DIR/status-map-fence.sh"
REPO_ROOT="$(cd "$DIR/../.." && pwd)"
CI="$REPO_ROOT/.github/workflows/ci.yml"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
pass=0
fail=0

# run_fence <expected-exit> <root> <name> [<must-contain>] — run the REAL fence with
# STATUS_MAP_FENCE_ROOT pointed at <root> and assert exit code (+ output text).
run_fence() {
  local want="$1" root="$2" name="$3" needle="${4:-}" got=0
  STATUS_MAP_FENCE_ROOT="$root" bash "$FENCE" > "$TMP/out" 2>&1 || got=$?
  if [ "$got" -ne "$want" ]; then
    fail=$((fail + 1))
    printf 'FAIL %-72s want exit %s, got %s\n' "$name" "$want" "$got" >&2
    return
  fi
  if [ -n "$needle" ] && ! grep -qF -- "$needle" "$TMP/out"; then
    fail=$((fail + 1))
    printf 'FAIL %-72s output does not contain %s\n' "$name" "$needle" >&2
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

# The archetypal breach: a decision path branching on the map's best-effort output.
REF='bash .claude/hooks/status-map.sh | grep -q "autonomy opt-in: enabled" && promote'

# --- the fence FIRES on a reference from each control-authority surface class ----
mkfix "$TMP/a" ".claude/hooks/autonomy-mode.sh" "$REF"
run_fence 1 "$TMP/a" "fires: an autonomy hook consuming the map" \
  "P5 FENCE VIOLATION: .claude/hooks/autonomy-mode.sh"

mkfix "$TMP/b" ".claude/workflows/gate-loop.js" "const s = sh('.claude/hooks/status-map.sh')"
run_fence 1 "$TMP/b" "fires: the gate script consuming the map"

mkfix "$TMP/c" ".claude/hooks/reconcile-task-selection.sh" "$REF"
run_fence 1 "$TMP/c" "fires: a selection hook consuming the map"

mkfix "$TMP/d" ".claude/hooks/guard.sh" "$REF"
run_fence 1 "$TMP/d" "fires: the guard consuming the map"

mkfix "$TMP/e" ".claude/MODELS.md" 'Resolve the tier from `status-map.sh` output.'
run_fence 1 "$TMP/e" "fires: the model table (a tier surface) naming the map"

mkfix "$TMP/f" ".claude/skills/next-task/SKILL.md" 'Run `status-map.sh` to decide the branch.'
run_fence 1 "$TMP/f" "fires: a workflow binding consuming the map"

# The basename-stem token also catches relative/renamed reference forms.
mkfix "$TMP/g" ".claude/hooks/backlog-loop-select.sh" 'sh "$ROOT/../status-map.sh"'
run_fence 1 "$TMP/g" "fires: a relative-path reference from the backlog loop"

# The test allowlist names the two status-map harnesses exactly — an UNRELATED test file
# consuming the map still fires (tests run in the required `verify` job, so a glob
# exemption would let a future test's exit status consume the map unfenced; PR #283).
mkfix "$TMP/h" ".claude/hooks/gate-reader.test.sh" 'bash .claude/hooks/status-map.sh | grep verify'
run_fence 1 "$TMP/h" "fires: an unrelated *.test.sh consuming the map (tests named, not globbed)" \
  "P5 FENCE VIOLATION: .claude/hooks/gate-reader.test.sh"

# --- the sanctioned surfaces do NOT fire ------------------------------------------
mkfix "$TMP/i" ".claude/hooks/status-map.sh" '# status-map.sh — the orientation map'
addfix "$TMP/i" ".claude/hooks/status-map-fence.sh" "MAP_TOKEN='status-map'"
addfix "$TMP/i" ".claude/hooks/status-map.test.sh" 'bash status-map.sh > out'
addfix "$TMP/i" ".claude/hooks/status-map-fence.test.sh" 'bash status-map-fence.sh'
addfix "$TMP/i" ".claude/EXTRACTION.md" '| `hooks/status-map.sh` | KEEP | the orientation map |'
addfix "$TMP/i" ".claude/README.md" 'Orientation: `bash .claude/hooks/status-map.sh`.'
addfix "$TMP/i" "specs/001-x/tasks.md" '- [ ] T638 add the status-map command'
addfix "$TMP/i" "specs/001-x/spec.md" 'AC1: `status-map.sh` prints Markdown'
addfix "$TMP/i" "specs/TASK_INDEX.md" '| T638 | strong | [ ] | | | status-map |'
run_fence 0 "$TMP/i" "passes: the map + fence + tests + cut-list + doc pointer + backlog/spec/index"

# A token-free file is never a hit.
mkfix "$TMP/j" ".claude/hooks/guard.sh" 'echo no status map reference here'
run_fence 0 "$TMP/j" "passes: a control-authority file with no map reference"

# The SPACED prose form is not a reference to the command — the backlog already carries
# "harness status map" as English, and that must never fire.
mkfix "$TMP/k" ".claude/workflow/README.md" 'A read-only, observe-only harness status map exists.'
run_fence 0 "$TMP/k" "passes: 'status map' as spaced prose is not a command reference"

# --- the reciprocal manifest-fence surfaces are sanctioned (declaration, no execution) --
mkfix "$TMP/r" ".claude/hooks/harness-manifest-fence.sh" \
  '    .claude/hooks/status-map.sh | .claude/hooks/status-map.test.sh) return 0 ;;'
addfix "$TMP/r" ".claude/hooks/harness-manifest-fence.test.sh" \
  'addfix "$TMP/g" ".claude/hooks/status-map.sh" (the observe-only consumer)'
run_fence 0 "$TMP/r" "passes: the manifest fence's reciprocal allowlist entry + its fixture"

# --- lib-tasks-drift.sh is line-scoped: it is SOURCED by guard.sh rule 8 and the
# selection hooks, so a comment naming the map is benign but an executable invocation
# would put the map inside a decision path transitively — that must FIRE.
mkfix "$TMP/s" ".claude/hooks/lib-tasks-drift.sh" \
  '#   * status-map.sh — the observe-only orientation map (read-only, #234/T638).'
run_fence 0 "$TMP/s" "passes: the shared lib's consumer-list COMMENT naming the map"

mkfix "$TMP/t" ".claude/hooks/lib-tasks-drift.sh" \
  'tasks_drift_hint() { bash .claude/hooks/status-map.sh | grep drift; }'
run_fence 1 "$TMP/t" "fires: the shared lib EXECUTING the map (guard/selection source this lib)" \
  "P5 FENCE VIOLATION: .claude/hooks/lib-tasks-drift.sh"

# --- CI is line-scoped: the sanctioned wiring passes, a map-consuming step fires ---
mkfix "$TMP/l" ".github/workflows/ci.yml" '#'
{
  printf '      # status-map orientation wiring (comments are benign)\n'
  printf '      - name: Status-map tests\n'
  printf '        run: bash .claude/hooks/status-map.test.sh\n'
  printf '      - name: Status-map P5 fence\n'
  printf '        run: bash .claude/hooks/status-map-fence.sh\n'
} > "$TMP/l/.github/workflows/ci.yml"
git -C "$TMP/l" add .github/workflows/ci.yml
run_fence 0 "$TMP/l" "passes: CI's benign comment + test/fence wiring lines"

printf '        run: bash .claude/hooks/status-map.sh | grep -q "on base branch: no"\n' \
  >> "$TMP/l/.github/workflows/ci.yml"
git -C "$TMP/l" add .github/workflows/ci.yml
run_fence 1 "$TMP/l" "fires: a CI step that branches on the map's output (trailing pipe)"

# --- fail-closed: an unlistable/empty tree exits 2, never a silent pass ----------
mkdir -p "$TMP/m"
run_fence 2 "$TMP/m" "fail-closed: an empty tree cannot be fenced"

# --- the real tree passes (no control-authority path consumes the map) -----------
run_fence 0 "$REPO_ROOT" "real tree: fence passes"

# --- CI wiring: the fence and these tests run in verify (constitution P2) --------
for step in \
  'run: bash \.claude/hooks/status-map-fence\.sh' \
  'run: bash \.claude/hooks/status-map-fence\.test\.sh'
do
  if grep -qE "^ +$step[[:space:]]*$" "$CI"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL CI wiring: no active step matching %s in ci.yml\n' "$step" >&2
  fi
done

# ---------------------------------------------------------------------------------
echo "status-map-fence tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
