#!/usr/bin/env bash
# PreToolUse guard — the Claude Code [guard] binding. The runtime-neutral rules this
# enforces are specified in .claude/workflow/README.md → "The [guard] rules"; another
# runtime supplies its own implementation of those same rules.
# Enforces AGENTS.md workflow rules deterministically.
# Pure Git-Bash: needs only cat/grep/sed/git/mktemp (no node, jq, awk, or pwsh).
# PreToolUse — blocks (exit 2, message on stderr) before the action runs:
#   1. Any file edit (Edit/Write/MultiEdit/NotebookEdit) while on branch `main`.
#   2. `git add .` / `git add -A` / `git add --all` (stage specific files instead).
#   3. `git commit` / `git push` while on branch `main`.
#   4. Any `git push` whose refspec targets `main` (e.g. `HEAD:main`, `:main`,
#      or `main` as the destination), regardless of current branch.
#   5. Any Agent dispatch of `constitution-auditor` whose `model` parameter is
#      absent or names a below-strong tier — the strong floor (issue #94). Tier
#      names are resolved from .claude/MODELS.md at runtime, never hardcoded.
#   6. An in-place `sed` `s` substitution whose `#`/`/` delimiter ALSO occurs in
#      the URL it substitutes — an unescaped `https?://` under `s/`, or a `#`
#      fragment (a 4th `#`) under `s#` — which silently corrupts/blanks the output
#      (the PR-body-blank class, issue #95). Delimiter-specific, so a URL the
#      delimiter does not occur in (e.g. `s#a#https://h/p#g`), safe delimiters
#      (`@`, `|`), and seds without a URL are all left alone; addressed forms
#      (`1s#…`, `/re/s#…`) are caught.
# PostToolUse — fix-forward feedback (exit 2) AFTER the write, since PreToolUse
# cannot see an edit's result and PostToolUse cannot revert (issue #79):
#   7. An edit to a checked file that ADDS a diagnostic from the project's
#      configured per-type checker — measured as a DELTA against the file's
#      committed (HEAD) baseline, so an edit leaving diagnostics no worse than
#      before is allowed. No checker configured for the type, an unknown/out-of-
#      repo path, or an unavailable baseline all fail open. The file-type ->
#      checker map is a project fact (.claude/PROJECT.md -> "Edit-time checks");
#      the shipped checker is .claude/hooks/shell-lint.sh (bash -n + a BSD/GNU
#      portability denylist, folding in issue #97).
# Allows everything else (exit 0). Fails open: any uncertainty -> allow.
# Telemetry (workflow/telemetry.md): every block appends a `block` record and
# every constitution-auditor dispatch evaluation appends an `evaluation`
# record (the per-gate-run liveness signal) to the project's JSONL stream.
# Logging failures are swallowed — they never change guard exit behavior.
# Regression tests: .claude/hooks/guard.test.sh (run on every PR by the
# `verify` CI job) — extend them whenever you touch a rule here.
set -u

payload="$(cat)"

branch() { git branch --show-current 2>/dev/null; }

# Telemetry stream path, resolved in precedence order:
#   1. GUARD_TELEMETRY_FILE — test/override seam (mirrors GUARD_MODELS_FILE);
#   2. the profile's override — .claude/PROJECT.md → "Paths" → Telemetry is
#      authoritative (workflow/telemetry.md). A concrete override is the
#      bullet's first backticked `.jsonl` path; a placeholder-bearing value
#      (contains `<...>`) describes the default in prose and is not one;
#   3. the shipped default — <home>/.claude/triage/<repo-basename>-telemetry.jsonl.
profile_file="${GUARD_PROJECT_FILE:-$(cd "$(dirname "$0")" && pwd)/../PROJECT.md}"
profile_telemetry() {
  sed -n '/^[-*][[:space:]]*\*\*Telemetry:\*\*/,/^[-*#]/p' "$profile_file" 2>/dev/null \
    | grep -oE '`[^`<]+\.jsonl`' | head -1 | tr -d '`'
}
telemetry_file() {
  if [ -n "${GUARD_TELEMETRY_FILE:-}" ]; then
    printf '%s' "$GUARD_TELEMETRY_FILE"
    return 0
  fi
  local home="${HOME:-${USERPROFILE:-}}" root p
  p="$(profile_telemetry)"
  if [ -n "$p" ]; then
    case "$p" in
      "~/"*) [ -n "$home" ] || return 1; printf '%s/%s' "$home" "${p#\~/}" ;;
      /*|[a-zA-Z]:*) printf '%s' "$p" ;;
      *) root="$(git rev-parse --show-toplevel 2>/dev/null)" || return 1
         printf '%s/%s' "$root" "$p" ;;
    esac
    return 0
  fi
  [ -n "$home" ] || return 1
  root="$(git rev-parse --show-toplevel 2>/dev/null)" || return 1
  printf '%s/.claude/triage/%s-telemetry.jsonl' "$home" "${root##*/}"
}

