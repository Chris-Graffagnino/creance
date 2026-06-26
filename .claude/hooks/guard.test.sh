#!/usr/bin/env bash
# Regression tests for guard.sh (issue #61). Feeds simulated PreToolUse JSON
# payloads to the hook on stdin and asserts exit codes for all six rules:
#   1. file edits while on `main` (incl. the out-of-repo allowance and
#      Windows JSON-escaped backslash paths)
#   2. `git add .` / `-A` / `--all` / `./`
#   3. `git commit` / `git push` while on `main`
#   4. any `git push` whose refspec targets `main`, from any branch
#      (rules 2-4 also cover the #138 global-option `git -C`/`-c`/`--git-dir`
#      and `cd <path> && git …` effective-repo evasions)
#   5. strong-floored reviewer (constitution-auditor / spec-quality-auditor)
#      Agent dispatch with a missing or below-strong `model`, while the
#      un-floored acceptance/contract reviewers pass (tier names from a fixture
#      table via GUARD_MODELS_FILE)
#   6. self-colliding in-place sed edits — an `s#`/`s/` delimiter colliding with
#      a URL in the operand (the silent PR-body-blank class, issue #95)
# plus the telemetry logging paths (workflow/telemetry.md): block records,
# evaluation records, and the failure-stays-silent case (GUARD_TELEMETRY_FILE
# is the stream's test seam).
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

# Redirect telemetry for the whole run — without this, every blocked payload
# below would append to the user's real stream (guard.sh's default path).
TELE="$TMP/telemetry.jsonl"
export GUARD_TELEMETRY_FILE="$TELE"

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

# --- rule 1 (#165 / T623): relative file_path normalized BEFORE the in_repo decision ---
# The bypass: a relative in-repo path (e.g. "AGENTS.md") was read as outside the repo, so
# the edit-on-main guard let it through. guard.sh now resolves a relative path against the
# repo root and collapses '.'/'..' before the prefix test. Tests run with cwd = the repo,
# so the relative path anchors there. Paired control: a relative path that ESCAPES the repo
# ("../…") must still be ALLOWED — a "deny-everything-relative" shortcut fails the control.
check 2 "$MAIN" "r1 #165 block: relative in-repo path on main" "$(edit Edit "AGENTS.md")"
check 2 "$MAIN" "r1 #165 block: relative nested in-repo path on main" "$(edit Write "src/foo.ts")"
check 2 "$MAIN" "r1 #165 block: relative dot-slash in-repo path on main" "$(edit Edit "./notes.md")"
check 0 "$MAIN" "r1 #165 allow: relative path escaping the repo on main (control)" "$(edit Edit "../outside/notes.md")"
check 0 "$FEAT" "r1 #165 allow: relative in-repo path on a feature branch" "$(edit Edit "AGENTS.md")"

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

# --- #138 (T621): global-option / cwd evasions of rules 2/3/4 ---
# DW1 — a leading git global option no longer slips the bulk-staging / commit-push
# matchers (the bare-subcommand form already DENYs).
check 2 "$FEAT" "DW1 block: git -C <path> add --all" "$(bashp "git -C $FEAT_ROOT add --all")"
check 2 "$FEAT" "DW1 block: git -c k=v add --all"    "$(bashp 'git -c user.email=t@t.test add --all')"
check 2 "$FEAT" "DW1 block: git -C <path> add ."     "$(bashp "git -C $FEAT_ROOT add .")"
check 2 "$MAIN" "DW1 block: git --git-dir=<g> commit on main" "$(bashp "git --git-dir=$MAIN_ROOT/.git commit -m x")"
check 2 "$MAIN" "DW1 block: git -c k=v commit on main"        "$(bashp 'git -c user.name=t commit -m x')"
check 2 "$FEAT" "DW1 block: git -C <path> push HEAD:main (refspec)" "$(bashp "git -C $FEAT_ROOT push origin HEAD:main")"
# DW1 control (penalizes over-block): a -C-prefixed single-file add is still ALLOWED —
# a "deny anything containing -C" shortcut would fail here.
check 0 "$FEAT" "DW1 allow: git -C <path> add one/file (control)" "$(bashp "git -C $FEAT_ROOT add src/one.ts")"

