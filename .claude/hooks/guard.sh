#!/usr/bin/env bash
# PreToolUse guard — the Claude Code [guard] binding. The runtime-neutral rules this
# enforces are specified in .claude/workflow/README.md → "The [guard] rules"; another
# runtime supplies its own implementation of those same rules.
# Enforces AGENTS.md workflow rules deterministically.
# Pure Git-Bash: needs only cat/grep/sed/awk/git/mktemp (no node, jq, or pwsh). awk is used
# only for the quote tokenizer (quote_blank) with POSIX features (no {n} intervals), portable
# across BSD/GNU/Git-Bash awk.
# PreToolUse — blocks (exit 2, message on stderr) before the action runs:
#   1. Any file edit (Edit/Write/MultiEdit/NotebookEdit) while on branch `main`.
#   2. `git add .` / `git add -A` / `git add --all` / `git add ./` (stage
#      specific files instead).
#   3. `git commit` / `git push` while on branch `main`.
#   4. Any `git push` whose refspec targets `main` (e.g. `HEAD:main`, `:main`,
#      or `main` as the destination), regardless of current branch.
#   Rules 2-4 see through a leading git GLOBAL-option run (`git -C <path>`,
#   `git -c k=v`, `git --git-dir=…`) so it can't slip the subcommand anchor, and
#   the branch-gated rule 3 resolves the EFFECTIVE repo (an explicit `-C <path>`
#   or `--git-dir <path>` from the commit/push invocation, or a leading
#   `cd <path> &&`), not only the event cwd (issues #138, #173).
#   For rules 3-4, a `commit`/`push` verb appearing only inside a quoted argument (an
#   rg/grep pattern, an echo string, a `commit -m` message) or a `#` comment no longer
#   trips them (issue #256). When the command carries NO shell-execution vector, they
#   match a command SKELETON with quoted spans and comments blanked; when it DOES carry
#   one — a shell evaluator (`bash -c "…"`)/`eval`, or a command substitution whose body
#   holds the verb (`$(git … commit)`), which would execute it — they match the raw
#   payload as before (no hole). A `$(…)` WITHOUT the verb (a scan fileset/root like
#   `$(fd -e md)` / `"$(git rev-parse --show-toplevel)"`) is not a vector. The match stays
#   position-agnostic in both cases, so a genuine invocation after a shell keyword or an
#   env-assignment prefix still blocks (see command_skeleton and the target-selection at
#   rules 3-4).
#   5. Any Agent dispatch of a strong-floored reviewer — `constitution-auditor`
#      or `spec-quality-auditor` — whose `model` parameter is absent or names a
#      below-strong tier (the strong floor; issues #94, #147). Tier names are
#      resolved from .claude/MODELS.md at runtime, never hardcoded.
#   6. An in-place `sed` `s` substitution whose `#`/`/` delimiter ALSO occurs in
#      the URL it substitutes — an unescaped `https?://` under `s/`, or a `#`
#      fragment (a 4th `#`) under `s#` — which silently corrupts/blanks the output
#      (the PR-body-blank class, issue #95). Delimiter-specific, so a URL the
#      delimiter does not occur in (e.g. `s#a#https://h/p#g`), safe delimiters
#      (`@`, `|`), and seds without a URL are all left alone; addressed forms
#      (`1s#…`, `/re/s#…`) are caught.
#   8. A `git commit` whose message references a task id (`[T<nnn>]`) whose box
#      is still `- [ ]` in a live specs/*/tasks.md — done-but-unchecked drift
#      caught at commit time, before CI (issue #202). The pending id is read
#      from the command payload (the un-landed commit is not in `git log`); the
#      unchecked-box half is shared from lib-tasks-drift.sh, never a forked
#      drift definition. The boxes are read from the repo the commit TARGETS
#      (the invocation's `-C`/`--git-dir` or a leading `cd … &&`, like rule 3)
#      and from the view the commit will LAND — the index for a plain commit,
#      the working tree for `-a`/`--all`-style forms (PR #208 review). CI's
#      check-tasks-consistency.sh stays the authoritative backstop. Fails
#      open: no id in the command, a missing lib, an unreadable repo root, or
#      no live tasks files. (Numbered 8 because rule 7 below — the PostToolUse
#      [edit guard] — landed first.)
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

