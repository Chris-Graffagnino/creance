#!/usr/bin/env bash
# status-map.sh — the read-only, observe-only harness status map (T638, issue #234).
#
# WHAT IT IS: a one-screen Markdown orientation map, printed to STDOUT, mixing static
# harness facts with best-effort dynamic repo/tracker state — so a session (human or
# agent) can answer "what mode is this repo in / what branch / which issue / which gates
# / what's live" without rediscovering it from scattered docs, git, and the tracker.
#
# WHAT IT IS NOT: authority. It is an ORIENTATION tool, strictly subordinate to
# `.claude/PROJECT.md`, `.claude/workflow/**`, and `memory/constitution.md` — those win on
# ANY disagreement. It is observe-only (constitution P5): no gate, tier, guard, selection,
# or autonomy path may consume it, which `status-map-fence.sh` proves deterministically
# rather than leaving to reviewer judgment.
#
# STDOUT ONLY — no --write, no output file (issue #234: "writes no tracked file by
# default"). That is a design choice, not an omission: with no output artifact, the ONLY
# way to consume the map is to name this command, so the fence's token scan is complete.
# Running it leaves `git status` untouched.
#
# TWO INDEPENDENT DEGRADATIONS, both explicit, neither a crash (issue #234 criterion 2):
#   * tracker/network unavailable — the open-PR field renders `unknown`; every other field
#     is LOCAL (git + files), so the static summary still prints in full. Never guessed.
#   * the T637 lock absent — the profile-derived static fields render `unknown`; the
#     dynamic/filesystem sections still print (T638 soft-depends T637, and stays valuable
#     without it).
# The ONE hard failure is a local-repo error that makes even static status impossible: an
# unreadable root or a non-git tree exits 2 loud, never a silently empty map.
#
# REUSE, NEVER FORK (constitution P2): the done-but-unchecked drift line SOURCES
# lib-tasks-drift.sh (`tasks_drift_unchecked_ids` / `tasks_drift_is_drifted` /
# `tasks_drift_hit`) — this map is that lib's FIFTH consumer, so it cannot disagree with
# CI, selection, announce, or the guard about what drift means. The branch's task-id read
# below is a separate question (the `<type>: [<task-id>] <desc>` commit-subject convention
# from PROJECT.md, not a drift definition) and uses the same bracket-anchored form the
# guard's rule 8 already uses at the same seam (guard.sh: `grep -oE '\[T[0-9]+\]'`).
#
# STATIC FACTS COME FROM THE LOCK (issue #234 criterion 3): `.claude/HARNESS.lock.json` is
# read instead of re-parsing PROJECT.md, so this map cannot drift from the manifest's view
# of the profile. The lock is compiled EVIDENCE, never authority — it is reproduced here
# under the same rule (source docs win; staleness is fixed by regenerating the lock).
#
# Root override: STATUS_MAP_ROOT (default: the repo root) so the .test.sh can point the
# map at fixture trees. Bash + git + python3 (lock parse) + optional gh (the PR field).
#
# Run:   bash .claude/hooks/status-map.sh
# Tests: .claude/hooks/status-map.test.sh (wired into CI verify).
set -u

ROOT="${STATUS_MAP_ROOT:-$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)}"
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
UNKNOWN='unknown'

# --- the one hard failure: no readable local repo means no static status at all --------
if [ -z "$ROOT" ] || [ ! -d "$ROOT" ]; then
  printf 'status-map: root %s is not a readable directory — cannot emit even static status.\n' \
    "${ROOT:-<empty>}" >&2
  exit 2
fi
if ! git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  printf 'status-map: %s is not a git work tree — cannot emit even static status.\n' "$ROOT" >&2
  exit 2
fi
cd "$ROOT" || exit 2

# --- static facts, from the T637 lock when present -------------------------------------
# ONE python3 call emits TAB-separated key/value lines (one process, no jq dependency).
# Any absence/parse error leaves every field empty -> rendered `unknown` below.
LOCK='.claude/HARNESS.lock.json'
lock_present=no
lock_kv=''
if [ -f "$LOCK" ]; then
  lock_kv="$(python3 - "$LOCK" <<'PY' 2>/dev/null
import json, sys

try:
    with open(sys.argv[1], encoding="utf-8") as fh:
        lock = json.load(fh)
except Exception:
    sys.exit(1)