# DW2 — branch-gated rule 3 resolves the EFFECTIVE repo (the -C / cd && target), not
# only the event cwd. Paired (both directions), so neither "always deny" nor "always
# allow" passes: event cwd off-base but the target on base -> DENY; event cwd on base
# but the target off-base -> ALLOW.
check 2 "$FEAT" "DW2 block: -C <main-repo> commit, event cwd on feature" "$(bashp "git -C $MAIN_ROOT commit -m x")"
check 2 "$FEAT" "DW2 block: cd <main-repo> && git commit, event cwd on feature" "$(bashp "cd $MAIN_ROOT && git commit -m x")"
check 0 "$MAIN" "DW2 allow: -C <feature-repo> commit, event cwd on base" "$(bashp "git -C $FEAT_ROOT commit -m x")"
# DW2 fallback preserves strength: a `cd <gone>` target is unreadable, so resolution
# falls back to the event-cwd branch (main) -> still DENY (no new false-ALLOW).
check 2 "$MAIN" "DW2 block: cd <nonexistent> && git commit falls back to event cwd (main)" "$(bashp "cd $TMP/does-not-exist && git commit -m x")"

# DW3 — fail-open preserved, narrowly scoped: a genuinely parse-ambiguous form (an
# UNRECOGNIZED leading option that ends the global run) still abstains (ALLOW), while
# the DW1/DW2 forms above still DENY in this same run — so "classify everything as
# ambiguous -> ALLOW" fails DW1/DW2, and over-blocking fails this.
check 0 "$FEAT" "DW3 allow: git --unknown-flag add --all (ambiguous -> abstain)" "$(bashp 'git --unknown-flag add --all')"
check 0 "$MAIN" "DW3 allow: git --unknown-flag commit on main (ambiguous -> abstain)" "$(bashp 'git --unknown-flag commit -m x')"

# DW4 — the trailing-slash `git add ./` dot-operand variant is a DENY; `git add ./path`
# (a specific file) stays ALLOWED (covered above at "r2 allow: git add ./path").
check 2 "$FEAT" "DW4 block: git add ./ (dot-slash whole tree)" "$(bashp 'git add ./')"

# --- PR #173: review hardening of rule 3's effective-repo resolution ---
# P2 (Codex) — the repo-locating -C is taken from the SAME `git … commit` invocation, NOT
# an unrelated leading `git -C <other> …`. Paired both directions so a "first -C in the
# whole line" reader fails one and a "scope to the commit invocation" reader passes both:
#   event cwd on main, leading -C points at the feature repo, the commit itself has no -C
#   -> the commit lands on main -> DENY (the leading -C must be ignored).
check 2 "$MAIN" "P2 block: git -C <feat> status && git commit (commit's repo = main)" "$(bashp "git -C $FEAT_ROOT status && git commit -m x")"
#   event cwd on feature, leading -C points at the base repo -> the commit still acts on
#   the feature repo -> ALLOW (an old whole-line -C borrow would over-block here).
check 0 "$FEAT" "P2 allow: git -C <main> status && git commit (commit's repo = feature)" "$(bashp "git -C $MAIN_ROOT status && git commit -m x")"
# A non-global reuse-message `git commit -C HEAD` is still not misread as a repo dir: the
# -C is after the subcommand, outside the global run, so it never flips the branch read.
check 0 "$FEAT" "P2 allow: git commit -C HEAD (reuse-msg, not a repo dir)" "$(bashp 'git commit -C HEAD')"