# Rules 2/3/4 must see through a leading run of git GLOBAL options placed between
# `git` and the subcommand (`git -C <path> add --all`, `git -c k=v commit`,
# `git --git-dir=… push`), which standard git accepts and which would otherwise
# slip the subcommand anchor (issue #138). `gitg` is the alternation of recognized
# globals; `grun` is a (possibly empty) run of them. CONSERVATIVE: only well-known
# globals match, so an UNRECOGNIZED leading token ends the run — the rule then sees
# the original token and may abstain (fail-open, the narrowly-scoped DW3 posture).
# Path operands stop at shell separators and the JSON string's closing quote.
gitg='-C[[:space:]]+[^[:space:];&|"]+|-c[[:space:]]+[^[:space:];&|"]+|--git-dir=[^[:space:];&|"]*|--git-dir[[:space:]]+[^[:space:];&|"]+|--work-tree=[^[:space:];&|"]*|--work-tree[[:space:]]+[^[:space:];&|"]+|--namespace[[:space:]]+[^[:space:];&|"]+|--paginate|--no-pager|--bare|--literal-pathspecs|--no-optional-locks|-p'
grun="([[:space:]]+($gitg))*"

# Effective-repo resolution for the repo-state rules (the branch-gated rule 3, and
# rule 8's tasks-state read — PR #208 review). A `git -C <path>`, a
# `git --git-dir=<path>`, or a leading `cd <path> &&` makes a command act on a
# DIFFERENT repo than the event cwd, so the repo state must be resolved THERE, not only
# in the hook cwd (issue #138 DW2). The repo-locating globals are taken from the SAME
# `git … commit|push` invocation that the rule matched — NOT the first `git` token in the
# line — so an unrelated leading run (`git -C <other> status && git commit`) does not
# lend its `-C` to the commit's repo decision (PR #173, Codex P2); and `--git-dir`
# is honored alongside `-C` (PR #173, craft H1). Best-effort + fail-open: when the
# resolved target is unreadable (a bad path, a non-repo, a detached HEAD), each caller
# falls back to its event-cwd read — so the resolution only ADDS coverage and never
# weakens the existing event-cwd check.
cd_dir() { # a leading `cd <path> &&` -> <path> (empty otherwise)
  case "$1" in
    cd[[:space:]]*) printf '%s' "$1" | sed -E 's/^cd[[:space:]]+([^[:space:];&|"]+).*/\1/' ;;
  esac
}
commit_push_run() { # the `git <globals> commit|push` invocation's prefix -> string ('' if none)
  # The trailing boundary (a shell separator, a quote, or end of string) makes the locator
  # latch onto the EXACT invocation rule 3 matched, never a `git commitx` decoy sharing the
  # `commit` prefix; -oE includes the boundary char, which is harmless to -C/--git-dir extraction.
  printf '%s' "$1" | grep -oE "git${grun}[[:space:]]+(commit|push)([[:space:]]|;|&|\||\"|$)" | head -1
}
effective_git() { # effective_git <command> <git-args...> -> git output against the
  # repo the command acts on; rc 1 / no output when the command carries no locators
  # or the target is unreadable (the caller supplies its event-cwd fallback).
  local cmd="$1" run cddir copt gdir; shift
  run="$(commit_push_run "$cmd")"
  cddir="$(cd_dir "$cmd")"
  # `-C` / `--git-dir` taken ONLY from that invocation's leading global run, so a
  # non-global `git commit -C HEAD` (reuse-message) is never misread as a directory.
  copt="$(printf '%s' "$run" | grep -oE '\-C[[:space:]]+[^[:space:];&|"]+' | tail -1 | sed -E 's/^-C[[:space:]]+//')"
  gdir="$(printf '%s' "$run" | grep -oE '\-\-git-dir(=|[[:space:]]+)[^[:space:];&|"]+' | tail -1 | sed -E 's/^--git-dir(=|[[:space:]]+)//')"
  [ -n "$cddir$copt$gdir" ] || return 1
  # Replay the locator globals ahead of the caller's git args, in the hook cwd (= event
  # cwd) so relative paths resolve exactly as the real command would. git applies repeated
  # `-C` cumulatively, so a `cd <a> && git -C <b>` nests <b> under <a> for free, and an
  # absolute `-C`/`--git-dir` overrides it.
  [ -n "$gdir" ]  && set -- --git-dir "$gdir" "$@"
  [ -n "$copt" ]  && set -- -C "$copt" "$@"
  [ -n "$cddir" ] && set -- -C "$cddir" "$@"
  git "$@" 2>/dev/null
}
effective_branch() { # <command> -> branch of the repo the command acts on
  local b
  b="$(effective_git "$1" branch --show-current)"
  [ -n "$b" ] && { printf '%s' "$b"; return 0; }
  branch
}