def emit(key, value):
    if value not in (None, "", []):
        print("%s\t%s" % (key, str(value).replace("\t", " ").replace("\n", " ")))


profile = lock.get("profile") or {}
emit("schema_version", lock.get("schema_version"))
emit("base_branch", profile.get("base_branch"))
emit("required_check", profile.get("required_check"))
emit("merge_gate", profile.get("merge_gate"))
emit("constitution_path", profile.get("constitution_path"))
emit("spec_count", len(profile.get("spec_paths") or []) or None)
emit("tasks_count", len(profile.get("tasks_paths") or []) or None)
emit("autonomy_opt_in", (lock.get("autonomy") or {}).get("opt_in"))

passes = [
    "%s (%s)" % (p.get("role"), p.get("condition"))
    for p in (lock.get("review_passes") or [])
    if str(p.get("enabled")).lower() == "true"
]
emit("review_passes", ", ".join(passes))

checks = [
    "%s -> %s" % (c.get("glob"), c.get("checker"))
    for c in (lock.get("edit_time_checks") or [])
]
emit("edit_time_checks", ", ".join(checks))

channels = lock.get("observe_only_channels") or {}
emit("telemetry_path", (channels.get("telemetry") or {}).get("path"))
PY
  )" && [ -n "$lock_kv" ] && lock_present=yes
fi

# lock_field <key> — the lock value for <key>, or `unknown` when absent/unparsed.
lock_field() {
  local want="$1" key rest
  while IFS="$(printf '\t')" read -r key rest; do
    [ "$key" = "$want" ] || continue
    [ -n "$rest" ] || continue
    printf '%s' "$rest"
    return 0
  done <<EOF
$lock_kv
EOF
  printf '%s' "$UNKNOWN"
}

base_branch="$(lock_field base_branch)"
required_check="$(lock_field required_check)"
merge_gate="$(lock_field merge_gate)"
constitution_path="$(lock_field constitution_path)"
spec_count="$(lock_field spec_count)"
tasks_count="$(lock_field tasks_count)"
autonomy_opt_in="$(lock_field autonomy_opt_in)"
review_passes="$(lock_field review_passes)"
edit_time_checks="$(lock_field edit_time_checks)"
telemetry_path="$(lock_field telemetry_path)"
schema_version="$(lock_field schema_version)"

# --- dynamic LOCAL facts (no network: git + files only) --------------------------------
slug="$UNKNOWN"
remote="$(git remote get-url origin 2>/dev/null || true)"
if [ -n "$remote" ]; then
  # Both remote forms -> owner/repo: git@host:owner/repo(.git) and https://host/owner/repo(.git).
  # Two POSIX-ERE passes (strip the suffix, then take the last two segments) rather than one
  # pattern with an optional trailing group: the lazy `+?` that would need is a Perl/GNU-ism
  # BSD sed rejects outright — the exact BSD-vs-GNU divergence class shell-lint.sh exists for.
  slug="$(printf '%s' "$remote" | sed -E -e 's#\.git$##' -e 's#^.*[:/]([^/:]+/[^/]+)$#\1#')"
  [ -n "$slug" ] || slug="$UNKNOWN"
fi

branch="$(git branch --show-current 2>/dev/null || true)"
[ -n "$branch" ] || branch="$UNKNOWN"   # detached HEAD

on_base="$UNKNOWN"
if [ "$base_branch" != "$UNKNOWN" ] && [ "$branch" != "$UNKNOWN" ]; then
  if [ "$branch" = "$base_branch" ]; then on_base=yes; else on_base=no; fi
fi

dirty_count="$(git status --porcelain 2>/dev/null | grep -c . || true)"
[ -n "$dirty_count" ] || dirty_count=0
if [ "$dirty_count" -eq 0 ]; then
  worktree='clean'
else
  worktree="dirty ($dirty_count file(s))"
fi

in_workspace=no
[ -f "$ROOT/.git" ] && in_workspace='yes (linked worktree)'

# The issue number is carried by the branch name itself (`<type>/<issue#>-<slug>`,
# PROJECT.md conventions) — a LOCAL read, so it survives a tracker outage.
issue="$UNKNOWN"
issue_num="$(printf '%s' "$branch" | sed -nE 's#^[a-z]+/([0-9]+)-.*$#\1#p')"
[ -n "$issue_num" ] && issue="#$issue_num"