# H1 (craft) — rule 3 resolves --git-dir / --work-tree for the branch, not only -C / cd.
# Paired both directions, so it proves resolution rather than a "deny anything with
# --git-dir" shortcut: event cwd on feature but --git-dir targets the base repo -> DENY.
check 2 "$FEAT" "H1 block: git --git-dir=<main>/.git --work-tree=<main> commit (target main)" "$(bashp "git --git-dir=$MAIN_ROOT/.git --work-tree=$MAIN_ROOT commit -m x")"
#   event cwd on base but --git-dir targets the feature repo -> ALLOW.
check 0 "$MAIN" "H1 allow: git --git-dir=<feat>/.git commit (target feature)" "$(bashp "git --git-dir=$FEAT_ROOT/.git commit -m x")"
# P2 boundary — a `git commitx` decoy sharing the `commit` prefix must NOT capture the
# locator: the real `git -C <main> commit` still resolves to main -> DENY (a boundary-less
# locator would latch onto the decoy, find no -C, and fall back to the feature event cwd).
check 2 "$FEAT" "P2 block: decoy git commitx then real git -C <main> commit" "$(bashp "git commitx && git -C $MAIN_ROOT commit -m x")"

# --- rule 5: the strong-tier floor — constitution + spec-quality reviewers ---
# Fixture table mirrors .claude/MODELS.md's row shape; GUARD_MODELS_FILE is the
# hook's test seam so these tests don't couple to the real table's model names.
# The floor covers BOTH strong-floored reviewers (constitution-auditor and, per
# issue #147 / T701, spec-quality-auditor); the un-floored acceptance/contract
# reviewers must still pass on a cheap model.
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
# The floor generalizes to the spec-quality reviewer (issue #147 / T701): the
# same strong floor fires on a spec-quality-auditor dispatch.
check 2 "$FEAT" "r5 block: spec-quality-auditor, no model param" "$(agentnm Agent spec-quality-auditor)"
check 2 "$FEAT" "r5 block: spec-quality-auditor on cheap (sonnet)" "$(agentp Agent spec-quality-auditor sonnet)"
check 2 "$FEAT" "r5 block: spec-quality-auditor on cheap (haiku)" "$(agentp Agent spec-quality-auditor haiku)"
check 2 "$FEAT" "r5 block: spec-quality-auditor via legacy Task, cheap model" "$(agentp Task spec-quality-auditor sonnet)"
check 0 "$FEAT" "r5 allow: spec-quality-auditor at the floor" "$(agentp Agent spec-quality-auditor opus)"
check 0 "$FEAT" "r5 allow: spec-quality-auditor above the floor" "$(agentp Agent spec-quality-auditor fable)"
check 0 "$FEAT" "r5 allow: spec-quality-auditor unknown model (fail open)" "$(agentp Agent spec-quality-auditor some-new-model)"
# The acceptance reviewer (spec-auditor) is NOT strong-floored — a cheap-model
# dispatch is allowed; the case match is exact, so a spec-* prefix never floors it.
check 0 "$FEAT" "r5 allow: spec-auditor (acceptance) on cheap model, not floored" "$(agentp Agent spec-auditor sonnet)"
export GUARD_MODELS_FILE="$TMP/no-such-table.md"
check 0 "$FEAT" "r5 allow: table missing -> fail open (cheap model)" "$(agentp Agent constitution-auditor sonnet)"
unset GUARD_MODELS_FILE
# Default-path resolution against the real .claude/MODELS.md — the no-model
# block only needs the strong row to parse, so it survives model renames there.
check 2 "$FEAT" "r5 block: default table path resolves (no model)" "$(agentnm Agent constitution-auditor)"