# Escape-aware extraction of the JSON command value — keeps `\"` intact (unlike jstr), the
# payload form the quote tokenizer below expects.
cmd_value() {
  printf '%s' "$payload" \
    | grep -oE '"command"[[:space:]]*:[[:space:]]*"(\\.|[^"\\])*"' | head -1 \
    | sed -E 's/^"command"[[:space:]]*:[[:space:]]*"//; s/"$//'
}

# quote_blank <mode> — blank quoted spans of the command value read on stdin, with a single
# LEFT-TO-RIGHT pass that models shell quoting (whichever quote opens FIRST wins until it
# closes; the other quote type is literal inside it). This replaces the earlier pair of
# INDEPENDENT global seds (`s/'…'/` then `s/\"…\"/`), which cross-paired quotes across span
# boundaries and silently blanked a REAL git verb: `echo "here's" && git commit -m "that's"`
# has two apostrophes that are LITERAL (inside `"…"`), yet the single-quote sed paired them and
# erased the commit; symmetrically a `"` inside `'…'` (`echo 'a"b' && git commit -m 'c"d'`) fooled
# the double-quote sed. A per-type regex, in either order, always leaves one such hole; only a
# stateful pass is correct (issue #256 review — adversarial hole-hunt on PR #258).
#   mode=all  — blank EVERY quoted span (command_skeleton: drop quoted/commented data verbs).
#   mode=data — blank single-quoted spans and double-quoted spans free of `$`/backtick, but
#               KEEP a substitution-bearing double-quoted span (subst_probe: a `$(…)`/backtick
#               there EXECUTES, so its verb must stay visible — see the vector detection).
# Double-quote delimiter is the payload's `\"` (backslash+quote); single is `'`. An unterminated
# span keeps its raw remainder — fail toward NOT blanking (over-block, never a new hole). The
# quote chars are passed via -v (sq/dq) so the awk program body carries no literal quote.
quote_blank() {
  awk -v mode="$1" -v sq="'" -v dq='"' '
  {
    line=$0; out=""; st=0; i=1; n=length(line); buf=""; hassub=0
    while (i<=n) {
      c=substr(line,i,1); c2=substr(line,i+1,1)
      if (st==0) {                                   # unquoted
        if (c==sq) { out=out" "; st=1; i++ }
        else if (c=="\\" && c2==dq) { st=2; buf=""; hassub=0; i+=2 }
        else { out=out c; i++ }
      } else if (st==1) {                            # single-quoted: always blank
        if (c==sq) { out=out" "; st=0 } else out=out" "
        i++
      } else {                                       # double-quoted: decide at close
        if (c=="\\" && c2==dq) {
          if (mode=="data" && hassub) { out=out "\\" dq buf "\\" dq }   # keep: substitution runs
          else { g=buf; gsub(/./," ",g); out=out"  " g }               # blank
          st=0; i+=2
        } else { buf=buf c; if (c=="$"||c=="`") hassub=1; i++ }
      }
    }
    if (st==2) out=out "\\" dq buf                   # unterminated " : keep raw (over-block)
    print out
  }'
}

