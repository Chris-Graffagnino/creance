#!/usr/bin/env bash
# announce-task-selection.sh — runtime announce/confirm decision for /next-task (#103, T614).
#
# The UX complement to reconcile-task-selection.sh (T608). After [live-state reconciliation]
# resolves a candidate, /next-task ANNOUNCES the resolved target before the first edit, and —
# only when the selection was IMPLICIT (no explicit task id/issue named) AND live state
# CONTRADICTS the auto-picked candidate — PAUSES for confirmation instead of silently
# proceeding. This turns the manual "announce before editing" habit into a deterministic
# decision (constitution P3: a check, not the model "noticing") and is the UX half of the #80
# stale-pick fix that T608's refusal (the correctness half) left out.
#
# Mode is supplied EXPLICITLY by the caller (the binding knows whether the user named an
# id/issue) — never inferred from the environment (the explicit-context rule). The
# contradiction signal is the SAME done-but-unchecked drift the reconcile precondition refuses
# on, sourced from lib-tasks-drift.sh — one drift definition, now THREE consumers (the CI gate,
# the reconcile precondition, and this announce decision), so the pause can never disagree with
# the refusal. Like reconcile, this covers MERGED/LANDED drift only; the in-flight axis is #105.
#
# The pause is NOT a way to start stale work: a `confirm` asks the caller to confirm or REDIRECT
# the target, never to override reconcile's refusal — so "refused, not started" still holds.
#
# Run from the repo root:
#   bash .claude/hooks/announce-task-selection.sh <task-id> <explicit|implicit>
# Prints the DECISION on stdout — one of: `proceed` | `confirm` | `announce-only`.
# Exit: 0 decision made (the caller acts on the printed word) · 2 usage. FAILS OPEN: when live
# git state is unreadable an implicit pick degrades to `announce-only` (announce, no stall).
set -u

usage() {
  echo "usage: $(basename "$0") <task-id> <explicit|implicit>   e.g. $(basename "$0") T614 implicit" >&2
  exit 2
}

[ "$#" -eq 2 ] || usage
id="$1"
mode="$2"
case "$id" in
  T[0-9]*) ;;
  *) echo "announce: '$id' is not a T<nnn> task id" >&2; usage ;;
esac
case "$mode" in
  explicit|implicit) ;;
  *) echo "announce: mode must be 'explicit' or 'implicit', got '$mode'" >&2; usage ;;
esac

# Explicit selection: the user named the target, so announce it and proceed — never a
# confirmation prompt (done-when 1). reconcile-task-selection.sh, run upstream, already owns
# refusing an explicitly-named STALE task; this step does not second-guess an explicit intent.
if [ "$mode" = "explicit" ]; then
  echo "proceed"
  exit 0
fi

# Implicit selection from here down — whether to pause is decided deterministically.

# shellcheck source=lib-tasks-drift.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib-tasks-drift.sh"

# Fail open (done-when 4): if git history is unreadable we cannot test for contradiction, so
# announce WITHOUT a confirmation stall rather than manufacturing one we cannot justify.
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "announce-only"
  exit 0
fi

# Implicit + contradicted: the auto-picked box is unchecked but its work has merged/landed, so
# live state contradicts the silent pick — pause for confirmation before the first edit
# (done-when 2). The caller surfaces the drift evidence and asks the owner to confirm or
# redirect; it must NOT start the drifted candidate (reconcile still refuses that).
if tasks_drift_is_drifted "$id"; then
  echo "confirm"
  exit 0
fi

# Implicit + consistent: nothing contradicts the auto-pick, so proceed without a pause — the
# precision control proving the pause is contradiction-triggered, not unconditional (done-when 5).
echo "proceed"
exit 0
