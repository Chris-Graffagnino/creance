#!/usr/bin/env bash
# backlog-loop.sh — POSIX/cron launcher template for the [backlog-loop]: one
# bounded, gated, unattended run that drains up to N backlog tasks into a queue
# of ratifiable PRs (T905, spec 004 US1).
#
# Claude Code adapter artifact — a new adapter supplies its own launcher; the
# normative contract is .claude/workflow/backlog-loop.md (the neutral loop
# model: stop conditions, reachability, the observe-only run report).
#
# What this composes (the [scheduled run] / loop-wrapper mechanism):
#   .claude/hooks/backlog-loop.sh run <N>       — the control skeleton (T902)
#     BACKLOG_LOOP_ACTIVATION_CMD               — [autonomy activation]: the
#         default (hooks/autonomy-mode.sh) reads the profile's autonomy-opt-in
#         flag and FAILS CLOSED to review. A scheduled run has no session, so
#         the profile flag is the ONLY legitimate authorization here — do NOT
#         wire --session-authorized into an unattended launcher: that would
#         manufacture the explicit in-session authorization the check exists
#         to require. With the opt-in absent the loop starts, consults the
#         check once, and stops `fail-closed after 0 of N` — by design.
#     BACKLOG_LOOP_SELECT_CMD                   — the real selector (T905)
#     BACKLOG_LOOP_ITERATION_CMD                — the real cycle binding (T905):
#         each iteration is a fresh headless run of /next-task with the task ID
#         explicit in the prompt text (the explicit-context rule); the outcome
#         is read from the run's own return (the BACKLOG-LOOP-OUTCOME marker),
#         never from a report file (constitution P5)
#     BACKLOG_LOOP_SWEEP_CMD                    — the crash-recovery startup
#         sweep (T906): once per engaged run, the [isolated workspace] lifecycle
#         reaps the workspaces a PREVIOUS run leaked by being killed mid-iteration.
#         Driven write-only — its output and exit status are discarded, so a
#         broken sweep cannot stall or steer an unattended run. The loop appends
#         its session id, which is what scopes the reap to runs that have ended.
#     BACKLOG_LOOP_RUN_ID                       — enables the observe-only run
#         report (one line per iteration + the terminal summary) on the
#         existing out-of-repo telemetry stream; /triage surfaces the batch
#
# Run-log contract (the triage-heartbeat.sh dead-man idiom): one UNCONDITIONAL
# line per attempt, appended AFTER the run exits, nonzero exit propagated to
# the scheduler.
#
# Install (cron, weeknights 01:30):
#   crontab -e
#   30 1 * * 1-5 /path/to/backlog-loop.sh
# (launchd on macOS works too; the contract is scheduler-agnostic.)

set -u

# ── Configure these for your machine (absolute paths — never rely on cwd) ──────
REPO_ROOT="$HOME/<your-repo>"
N="<iteration budget — the max-N stop condition; never hardcode it elsewhere>"
RUNLOG="$HOME/<out-of-repo-inbox-dir>/<repo-basename>-backlog-loop.log"
# The per-run model for every iteration's headless cycle. Tier tags on task
# lines are MINIMUMS (AGENTS.md "Model & usage economy"): a fixed launcher
# model must satisfy the highest tag the run may select, so default to the
# STRONG row of .claude/MODELS.md — rounding up is allowed, down never is.
MODEL="<strong-tier row of .claude/MODELS.md>"
TOKEN_FILE="$HOME/.claude/.oauth-token"                  # see docs/headless-auth.md
CLAUDE_BIN="$(command -v claude || echo "$HOME/.local/bin/claude")"
# ────────────────────────────────────────────────────────────────────────────────

start=$(date +%s)
code=1
note="launcher died before invoking the loop"

finalize() {
  dur=$(( $(date +%s) - start ))
  printf '%s exit=%s duration=%ss note=%s\n' \
    "$(date +%Y-%m-%dT%H:%M:%S)" "$code" "$dur" "$note" >> "$RUNLOG"
  exit "$code"
}
trap finalize EXIT

if [ ! -x "$CLAUDE_BIN" ]; then
  note="claude CLI not found"
  exit 1
fi

# Auth is REQUIRED for an unattended run (docs/headless-auth.md; the
# triage-heartbeat.sh contract): a missing token must be a scheduler-visible
# failure (`exit=1 note=auth...` in the run log), never a silent slide into
# unauthenticated cycles — the iterate binding maps a failed cycle to
# `aborted` and the loop exits 0 on a clean fail-closed stop, so without this
# preflight an auth outage would masquerade as a successful completed loop.
if [ -f "$TOKEN_FILE" ]; then
  CLAUDE_CODE_OAUTH_TOKEN="$(cat "$TOKEN_FILE")"
  export CLAUDE_CODE_OAUTH_TOKEN
else
  note="auth: $(basename "$TOKEN_FILE") missing"
  exit 1
fi

cd "$REPO_ROOT" || { note="repo root missing: $REPO_ROOT"; exit 1; }

# One run id ties the report's iteration lines and summary together.
run_id="bl-$(date +%Y%m%dT%H%M%S)-$$"

# The headless cycle invocation the iterate binding wraps: the prompt argument
# (composed by backlog-loop-iterate.sh, task ID embedded) lands after these
# flags.
# --dangerously-skip-permissions: deliberate for unattended runs (a permission
# prompt would hang the iteration forever — docs/headless-auth.md). The
# compensating controls for THIS launcher: the deterministic guard hook, the
# fail-closed [autonomy activation] check (without the profile opt-in the loop
# stops before any iteration), the [isolated workspace] each engaged cycle
# runs in, and the §7 gate every promotion must pass.
export BACKLOG_LOOP_HEADLESS_CMD="$CLAUDE_BIN -p --model $MODEL --dangerously-skip-permissions"

out="$(BACKLOG_LOOP_SELECT_CMD="bash .claude/hooks/backlog-loop-select.sh" \
  BACKLOG_LOOP_ITERATION_CMD="bash .claude/hooks/backlog-loop-iterate.sh" \
  BACKLOG_LOOP_SWEEP_CMD="bash .claude/hooks/isolated-workspace.sh sweep --session" \
  BACKLOG_LOOP_RUN_ID="$run_id" \
  bash .claude/hooks/backlog-loop.sh run "$N" 2>&1)"
code=$?

stop_line="$(printf '%s\n' "$out" | tail -1)"
note="run_id=$run_id ${stop_line:-no stop line}"
exit "$code"
