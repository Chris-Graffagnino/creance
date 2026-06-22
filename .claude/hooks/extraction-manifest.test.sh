#!/usr/bin/env bash
# Completeness backstop for .claude/EXTRACTION.md §2 (issue #90).
#
# The extraction cut-list is the handoff manifest for every source file under
# .claude/. A missing disposition can drop a file during extraction or ship
# instance-stained material into a template. This test compares the §2 table to
# git's tracked inventory and fails on a stale count, a missing row, a duplicate
# row, an untracked row, or a category outside the four extraction dispositions.
# Rows whose action starts "Omit from extracted template;" are source-only
# TEMPLATE inputs and may be absent after extraction.
#
# Run: bash .claude/hooks/extraction-manifest.test.sh
set -u

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
EXTRACT="$ROOT/.claude/EXTRACTION.md"
CI="$ROOT/.github/workflows/ci.yml"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0

ok() { pass=$((pass + 1)); }
bad() {
  fail=$((fail + 1))
  printf 'FAIL %s\n' "$1" >&2
}

if [ ! -f "$EXTRACT" ]; then
  echo "FAIL: missing $EXTRACT" >&2
  exit 1
fi

git -C "$ROOT" ls-files .claude | sed 's#^\.claude/##' | sort > "$TMP/tracked"
tracked_count="$(wc -l < "$TMP/tracked" | tr -d '[:space:]')"

awk '
  BEGIN { FS = "|" }

  function trim(s) {
    sub(/^[ \t][ \t]*/, "", s)
    sub(/[ \t][ \t]*$/, "", s)
    return s
  }

  /^## 2[.] / { section = 1; next }
  /^## 3[.] / { section = 0 }
  section && /^\| `[^`][^`]*` \|/ {
    path = $2
    sub(/^[ \t]*`/, "", path)
    sub(/`[ \t]*$/, "", path)

    category = trim($3)

    action = $4
    for (i = 5; i < NF; i++) {
      action = action "|" $i
    }
    action = trim(action)

    print path "\t" category "\t" action
  }
' "$EXTRACT" > "$TMP/manifest_rows"

cut -f1 "$TMP/manifest_rows" | sort > "$TMP/manifest"
awk -F '	' '$3 ~ /^Omit from extracted template;/ { print $1 }' "$TMP/manifest_rows" \
  | sort > "$TMP/omit_only"

row_count="$(wc -l < "$TMP/manifest_rows" | tr -d '[:space:]')"
manifest_count="$(grep -E '^Manifest source inventory: [0-9][0-9]* rows[.]$' "$EXTRACT" \
  | head -1 | sed -E 's/[^0-9]*([0-9][0-9]*).*/\1/')"
if [ "$manifest_count" = "$row_count" ]; then
  ok
else
  bad "EXTRACTION.md §2 source count is stale (manifest=${manifest_count:-missing}, rows=$row_count)"
fi

comm -23 "$TMP/omit_only" "$TMP/tracked" > "$TMP/absent_omit_only"
absent_omit_count="$(wc -l < "$TMP/absent_omit_only" | tr -d '[:space:]')"
effective_row_count=$((row_count - absent_omit_count))
if [ "$effective_row_count" = "$tracked_count" ]; then
  ok
else
  bad "EXTRACTION.md §2 has $effective_row_count effective table rows; tracked inventory has $tracked_count files"
fi

invalid_categories="$(awk -F '	' '$2 !~ /^(KEEP|GENERICIZE|RESET|TEMPLATE)$/ { print $1 " -> " $2 }' "$TMP/manifest_rows")"
if [ -z "$invalid_categories" ]; then
  ok
else
  bad "EXTRACTION.md §2 has invalid category values:"
  printf '%s\n' "$invalid_categories" | sed 's/^/  /' >&2
fi

duplicates="$(sort "$TMP/manifest" | uniq -d)"
if [ -z "$duplicates" ]; then
  ok
else
  bad "EXTRACTION.md §2 has duplicate file rows:"
  printf '%s\n' "$duplicates" | sed 's/^/  /' >&2
fi

comm -23 "$TMP/tracked" "$TMP/manifest" > "$TMP/missing"
if [ ! -s "$TMP/missing" ]; then
  ok
else
  bad "EXTRACTION.md §2 is missing tracked .claude files:"
  sed 's/^/  /' "$TMP/missing" >&2
fi

comm -13 "$TMP/tracked" "$TMP/manifest" > "$TMP/extra_all"
comm -23 "$TMP/extra_all" "$TMP/omit_only" > "$TMP/extra"
if [ ! -s "$TMP/extra" ]; then
  ok
else
  bad "EXTRACTION.md §2 lists files that are not tracked under .claude and not marked omit-only:"
  sed 's/^/  /' "$TMP/extra" >&2
fi

if [ -f "$CI" ]; then
  ok
else
  bad "missing CI workflow: $CI"
fi

# Lines belonging to the `verify:` job: from its 2-space-indented key to the next
# 2-space-indented job key (or EOF). No awk interval syntax (portable to BSD awk).
verify_steps() { awk '/^  [A-Za-z]/ { inblk = ($0 ~ /^  verify:/) } inblk { print }' "$CI"; }
# 0 iff an active (uncommented) `run: bash <path>` step invokes $1 within verify.
runs_in_verify() { verify_steps | grep -qE "^[[:space:]]*run:[[:space:]]+bash[[:space:]]+$1([[:space:]]|\$)"; }
if runs_in_verify '\.claude/hooks/extraction-manifest\.test\.sh'; then
  ok
else
  bad "verify must RUN extraction-manifest.test.sh (active run: step)"
fi

printf 'extraction-manifest.test.sh: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
