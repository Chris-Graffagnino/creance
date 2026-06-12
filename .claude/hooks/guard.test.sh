#!/usr/bin/env bash
# Regression tests for guard.sh (issue #61). Feeds simulated PreToolUse JSON
# payloads to the hook on stdin and asserts exit codes for all five rules:
#   1. file edits while on `main` (incl. the out-of-repo allowance and
#      Windows JSON-escaped backslash paths)
#   2. `git add .` / `-A` / `--all`
#   3. `git commit` / `git push` while on `main`
#   4. any `git push` whose refspec targets `main`, from any branch
#   5. constitution-auditor Agent dispatch with a missing or below-strong
#      `model` (tier names from a fixture table via GUARD_MODELS_FILE)
# Branch-dependent rules run from throwaway repos created in a temp dir (one
# on `main`, one on a feature branch) — that is how `git branch --show-current`
# is "stubbed". Needs only bash + git, runs in <1s; wired into the `verify` CI
# job (.github/workflows/ci.yml).
# NOTE: never type these payloads inline in an interactive shell command — the
# live guard greps the raw tool-call payload and will veto the command itself.
# Execute this file instead: bash .claude/hooks/guard.test.sh
set -u

HOOK="$(cd "$(dirname "$0")" && pwd)/guard.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

MAIN="$TMP/on-main"
FEAT="$TMP/on-feature"
git init -q -b main "$MAIN"
git init -q -b feature/test "$FEAT"
# Resolve roots the way the hook does (git may report a different spelling of
# the temp path than mktemp did, e.g. drive-letter form on Windows).
MAIN_ROOT="$(git -C "$MAIN" rev-parse --show-toplevel)"
FEAT_ROOT="$(git -C "$FEAT" rev-parse --show-toplevel)"
OUTSIDE="$(dirname "$MAIN_ROOT")/outside/notes.md"
# Windows-style variants: JSON-escaped backslashes, exactly as the Claude Code
# runtime serializes file_path on Windows.
MAIN_ROOT_WIN="$(printf '%s' "$MAIN_ROOT" | sed -e 's#/#\\\\#g')"
OUTSIDE_WIN="$(printf '%s' "$OUTSIDE" | sed -e 's#/#\\\\#g')"

pass=0
fail=0

