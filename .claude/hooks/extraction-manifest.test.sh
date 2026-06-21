#!/usr/bin/env bash
# Completeness backstop for .claude/EXTRACTION.md §2 (issue #90).
#
# The extraction cut-list is the handoff manifest for every tracked file under
# .claude/. A missing disposition can drop a file during extraction or ship
# instance-stained material into a template. This test compares the §2 table to
# git's tracked inventory and fails on a stale count, a missing row, a duplicate
# row, an untracked row, or a category outside the four extraction dispositions.
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

manifest_count="$(grep -E '^Current tracked inventory: [0-9][0-9]* files[.]$' "$EXTRACT" \
  | head -1 | sed -E 's/[^0-9]*([0-9][0-9]*).*/\1/')"
if [ "$manifest_count" = "$tracked_count" ]; then
  ok
else
  bad "EXTRACTION.md §2 count is stale (manifest=${manifest_count:-missing}, tracked=$tracked_count)"
fi

awk '
  /^## 2[.] / { section = 1; next }
  /^## 3[.] / { section = 0 }
  section && /^\| `[^`][^`]*` \|/ {
    path = $0
    sub(/^\| `/, "", path)
    sub(/` \|.*/, "", path)
    category = $0
    sub(/^\| `[^`][^`]*` \|[ \t]*/, "", category)
    sub(/[ \t]*\|.*/, "", category)
    print path "\t" category
  }
' "$EXTRACT" > "$TMP/manifest_rows"

cut -f1 "$TMP/manifest_rows" | sort > "$TMP/manifest"
row_count="$(wc -l < "$TMP/manifest_rows" | tr -d '[:space:]')"
if [ "$row_count" = "$tracked_count" ]; then
  ok
else
  bad "EXTRACTION.md §2 has $row_count table rows; tracked inventory has $tracked_count files"
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

comm -13 "$TMP/tracked" "$TMP/manifest" > "$TMP/extra"
if [ ! -s "$TMP/extra" ]; then
  ok
else
  bad "EXTRACTION.md §2 lists files that are not tracked under .claude:"
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