# --- rule 6: self-colliding in-place sed edits (delimiter occurs in the URL) ---
# The dangerous form blanks PR bodies silently: `sed -e "s#__T__#$URL#g"` where the URL
# carries a `#issuecomment` anchor (the 4th `#`) — or any `s/…/https://…/` whose URL
# slashes collide with the `/` delimiter — so sed errors, the redirect leaves an empty
# file, and the body-edit consumer blanks the body with exit 0 (issue #95). The rule is
# DELIMITER-SPECIFIC (PR #98 review): a URL the delimiter does not occur in is NOT
# blocked. Branch-independent, so run on the feature repo. NOTE: these dangerous strings
# live ONLY inside this file's payloads, fed to the hook on stdin — never type them as a
# live shell command, or the guard vetoes it.
# Block: the delimiter actually collides with the URL.
check 2 "$FEAT" "r6 block: s# delimiter, URL with a # fragment (PR-body form)" "$(bashp 'sed -e \"s#__SPEC_URL__#https://github.com/o/r/pull/88#issuecomment-1#g\" body.md')"
check 2 "$FEAT" "r6 block: s/ delimiter, URL with // slashes" "$(bashp 'sed -i '\''s/__T__/https://x/'\'' body.md')"
check 2 "$FEAT" "r6 block: dangerous (fragment) sed inside a gh-body command substitution" "$(bashp 'gh pr edit 5 --body-file <(sed -e \"s#__T__#https://x#frag#g\" tmpl.md)')"
check 2 "$FEAT" "r6 block: s# fragment URL via PowerShell" "$(pwshp 'sed -e \"s#a#https://x#frag#\" f')"
# Block: addressed substitutions (s not preceded by quote/space) — Finding B (PR #98).
check 2 "$FEAT" "r6 block: line-addressed 1s# with a # fragment URL" "$(bashp 'sed -e \"1s#__T__#https://x#frag#\" tmpl > body.md')"
check 2 "$FEAT" "r6 block: pattern-addressed /re/s# with a # fragment URL" "$(bashp 'sed -e \"/foo/s#a#https://x#frag#g\" f')"
check 2 "$FEAT" "r6 block: line-addressed 2s/ with a // URL" "$(bashp 'sed -i \"2s/__T__/https://x/\" f')"
# Block: compound (;-separated) script where ONE sub genuinely collides — the count
# must still fire within the colliding expression (PR #98 review, commit 2).
check 2 "$FEAT" "r6 block: compound script, first s# sub has a # fragment" "$(bashp 'sed -e \"s#__T__#https://x#frag#g; s#foo#bar#g\" f')"
# Allow: safe delimiters, non-URL text, and — Finding A (PR #98) — a URL the delimiter
# does NOT occur in (a no-fragment URL under s#; a `/`-free word under s/).
check 0 "$FEAT" "r6 allow: s@ delimiter (safe) with a URL" "$(bashp 'sed -e \"s@__SPEC_URL__@https://github.com/o/r/pull/88#issuecomment-1@g\" body.md')"
check 0 "$FEAT" "r6 allow: s| delimiter (safe) with a URL" "$(bashp 'sed -e \"s|__T__|https://x|g\" f')"
check 0 "$FEAT" "r6 allow: s# delimiter, no-fragment URL (delimiter absent from content)" "$(bashp 'sed -e \"s#__T__#https://example.com/path#g\" body.md')"
check 0 "$FEAT" "r6 allow: compound s# script, both subs no-fragment (PR #98 commit 2)" "$(bashp 'sed -e \"s#__T__#https://example.com/path#g; s#foo#bar#g\" body.md')"
check 0 "$FEAT" "r6 allow: s/ delimiter, no-slash replacement (bare word http)" "$(bashp 'sed -e \"s/x/http/\" f')"
check 0 "$FEAT" "r6 allow: s# delimiter, non-URL text" "$(bashp 'sed -e \"s#foo#bar#g\" f')"
check 0 "$FEAT" "r6 allow: s/ delimiter, non-URL text" "$(bashp 'sed -i '\''s/foo/bar/g'\'' f')"
check 0 "$FEAT" "r6 allow: URL upstream of sed in a pipe" "$(bashp 'curl https://github.com/o/r | sed -e \"s/a/b/\"')"
check 0 "$FEAT" "r6 allow: URL in a separate command after the sed" "$(bashp 'sed -i '\''s/a/b/'\'' f ; echo https://x')"
check 0 "$FEAT" "r6 allow: s/-suffixed path + URL but no sed" "$(bashp 'ls tools/ && curl https://x')"

# --- rule 7: the [edit guard] (PostToolUse) — delta-based lint reject (#79) ---
# A committed .sh baseline carrying ONE pre-existing portability failure; each
# "edit" rewrites the working-tree file before its payload. The checker is the
# real shell-lint.sh, resolved from guard.sh's own repo root via the profile's
# relative path (GUARD_PROJECT_FILE points the map at a fixture). The denylisted
# construct is assembled at runtime ($D) so this test file stays lint-clean.
EDIT_PROF="$TMP/profile-edit.md"
cat > "$EDIT_PROF" <<'EOF'
## Edit-time checks
- `*.sh` → `.claude/hooks/shell-lint.sh`

