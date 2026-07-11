#!/usr/bin/env bash
# doc-pointer-check.sh — deterministic doc-pointer resolution check (T1208,
# spec 007 US8; issue #273).
#
# Scans the pointer-bearing documentation surfaces, extracts the backtick-quoted
# repo-relative path pointers they contain, and FAILs when any such path does not
# exist from the repo root — naming the offending surface, the unresolved path,
# and its line (US8.AC1; the diagnostics rule, US6.AC3). The class this closes:
# a rename/move under .claude/ silently strands every doc reference (found on
# PR #272 — bare `workflow/…` pointers that resolve only under `.claude/`).
#
# A path pointer is recognized by SHAPE — a backtick token carrying a `/`
# separator and a file-type suffix — minus the non-path forms (US8.AC2):
# whitespace-bearing tokens (commands, `→ "Heading"` anchors), `*` globs,
# `{…,…}` brace-expansions, `<…>` placeholders — and minus any token that is
# not lexically repo-relative: absolute paths (leading `/`), `..` parent
# traversal, and `scheme://` URIs are OUT OF CONTRACT — never resolved and
# never flagged (US8.AC1), so the check is deterministic across machines and
# a documentation URL is never mis-flagged.
#
# Candidacy does NOT depend on the token's leading segment already existing and
# carries no segment allowlist — a bare `workflow/…md` pointer is a candidate
# and then fails the existence check (leading-segment-agnostic, US8.AC1; proven
# by the held-out planted case in doc-pointer-check.test.sh).
#
# Scope: path existence only — section-anchor resolution is a deferred
# follow-on (spec 007 non-goals; issue #273).
#
# Resolves candidates by joining them to the repo root = CWD (the same CWD
# contract compact-packet-drift.sh / token-budget-check.sh use; CI runs it from
# the repo root). Bash + grep only — no git, no network.
#
# Run:      bash .claude/hooks/doc-pointer-check.sh [surface ...]
#           (no args → the default surface set below)
# Extract:  bash .claude/hooks/doc-pointer-check.sh --extract [surface ...]
#           prints `surface:line:path` per candidate, no existence check — the
#           test suite's positive-extraction assertion runs this unmodified
#           extractor against a hand-verified oracle (US8.AC1 non-vacuity).
set -u
export LC_ALL=C

MODE=check
if [ "${1:-}" = "--extract" ]; then
  MODE=extract
  shift
fi

if [ "$#" -gt 0 ]; then
  SURFACES=("$@")
else
  SURFACES=(AGENTS.md .claude/PROJECT.md .claude/PROJECT.compact.md)
fi

failures=0
resolved=0

for f in "${SURFACES[@]}"; do
  if [ ! -f "$f" ]; then
    echo "FAIL: surface '$f' not found from $(pwd) — run from the repo root (repair: restore the surface or fix the scanned-surface list)" >&2
    failures=$((failures + 1))
    continue
  fi
  # Each backtick-quoted token with its line number; a line may carry several.
  while IFS= read -r rec; do
    line="${rec%%:*}"
    tok="${rec#*:}"
    tok="${tok#\`}"
    tok="${tok%\`}"
    case "$tok" in
      '') continue ;;                              # empty span
      *[[:space:]]*) continue ;;                   # command/flag tokens, anchors
      *'*'* | *'{'* | *'}'* | *'<'* | *'>'*) continue ;; # globs, braces, placeholders
      *'://'*) continue ;;                         # scheme:// URI — out of contract
      /*) continue ;;                              # absolute path — out of contract
      .. | ../* | */.. | */../*) continue ;;       # parent traversal — out of contract
      */*) ;;                                      # has the / separator — keep going
      *) continue ;;                               # no separator — not a path pointer
    esac
    # file-type suffix required (e.g. .md/.sh/.py); bare dirs are out of scope
    printf '%s' "$tok" | grep -qE '\.[A-Za-z0-9]{1,10}$' || continue

    if [ "$MODE" = "extract" ]; then
      printf '%s:%s:%s\n' "$f" "$line" "$tok"
      continue
    fi
    if [ -e "$tok" ]; then
      resolved=$((resolved + 1))
    else
      echo "FAIL: dangling pointer: $f:$line: \`$tok\` does not exist from the repo root (repair: point it at the file's real path — the target may live under .claude/ or have moved — or restore the missing file)" >&2
      failures=$((failures + 1))
    fi
  done < <(grep -n -o '`[^`]*`' "$f" || true)
done

if [ "$failures" -gt 0 ]; then
  echo "doc-pointer check: FAIL ($failures dangling pointer(s)/unreadable surface(s); surfaces: ${SURFACES[*]})" >&2
  exit 1
fi
if [ "$MODE" = "check" ]; then
  echo "doc-pointer check: OK ($resolved path pointer(s) resolve across ${#SURFACES[@]} surface(s))"
fi