# log_telemetry <record-type> <rule> — append one JSONL line (envelope per
# workflow/telemetry.md plus rule/tool). Every failure path is swallowed: a
# telemetry write must never block, fail, or alter the guard's own behavior.
log_telemetry() {
  {
    local f ts repo
    f="$(telemetry_file)" || return 0
    [ -n "$f" ] || return 0
    mkdir -p "$(dirname "$f")" || return 0
    ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)" || return 0
    repo="$(git rev-parse --show-toplevel 2>/dev/null)"; repo="${repo##*/}"
    printf '{"record":"%s","timestamp":"%s","repo":"%s","rule":"%s","tool":"%s"}\n' \
      "$1" "$ts" "$repo" "$2" "$tool" >> "$f"
  } 2>/dev/null || true
}

block() { # block <rule> <message>
  log_telemetry block "$1"
  printf '⛔ %s\n' "$2" >&2
  exit 2
}

# tool_name has no special chars, so a plain grep/sed extraction is safe.
tool="$(printf '%s' "$payload" \
  | grep -oE '"tool_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 \
  | sed -E 's/.*:[[:space:]]*"([^"]*)".*/\1/')"

# Normalize a path for prefix comparison: backslashes -> '/', repeated slashes
# collapsed (a JSON-escaped Windows path arrives as 'C:\\dev\\..' and would
# otherwise become 'c://dev//..' and dodge the prefix check), drive lowercased,
# '/c/foo' (git-bash form) -> 'c:/foo'. Used to tell repo edits from out-of-repo
# writes (e.g. the user's ~/.claude memory dir, which the on-main rule must not block).
norm() { printf '%s' "$1" | tr '\\' '/' 2>/dev/null | sed -E 's#/+#/#g; s#^/([a-zA-Z])/#\1:/#' | tr 'A-Z' 'a-z'; }

# Is the edit target inside this repo? Default YES so an unparseable/missing path
# still blocks on main (preserve the guard's strength); only a path we can confirm
# lies outside the repo root is allowed through.
in_repo() {
  local root fp
  root="$(git rev-parse --show-toplevel 2>/dev/null)" || return 0
  fp="$(printf '%s' "$payload" \
    | grep -oE '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 \
    | sed -E 's/.*:[[:space:]]*"([^"]*)".*/\1/')"
  [ -n "$fp" ] || return 0
  root="$(norm "$root")"; fp="$(norm "$fp")"
  case "$fp/" in "$root"/*) return 0 ;; *) return 1 ;; esac
}

# Extract a string field from the payload (same shape as the tool_name
# extraction above). Escaped quotes inside a JSON string (e.g. `\"model\"`
# in a prompt) cannot match the leading bare quote, so prompt text never
# false-matches a field.
jstr() {
  printf '%s' "$payload" \
    | grep -oE "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -1 \
    | sed -E 's/.*:[[:space:]]*"([^"]*)".*/\1/'
}

# Rule 5 helpers: the adapter model table is the ONLY file naming models — the
# hook resolves tier rows from it at runtime (GUARD_MODELS_FILE is a test seam).
# A tier's models are the backticked names in its table row; empty output means
# the row/table is unreadable and the caller must fail open.
models_file="${GUARD_MODELS_FILE:-$(cd "$(dirname "$0")" && pwd)/../MODELS.md}"
tier_models() {
  grep -iE "^\|[[:space:]]*\*\*\[$1 tier\]\*\*" "$models_file" 2>/dev/null | head -1 \
    | grep -oE '`[^`]+`' | tr -d '`'
}
model_in() { # model_in <model> <names...> — containment, so full IDs match too
  local m="$1" n; shift
  for n in "$@"; do
    [ -n "$n" ] || continue
    case "$m" in *"$n"*) return 0 ;; esac
  done
  return 1
}

# Rule 7 helpers (the [edit guard], PostToolUse). All paths fail open.
# norm_rel <abs-file> <repo-root> -> path relative to root ('' if outside root).
# Backslashes (a Windows-serialized path) are folded; case is preserved (git
# paths are case-sensitive), unlike norm() which lowercases for prefix matching.
norm_rel() {
  local fp root
  fp="$(printf '%s' "$1" | tr '\\' '/')"
  root="$(printf '%s' "$2" | tr '\\' '/')"
  case "$fp" in "$root"/*) printf '%s' "${fp#"$root"/}" ;; *) : ;; esac
}
# edit_checker <file> -> the checker script mapped to <file>'s type in the
# profile's "Edit-time checks" map ('' if none). Rows: `<glob>` -> `<checker>`.
edit_checker() {
  local base line glob chk
  base="${1##*/}"
  while IFS= read -r line; do
    glob="$(printf '%s' "$line" | grep -oE '`[^`]+`' | head -1   | tr -d '`')"
    chk="$(printf '%s' "$line"  | grep -oE '`[^`]+`' | sed -n 2p | tr -d '`')"
    [ -n "$glob" ] && [ -n "$chk" ] || continue
    case "$base" in $glob) printf '%s' "$chk"; return 0 ;; esac
  done < <(sed -n '/^##[[:space:]]*Edit-time checks/,/^##[[:space:]]/p' "$profile_file" 2>/dev/null | grep -E '^[-*][[:space:]]')
}
# edit_baseline_diags <file> <checker> -> diagnostic count on <file>'s committed
# (HEAD) blob. Prints nothing (caller fails open) when there is no repo or no
# HEAD; prints 0 for an in-repo file not tracked at HEAD (its diagnostics are
# all "new").
edit_baseline_diags() {
  local root rel tmp n
  root="$(git rev-parse --show-toplevel 2>/dev/null)" || return 0
  [ -n "$root" ] || return 0
  git rev-parse --verify -q HEAD >/dev/null 2>&1 || return 0
  rel="$(norm_rel "$1" "$root")"
  [ -n "$rel" ] || { printf '0'; return 0; }
  if git cat-file -e "HEAD:$rel" 2>/dev/null; then
    tmp="$(mktemp -d 2>/dev/null)" || { printf '0'; return 0; }
    git show "HEAD:$rel" > "$tmp/base" 2>/dev/null
    n="$(bash "$2" "$tmp/base" 2>/dev/null | grep -cE '[^[:space:]]')"; [ -n "$n" ] || n=0
    rm -rf "$tmp"
    printf '%s' "$n"
  else
    printf '0'
  fi
}

