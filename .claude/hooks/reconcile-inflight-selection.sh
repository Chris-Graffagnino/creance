#!/usr/bin/env bash
# reconcile-inflight-selection.sh — the IN-FLIGHT half of /next-task live-state
# reconciliation (#105, T615). Complements reconcile-task-selection.sh (the merged/landed,
# git-only half, #80/T608): run this AFTER that one clears a candidate on the merged axis, to
# additionally refuse a candidate whose MAPPED ISSUE has an OPEN, UNMERGED PR or branch — work
# already in flight, which the git-only check (it reads landed commit subjects) cannot see.
#
# Necessarily a tracker read (a remote open PR/branch is invisible to git), so — unlike the
# merged half — it lives in the adapter and uses `gh`. It FAILS OPEN (warn + exit 0) when
# gh/network is unavailable: degrade to the merged-only result with a surfaced warning, never a
# hard stall (done-when 4), the same posture as the git half.
#
# It deliberately does NOT source lib-tasks-drift.sh: that lib is the git "done-but-unchecked"
# drift DEFINITION (commit subjects), and in-flight is a DISTINCT tracker signal (open
# PR/branch) — a separate concern, not a fork of the shared drift logic (constitution P2).
#
# In-flight signals, all bracket/delimiter-anchored exactly like the merged half's [T<nnn>]
# commit match (so [T90] never trips T901, and /105- never trips /1054-):
#   * an OPEN PR whose title carries `[<task-id>]` (PR title convention <type>: [<id>] <desc>);
#   * a remote branch `<type>/<issue#>-…` bound to the candidate's mapped issue (resolved from
#     the task id) — covers both a PR's head branch AND a branch pushed before its PR exists
#     (branch cut at §4, PR opened at §8: the real "started, not yet PR'd" window).
#
# Run from the repo root:  bash .claude/hooks/reconcile-inflight-selection.sh <task-id>
# Exit: 0 selectable (or fail-open) · 2 usage · 3 in-flight (candidate is being worked — refuse).
# GH overrides the tracker CLI (tests inject a stub on this seam); production uses `gh` from PATH.
set -u

INFLIGHT_EXIT=3
GH="${GH:-gh}"

usage() {
  echo "usage: $(basename "$0") <task-id>   e.g. $(basename "$0") T615" >&2
  exit 2
}

[ "$#" -eq 1 ] || usage
id="$1"
case "$id" in
  T[0-9]*) ;;
  *) echo "inflight: '$id' is not a T<nnn> task id" >&2; usage ;;
esac

# Fail open: with no usable tracker CLI we cannot read in-flight state, so degrade to the
# merged-only result (done-when 4) rather than blocking honest work.
fail_open() {
  echo "inflight: tracker unavailable ($1) — proceeding without in-flight reconciliation (fail-open); verify $id by hand." >&2
  exit 0
}

# Refuse the candidate, surfacing the conflicting evidence (done-when 1).
refuse() {
  {
    echo "inflight: REFUSING $id — work is already in flight for it:"
    printf '    %s\n' "$1"
    echo "  Starting $id now would duplicate in-flight work. Take over that PR/branch, or pick another task."
  } >&2
  exit "$INFLIGHT_EXIT"
}

command -v "$GH" >/dev/null 2>&1 || fail_open "gh not found"

# Signal 1 — an OPEN PR whose title carries [<id>]. TSV: <number>\t<title>\t<url>. The
# bracket-anchored grep is whole-id-safe ([T61] never matches an unchecked T615). A gh failure
# (auth/network) drops to fail-open, never a stall. A PR hit is CONCLUSIVE: refuse at once,
# before any further tracker read, so a later partial failure can never mask the refusal
# (and a PR's head branch is already a branch, so signal 2 would add nothing here).
prs="$( "$GH" pr list --state open --limit 200 --json number,title,url \
          --jq '.[] | [.number, .title, .url] | @tsv' 2>/dev/null )" \
  || fail_open "gh pr list failed"
pr_hit="$( printf '%s\n' "$prs" | grep -F "[$id]" | head -1 )"
[ -n "$pr_hit" ] && refuse "open PR:     $pr_hit"

# Signal 2 — no PR carries [<id>], so look for a branch <type>/<issue#>-… pushed before its PR
# exists (the real "started, not yet PR'd" window). First resolve the candidate's mapped issue
# (its title carries [<id>]) for the anchor: the server-side search is only a prefilter, the
# client-side bracket grep makes the match exact. Then the /<n>- match is delimiter-anchored,
# so /105- never matches /1054- or /15-.
issues="$( "$GH" issue list --state all --search "$id in:title" --limit 50 \
             --json number,title --jq '.[] | [.number, .title] | @tsv' 2>/dev/null )" \
  || fail_open "gh issue list failed"
issue_no="$( printf '%s\n' "$issues" | grep -F "[$id]" | head -1 | cut -f1 )"
if [ -n "$issue_no" ]; then
  branches="$( "$GH" api --paginate "repos/{owner}/{repo}/branches" --jq '.[].name' 2>/dev/null )" \
    || fail_open "gh api branches failed"
  branch_hit="$( printf '%s\n' "$branches" | grep -F "/$issue_no-" | head -1 )"
  [ -n "$branch_hit" ] && refuse "open branch: $branch_hit (issue #$issue_no)"
fi

echo "inflight: $id is selectable — no open PR/branch in flight for it."
exit 0