## Next
EOF
D="-"   # leading dash, kept out of literals so this file lints clean
ELR="$TMP/edit-repo"
git init -q -b feature/edit "$ELR"
ELR_ROOT="$(git -C "$ELR" rev-parse --show-toplevel)"
EDITED="$ELR_ROOT/sample.sh"
{ printf '#!/usr/bin/env bash\n'; printf "yes '%s a' | head -n1\n" "$D"; } > "$EDITED"
git -C "$ELR" add sample.sh
git -C "$ELR" -c user.email=t@t.test -c user.name=t commit -qm baseline
postedit() { printf '{"hook_event_name":"PostToolUse","tool_name":"%s","tool_input":{"file_path":"%s"}}' "$1" "$2"; }

export GUARD_PROJECT_FILE="$EDIT_PROF"
# THE delta case (done-when #1): the file already fails; an edit adding NO new
# diagnostic is ALLOWED. A guard that blocked on any current failure fails here.
{ printf '#!/usr/bin/env bash\n'; printf "yes '%s a' | head -n1\n" "$D"; printf '# touched, no new issue\n'; } > "$EDITED"
check 0 "$ELR" "r7 allow: pre-existing failure, edit adds no new diagnostic" "$(postedit Edit "$EDITED")"
# an edit that ADDS a diagnostic is rejected (fix-forward, exit 2).
{ printf '#!/usr/bin/env bash\n'; printf "yes '%s a' | head -n1\n" "$D"; printf "yes '%s b' | head -n1\n" "$D"; } > "$EDITED"
check 2 "$ELR" "r7 block: edit adds a new diagnostic" "$(postedit Edit "$EDITED")"
# an edit that REMOVES the pre-existing failure is allowed (improvement, delta<0).
{ printf '#!/usr/bin/env bash\n'; printf "yes '# a' | head -n1\n"; } > "$EDITED"
check 0 "$ELR" "r7 allow: edit fixes the pre-existing failure" "$(postedit Edit "$EDITED")"
# a brand-new (untracked) file: baseline is empty (0), so any diagnostic is new.
NEWF="$ELR_ROOT/fresh.sh"
{ printf '#!/usr/bin/env bash\n'; printf "yes '%s c' | head -n1\n" "$D"; } > "$NEWF"
check 2 "$ELR" "r7 block: new untracked file introduces a diagnostic" "$(postedit Write "$NEWF")"
# fail-open: a file type with no checker row in the map.
printf 'plain text\n' > "$ELR_ROOT/notes.md"
check 0 "$ELR" "r7 allow: unmapped file type fails open" "$(postedit Edit "$ELR_ROOT/notes.md")"
# fail-open: a PostToolUse edit carrying no file_path.
check 0 "$ELR" "r7 allow: PostToolUse edit with no file_path fails open" '{"hook_event_name":"PostToolUse","tool_name":"Edit","tool_input":{}}'
# fail-open: an out-of-repo .sh (would be flagged if linted) — the in_repo gate.
OUT_SH="$(dirname "$ELR_ROOT")/outside.sh"
{ printf '#!/usr/bin/env bash\n'; printf "yes '%s z' | head -n1\n" "$D"; } > "$OUT_SH"
check 0 "$ELR" "r7 allow: out-of-repo .sh edit fails open" "$(postedit Edit "$OUT_SH")"
# a non-edit tool at PostToolUse is ignored.
check 0 "$ELR" "r7 allow: non-edit tool at PostToolUse ignored" "$(postedit Bash "$EDITED")"
# event gating: the SAME diagnostic-adding content at PreToolUse (no
# hook_event_name) must NOT fire rule 7 — the edit has not happened yet.
{ printf '#!/usr/bin/env bash\n'; printf "yes '%s a' | head -n1\n" "$D"; printf "yes '%s b' | head -n1\n" "$D"; } > "$EDITED"
check 0 "$ELR" "r7 allow: edit-time lint does not fire at PreToolUse" "$(edit Edit "$EDITED")"

