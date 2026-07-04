#!/usr/bin/env bash
# backlog-loop-select.sh — the [backlog-loop]'s real selection binding (T905,
# spec 004 US1.AC7; neutral model: .claude/workflow/backlog-loop.md → "The loop").
#
# The concrete BACKLOG_LOOP_SELECT_CMD for backlog-loop.sh: prints the
# lowest-numbered unchecked task across the live tasks files whose dependencies
# are met, excluding the profile/tasks-file blocked lists and every identity
# passed as an argument (the loop's skip/ineligible bookkeeping). Prints nothing
# when no candidate remains (stop condition (b), backlog-drained). Adapter-side,
# so it may name concrete files — it is NOT a `workflow/**` neutral doc.
#
# Deliberately a pure tasks-file reader: it does NOT reconcile live git/tracker
# state. A drifted or in-flight candidate is refused INSIDE the cycle by
# [live-state reconciliation] (next-task.md §1), which the loop consumes as the
# `refused` outcome and marks ineligible — selection here stays deterministic
# and offline (no git, no network).
#
# Usage: backlog-loop-select.sh [excluded-id ...]
#   Run from the repo root (the lib-tasks-drift.sh CWD convention): reads the
#   live tasks files at specs/*/tasks.md (skeleton *.template.md files never
#   match) and the profile at .claude/PROJECT.md
#   (override: BACKLOG_LOOP_SELECT_PROFILE, a test seam).
#
# Selection contract (each rule deterministic, documented here and pinned by
# .claude/hooks/backlog-loop-select.test.sh):
#   * candidates      — `- [ ] T<n>` lines in any live tasks file;
#   * excluded ids    — any argument, matched whole-id (T90 never excludes T901);
#   * blocked lists   — in the profile and every live tasks file, a
#                       "Blocked / owner-only tasks" section bullet that STARTS
#                       with a task ID (`- T<n> …`) excludes that task; prose
#                       mentions elsewhere in a bullet (e.g. "- none. (T101 …)")
#                       do not (never auto-start — the loop surfaces them by
#                       draining around them);
#   * dependencies    — a candidate entry (its `- [ ]` line plus indented
#                       continuation lines) carrying a `Blocked by` clause is
#                       eligible only when EVERY task ID it references —
#                       `T<a>`, and each id in a `T<a>–T<b>`/`T<a>-T<b>` range —
#                       is checked (`- [x]`) in a live tasks file. A referenced
#                       id that exists nowhere, or a malformed range, reads as
#                       UNMET (fail closed toward not starting);
#   * winner          — the numerically lowest surviving id, printed alone.
# Output: exactly one task ID, or nothing (backlog drained). Exit 0 on both;
# exit 1 (LOUD) when no live tasks file is readable at all — a selector that
# cannot see the backlog must fail closed (the loop's condition (d)), never
# report a drained backlog it never read.
# Tests: .claude/hooks/backlog-loop-select.test.sh (wired into CI verify).
set -u

PROFILE="${BACKLOG_LOOP_SELECT_PROFILE:-.claude/PROJECT.md}"

# ── the backlog (fail LOUD when unreadable — never a silent "drained") ─────────
tasks_files=""
for f in specs/*/tasks.md; do
  [ -f "$f" ] && tasks_files="$tasks_files$f
"
done
if [ -z "$tasks_files" ]; then
  echo "backlog-loop-select: no live tasks file at specs/*/tasks.md under $PWD — cannot select (failing closed)" >&2
  exit 1
fi

checked_ids="$(grep -hoE '^- \[x\] T[0-9]+' specs/*/tasks.md 2>/dev/null \
  | grep -oE 'T[0-9]+')"

id_checked() { printf '%s\n' "$checked_ids" | grep -qxF "$1"; }

# ── blocked lists (profile + every live tasks file) ────────────────────────────
# Bullets that START with a task ID inside a "Blocked / owner-only tasks"
# section, the section ending at the next heading. POSIX awk; no {n} intervals
# (shell-lint.sh, #97). A missing profile only degrades this list, never the
# candidate scan (the awk still emits every earlier file's hits).
blocked_ids="$(
  # shellcheck disable=SC2086 # tasks_files is a newline list of glob-safe paths
  awk '
    /^#+ / { insec = (index($0, "Blocked / owner-only tasks") > 0) ? 1 : 0; next }
    insec && /^[-*][ \t]+T[0-9]/ {
      s = $2
      gsub(/[^0-9A-Za-z].*$/, "", s)
      print s
    }
  ' $tasks_files "$PROFILE" 2>/dev/null | sort -u
)"

id_blocked() { printf '%s\n' "$blocked_ids" | grep -qxF "$1"; }

# ── entry text (the `- [ ]` line + its indented continuation lines, joined) ────
entry_text() { # <id> <file>
  awk -v id="$1" '
    found && /^[ \t]/ { printf " %s", $0; next }
    found { exit }
    index($0, "- [ ] " id " ") == 1 || $0 == "- [ ] " id { found = 1; printf "%s", $0 }
    END { if (found) printf "\n" }
  ' "$2"
}

# ── dependency check: every id referenced after "Blocked by" must be checked ───
deps_met() { # <entry-text> -> 0 met / 1 unmet
  local entry="$1" clause tok lo hi n
  case "$entry" in *"Blocked by"*) ;; *) return 0 ;; esac
  clause="${entry#*Blocked by}"
  # Normalize the range en-dash to an ASCII hyphen FIRST (a byte-sequence sed,
  # correct under any locale), so every later pattern is plain ASCII.
  clause="$(printf '%s\n' "$clause" | sed 's/–/-/g')"
  for tok in $(printf '%s\n' "$clause" | grep -oE 'T[0-9]+(-T[0-9]+)?'); do
    case "$tok" in
      *-T*)
        lo="${tok%%-*}"; hi="${tok#*-}"
        lo="${lo#T}"; hi="${hi#T}"
        case "$lo$hi" in *[!0-9]*) return 1 ;; esac
        { [ "$lo" -le "$hi" ] && [ $((hi - lo)) -lt 1000 ]; } || return 1
        n="$lo"
        while [ "$n" -le "$hi" ]; do
          id_checked "T$n" || return 1
          n=$((n + 1))
        done
        ;;
      *)
        id_checked "$tok" || return 1
        ;;
    esac
  done
  return 0
}

# ── candidates: unchecked ids, filtered, numerically lowest wins ───────────────
best_id=""
best_num=""
while IFS= read -r file; do
  [ -n "$file" ] || continue
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    excluded=0
    for x in "$@"; do
      if [ "$x" = "$id" ]; then excluded=1; break; fi
    done
    [ "$excluded" -eq 0 ] || continue
    id_blocked "$id" && continue
    num="${id#T}"
    if [ -n "$best_num" ] && [ "$num" -ge "$best_num" ]; then continue; fi
    deps_met "$(entry_text "$id" "$file")" || continue
    best_id="$id"
    best_num="$num"
  done <<EOF2
$(grep -oE '^- \[ \] T[0-9]+' "$file" 2>/dev/null | grep -oE 'T[0-9]+')
EOF2
done <<EOF
$tasks_files
EOF

[ -z "$best_id" ] || printf '%s\n' "$best_id"
exit 0
