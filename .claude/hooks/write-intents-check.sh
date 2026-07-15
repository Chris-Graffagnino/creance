#!/usr/bin/env bash
# write-intents-check.sh — deterministic write-intent / safe-output contract check
# (T636, issue #232; constitution P1/P3).
#
# Verifies the closed write-intent role family end-to-end, both directions:
#   1. The contract (workflow/README.md → "Write intents (safe outputs)") defines a
#      non-empty, enumerated family — an empty/unparseable family FAILs loud (P2,
#      never a vacuous pass).
#   2. Every intent the profile declares (PROJECT.md → "Write intents") is a member
#      of the contract family — an unknown/catch-all intent FAILs.
#   3. Every declared intent has a mapping row in the active adapter's write-intent
#      table (.claude/README.md) — a declared-but-unmapped intent FAILs (direction a).
#   4. Every required writing workflow has a declaration row (possibly `none`) — a
#      writing ritual with no declared set FAILs (the "too narrow" direction).
#   5. No neutral workflow doc names a concrete tracker write command (e.g. a
#      `gh issue comment` form) where an intent role exists (direction b, P1) —
#      the dedicated leak scan alongside the general neutrality scanner.
#
# Surfaces are overridable for fixture-based falsification tests
# (write-intents-check.test.sh); defaults are the live tree read from the repo
# root = CWD (the same CWD contract doc-pointer-check.sh uses).
#
# Run: bash .claude/hooks/write-intents-check.sh
set -u
export LC_ALL=C

CONTRACT="${WIC_CONTRACT:-.claude/workflow/README.md}"
PROFILE="${WIC_PROFILE:-.claude/PROJECT.md}"
ADAPTER="${WIC_ADAPTER:-.claude/README.md}"
WORKFLOW_DIR="${WIC_WORKFLOW_DIR:-.claude/workflow}"
REQUIRED_WORKFLOWS="${WIC_REQUIRED_WORKFLOWS:-next-task pr-review review-response triage intake retrospective}"

failures=0
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}

for f in "$CONTRACT" "$PROFILE" "$ADAPTER"; do
  if [ ! -f "$f" ]; then
    echo "FAIL: surface '$f' not found from $(pwd) — run from the repo root" >&2
    echo "write-intents check: FAIL (surface missing)" >&2
    exit 1
  fi
done

# --- 1. The contract family: role-defining table rows (`| **[<op> output]** | ...`)
# in the contract surface. Row-anchored so prose references elsewhere don't count.
family="$(grep -oE '^\| \*\*\[[a-z][a-z-]* output\]\*\*' "$CONTRACT" | grep -oE '\[[a-z][a-z-]* output\]' | sort -u)"
if [ -z "$family" ]; then
  fail "contract surface '$CONTRACT' defines no write-intent role rows — the closed family is empty or unparseable (repair: restore the \"Write intents (safe outputs)\" table)"
fi

in_family() { # in_family <[role]> -> 0/1
  printf '%s\n' "$family" | grep -qFx "$1"
}

# --- 3's input: the adapter mapping rows (same row-anchored shape). A mapping row
# must carry a non-empty mechanism/degradation cell — a bare role row maps nothing
# (the binding contract requires a concrete mechanism or a documented degradation).
adapter_row_lines="$(grep -nE '^\| \*\*\[[a-z][a-z-]* output\]\*\*' "$ADAPTER")" || adapter_row_lines=""
adapter_rows=""
while IFS= read -r numbered; do
  [ -n "$numbered" ] || continue
  lineno="${numbered%%:*}"
  row="${numbered#*:}"
  role="$(printf '%s' "$row" | grep -oE '\[[a-z][a-z-]* output\]' | head -n 1)"
  cell="$(printf '%s' "$row" | sed -E 's/^\| \*\*\[[a-z][a-z-]* output\]\*\* \|(.*)\|[[:space:]]*$/\1/')"
  if [ "$cell" = "$row" ] || ! printf '%s' "$cell" | grep -qE '[^[:space:]]'; then
    fail "adapter mapping row for '$role' ($ADAPTER:$lineno) has an empty mechanism/degradation cell — a bare role row maps nothing (repair: name the concrete mechanism, or the documented degradation)"
  fi
  adapter_rows="$adapter_rows$role
