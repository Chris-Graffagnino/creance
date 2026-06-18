#!/usr/bin/env bash
# Tasks-file consistency backstop (issues #21, #69).
#
# The engine's PROJECT.md-absent fallback resolves the backlog via the
# specs/*/tasks.md glob and picks the lowest-numbered unchecked task. Two
# failure modes make that resolution ambiguous, and both once shipped in this
# repo:
#   1. A template/skeleton dir containing a glob-selectable spec.md or tasks.md
#      (the skeleton's placeholder T101 becomes the lowest unchecked task).
#   2. The same task ID defined in more than one live tasks file.
#   3. A task left unchecked after a commit carrying its ID has landed —
#      "done-but-unchecked" drift that mis-steers next-task selection (#69).
# This check makes all three impossible to reintroduce silently. Bash + git +
# grep only (commit subjects carry the task ID, so no GitHub API is needed).
set -u

# Rule 3's drift detection is shared with the runtime selection precondition
# (reconcile-task-selection.sh, #80/T608) via lib-tasks-drift.sh — one definition, two
# consumers (DESIGN-NOTES §12), so the CI gate and the selector can never disagree.
# shellcheck source=lib-tasks-drift.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib-tasks-drift.sh"

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

# 3. No task may stay unchecked once a commit carrying its task ID has landed.
#    Commit subjects follow `<type>: [<task-id>] <desc>` (PROJECT.md task &
#    branch conventions), so a commit reachable from HEAD whose subject carries
#    `[T<nnn>]` means T<nnn> has committed/merged work — a still-`[ ]` box is
#    "done-but-unchecked" drift that mis-steers next-task selection (it picks
#    the lowest-numbered unchecked task). Triage §2 surfaces this advisorily;
#    this is the deterministic backstop (DESIGN-NOTES §12). The detection is
#    shared via lib-tasks-drift.sh (see the source line above).
committed_ids=$(tasks_drift_committed_ids)
if [ -n "$committed_ids" ]; then
  for id in $(tasks_drift_unchecked_ids); do
    # whole-line match, so a [T10] commit never trips an unchecked T101
    if printf '%s\n' "$committed_ids" | grep -qxF "$id"; then
      hit=$(tasks_drift_hit "$id")
      echo "FAIL: $id is unchecked but has committed work ($hit) — tick its box in the tasks file" >&2
      fail=1
    fi
  done
fi

if [ "$fail" -ne 0 ]; then
  exit 1
fi
echo "tasks-file consistency: OK"