# Command skeleton for the base-branch rules (3, 4): the invoked command with quoted argument
# spans and `#` comments BLANKED (and JSON newline/tab escapes normalized), so a `commit`/`push`
# verb that appears only inside a quoted argument (an rg/grep pattern, an echo string, a
# `commit -m` message) or in a comment no longer trips the base-branch rules (issue #256 — a
# recurring block on read-only `main`-branch work: issue-filing, neutrality scans). SAFETY:
# quoted text is NOT universally inert — a shell evaluator (`bash -c "…"`) or a command
# substitution (`$(…)`/backticks) EXECUTES quoted content, so blanking it there would hide a real
# command. The skeleton is therefore used ONLY when the command carries no such execution vector;
# the vector case matches the raw payload instead (see the target-selection at rules 3/4). Within
# a vector-free command, quoted spans and comments are genuinely non-executed, so blanking drops
# only FALSE matches — never a genuine invocation, which stays unquoted and is caught
# position-agnostically (so `if …; then git commit` and `GIT_DATE=… git commit` still match; there
# is deliberately no command-position anchor, which would miss those). Steps, in order:
#   1. cmd_value: escape-aware extraction of the command value (keeps `\"` intact);
#   2. quote_blank all: blank quoted spans with the correct stateful pass (see quote_blank);
#   3. `\t`->space and `\n`/`\r`->`;` — a newline becomes a command separator so a comment
#      ends at the line, WITHOUT a sed newline-in-replacement (stays BSD/GNU-portable);
#   4. blank a `#` comment (whitespace-/line-anchored so `${x#y}`, `$#`, `${#x}` — `#` after
#      a word or `{`/`$`, never after whitespace — are untouched) to the line's end (`;`).
# effective_branch still reads the real $cmd, so the #138/#173 effective-repo resolution is
# untouched.
command_skeleton() {
  cmd_value | quote_blank all \
    | sed -E 's/\\t/ /g; s/\\[nr]/;/g' \
    | sed -E 's/(^|[[:space:]])#[^;]*/\1/g'
}

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