# The task id comes from the branch's own commit subjects (`<type>: [<task-id>] <desc>`).
# Bracket-anchored, matching the guard's rule 8 read of the same convention, so [T90]
# never matches T901. Not a drift definition — the drift half is SOURCED below.
task_id="$UNKNOWN"
if [ "$base_branch" != "$UNKNOWN" ] && [ "$branch" != "$UNKNOWN" ]; then
  found="$(git log --format='%s' "$base_branch..HEAD" 2>/dev/null \
    | grep -oE '\[T[0-9]+\]' | tr -d '[]' | sort -u | head -1)"
  [ -n "$found" ] && task_id="$found"
fi

# --- dynamic TRACKER facts (network; `unknown` when unreachable, never guessed) ---------
pr="$UNKNOWN"
tracker="$UNKNOWN (not reached)"
if command -v gh >/dev/null 2>&1 && [ "$branch" != "$UNKNOWN" ]; then
  if pr_out="$(gh pr list --head "$branch" --state open --json number --jq '.[0].number' 2>/dev/null)"; then
    tracker='reachable'
    if [ -n "$pr_out" ]; then pr="#$pr_out"; else pr='none open'; fi
  fi
fi

# --- live inputs + drift (SOURCED from lib-tasks-drift.sh — never a second definition) --
unchecked_count="$UNKNOWN"
drift_line='none'
drift_lib="$HOOK_DIR/lib-tasks-drift.sh"
if [ -f "$drift_lib" ]; then
  # shellcheck source=/dev/null
  . "$drift_lib"
  unchecked="$(tasks_drift_unchecked_ids 2>/dev/null || true)"
  unchecked_count="$(printf '%s' "$unchecked" | grep -c . || true)"
  drifted=''
  for id in $unchecked; do
    if tasks_drift_is_drifted "$id" 2>/dev/null; then
      drifted="$drifted $id ($(tasks_drift_hit "$id" | cut -d' ' -f1))"
    fi
  done
  [ -n "$drifted" ] && drift_line="done-but-unchecked:$drifted"
fi

contracts='absent'
[ -d specs/contracts ] && contracts='present'
for d in specs/*/contracts; do
  [ -d "$d" ] && contracts='present' && break
done

manifest="absent (static profile facts unavailable)"
[ "$lock_present" = yes ] && manifest="present (schema $schema_version)"

mode_line="review — open PRs, a human merges"
[ "$autonomy_opt_in" = 'enabled' ] && mode_line="autonomous opt-in present — activation still fails closed to review"
[ "$autonomy_opt_in" = "$UNKNOWN" ] && mode_line="$UNKNOWN — read .claude/PROJECT.md § Autonomy"

# --- render (Markdown, stdout only) ----------------------------------------------------
cat <<MAP
# Harness status map — $slug

> **Orientation only — never authority.** \`.claude/PROJECT.md\`, \`.claude/workflow/**\`,
> and \`$constitution_path\` are the source of truth and win on any disagreement. This map
> is observe-only (constitution P5): no gate, tier, guard, selection, or autonomy path
> reads it (\`status-map-fence.sh\`). Generated on demand; \`unknown\` means *not readable
> here*, never *absent* — go read the source doc.

## Repo
- slug: $slug
- base branch: $base_branch
- current branch: $branch
- on base branch: $on_base
- worktree: $worktree
- linked worktree: $in_workspace

## Task / issue / PR
- task id: $task_id
- issue: $issue
- open PR: $pr
- tracker: $tracker

## Mode
- autonomy opt-in: $autonomy_opt_in
- run mode: $mode_line
- the deterministic check owns activation: \`.claude/hooks/autonomy-mode.sh\`

## Required gates
- required check: $required_check
- merge gate: $merge_gate
- review passes: $review_passes
- constitution: $constitution_path

## Live inputs
- specs: $spec_count | tasks files: $tasks_count | unchecked tasks: $unchecked_count
- contracts dir: $contracts
- edit-time checks: $edit_time_checks

## Freshness / warnings
- harness manifest: $manifest
- tasks drift: $drift_line

## Observe-only channels
- telemetry: $telemetry_path — observes, never decides (constitution P5)
- maker-eval: see \`.claude/PROJECT.md\` § Paths — observes, never decides (constitution P5)
- this map: observes, never decides (constitution P5)
MAP
exit 0
