#!/usr/bin/env bash
# compact-packet-drift.sh — deterministic drift check between the compact project
# packet (.claude/PROJECT.compact.md) and the full profile (.claude/PROJECT.md)
# (T1203, spec 007 US3.AC2; epic #166).
#
# The packet is the DEFAULT profile read for ordinary workflow runs (US3.AC3); the
# full profile stays the source of truth. A hand-maintained summary with no drift
# detection is exactly the failure class spec 007 forbids (non-goals; the
# silently-dead-guard class, constitution P2) — so every covered field below is
# extracted from BOTH files with anchored, deterministic greps and compared, and a
# mismatch FAILs naming the drifted field plus the repair target (spec 007 US6.AC3's
# diagnostics rule). An extraction anchor that stops matching (the profile or packet
# was restructured) FAILs loud as the same field — never a vacuous pass.
#
# Covered fields (US3.AC1's routing-fact list):
#   base-branch, required-check, merge-gate, repo-model, autonomy-opt-in,
#   constitution-path, telemetry-path, spec-paths, tasks-paths, title-conventions,
#   branch-convention, task-id-format, tier-tags, issue-lifecycle, blocked-tasks,
#   review-passes, checker-map, invariant-count, invariant-backstops
#
# Every active routing fact the packet carries is covered here — if a fact is worth
# putting in the packet it is worth drift-checking, so a packet-only edit to it fails
# rather than passing vacuously (the silently-dead-guard class this whole check exists
# to close; PR #249 review). blocked-tasks is compared as a none/present classification
# (the live profile lists none; if entries ever appear, the mismatch forces the packet
# update and this check then needs the deeper per-entry comparison). Anything in the
# packet outside the covered fields is deliberately-uncovered prose — keep it minimal.
#
# Resolves paths relative to CWD (the same CWD contract token-budget-check.sh uses;
# CI runs it from the repo root). Bash + grep/sed/awk only — no git, no network.
# Run: bash .claude/hooks/compact-packet-drift.sh
set -u
export LC_ALL=C

PROFILE=".claude/PROJECT.md"
PACKET=".claude/PROJECT.compact.md"
BT='`'
failures=0

fail() { # <field> <detail>
  echo "FAIL: field '$1': $2" >&2
  echo "      (repair: update $PACKET to mirror $PROFILE on this field — or, if the profile itself is wrong, fix it there; the full profile is the source of truth)" >&2
  failures=$((failures + 1))
}

for f in "$PROFILE" "$PACKET"; do
  if [ ! -f "$f" ]; then
    echo "FAIL: $f not found in $(pwd) — run from the repo root (repair: restore $f; this check compares the compact packet against the full profile)" >&2
    exit 1
  fi
done

# section <file> <literal heading prefix>: the lines under the first heading whose
# line STARTS with the prefix, up to (not including) the next heading.
section() {
  awk -v s="$2" '
    inblk && /^#/ { exit }
    inblk { print }
    index($0, s) == 1 { inblk = 1 }
  ' "$1"
}

# tokens: stdin -> each `backticked` token, one per line, backticks stripped.
tokens() { grep -o '`[^`]*`' | tr -d '\140'; }

# line_tokens <file> <line prefix>: tokens of the first line starting with <prefix>.
line_tokens() { grep "^$2" "$1" 2>/dev/null | head -1 | tokens; }

# compare_scalar <field> <profile-value> <packet-value>
compare_scalar() {
  if [ -z "$2" ]; then
    fail "$1" "could not extract the value from $PROFILE (the check's anchor no longer matches — fix the anchor or the profile line)"
  elif [ -z "$3" ]; then
    fail "$1" "could not extract the value from $PACKET (the packet line is missing or renamed)"
  elif [ "$2" != "$3" ]; then
    fail "$1" "packet has '$3' but profile has '$2'"
  fi
}

# compare_sets <field> <profile-set> <packet-set> — newline-separated values.
compare_sets() {
  local field="$1" p_sorted k_sorted missing stale
  p_sorted="$(printf '%s\n' "$2" | grep . | sort -u)"
  k_sorted="$(printf '%s\n' "$3" | grep . | sort -u)"
  if [ -z "$p_sorted" ]; then
    fail "$field" "could not extract any value from $PROFILE (the check's anchor no longer matches — fix the anchor or the profile section)"
    return
  fi
  if [ -z "$k_sorted" ]; then
    fail "$field" "could not extract any value from $PACKET (the packet section is missing or renamed)"
    return
  fi
  missing="$(comm -23 <(printf '%s\n' "$p_sorted") <(printf '%s\n' "$k_sorted") | tr '\n' ' ' | sed 's/ $//')"
  stale="$(comm -13 <(printf '%s\n' "$p_sorted") <(printf '%s\n' "$k_sorted") | tr '\n' ' ' | sed 's/ $//')"
  if [ -n "$missing" ] || [ -n "$stale" ]; then
    fail "$field" "packet disagrees with profile — missing from packet: [${missing:-none}]; stale in packet: [${stale:-none}]"
  fi
}

