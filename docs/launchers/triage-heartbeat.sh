#!/usr/bin/env bash
# triage-heartbeat.sh — POSIX/cron launcher template for the /triage dead-man switch.
#
# Implements the launcher contract in .claude/workflow/triage.md §6. The contract,
# not this script, is normative — every rewrite must honor it:
#   1. One line per attempt, appended to a run log next to the inbox; inbox + run-log
#      paths passed IN THE PROMPT TEXT (the explicit-context rule), env vars as
#      redundant hints only.
#   2. The line is UNCONDITIONAL (try/finally) — even a crash writes `exit=1`.
#   3. Appended AFTER the agent exits, so the last line always describes a completed
#      attempt.
#   4. Nonzero exit propagates to the scheduler.
#
# Install (cron, weekdays 07:30):
#   crontab -e
#   30 7 * * 1-5 /path/to/triage-heartbeat.sh
# (launchd on macOS works too; the contract is scheduler-agnostic.)

set -u

# ── Configure these for your machine (absolute paths — never rely on cwd) ──────
REPO_ROOT="$HOME/<your-repo>"
INBOX="$HOME/<out-of-repo-inbox-dir>/triage-inbox.md"   # OUT of the repo by design
MODEL="<cheap-tier row of .claude/MODELS.md>"
TOKEN_FILE="$HOME/.claude/.oauth-token"                  # see docs/headless-auth.md
CLAUDE_BIN="$(command -v claude || echo "$HOME/.local/bin/claude")"
# ────────────────────────────────────────────────────────────────────────────────

RUNLOG="$(dirname "$INBOX")/$(basename "$REPO_ROOT")-heartbeat.log"
start=$(date +%s)
code=1
note="launcher died before invoking the agent"

# Contract rule 2: the run-log line is unconditional — write it on EVERY exit path,
# after the agent has exited (rule 3), then propagate the exit code (rule 4).
finalize() {
  dur=$(( $(date +%s) - start ))
  printf '%s exit=%s duration=%ss note=%s\n' \
    "$(date +%Y-%m-%dT%H:%M:%S)" "$code" "$dur" "$note" >> "$RUNLOG"
  exit "$code"
}
trap finalize EXIT

# Skip if today's attempt already succeeded (keeps re-fired schedulers idempotent).
if [ -f "$RUNLOG" ] && tail -1 "$RUNLOG" | grep -q "^$(date +%Y-%m-%d).*exit=0"; then
  code=0; note="skip: already ran today"
  exit 0
fi

if [ ! -x "$CLAUDE_BIN" ]; then
  note="claude CLI not found"
  exit 1
fi

if [ -f "$TOKEN_FILE" ]; then
  CLAUDE_CODE_OAUTH_TOKEN="$(cat "$TOKEN_FILE")"
  export CLAUDE_CODE_OAUTH_TOKEN
else
  note="auth: $(basename "$TOKEN_FILE") missing"
  exit 1
fi

# Contract rule 1 / explicit-context rule: every value the run must honor goes in the
# PROMPT TEXT. Env vars below are redundant hints only — never the only carrier.
export TRIAGE_INBOX="$INBOX" TRIAGE_RUNLOG="$RUNLOG"
PROMPT="/triage run log: $RUNLOG. inbox: $INBOX. repo root: $REPO_ROOT."

# --dangerously-skip-permissions: deliberate for unattended runs (a permission prompt
# would hang forever). Compensating controls: the deterministic guard hook + /triage's
# read-only contract. See docs/headless-auth.md before enabling.
cd "$REPO_ROOT" || { note="repo root missing"; exit 1; }
"$CLAUDE_BIN" -p "$PROMPT" --model "$MODEL" --dangerously-skip-permissions </dev/null
code=$?
note="ok"
[ "$code" -ne 0 ] && note="agent exited nonzero"
exit "$code"