check() { # check <expected-exit> <cwd> <name> <payload>
  local want="$1" cwd="$2" name="$3" payload="$4" got=0
  ( cd "$cwd" && printf '%s' "$payload" | bash "$HOOK" >/dev/null 2>&1 ) || got=$?
  if [ "$got" -eq "$want" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL %-55s want exit %s, got %s\n' "$name" "$want" "$got" >&2
  fi
}

edit() { printf '{"tool_name":"%s","tool_input":{"file_path":"%s"}}' "$1" "$2"; }
bashp() { printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$1"; }
pwshp() { printf '{"tool_name":"PowerShell","tool_input":{"command":"%s"}}' "$1"; }

# --- rule 1: no repo edits while on main (out-of-repo writes allowed) ---
check 2 "$MAIN" "r1 block: Edit in-repo on main" "$(edit Edit "$MAIN_ROOT/src/foo.ts")"
check 2 "$MAIN" "r1 block: Write in-repo on main" "$(edit Write "$MAIN_ROOT/notes.md")"
check 2 "$MAIN" "r1 block: NotebookEdit in-repo on main" "$(edit NotebookEdit "$MAIN_ROOT/nb.ipynb")"
check 2 "$MAIN" "r1 block: Windows escaped-backslash path on main" "$(edit Edit "$MAIN_ROOT_WIN\\\\src\\\\foo.ts")"
check 2 "$MAIN" "r1 block: Edit with no file_path on main (fail closed)" '{"tool_name":"Edit","tool_input":{}}'
check 0 "$MAIN" "r1 allow: Edit outside the repo on main" "$(edit Edit "$OUTSIDE")"
check 0 "$MAIN" "r1 allow: Write outside repo, Windows path, on main" "$(edit Write "$OUTSIDE_WIN")"
check 0 "$FEAT" "r1 allow: Edit in-repo on a feature branch" "$(edit Edit "$FEAT_ROOT/src/foo.ts")"
check 0 "$MAIN" "r1 allow: non-edit tool (Read) on main" "$(edit Read "$MAIN_ROOT/src/foo.ts")"

# --- rule 2: no blanket staging (run on the feature repo so rule 3 stays out) ---
check 2 "$FEAT" "r2 block: git add ." "$(bashp 'git add .')"
check 2 "$FEAT" "r2 block: git add -A" "$(bashp 'git add -A')"
check 2 "$FEAT" "r2 block: git add --all" "$(bashp 'git add --all')"
check 2 "$FEAT" "r2 block: git add . in a compound command" "$(bashp 'git add . ; git status')"
check 0 "$FEAT" "r2 allow: git add specific files" "$(bashp 'git add src/a.ts src/b.ts')"
check 0 "$FEAT" "r2 allow: git add ./path (specific, dot-slash)" "$(bashp 'git add ./src/a.ts')"

# --- rule 3: no commit/push while on main ---
check 2 "$MAIN" "r3 block: git commit on main" "$(bashp 'git commit -m \"msg\"')"
check 2 "$MAIN" "r3 block: git push (feature dest) on main" "$(bashp 'git push -u origin feature/x')"
check 2 "$MAIN" "r3 block: git commit on main via PowerShell" "$(pwshp 'git commit -m \"msg\"')"
check 0 "$FEAT" "r3 allow: git commit on a feature branch" "$(bashp 'git commit -m \"msg\"')"
check 0 "$MAIN" "r3 allow: non-git command on main" "$(bashp 'npm test')"

# --- rule 4: no push whose refspec targets main, from any branch ---
check 2 "$FEAT" "r4 block: HEAD:main refspec" "$(bashp 'git push origin HEAD:main')"
check 2 "$FEAT" "r4 block: bare main destination" "$(bashp 'git push origin main')"
check 2 "$FEAT" "r4 block: forced feature:main" "$(bashp 'git push --force origin feature:main')"
check 2 "$FEAT" "r4 block: refs/heads/main destination" "$(bashp 'git push origin HEAD:refs/heads/main')"
check 2 "$FEAT" "r4 block: remote delete :main" "$(bashp 'git push origin :main')"
check 2 "$FEAT" "r4 block: HEAD:main via PowerShell" "$(pwshp 'git push origin HEAD:main')"
check 2 "$FEAT" "r4 block: push-to-main prose in inline commit msg (fail closed)" "$(bashp 'git commit -m \"revert: git push origin main broke X\"')"
check 0 "$FEAT" "r4 allow: normal feature-branch push" "$(bashp 'git push -u origin chore/61-guard-tests')"
check 0 "$FEAT" "r4 allow: HEAD:main-backup refspec" "$(bashp 'git push origin HEAD:main-backup')"
check 0 "$FEAT" "r4 allow: branch named maintenance" "$(bashp 'git push origin maintenance')"
check 0 "$FEAT" "r4 allow: push && gh pr create --base main" "$(bashp 'git push -u origin feature/x && gh pr create --base main')"
check 0 "$FEAT" "r4 allow: no push in the command" "$(bashp 'git status')"

# --- rule 5: constitution-auditor strong floor (model names from the table) ---
# Fixture table mirrors .claude/MODELS.md's row shape; GUARD_MODELS_FILE is the
# hook's test seam so these tests don't couple to the real table's model names.
MODELS_FIXTURE="$TMP/MODELS.md"
cat > "$MODELS_FIXTURE" <<'EOF'
| Tier (ordinal, highest first) | Model | Effort |
|---|---|---|
| **[frontier tier]** | `fable` | high |
| **[strong tier]** | `opus` | — |
| **[cheap tier]** | `sonnet` (`haiku` acceptable) | — |
EOF
agentp() { printf '{"tool_name":"%s","tool_input":{"subagent_type":"%s","prompt":"audit the diff","model":"%s"}}' "$1" "$2" "$3"; }
agentnm() { printf '{"tool_name":"%s","tool_input":{"subagent_type":"%s","prompt":"audit the diff"}}' "$1" "$2"; }

export GUARD_MODELS_FILE="$MODELS_FIXTURE"
check 2 "$FEAT" "r5 block: constitution-auditor, no model param" "$(agentnm Agent constitution-auditor)"
check 2 "$FEAT" "r5 block: constitution-auditor on cheap (sonnet)" "$(agentp Agent constitution-auditor sonnet)"
check 2 "$FEAT" "r5 block: constitution-auditor on cheap (haiku)" "$(agentp Agent constitution-auditor haiku)"
check 2 "$FEAT" "r5 block: legacy Task tool name, cheap model" "$(agentp Task constitution-auditor sonnet)"
check 0 "$FEAT" "r5 allow: constitution-auditor at the floor" "$(agentp Agent constitution-auditor opus)"
check 0 "$FEAT" "r5 allow: constitution-auditor above the floor" "$(agentp Agent constitution-auditor fable)"
check 0 "$FEAT" "r5 allow: full model ID containing the floor name" "$(agentp Agent constitution-auditor claude-opus-4-8)"
check 0 "$FEAT" "r5 allow: other subagent without a model param" "$(agentnm Agent spec-auditor)"
check 0 "$FEAT" "r5 allow: unknown model name (fail open)" "$(agentp Agent constitution-auditor some-new-model)"
check 0 "$FEAT" "r5 allow: cheap name only in prompt, model at floor" '{"tool_name":"Agent","tool_input":{"subagent_type":"constitution-auditor","prompt":"sonnet is the cheap tier","model":"opus"}}'
export GUARD_MODELS_FILE="$TMP/no-such-table.md"
check 0 "$FEAT" "r5 allow: table missing -> fail open (cheap model)" "$(agentp Agent constitution-auditor sonnet)"
unset GUARD_MODELS_FILE
# Default-path resolution against the real .claude/MODELS.md — the no-model
# block only needs the strong row to parse, so it survives model renames there.
check 2 "$FEAT" "r5 block: default table path resolves (no model)" "$(agentnm Agent constitution-auditor)"

# --- hook wiring: the PreToolUse matcher must route every tool guard.sh handles ---
# Conformance-probe finding (issue #110, P-GD.5): rule 5 was dead on the live
# driver because settings.json's matcher omitted Agent|Task — guard.sh never saw
# the dispatch, while these payload tests stayed green. The wiring is part of the
# binding, so it gets its own assertion.
SETTINGS="$(cd "$(dirname "$0")" && pwd)/../settings.json"
matcher="$(grep -oE '"matcher"[[:space:]]*:[[:space:]]*"[^"]*"' "$SETTINGS" | head -1 \
  | sed -E 's/.*:[[:space:]]*"([^"]*)".*/\1/')"
for t in Edit Write MultiEdit NotebookEdit Bash PowerShell Agent Task; do
  if printf '|%s|' "$matcher" | grep -qF "|$t|"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL %-55s matcher must include it\n' "wiring: PreToolUse matcher routes $t" >&2
  fi
done

# --- fail-open posture for unrecognized input ---
check 0 "$FEAT" "misc allow: garbage payload" 'not json'
check 0 "$FEAT" "misc allow: empty payload" ''

printf 'guard.test.sh: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
