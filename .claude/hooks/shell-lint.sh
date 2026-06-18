#!/usr/bin/env bash
# shell-lint.sh — this project's shell [syntax/type check] (issues #79, #97).
# Lints shell files for (a) syntax errors via `bash -n` and (b) a denylist of
# BSD-vs-GNU portability gotchas that pass on one libc/coreutils and fail on the
# other (macOS dev = BSD, CI = GNU). Prints ONE diagnostic per line to stdout:
#     <file>:<line>: <rule>: <detail>
# Exit 1 when any diagnostic is printed, 0 when clean. Consumed two ways:
#   * the [edit guard] (guard.sh rule 7, PostToolUse) runs it on a touched *.sh
#     file and rejects an edit that ADDS a diagnostic (delta vs. the committed
#     baseline — see guard.sh);
#   * CI `verify` runs it over .claude/hooks/*.sh as a standing portability gate.
# Denylist — deterministic, low-false-positive, NOT a general portability oracle
# (issue #97's stated scope), seeded from the two divergences already hit:
#   * yes-dash-arg  — a leading-dash argument to `yes`. GNU `yes` reads it as an
#     option ("invalid option") and prints nothing; the macOS form printed the
#     literal arg. Passed locally, broke CI (PR #94, fixed in 981e04c).
#   * awk-interval  — an `awk` line carrying a regex interval `{n}`/`{n,m}`:
#     unsupported by some BSD awk without --re-interval (avoided in #92/#94).
# This linter must itself stay portable: its OWN patterns use POSIX ERE only —
# no \b, no `{n}` intervals, no GNU-only grep flags — so it runs identically on
# BSD and GNU. It also avoids writing either denylisted construct verbatim in
# its own source (the metavariable `{n}` carries no digit; no `yes` token is
# followed by a dash), so a standing lint of .claude/hooks/*.sh stays clean on
# this file. Tests: .claude/hooks/shell-lint.test.sh (wired into CI verify).
set -u

rc=0
emit() { printf '%s\n' "$1"; rc=1; }

for f in "$@"; do
  [ -f "$f" ] || continue

  # (a) syntax — bash -n prints the first error to stderr and exits non-zero.
  errs="$(bash -n "$f" 2>&1)" || emit "$f: syntax: $(printf '%s' "$errs" | head -1 | sed -E 's#^[^:]*: *##')"

  # (b) portability denylist. grep -n yields <line>:<text>; reshape to a
  # diagnostic, keeping only the line number (${hit%%:*}).
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    emit "$f:${hit%%:*}: yes-dash-arg: a leading-dash argument to yes is read as an option by GNU yes"
  done < <(grep -nE "(^|[^[:alnum:]_./-])yes[[:space:]]+['\"]?-" "$f" 2>/dev/null)

  # An awk command line that also carries a brace-then-digit interval. Scoped to
  # lines naming awk so a portable grep/sed interval (same brace syntax, but
  # honored everywhere) is left alone; a multi-line awk program is a known gap
  # (denylist, not an oracle).
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    emit "$f:${hit%%:*}: awk-interval: regex interval {n}/{n,m} is non-portable to BSD awk"
  done < <(grep -nE '(^|[^[:alnum:]_])awk' "$f" 2>/dev/null | grep -E '[{][0-9]')
done

exit "$rc"