"
done <<< "$adapter_row_lines"
adapter_rows="$(printf '%s' "$adapter_rows" | sort -u)"

has_adapter_row() {
  printf '%s\n' "$adapter_rows" | grep -qFx "$1"
}

# --- 2 + 3 + 4. The profile declaration table: rows shaped `| `<workflow>` | ... |`.
# NOTE: backticks are NOT backslash-escaped in these EREs — GNU grep/sed treat
# `\`` as a start-of-buffer anchor (BSD treats it as a literal), so escaping
# silently empties every match on Linux (caught by CI on PR #285).
decl_rows="$(grep -E '^\| `[a-z][a-z-]*` \|' "$PROFILE")" || decl_rows=""
if [ -z "$decl_rows" ]; then
  fail "profile surface '$PROFILE' carries no write-intent declaration rows (repair: restore the \"Write intents\" table)"
fi

declared_workflows=""
while IFS= read -r row; do
  [ -n "$row" ] || continue
  wf="$(printf '%s' "$row" | sed -E 's/^\| `([a-z][a-z-]*)` \|.*/\1/')"
  cell="$(printf '%s' "$row" | sed -E 's/^\| `[a-z][a-z-]*` \|(.*)\|$/\1/')"
  declared_workflows="$declared_workflows $wf"
  intents="$(printf '%s' "$cell" | grep -oE '\[[a-z][a-z-]* output\]')" || intents=""
  if [ -z "$intents" ]; then
    # An empty intent list is legal ONLY as the literal `none`.
    if ! printf '%s' "$cell" | grep -qE '^[[:space:]]*none[[:space:]]*$'; then
      fail "workflow '$wf' declares neither an intent role nor the literal 'none' in '$PROFILE' (repair: declare its allowed intents, or 'none' for a read-only posture)"
    fi
    continue
  fi
  while IFS= read -r intent; do
    [ -n "$intent" ] || continue
    if ! in_family "$intent"; then
      fail "workflow '$wf' declares '$intent', which is not in the contract's closed family ('$CONTRACT') (repair: use a family role, or add the role there by reviewed PR)"
    fi
    if ! has_adapter_row "$intent"; then
      fail "declared intent '$intent' (workflow '$wf') has no mapping row in the active adapter '$ADAPTER' (repair: add its intent→mechanism row or a documented degradation)"
    fi
  done <<< "$intents"
done <<< "$decl_rows"

for wf in $REQUIRED_WORKFLOWS; do
  if ! printf '%s\n' $declared_workflows | grep -qFx "$wf"; then
    fail "writing workflow '$wf' has no declaration row in '$PROFILE' — a missing row is a defect, not an implicit empty set (repair: add its row, 'none' if it writes nothing)"
  fi
done

# --- 5. Leak scan (direction b): neutral workflow docs must not name concrete
# tracker write commands — an intent role exists for each of these operations.
LEAK_PATTERN='\bgh[[:space:]]+(issue|pr)[[:space:]]+(create|comment|edit|close|reopen|merge|review|ready|lock)\b|\bgh[[:space:]]+api\b'
if [ -n "${WIC_WORKFLOW_DIR+x}" ]; then
  docs="$(find "$WORKFLOW_DIR" -name '*.md' -type f | sort)"
else
  docs="$(git ls-files "$WORKFLOW_DIR" | grep -E '[.]md$')" || docs=""
fi
if [ -z "$docs" ]; then
  fail "no neutral workflow docs found under '$WORKFLOW_DIR' — the leak scan has nothing to cover (P2, never a vacuous pass)"
fi
while IFS= read -r doc; do
  [ -n "$doc" ] || continue
  hits="$(grep -nE "$LEAK_PATTERN" "$doc")" || hits=""
  if [ -n "$hits" ]; then
    while IFS= read -r hit; do
      fail "concrete tracker write command in neutral doc $doc:${hit%%:*} — name the write-intent role instead (P1): ${hit#*:}"
    done <<< "$hits"
  fi
done <<< "$docs"

if [ "$failures" -gt 0 ]; then
  echo "write-intents check: FAIL ($failures finding(s))" >&2
  exit 1
fi
family_n="$(printf '%s\n' "$family" | grep -c .)"
echo "write-intents check: OK (closed family of $family_n intent role(s); every declared intent mapped; no neutral-doc write-command leak)"