# --- base-branch -------------------------------------------------------------
p_base="$(sed -n 's/^- \*\*Base branch:\*\* *//p' "$PROFILE" | head -1 | sed 's/[[:space:]]*$//')"
k_base="$(line_tokens "$PACKET" "- Base branch:" | head -1)"
compare_scalar "base-branch" "$p_base" "$k_base"

# --- required-check ----------------------------------------------------------
p_check="$(grep '^- \*\*Required check:\*\*' "$PROFILE" | head -1 | tokens | head -1)"
k_check="$(line_tokens "$PACKET" "- Required check:" | head -1)"
compare_scalar "required-check" "$p_check" "$k_check"

# --- merge-gate (the ruleset value; the packet folds it onto the required-check
#     line as "merge gate: <value>") ------------------------------------------
p_merge="$(sed -n 's/^- \*\*Merge-gate ruleset:\*\* *\([A-Za-z]*\).*/\1/p' "$PROFILE" | head -1)"
k_merge="$(sed -n 's/.*merge gate: *\([A-Za-z]*\).*/\1/p' "$PACKET" | head -1)"
compare_scalar "merge-gate" "$p_merge" "$k_merge"

# --- autonomy-opt-in (the autonomy-mode.sh code-span grammar: comment lines
#     dropped, exactly one genuine declaration expected) -----------------------
p_auto_values="$(grep -vE '^[[:space:]]*#|<!--' "$PROFILE" \
  | grep -oE "${BT}autonomy-opt-in:[[:space:]]*[A-Za-z]+${BT}" \
  | grep -oE ':[[:space:]]*[A-Za-z]+' | grep -oE '[A-Za-z]+$')"
p_auto_count="$(printf '%s\n' "$p_auto_values" | grep -c .)"
k_auto="$(line_tokens "$PACKET" "- Autonomy opt-in:" | head -1)"
if [ "$p_auto_count" != "1" ]; then
  fail "autonomy-opt-in" "profile declaration missing or ambiguous ($p_auto_count code-span declarations; the activation check would fail closed — fix $PROFILE → \"Autonomy\")"
else
  compare_scalar "autonomy-opt-in" "$p_auto_values" "$k_auto"
fi

# --- constitution-path -------------------------------------------------------
p_con="$(section "$PROFILE" "## Paths" | grep 'Constitution' | head -1 | tokens | head -1)"
k_con="$(line_tokens "$PACKET" "- Constitution:" | head -1)"
compare_scalar "constitution-path" "$p_con" "$k_con"

# --- repo-model (direct|fork — the tracker-remote model; a switch away from the
#     packet's value would point ordinary runs at the wrong remote) -----------
p_repo="$(sed -n 's/^- \*\*Repo model:\*\* *\([A-Za-z]*\).*/\1/p' "$PROFILE" | head -1)"
k_repo="$(sed -n 's/^- Repo model: *\([A-Za-z]*\).*/\1/p' "$PACKET" | head -1)"
compare_scalar "repo-model" "$p_repo" "$k_repo"

# --- telemetry-path (the stream token, wherever it sits in the Paths bullets) --
p_tel="$(section "$PROFILE" "## Paths" | tokens | grep -E 'telemetry\.jsonl$' | head -1)"
k_tel="$(section "$PACKET" "## Paths" | tokens | grep -E 'telemetry\.jsonl$' | head -1)"
compare_scalar "telemetry-path" "$p_tel" "$k_tel"

# --- spec-paths / tasks-paths ------------------------------------------------
p_specs="$(section "$PROFILE" "## Paths" | tokens | grep -E '^specs/[0-9][0-9a-z-]*/spec\.md$')"
k_specs="$(section "$PACKET" "## Paths" | tokens | grep -E '^specs/[0-9][0-9a-z-]*/spec\.md$')"
compare_sets "spec-paths" "$p_specs" "$k_specs"

p_tasks="$(section "$PROFILE" "## Paths" | tokens | grep -E '^specs/[0-9][0-9a-z-]*/tasks\.md$')"
k_tasks="$(section "$PACKET" "## Paths" | tokens | grep -E '^specs/[0-9][0-9a-z-]*/tasks\.md$')"
compare_sets "tasks-paths" "$p_tasks" "$k_tasks"

# --- title-conventions / branch-convention (section-scoped: the profile wraps
#     its bullets, so a line-anchored read would drop a continuation token) -----
p_title="$(section "$PROFILE" "## Task & branch conventions" | tokens | grep '^<type>: ')"
k_title="$(section "$PACKET" "## Conventions" | tokens | grep '^<type>: ')"
compare_sets "title-conventions" "$p_title" "$k_title"

p_branch="$(section "$PROFILE" "## Task & branch conventions" | tokens | grep '^<type>/')"
k_branch="$(section "$PACKET" "## Conventions" | tokens | grep '^<type>/')"
compare_sets "branch-convention" "$p_branch" "$k_branch"