# DW2 (#165 / T623): the PostToolUse edit-guard resolves a RELATIVE file_path too — the
# in_repo gate AND the checker/baseline run on the normalized absolute path. Mirror the
# PreToolUse pair: a relative in-repo .sh adding a diagnostic -> blocked; a relative path
# escaping the repo -> fails open (control). The "no NEW diagnostic" case is the key pin:
# if the baseline were taken on the raw relative path, norm_rel could not relativize it
# (baseline 0) so a pre-existing-only diagnostic would wrongly block — it proves fp is
# resolved before the checker/baseline, not only inside in_repo.
{ printf '#!/usr/bin/env bash\n'; printf "yes '%s a' | head -n1\n" "$D"; printf "yes '%s b' | head -n1\n" "$D"; } > "$EDITED"
check 2 "$ELR" "r7 #165 block: relative in-repo .sh adds a diagnostic" "$(postedit Edit "sample.sh")"
{ printf '#!/usr/bin/env bash\n'; printf "yes '%s a' | head -n1\n" "$D"; printf '# touched, no new issue\n'; } > "$EDITED"
check 0 "$ELR" "r7 #165 allow: relative in-repo .sh, no new diagnostic (baseline correct)" "$(postedit Edit "sample.sh")"
check 0 "$ELR" "r7 #165 allow: relative .sh escaping the repo fails open (control)" "$(postedit Edit "../outside.sh")"
unset GUARD_PROJECT_FILE

