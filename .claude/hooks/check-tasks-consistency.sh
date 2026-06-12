#!/usr/bin/env bash
# Tasks-file consistency backstop (issue #21).
#
# The engine's PROJECT.md-absent fallback resolves the backlog via the
# specs/*/tasks.md glob and picks the lowest-numbered unchecked task. Two
# failure modes make that resolution ambiguous, and both once shipped in this
# repo:
#   1. A template/skeleton dir containing a glob-selectable spec.md or tasks.md
#      (the skeleton's placeholder T101 becomes the lowest unchecked task).
#   2. The same task ID defined in more than one live tasks file.
# This check makes both impossible to reintroduce silently. Bash + grep only.
set -u

fail=0

# 1. Template dirs must only ship *.template.md spec/tasks skeletons.
for f in specs/*template*/spec.md specs/*template*/tasks.md; do
  [ -e "$f" ] || continue
  echo "FAIL: $f is selectable by the engine's fallback glob — rename to ${f%.md}.template.md" >&2
  fail=1
done

# 2. No task ID may appear in more than one live tasks file.
dupes=$(grep -hoE '^- \[[ xX]\] T[0-9]+' specs/*/tasks.md 2>/dev/null \
  | grep -oE 'T[0-9]+' | sort | uniq -d)
if [ -n "$dupes" ]; then
  echo "FAIL: task ID(s) defined in more than one live tasks file:" >&2
  for id in $dupes; do
    echo "  $id:" >&2
    grep -lE "^- \[[ xX]\] $id\b" specs/*/tasks.md | sed 's/^/    /' >&2
  done
  fail=1
fi

if [ "$fail" -ne 0 ]; then
  exit 1
fi
echo "tasks-file consistency: OK"
