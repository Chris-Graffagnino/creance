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
#   (hooks/maker-eval-emit.sh), its RUN binding (skills/maker-eval/SKILL.md, which only
#   DRIVES the writer — T805), and the triage READER (skills/triage/SKILL.md), and by
#   NO gate, tier, guard, or selection code path. A reference anywhere outside the
#   allowlist below means a control-authority path can read or write the observe-only
#   channel — exactly the P5 breach this fences against. (The non-executable declaration /
#   manifest / probe-doc / test surface in Tier 2 names the channel by nature, not to act
#   on it.)
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
# transcript-packet storage dir (`packets`), the env access seam, the channel dir name
# suffix, and the writer invocation. The packet dir is matched as a PATH SEGMENT — adjacent
# to a `/` or a quote on either side — so all reference forms fire (`packets/`,
# `$channel/packets` with no trailing slash, the pathlib `… / "packets"`, `'packets'`) while
# the bare English plural in prose (".. transcript packets are ..") does not. Matching only
# `packets/` let the no-trailing-slash forms evade (PR #162 Codex P2). ERE; portable
# constructs only — char classes and '+'/'*', no awk-style {n} interval (shell-lint.sh, #97).
CHANNEL_TOKENS='records\.jsonl|[/"'\'']packets|packets[/"'\'']|MAKER_EVAL_DIR|MAKER_EVAL_ROOT|-maker-eval|maker-eval-emit'

# Files permitted to carry the channel tokens. Tier 1 is the AC's "eval writer and
# triage reader" — the only two control-authority code paths sanctioned to touch the
# channel. Tier 2 is the non-executable / non-control surface that must name the path by
# its nature: the profile declaration, the extraction manifest, every test harness (tests
# exercise the channel but carry no runtime authority), and the fence itself. CI is the
# deliberate exception — it carries the wiring that RUNS the channel's tests, but it is
# also a gate (it decides the merge), so it is NOT wholly trusted here: it is scanned
# line-by-line in the loop below (see CI_BENIGN_LINE), not blanket-allowed. Anything NOT
# matched here — guard.sh, gate-loop.{js,md}, MODELS.md, the reconcile-*/announce-*
# selection hooks, next-task.md, and any future code path — is a gate/tier/guard/selection
# path, and a reference there is the P5 violation.
allowed() {
  case "$1" in
    # Tier 1 — the channel's sanctioned CODE paths: the writer, its run binding, and the
    # reader. None carries gate/tier/guard/selection authority — they ARE the eval
    # write/read surface (the run binding only DRIVES the writer; T805).
    .claude/hooks/maker-eval-emit.sh)       return 0 ;;  # the eval WRITER (appends the record)
    .claude/skills/maker-eval/SKILL.md)     return 0 ;;  # the eval RUN binding (drives the writer)
    .claude/skills/triage/SKILL.md)         return 0 ;;  # the triage READER (surfaces, never writes)
    # Tier 2 — declaration / manifest / probe-doc / tests / the fence itself (non-executable,
    # or no control authority). CI is intentionally absent: it is line-scoped below, not here.
    .claude/PROJECT.md)                     return 0 ;;  # the profile path declaration
    .claude/PROJECT.template.md)            return 0 ;;  # the template's path row
    .claude/EXTRACTION.md)                  return 0 ;;  # the extraction cut-list
    .claude/adapters/claude-code-probes.md) return 0 ;;  # the P-ME probe instantiation (names the writer/channel by nature)
    .claude/hooks/maker-eval-fence.sh)      return 0 ;;  # the fence (names the tokens to scan)
    *.test.sh | *.test.js)                  return 0 ;;  # tests exercise the channel (no authority)
    *) return 1 ;;
  esac
}

# CI line-scope. CI is allowlisted only for the wiring that RUNS the channel's tests; as a
# gate surface (it decides the merge) it must not hide a step that reads or writes the
# channel. So ci.yml is scanned (absent from allowed() above) and each token-bearing line
# is treated as a violation UNLESS it is benign: a YAML comment (cannot execute), or a step
# invoking a maker-eval *.test.sh harness (running the channel's tests carries no control
# authority). A surviving hit — e.g. a `run:` step that cats records.jsonl, or one that
# invokes the writer maker-eval-emit.sh to fold a score into pass/fail — is the P5 breach.
# Patterns match `grep -n` output (`<lineno>:<text>`); the `$` anchor keeps the test-wiring
# allowance to a bare invocation (a trailing `&& cat records.jsonl` does not match).
CI_WORKFLOW='.github/workflows/ci.yml'
CI_BENIGN_LINE='^[0-9]+:[[:space:]]*#|^[0-9]+:[[:space:]]*run: bash \.claude/hooks/[a-z0-9-]+\.test\.sh[[:space:]]*$'

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
  # CI is scanned, not wholly allowlisted (it is a gate surface): drop the benign lines
  # (comment / sanctioned *.test.sh wiring) and treat only what survives as a violation.
  if [ "$rel" = "$CI_WORKFLOW" ]; then
    hits="$(printf '%s\n' "$hits" | grep -vE "$CI_BENIGN_LINE")"
    [ -n "$hits" ] || continue
  fi
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