# --- telemetry: block + evaluation records (workflow/telemetry.md, US1.AC3/AC4) ---
# tcount <want> <pattern> <name> — assert how many telemetry lines match.
tcount() {
  local want="$1" pat="$2" name="$3" got
  got="$(grep -cE "$pat" "$TELE" 2>/dev/null)"; [ -n "$got" ] || got=0
  if [ "$got" -eq "$want" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL %-55s want %s matching line(s), got %s\n' "$name" "$want" "$got" >&2
  fi
}

export GUARD_MODELS_FILE="$MODELS_FIXTURE"

# Block path: one `block` record per blocked action, carrying rule + tool + timestamp.
: > "$TELE"
check 2 "$MAIN" "tele: rule-1 block still exits 2" "$(edit Edit "$MAIN_ROOT/src/foo.ts")"
tcount 1 '"record":"block"' "tele: rule-1 block appends one block record"
tcount 1 '"record":"block".*"rule":"edit-on-main".*"tool":"Edit"' "tele: block record carries rule + tool"
tcount 1 '"timestamp":"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z"' "tele: block record carries ISO-8601 UTC timestamp"

# Rule 6 takes the same block path — its record names the sed-collision rule + Bash tool.
: > "$TELE"
check 2 "$FEAT" "tele: rule-6 block still exits 2" "$(bashp 'sed -e \"s#a#https://x#frag#g\" f')"
tcount 1 '"record":"block".*"rule":"sed-url-delimiter-collision".*"tool":"Bash"' "tele: rule-6 block record carries rule + tool"

# Evaluation path: every constitution-auditor dispatch logs liveness, allowed or blocked.
: > "$TELE"
check 0 "$FEAT" "tele: dispatch at floor still allowed" "$(agentp Agent constitution-auditor opus)"
tcount 1 '"record":"evaluation".*"rule":"strong-floor".*"tool":"Agent"' "tele: allowed dispatch appends one evaluation record"
tcount 0 '"record":"block"' "tele: allowed dispatch appends no block record"
# The spec-quality reviewer's dispatch logs the same liveness signal (issue #147).
: > "$TELE"
check 0 "$FEAT" "tele: spec-quality-auditor dispatch at floor allowed" "$(agentp Agent spec-quality-auditor opus)"
tcount 1 '"record":"evaluation".*"rule":"strong-floor".*"tool":"Agent"' "tele: spec-quality-auditor dispatch appends one evaluation record"
tcount 0 '"record":"block"' "tele: spec-quality-auditor allowed dispatch appends no block record"
: > "$TELE"
check 2 "$FEAT" "tele: no-model dispatch still blocked" "$(agentnm Agent constitution-auditor)"
tcount 1 '"record":"evaluation"' "tele: blocked dispatch logs evaluation first"
tcount 1 '"record":"block".*"rule":"strong-floor-no-model"' "tele: blocked dispatch logs the block too"

# Allowed non-guard-relevant actions stay silent — no record spam.
: > "$TELE"
check 0 "$FEAT" "tele: plain allowed command" "$(bashp 'git status')"
check 0 "$FEAT" "tele: other subagent dispatch" "$(agentnm Agent spec-auditor)"
tcount 0 '.' "tele: allowed non-dispatch actions append nothing"
unset GUARD_MODELS_FILE

# Failure stays silent: an unwritable stream (parent is a regular file, so
# mkdir -p and the append both fail) must not change exit codes or stderr.
touch "$TMP/notadir"
export GUARD_TELEMETRY_FILE="$TMP/notadir/telemetry.jsonl"
check 2 "$MAIN" "tele: block exit unchanged when write fails" "$(edit Edit "$MAIN_ROOT/src/foo.ts")"
check 0 "$FEAT" "tele: allow exit unchanged when write fails" "$(edit Edit "$FEAT_ROOT/src/foo.ts")"
err="$( cd "$FEAT" && printf '%s' "$(edit Edit "$FEAT_ROOT/src/foo.ts")" | bash "$HOOK" 2>&1 >/dev/null )" || true
if [ -z "$err" ]; then pass=$((pass + 1)); else
  fail=$((fail + 1)); printf 'FAIL %-55s allowed action must stay silent, got: %s\n' "tele: failed write emits no stderr on allow" "$err" >&2
fi
export GUARD_TELEMETRY_FILE="$TELE"

# --- telemetry: profile path resolution (PROJECT.md → "Paths" → Telemetry) ---
# Precedence: GUARD_TELEMETRY_FILE seam > profile override > shipped default.
# Fixtures via GUARD_PROJECT_FILE (the profile's test seam).
HOMEFIX="$TMP/home"; mkdir -p "$HOMEFIX"
PROF_REL="$TMP/profile-rel.md"
cat > "$PROF_REL" <<'EOF'
## Paths
- **Telemetry:** `custom/stream.jsonl` (in-repo override)
- **Tasks:** `specs/tasks.md`
EOF
PROF_ABS="$TMP/profile-abs.md"
printf -- '- **Telemetry:** `%s`\n' "$TMP/abs-stream.jsonl" > "$PROF_ABS"
PROF_DEFAULT="$TMP/profile-default.md"
cat > "$PROF_DEFAULT" <<'EOF'
- **Telemetry:** default per `workflow/telemetry.md` — out-of-repo beside the
  triage inbox: `<triage inbox dir>/<repo-basename>-telemetry.jsonl`
EOF

unset GUARD_TELEMETRY_FILE
export GUARD_PROJECT_FILE="$PROF_REL"
check 2 "$FEAT" "tele: block under relative profile override" "$(bashp 'git add .')"
TELE="$FEAT_ROOT/custom/stream.jsonl"
tcount 1 '"record":"block".*"rule":"git-add-all"' "tele: relative override resolves against repo root"

export GUARD_PROJECT_FILE="$PROF_ABS"
check 2 "$FEAT" "tele: block under absolute profile override" "$(bashp 'git add .')"
TELE="$TMP/abs-stream.jsonl"
tcount 1 '"record":"block"' "tele: absolute override honored"

# A placeholder-bearing (<...>) Telemetry value is prose describing the default,
# not an override — the stream must land at the shipped default path. HOME is
# pointed at a fixture so the test never touches the user's real stream.
export GUARD_PROJECT_FILE="$PROF_DEFAULT"
OLD_HOME="$HOME"; export HOME="$HOMEFIX"
check 2 "$FEAT" "tele: block under placeholder profile value" "$(bashp 'git add .')"
export HOME="$OLD_HOME"
TELE="$HOMEFIX/.claude/triage/on-feature-telemetry.jsonl"
tcount 1 '"record":"block"' "tele: placeholder value falls back to shipped default"

export GUARD_PROJECT_FILE="$TMP/no-such-profile.md"
export HOME="$HOMEFIX"
check 2 "$MAIN" "tele: block under missing profile file" "$(edit Edit "$MAIN_ROOT/src/foo.ts")"
export HOME="$OLD_HOME"
TELE="$HOMEFIX/.claude/triage/on-main-telemetry.jsonl"
tcount 1 '"record":"block".*"rule":"edit-on-main"' "tele: missing profile falls back to shipped default"

# The env seam outranks any profile override.
TELE="$TMP/telemetry.jsonl"
export GUARD_TELEMETRY_FILE="$TELE" GUARD_PROJECT_FILE="$PROF_ABS"
: > "$TELE"
check 2 "$FEAT" "tele: block with both seam and override set" "$(bashp 'git add .')"
tcount 1 '"record":"block"' "tele: env seam outranks the profile override"
unset GUARD_PROJECT_FILE

# --- hook wiring: each phase's matcher must route every tool guard.sh handles ---
# Conformance-probe finding (issue #110, P-GD.5): rule 5 was dead on the live
# driver because settings.json's PreToolUse matcher omitted Agent|Task — guard.sh
# never saw the dispatch, while these payload tests stayed green. The wiring is
# part of the binding, so it gets its own assertion. Rule 7 (the [edit guard],
# issue #79 done-when #3) enumerates its edit tools the same way: an edit tool
# absent from the PostToolUse matcher would leave rule 7 silently dead. Both
# matchers are extracted by event so the assertion is order-independent.
SETTINGS="$(cd "$(dirname "$0")" && pwd)/../settings.json"
event_matcher() { # event_matcher <EventKey> -> that block's first matcher string
  sed -n "/\"$1\"/,/]/p" "$SETTINGS" \
    | grep -oE '"matcher"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 \
    | sed -E 's/.*:[[:space:]]*"([^"]*)".*/\1/'
}
routes() { printf '|%s|' "$1" | grep -qF "|$2|"; } # routes <matcher> <tool>
pre_matcher="$(event_matcher PreToolUse)"
for t in Edit Write MultiEdit NotebookEdit Bash PowerShell Agent Task; do
  if routes "$pre_matcher" "$t"; then pass=$((pass + 1)); else
    fail=$((fail + 1))
    printf 'FAIL %-55s PreToolUse matcher must include it\n' "wiring: PreToolUse routes $t" >&2
  fi