# Resolve a possibly-relative edit path to an absolute, lexically-normalized form
# BEFORE the in_repo decision (issue #165). A relative IN-repo path (e.g.
# "AGENTS.md") must register as in-repo so the on-main rule DENIES it — the bare
# string was previously read as outside-repo and slipped the guard — while a
# relative path that ESCAPES the repo ("../outside") must still register as
# outside (ALLOW). Backslash separators are folded to '/' FIRST (matching norm()
# / norm_rel()) so the absolute-path test and the '.'/'..' collapse below treat a
# Windows-serialized path identically to its POSIX twin — without the fold a
# backslash escape ("..\outside") survives the slash-only collapse and norm()
# later rewrites it to "<root>/../outside", which the literal prefix test WRONGLY
# reads as in-repo (#175 review). Relative inputs then anchor on the repo root
# (= the hook cwd in this runtime; resolved via git so its spelling matches the
# root in_repo compares against), and '.'/'..' segments are collapsed LEXICALLY:
# a literal prefix test on an un-collapsed "<root>/../x" would WRONGLY match the
# root prefix (the over-capture the #165 control forbids). Pure lexical — no
# realpath/symlink/filesystem lookup, so a not-yet-created edit target resolves
# too. Already-absolute inputs (POSIX "/", Windows "C:\" -> "C:/", UNC "\\" ->
# "//") are left for norm() to canonicalize. Fail-open: an unreadable repo root
# leaves the path as-is (in_repo's own default still preserves the guard's strength).
abspath() {
  local p="$1" root='' prev=''
  p="$(printf '%s' "$p" | tr '\\' '/')"   # fold Windows '\' before the tests below
  case "$p" in
    /*|[a-zA-Z]:/*) ;;
    *) root="$(git rev-parse --show-toplevel 2>/dev/null)" \
         && [ -n "$root" ] && p="$root/$p" ;;
  esac
  p="$(printf '%s' "$p" | sed -E 's#/\./#/#g; s#/\.$#/#')"
  while [ "$p" != "$prev" ]; do
    prev="$p"
    p="$(printf '%s' "$p" | sed -E 's#/[^/]+/\.\.(/|$)#/#')"
  done
  printf '%s' "$p"
}

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
  fp="$(abspath "$fp")"          # #165: relative -> absolute before the prefix test
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
# A tier's models are the backticked names in its Model cell; later cells may
# carry other backticked attributes such as context-window values. Empty output
# means the row/table is unreadable and the caller must fail open.
models_file="${GUARD_MODELS_FILE:-$(cd "$(dirname "$0")" && pwd)/../MODELS.md}"
tier_models() {
  grep -iE "^\|[[:space:]]*\*\*\[$1 tier\]\*\*" "$models_file" 2>/dev/null | head -1 \
    | awk -F '|' '{ print $3 }' \
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
  fp="$(abspath "$fp")"          # #165: resolve a relative path so the checker + baseline (norm_rel) stay consistent
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
    # Match against the raw payload; the command field carries these verbatim. Each
    # rule allows a leading git global-option run (grun) before the subcommand, so a
    # `-C <path>` / `-c k=v` / `--git-dir=…` prefix no longer slips the matcher (#138
    # DW1). The trailing `\./?` folds in the `git add ./`-operand variant (#138 DW4).
    cmd="$(jstr command)"
    if printf '%s' "$payload" | grep -qE "git${grun}"'[[:space:]]+add[[:space:]]+(--all|-A|\./?)([[:space:]]|;|&|\\|")'; then
      block git-add-all "\`git add .\` / -A / --all is not allowed (AGENTS.md). Stage specific files:
   git add <path1> <path2>"
    fi
    # Target selection for the base-branch rules (3, 4) — issue #256. If the command can
    # EXECUTE the git verb from otherwise-blanked text, match the RAW payload (the original
    # over-blocking behavior — no hole); else the verb inside a quoted argument or a comment is
    # inert data, so match the blanked command_skeleton, which drops those false positives.
    # Two execution vectors are detected, on DIFFERENT targets:
    #   1. a shell evaluator token (`bash`/`sh`/`dash`/`zsh`/`ksh`/`ash`/`mksh`/`csh`/`tcsh`/
    #      `fish`, normally `… -c "…"`) or `eval` — it runs its quoted argument as shell.
    #      Detected in the SKELETON, not the raw payload: a genuine evaluator name is unquoted
    #      and survives blanking, while an evaluator word that is only quoted search DATA
    #      (`rg "bash -c git commit"`, `echo "bash" "git commit"`) is blanked away and no longer
    #      forces a raw match (issue #256 review finding 2 — the quoted-argument goal reached for
    #      the evaluator token itself). Each name is word-boundaried so `.sh`/`.csh` filenames,
    #      `ssh`, `git stash`, and `git push` do NOT false-trigger.
    #   2. a command substitution `$(…)`/backticks whose body holds the git verb (`$(git …
    #      commit)`) — it RUNS the body, even inside double quotes, at ANY nesting depth. Regex
    #      cannot balance parens, so rather than match the verb inside `$(…)` we build a probe
    #      that blanks only INERT quoted DATA — single-quoted spans, and PURE-DATA double-quoted
    #      spans (those with no `$`/backtick) — and KEEPS substitution-bearing double-quoted
    #      spans. If the probe still holds BOTH a substitution opener and the verb, the verb may
    #      execute, so a nested `$(echo $(date); git commit)` is caught at any depth (issue #256
    #      review High finding — a flat `$([^)]*…)` regex stopped at the inner `)` and hid the
    #      verb). A `$(…)` whose body LACKS the verb while the verb sits in a now-blanked data
    #      quote (`rg "git commit" $(fd -e md)`, `"$(git rev-parse --show-toplevel)"`) leaves no
    #      verb in the probe — NOT a vector, so read-only scans whose fileset/root is a
    #      substitution stay allowed.
    # A false vector hit only over-blocks (safe). NOT detected (accepted residual, documented in
    # the PR): a NON-shell interpreter shelling out from a quoted string (`python -c
    # "…os.system('git commit')"`, `perl -e`), `ssh host "…"`, a shell reached through a
    # variable (`$SHELL -c "…"` — the shell name never appears literally), or a niche shell not
    # in the set (`nu`/`rc`/`elvish`) — the guard backstops the agent's own ACCIDENTAL
    # base-branch writes, not adversarial evasion, and the human merge remains the wall.
    vsub="git${grun}"'[[:space:]]+(commit|push)'   # git + optional globals + the verb
    cmdv="$(cmd_value)"                             # extracted command value (reused below)
    # JSON-tab normalization for the RAW-target matches. The verb/refspec regexes use
    # `[[:space:]]`, which matches a whitespace BYTE — NOT the 2-char JSON escape `\t`. The shell
    # DECODES `\t` to a real tab and word-splits on it, so `git\tcommit` executes; the skeleton
    # already folds `\t`->space (command_skeleton), but the raw-payload/substitution-probe targets
    # did not, so a `\t` between `git` and the verb slipped rules 3/4 whenever a vector (bash -c /
    # esc_quote / a `$(…)`) routed the match onto raw (issue #256 review — round-3 hole-hunt).
    # Fold `\t`->space on those targets too. `\n`/`\r` are NOT folded here — they decode to command
    # SEPARATORS that split the verb, so they cannot smuggle one.
    payload_ns="$(printf '%s' "$payload" | sed -E 's/\\t/ /g')"
    skel="$(command_skeleton)"
    evaltok='(^|[^[:alnum:]_.])(bash|dash|zsh|ksh|ash|mksh|csh|tcsh|fish|eval)([^[:alnum:]_]|$)|(^|[^[:alnum:]_.])sh([^[:alnum:]_]|$)'
    # Substitution probe (quote_blank data): blank inert quoted data — single-quoted spans, and
    # double-quoted spans free of `$`/backtick — but KEEP a substitution-bearing double-quoted
    # span, whose `$(…)`/backtick verb executes. Same stateful pass as the skeleton, so it inherits
    # the correct quote handling (no apostrophe/`"` cross-pairing hole). A verb inside a live `$(…)`
    # is shielded by the `$` that keeps its span, so the probe stays fail-safe.
    subst_probe="$(printf '%s' "$cmdv" | quote_blank data | sed -E 's/\\t/ /g')"
    # Escaped-quote fail-safe. quote_blank models plain shell quoting but NOT backslash-escaping
    # of a quote: a shell `\"`/`\'` (JSON `\\\"` / `\\'`) is a LITERAL quote, not a delimiter, and
    # an odd number of them flips the tokenizer's quoted/unquoted parity — desyncing it so a real
    # unquoted `git commit`/`git push` can land in a phantom span and be blanked (a hole; issue
    # #256 review — the round-2 hole-hunt on the tokenizer). Rather than fully parse shell escaping
    # (escaped separators/verbs are their own rabbit hole), detect the escape and match the RAW
    # payload — over-block, never a hole. The pattern is a shell backslash (`\\`) immediately before
    # a shell quote; a backslash before a non-quote (an escaped pipe `\|` in a BRE scan, a path
    # `\\`) does NOT trigger, so ordinary read-only scans are unaffected.
    esc_quote='\\\\(\\"|'\'')'
    if printf '%s' "$skel" | grep -qE "$evaltok" \
       || { printf '%s' "$subst_probe" | grep -qE '\$\(|`' && printf '%s' "$subst_probe" | grep -qE "$vsub"; } \
       || printf '%s' "$cmdv" | grep -qE "$esc_quote"; then
      vector=1; target="$payload_ns"
    else
      vector=0; target="$skel"
    fi
    # Branch-gated: resolve the EFFECTIVE repo (a `-C <path>` / `cd <path> &&` target),
    # not just the event cwd, so a commit/push into a different on-base repo is caught
    # (#138 DW2). effective_branch falls back to the event-cwd branch when unreadable.
    # The pattern stays position-AGNOSTIC (no command-position anchor), so a genuine
    # invocation after a shell keyword or an env-assignment prefix (`if …; then git commit`,
    # `GIT_DATE=… git commit`) still matches. The trailing boundary spans both targets: the
    # JSON `\`/`"` of the raw payload and the `;`/`&`/`|`/`)`/end-of-string of the skeleton
    # (which has the outer JSON quote stripped, so a bare `git push` at the end needs `$`).
    if printf '%s' "$target" | grep -qE "git${grun}"'[[:space:]]+(commit|push)([[:space:]]|[;&|)]|\\|"|$)' && [ "$(effective_branch "$cmd")" = "main" ]; then
      block commit-push-on-main "Never commit or push to 'main' (AGENTS.md). Work on a feature branch and open a PR."
    fi
    # Refspec rule: a push can target main from ANY branch (`git push origin HEAD:main`),
    # so match the destination ref, not just the current branch. [^";&|]* keeps the match
    # inside a single shell command, so `git push ... && gh pr create --base main` is allowed.
    #
    # A real push's DESTINATION is genuine even when the refspec is QUOTED (`git push origin
    # 'HEAD:main'`, issue #256 review Codex P1) — the command_skeleton blanks that quoted span,
    # so matching only the skeleton would miss it. So whenever a REAL push exists — an execution
    # vector runs it, or an unquoted `git push` verb survives in the skeleton — ALSO match the
    # RAW payload, where the quoted `main` is still present (`[^";&|]` spans the single quotes of
    # 'HEAD:main' / ':main' / 'feature:main'). When the push verb is quoted DATA (`rg "git push
    # origin main"` — no vector, no skeleton push verb), real_push stays 0 and the raw is never
    # consulted, so the #256 read-only-scan allow is preserved. (A DOUBLE-quoted refspec
    # `"…:main"` is a pre-existing rule-4 gap — the `[^";&|]` boundary excludes `"` to stay
    # within one command — unchanged by #256 and out of its scope.)
    refspec="git${grun}"'[[:space:]]+push[^";&|]*(:|[[:space:]])(refs/heads/)?main([^a-zA-Z0-9_./-]|$)'
    real_push=0
    [ "$vector" = 1 ] && real_push=1
    printf '%s' "$skel" | grep -qE "git${grun}"'[[:space:]]+push([[:space:]]|[;&|)]|\\|"|$)' && real_push=1
    if [ "$real_push" = 1 ]; then
      if printf '%s' "$skel" | grep -qE "$refspec" || printf '%s' "$payload_ns" | grep -qE "$refspec"; then
        block push-refspec-main "This push targets 'main' (refspec). Never push to 'main' (AGENTS.md) — push the feature branch and open a PR."
      fi
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
    # Rule 8: pending-commit tasks-drift check (issue #202 / T633). A commit
    # whose message carries [T<nnn>] while that task's box is still `- [ ]` in
    # a live specs/*/tasks.md would land done-but-unchecked drift that CI's
    # check-tasks-consistency.sh (the authoritative backstop — unchanged, P5)
    # only surfaces after a push→CI round-trip. The attempted commit is NOT yet
    # reachable from `git log`, so its ids come from the command payload itself
    # — extracted escape-aware, since the [T###] lives inside the JSON string's
    # \"…\" message where jstr's [^"]* would truncate. The unchecked-box half is
    # SHARED from lib-tasks-drift.sh (tasks_drift_unchecked_ids) — one drift
    # definition, never a fork (P2). Two resolution rules (PR #208 review, both P2):
    #   • REPO: the tasks state is read from the repo the commit TARGETS — the
    #     invocation's own `-C`/`--git-dir`, or a leading `cd … &&`, resolved
    #     via effective_git exactly like rule 3 — falling back to the event-cwd
    #     repo when no locator resolves.
    #   • VIEW: a plain `git commit` lands the INDEX, so the boxes are read from
    #     the STAGED tasks files (materialized via `git show :<path>` into a
    #     temp dir the shared lib greps, keeping the one drift definition) — a
    #     tick left only in the working tree still lands `- [ ]` and is drift.
    #     A worktree-landing form (`-a`/`--all`/`--include`, or a pathspec
    #     naming a tasks file) reads the working tree instead; the form
    #     detection is textual and fail-open — a false worktree read only
    #     weakens back to the pre-#208 read, never a false block. (A pathspec
    #     commit that EXCLUDES a staged tasks fix lands HEAD's boxes — residual
    #     miss, accepted: CI stays authoritative.)
    # Fail-open: no [T###] in the command, a missing lib, an unreadable repo
    # root, no live tasks files, or an unmaterializable index view all allow.
    if printf '%s' "$payload" | grep -qE "git${grun}"'[[:space:]]+commit([[:space:]]|\\|")'; then
      cmdq="$(printf '%s' "$payload" \
        | grep -oE '"command"[[:space:]]*:[[:space:]]*"(\\.|[^"\\])*"' | head -1)"
      pend="$(printf '%s' "$cmdq" | grep -oE '\[T[0-9]+\]' | tr -d '[]' | sort -u)"
      drift_lib="$(cd "$(dirname "$0")" && pwd)/lib-tasks-drift.sh"
      root="$(effective_git "$cmd" rev-parse --show-toplevel)"
      [ -n "$root" ] || root="$(git rev-parse --show-toplevel 2>/dev/null)"
      if [ -n "$pend" ] && [ -f "$drift_lib" ] && [ -n "$root" ]; then
        view="$root"; staged=''
        if ! printf '%s' "$cmdq" | grep -qE 'tasks\.md|[[:space:]]--(all|include)([[:space:]=]|\\|"|$)|[[:space:]]-[a-zA-Z]*a[a-zA-Z]*([[:space:]]|\\|"|$)'; then
          staged="$(mktemp -d 2>/dev/null)" || staged=''
          if [ -n "$staged" ]; then
            git -C "$root" ls-files -- 'specs/*/tasks.md' 2>/dev/null \
            | while IFS= read -r tf; do
                [ -n "$tf" ] || continue
                mkdir -p "$staged/${tf%/*}" 2>/dev/null || continue
                git -C "$root" show ":$tf" > "$staged/$tf" 2>/dev/null
              done
            view="$staged"
          fi
        fi
        unchecked="$( (cd "$view" && . "$drift_lib" && tasks_drift_unchecked_ids) 2>/dev/null )"
        [ -n "$staged" ] && rm -rf "$staged"
        drifted=''
        for id in $pend; do
          printf '%s\n' "$unchecked" | grep -qxF "$id" && drifted="$drifted $id"
        done
        if [ -n "$drifted" ]; then
          block commit-tasks-drift "This commit's message references$(printf ' [%s]' $drifted) but that task's box in specs/*/tasks.md is still '- [ ]' in what this commit will land — done-but-unchecked drift the CI consistency check will fail after push. Tick the box (- [x]) in the tasks file AND stage it in this commit (git add <tasks-file>), or drop the id if the work is not that task's. (Advisory local copy of check-tasks-consistency.sh rule 3; CI stays authoritative.)"
        fi
      fi
    fi
    ;;
  Agent|Task)
    # Rule 5: the strong-tier floor for the values / spec-quality [reviewer]s.
    # Both the constitution [reviewer] and the spec-quality [reviewer] (issue
    # #147) are pinned at-or-above the [strong tier] (DESIGN-NOTES §6): the
    # cheapest place to lose a project is shipping a constitution violation, or
    # grading every later diff against a bad spec, on a downgraded model. The
    # auditor agents carry no model pin (the model table owns all model names),
    # so an omitted `model` parameter silently inherits the session model — on a
    # cheap-tier session, exactly the downgrade the floor forbids. Unknown model
    # names and an unreadable table fail open; the acceptance/contract reviewers
    # and all other subagents are untouched.
    sub="$(jstr subagent_type)"
    case "$sub" in
      constitution-auditor|spec-quality-auditor)
        # Liveness signal (workflow/telemetry.md): a floored reviewer's dispatch
        # logs one `evaluation` record whatever the check's outcome, so a live
        # guard is distinguishable from "nothing to block" — the constitution
        # reviewer fires on every gate run, the spec-quality reviewer on every
        # spec-touching one.
        log_telemetry evaluation strong-floor
        strong="$(tier_models strong)"
        if [ -n "$strong" ]; then
          model="$(jstr model)"
          if [ -z "$model" ]; then
            block strong-floor-no-model "$sub dispatched without a 'model' parameter — it would inherit the session model and can silently break the [strong tier] floor. Pass the strong-tier model from .claude/MODELS.md explicitly on the dispatch."
          fi
          if ! model_in "$model" $strong $(tier_models frontier) \
             && model_in "$model" $(tier_models cheap); then
            block strong-floor-below "$sub dispatched below the [strong tier] floor (model: '$model'). This reviewer never downgrades — pass a model at-or-above the strong-tier row of .claude/MODELS.md."
          fi
        fi
        ;;
    esac
    ;;
esac
exit 0