# --- task-id-format (the `T` + N–M digit signature) --------------------------
p_tid="$(sed -n "s/.*\(${BT}T${BT} + [0-9].*[0-9] digits\).*/\1/p" "$PROFILE" | head -1)"
k_tid="$(sed -n "s/.*\(${BT}T${BT} + [0-9].*[0-9] digits\).*/\1/p" "$PACKET" | head -1)"
compare_scalar "task-id-format" "$p_tid" "$k_tid"

# --- tier-tags (the per-task minimum-capability tags the selector resolves) ----
p_tiers="$(section "$PROFILE" "## Task & branch conventions" | tokens | grep -E '^\[(frontier|strong|cheap)\]$')"
k_tiers="$(section "$PACKET" "## Conventions" | tokens | grep -E '^\[(frontier|strong|cheap)\]$')"
compare_sets "tier-tags" "$p_tiers" "$k_tiers"

# --- issue-lifecycle (open-before-first-edit / close-by-PR): the create-on-demand
#     policy word and the `Closes #<n>` PR-close directive, compared as a set. ----
lifecycle_sig() { # <file> <section prefix>
  local sec; sec="$(section "$1" "$2")"
  printf '%s\n' "$sec" | grep -o 'create-on-demand'
  printf '%s\n' "$sec" | grep -o "${BT}Closes #<n>${BT}" | tr -d '\140'
}
p_life="$(lifecycle_sig "$PROFILE" "## Task & branch conventions")"
k_life="$(lifecycle_sig "$PACKET" "## Conventions")"
compare_sets "issue-lifecycle" "$p_life" "$k_life"

# --- blocked-tasks (none/present classification; see the header note) ----------
classify_blocked() { # <file>
  local first
  first="$(section "$1" "## Blocked / owner-only tasks" | grep '^- ' | head -1)"
  case "$first" in
    '') echo "" ;;
    '- none'*) echo "none" ;;
    *) echo "present" ;;
  esac
}
p_blocked="$(classify_blocked "$PROFILE")"
k_blocked="$(classify_blocked "$PACKET")"
compare_scalar "blocked-tasks" "$p_blocked" "$k_blocked"

# --- review-passes (data rows compared verbatim after whitespace squeeze) ------
pass_rows() { # <file>
  section "$1" "## Review passes" | grep "^| ${BT}" | tr -s '[:space:]' ' ' | sed 's/[[:space:]]*$//'
}
p_passes="$(pass_rows "$PROFILE")"
k_passes="$(pass_rows "$PACKET")"
compare_sets "review-passes" "$p_passes" "$k_passes"

# --- checker-map (each row's first two backticked tokens: glob -> checker) -----
map_pairs() { # <file>
  section "$1" "## Edit-time checks" | grep "^- ${BT}" | while IFS= read -r ln; do
    printf '%s\n' "$ln" | tokens | head -2 | tr '\n' ' ' | sed 's/ $//'
    echo
  done | grep .
}
p_map="$(map_pairs "$PROFILE")"
k_map="$(map_pairs "$PACKET")"
compare_sets "checker-map" "$p_map" "$k_map"

# --- invariants: bullet count mirrors the enforcement-mapping row count, and the
#     deterministic-backstop script set (backticked *.sh / *.js tokens, globs
#     excluded) mirrors the mapping table's backstop column --------------------
p_rows="$(section "$PROFILE" "### Invariant" | grep '^| ' | grep -v '^| Invariant ')"
p_count="$(printf '%s\n' "$p_rows" | grep -c .)"
k_inv="$(section "$PACKET" "## Critical invariants")"
k_count="$(printf '%s\n' "$k_inv" | grep -c '^- ')"
if [ "$p_count" -eq 0 ]; then
  fail "invariant-count" "could not extract any mapping-table row from $PROFILE (the check's anchor no longer matches — fix the anchor or the \"Invariant → enforcement mapping\" table)"
elif [ "$p_count" -ne "$k_count" ]; then
  fail "invariant-count" "profile's enforcement mapping has $p_count rows but the packet lists $k_count invariant bullets"
fi

p_back="$(printf '%s\n' "$p_rows" | awk -F'|' '{ print $(NF-1) }' | tokens | grep -E '\.(sh|js)$' | grep -v '[*]')"
k_back="$(printf '%s\n' "$k_inv" | tokens | grep -E '\.(sh|js)$' | grep -v '[*]')"
compare_sets "invariant-backstops" "$p_back" "$k_back"

# ------------------------------------------------------------------------------
if [ "$failures" -gt 0 ]; then
  echo "compact-packet drift: FAIL ($failures drifted/unextractable field(s); packet: $PACKET, source of truth: $PROFILE)" >&2
  exit 1
fi
echo "compact-packet drift: OK ($PACKET agrees with $PROFILE on every covered field)"