done
post_matcher="$(event_matcher PostToolUse)"
for t in Edit Write MultiEdit NotebookEdit; do
  if routes "$post_matcher" "$t"; then pass=$((pass + 1)); else
    fail=$((fail + 1))
    printf 'FAIL %-55s PostToolUse matcher must route it (else rule 7 is dead)\n' "wiring: PostToolUse routes $t" >&2
  fi
done

# --- T623 (#165): default review mode pre-approves no `gh pr merge` (DW3) ---
# Merge authorization is session-explicit (AGENTS.md "Autonomy and Merge Rules"). A
# `gh pr merge` pre-approval in the allowlist would make the merge boundary
# model-compliance-bound rather than deterministic, so NO allow rule (Bash or
# PowerShell) may grant it in default review mode. Asserted statically against the
# real settings.json (the same file the wiring assertions above read); a re-added
# entry fails this.
merge_allows="$(grep -cE '"(Bash|PowerShell)\(gh pr merge' "$SETTINGS" 2>/dev/null)"
[ -n "$merge_allows" ] || merge_allows=0
if [ "$merge_allows" -eq 0 ]; then pass=$((pass + 1)); else
  fail=$((fail + 1))
  printf 'FAIL %-55s settings.json must not pre-approve gh pr merge (found %s)\n' "settings #165: no gh pr merge pre-approval" "$merge_allows" >&2
fi

# --- fail-open posture for unrecognized input ---
check 0 "$FEAT" "misc allow: garbage payload" 'not json'
check 0 "$FEAT" "misc allow: empty payload" ''

printf 'guard.test.sh: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