if [ "$(jstr hook_event_name)" = "PostToolUse" ]; then
  case "$tool" in Edit|Write|MultiEdit|NotebookEdit) ;; *) exit 0 ;; esac
  in_repo || exit 0
  fp="$(jstr file_path)"; [ -n "$fp" ] || exit 0
  checker_rel="$(edit_checker "$fp")"; [ -n "$checker_rel" ] || exit 0
  adapter_root="$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)" || exit 0
  case "$checker_rel" in /*) checker="$checker_rel" ;; *) checker="$adapter_root/$checker_rel" ;; esac
  [ -f "$checker" ] || exit 0
  diags="$(bash "$checker" "$fp" 2>/dev/null)"
  cur="$(printf '%s\n' "$diags" | grep -cE '[^[:space:]]')"; [ -n "$cur" ] || cur=0
  base="$(edit_baseline_diags "$fp" "$checker")"
  [ -n "$base" ] || exit 0
  if [ "$cur" -gt "$base" ]; then
    block edit-lint-regression "This edit adds $((cur - base)) new diagnostic(s) to a checked file (baseline $base, now $cur). The project's edit-time check reports:
$diags
Fix these forward. (An edit leaving diagnostics no worse than the committed baseline is allowed; the check fails open when none is configured.)"
  fi
  exit 0
fi

case "$tool" in
  Edit|Write|MultiEdit|NotebookEdit)
    if [ "$(branch)" = "main" ] && in_repo; then
      block edit-on-main "On 'main' — AGENTS.md forbids editing on main. Create a feature branch first:
   git switch -c <type>/<task-id>-<short-desc>   (or run /next-task)"
    fi
    ;;
  Bash|PowerShell)
    # Match against the raw payload; the command field carries these verbatim.
    if printf '%s' "$payload" | grep -qE 'git[[:space:]]+add[[:space:]]+(--all|-A|\.)([[:space:]]|;|&|\\|")'; then
      block git-add-all "\`git add .\` / -A / --all is not allowed (AGENTS.md). Stage specific files:
   git add <path1> <path2>"
    fi
    if printf '%s' "$payload" | grep -qE 'git[[:space:]]+(commit|push)([[:space:]]|\\|")' && [ "$(branch)" = "main" ]; then
      block commit-push-on-main "Never commit or push to 'main' (AGENTS.md). Work on a feature branch and open a PR."
    fi
    # Refspec rule: a push can target main from ANY branch (`git push origin HEAD:main`),
    # so match the destination ref, not just the current branch. [^";&|]* keeps the match
    # inside a single shell command, so `git push ... && gh pr create --base main` is allowed.
    if printf '%s' "$payload" | grep -qE 'git[[:space:]]+push[^";&|]*(:|[[:space:]])(refs/heads/)?main([^a-zA-Z0-9_./-]|$)'; then
      block push-refspec-main "This push targets 'main' (refspec). Never push to 'main' (AGENTS.md) — push the feature branch and open a PR."
    fi
    # Rule 6: a self-colliding in-place sed substitution — the delimiter char also
    # occurs in the URL operand, so the URL ends the expression early and silently
    # corrupts/blanks output (the documented PR-body-blank class, issue #95): sed
    # errors, the `>` redirect leaves an empty file, and the consumer (e.g. `gh pr
    # edit --body-file`) blanks the body with exit 0. Per-delimiter, so a URL the
    # delimiter does NOT occur in is NOT over-blocked (PR #98 review, Codex/owner):
    #   • `/` delimiter — only an UNescaped scheme `https?://` collides (its `//` are
    #     bare delimiters). `s/__T__/https://x/` blocks; `s/x/http/` (no `://`) and an
    #     escaped `s/__T__/https:\/\/x\//` (the `:\` breaks the literal `://`) do not.
    #   • `#` delimiter — collides ONLY when the URL carries a `#` fragment, i.e. the
    #     `s#` expression has a 4th `#` beyond the well-formed three (`s#pat#rep#flags`).
    #     `s#a#https://h/p#g` (exactly three `#`, no fragment) is safe → allowed; the
    #     `#`-run segments exclude quotes AND `;` so a later expression (`…; s#…`, or a
    #     second `-e`) cannot lend its `#` as the bogus 4th (PR #98 review, commit 2).
    # The opener's lead char is any NON-LETTER (`[^[:alpha:]_]`), so addressed forms
    # (`1s#…`, `$s#…`, `/re/s#…`) are caught while word-internal `s#`/`s/` (`tools/`,
    # `users/`) are not. `[^;&|]` spans confine each match to one command (a URL
    # upstream of a pipe, or in a separate command, stays allowed). Fail open.
    sed_pre='(^|[^[:alnum:]_])sed[^;&|]*[^[:alpha:]_]'
    if printf '%s' "$payload" | grep -qE "${sed_pre}s/[^/'\" ]*/https?://" \
       || printf '%s' "$payload" | grep -qE "${sed_pre}s#[^#'\";]*#[^#'\";]*http[^#'\";]*#[^#'\";]*#"; then
      block sed-url-delimiter-collision "This in-place sed substitution's delimiter ('#' or '/') also occurs in the URL it substitutes — the URL's unescaped '/' (or a '#…' fragment) is read as the delimiter, ends the expression early, and can silently corrupt or blank the output (the PR-body-blank class). Use a delimiter absent from the URL, e.g. 's@…@…@' or 's|…|…|', and compose PR/issue bodies via a file, then verify the result is non-empty."
    fi
    ;;
  Agent|Task)
    # Rule 5: the constitution [reviewer]'s strong floor. The auditor agents
    # carry no model pin (the model table owns all model names), so an omitted
    # `model` parameter silently inherits the session model — on a cheap-tier
    # session, exactly the downgrade the floor forbids. Unknown model names and
    # an unreadable table fail open; other subagents are untouched.
    if [ "$(jstr subagent_type)" = "constitution-auditor" ]; then
      # Liveness signal (workflow/telemetry.md): this path fires on every gate
      # run (the gate always dispatches the constitution [reviewer]), so one
      # `evaluation` record per dispatch distinguishes a live guard from
      # "nothing to block" — logged whatever the check's outcome.
      log_telemetry evaluation strong-floor
      strong="$(tier_models strong)"
      if [ -n "$strong" ]; then
        model="$(jstr model)"
        if [ -z "$model" ]; then
          block strong-floor-no-model "constitution-auditor dispatched without a 'model' parameter — it would inherit the session model and can silently break the [strong tier] floor. Pass the strong-tier model from .claude/MODELS.md explicitly on the dispatch."
        fi
        if ! model_in "$model" $strong $(tier_models frontier) \
           && model_in "$model" $(tier_models cheap); then
          block strong-floor-below "constitution-auditor dispatched below the [strong tier] floor (model: '$model'). The constitution reviewer never downgrades — pass a model at-or-above the strong-tier row of .claude/MODELS.md."
        fi
      fi
    fi
    ;;
esac
exit 0
