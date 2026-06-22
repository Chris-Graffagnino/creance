#!/usr/bin/env bash
# Global runtime-neutral workflow-doc scan (#122 review follow-up).
# Any tracked workflow markdown file is scanned through the shared banned-token
# set, so a future neutral doc cannot opt out by forgetting a local encoding test.
set -u

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=lib-neutrality-scan.sh
. "$ROOT/.claude/hooks/lib-neutrality-scan.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0

ok() { pass=$((pass + 1)); }
bad() {
  fail=$((fail + 1))
  printf 'FAIL %s\n' "$1" >&2
}

docs="$TMP/workflow-docs"
git -C "$ROOT" ls-files .claude/workflow | grep -E '[.]md$' | sort > "$docs"
doc_count="$(wc -l < "$docs" | tr -d '[:space:]')"

if [ "$doc_count" -gt 0 ]; then
  ok
else
  bad "no tracked workflow markdown files found to scan"
fi

scanned=0
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  scanned=$((scanned + 1))
  doc="$ROOT/$rel"
  leaks="$(neutral_mechanism_leaks "$doc")"
  rc=$?
  if [ "$rc" -eq 0 ] && [ -z "$leaks" ]; then
    ok
  else
    bad "runtime-specific mechanism leaked into $rel (rc=$rc found: ${leaks:-<empty>})"
  fi
done < "$docs"

if [ "$scanned" -eq "$doc_count" ]; then
  ok
else
  bad "scan count mismatch: expected $doc_count, scanned $scanned"
fi

printf 'neutrality-scan-coverage.test.sh: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
