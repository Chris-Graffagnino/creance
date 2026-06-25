#!/usr/bin/env bash
# maker-eval-fence.sh — the deterministic P5 fence over the maker-eval channel
# (T804, spec 003 US2.AC3). The runtime-neutral doc (.claude/workflow/maker-eval.md →
# "Observe-only") states the boundary; this is the deterministic CI assertion that
# enforces it, rather than leaving P5 to reviewer judgment (a deliberate strengthening
# over spec-001 telemetry, whose P5 enforcement is judgment-only). Adapter-side, so it
# may name concrete files — it is NOT a `workflow/**` neutral doc.
#
# WHAT IT PROVES (constitution P5 — telemetry/evaluation observes, never decides):
#   The eval-record path (`records.jsonl`) and the transcript-packet storage under it
#   (`packets/`) — together with the channel access seam (the `MAKER_EVAL_DIR` /
#   `MAKER_EVAL_ROOT` env override, the `<repo>-maker-eval` channel dir name, and
#   invoking the `maker-eval-emit` writer) — are referenced ONLY by the eval WRITER
#   (hooks/maker-eval-emit.sh) and the triage READER (skills/triage/SKILL.md), and by
#   NO gate, tier, guard, or selection code path. A reference anywhere outside the
#   allowlist below means a control-authority path can read or write the observe-only
#   channel — exactly the P5 breach this fences against.
#
# WHY TOKENS, NOT THE ABSOLUTE PATH: the channel is an OUT-OF-REPO directory resolved
# at run time (.claude/PROJECT.md → "Paths" → Maker-eval records), so the fence keys on
# the concrete identifiers any referencing code MUST name. By the engine's runtime
# neutrality these tokens appear only in adapter/profile/test files — the neutral engine
# docs (workflow/**) carry none of them — so a clean tree needs no neutral-doc exception.
#
# DETERMINISM + FAIL-CLOSED: a plain `grep` over the tracked tree (NOT ripgrep, whose
# user config can silently skip files — the check-tasks-consistency.sh idiom). If the
# tree cannot be listed at all it exits LOUD (not a silent pass — the "silently dead
# machinery" anti-pattern, constitution P2).
#
# Root override: MAKER_EVAL_FENCE_ROOT (default: the repo root) so the .test.sh can
# point the scan at a throwaway fixture tree with a planted cross-reference.
#
# Run:   bash .claude/hooks/maker-eval-fence.sh
# Tests: .claude/hooks/maker-eval-fence.test.sh (wired into CI verify).
set -u

ROOT="${MAKER_EVAL_FENCE_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"

# The eval channel's path/IO surface — the eval-record path leaf (`records.jsonl`), the
# transcript-packet storage leaf (`packets/`), the env access seam, the channel dir name
# suffix, and the writer invocation. ERE; '+'/'*' only (no awk-style {n} interval — the
# BSD/GNU-portable form shell-lint.sh enforces, #97).
CHANNEL_TOKENS='records\.jsonl|packets/|MAKER_EVAL_DIR|MAKER_EVAL_ROOT|-maker-eval|maker-eval-emit'

# Files permitted to carry the channel tokens. Tier 1 is the AC's "eval writer and
# triage reader" — the only two control-authority code paths sanctioned to touch the
# channel. Tier 2 is the non-control-authority surface that must name the path by its
# nature: the profile declaration, the extraction manifest, CI wiring, every test
# harness (tests exercise the channel but carry no runtime authority), and the fence
# itself. Anything NOT matched here — guard.sh, gate-loop.{js,md}, MODELS.md, the
# reconcile-*/announce-* selection hooks, next-task.md, and any future code path — is a
# gate/tier/guard/selection path, and a reference there is the P5 violation.
allowed() {
  case "$1" in
    # Tier 1 — the channel's two sanctioned code paths.
    .claude/hooks/maker-eval-emit.sh) return 0 ;;  # the eval WRITER
    .claude/skills/triage/SKILL.md)   return 0 ;;  # the triage READER
    # Tier 2 — declaration / manifest / wiring / tests / the fence itself.
    .claude/PROJECT.md)                return 0 ;;  # the profile path declaration
    .claude/PROJECT.template.md)       return 0 ;;  # the template's path row
    .claude/EXTRACTION.md)             return 0 ;;  # the extraction cut-list
    .github/workflows/ci.yml)          return 0 ;;  # CI wiring (runs the writer/fence tests)
    .claude/hooks/maker-eval-fence.sh) return 0 ;;  # the fence (names the tokens to scan)
    *.test.sh | *.test.js)             return 0 ;;  # tests exercise the channel (no authority)
    *) return 1 ;;
  esac
}

# Tracked-tree listing, repo-relative. git ls-files when ROOT is a work tree (skips
# untracked build artifacts deterministically); else a find fallback so a non-git
# fixture still scans. Either way paths are ROOT-relative for the allowlist match.
list_files() {
  if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "$ROOT" ls-files
  else
    ( cd "$ROOT" && find . -type f -not -path './.git/*' | sed 's#^\./##' )
  fi
}

files="$(list_files | LC_ALL=C sort)"
if [ -z "$files" ]; then
  printf 'maker-eval-fence: no files to scan under %s — cannot enforce the P5 fence (failing closed).\n' "$ROOT" >&2
  exit 2
fi

violations=0
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  allowed "$rel" && continue
  hits="$(grep -I -nE "$CHANNEL_TOKENS" "$ROOT/$rel" 2>/dev/null)"
  [ -n "$hits" ] || continue
  violations=$((violations + 1))
  printf 'P5 FENCE VIOLATION: %s references the observe-only maker-eval channel (eval-record path / transcript packets) — only the eval writer and the triage reader may, never a gate/tier/guard/selection path (constitution P5):\n' "$rel" >&2
  printf '%s\n' "$hits" | sed 's/^/    /' >&2
done <<EOF
$files
EOF

if [ "$violations" -gt 0 ]; then
  printf 'maker-eval-fence: %d file(s) outside the writer/reader allowlist reference the eval channel — P5 (observe-only) breached.\n' "$violations" >&2
  exit 1
fi
printf 'maker-eval-fence: OK — the maker-eval channel (records.jsonl + packets/) is referenced only by the eval writer and the triage reader.\n'
exit 0
