#!/usr/bin/env bash
# harness-manifest-fence.sh — the deterministic P5 fence over the generated harness
# manifest (T637, issue #233; the maker-eval-fence.sh pattern).
#
# WHAT IT PROVES (constitution P5 — the manifest observes, never decides): the committed
# lock artifact (`.claude/HARNESS.lock.json`) is COMPILED EVIDENCE, never authority — it
# is written by its generator and read by humans/CI staleness checks only. NO gate, tier,
# guard, selection, or autonomy code path may read it: a reference outside the allowlist
# below means a control-authority path could consume the compiled snapshot instead of the
# source-of-truth docs — exactly the hidden-control-path breach issue #233's non-goals
# forbid. Source docs win on any disagreement; disagreement requires regeneration
# (`python3 .claude/hooks/harness-manifest.py --write`), never trusting the lock.
#
# The fence keys on the lock file's name (`HARNESS.lock`) — the token any referencing
# code MUST carry. Allowlisted: the generator (writes it), the lock itself, the
# extraction cut-list, the backlog/spec declaration surfaces (prose that names the
# artifact by nature, no execution), the two manifest test harnesses by exact name
# (never a *.test.sh glob — tests run in the required verify job), and this fence. CI is
# line-scoped like maker-eval-fence.sh: it may RUN the staleness check and the tests,
# but a surviving hit (e.g. a step that parses the lock to decide a gate) is the breach.
#
# DETERMINISM + FAIL-CLOSED: a plain `grep` over the tracked tree (NOT ripgrep, whose
# user config can silently skip files). An unlistable tree exits LOUD (constitution P2).
#
# Root override: HARNESS_MANIFEST_FENCE_ROOT (default: the repo root) so the .test.sh
# can point the scan at a fixture tree with a planted cross-reference.
#
# Run:   bash .claude/hooks/harness-manifest-fence.sh
# Tests: .claude/hooks/harness-manifest-fence.test.sh (wired into CI verify).
set -u

ROOT="${HARNESS_MANIFEST_FENCE_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"

# The lock artifact's identifying token. Matching the basename stem (not the full path)
# closes the relative-reference forms (`../HARNESS.lock.json`, a bare `HARNESS.lock.json`
# after a cd) a path-anchored pattern would let evade.
MANIFEST_TOKEN='HARNESS\.lock'

# Files permitted to name the lock artifact. Everything here is either the write/check
# surface (the generator), a non-executable declaration surface (prose naming the
# artifact by nature), or one of the two manifest test harnesses, named exactly.
# Anything NOT matched here or line-scoped below — guard.sh, gate-loop.{js,md},
# autonomy-mode.sh, the reconcile-*/announce-* selection hooks, backlog-loop-*, MODELS.md,
# any future code path — is a gate/tier/guard/selection/autonomy surface, and a reference
# there is the P5 violation. (A future observe-only consumer — e.g. the #234/T638 status
# map — must be added here explicitly by PR, with its observe-only nature stated.)
allowed() {
  case "$1" in
    .claude/hooks/harness-manifest.py)       return 0 ;;  # the generator + staleness check (the WRITER)
    .claude/HARNESS.lock.json)               return 0 ;;  # the lock artifact itself
    .claude/hooks/harness-manifest-fence.sh) return 0 ;;  # the fence (names the token to scan)
    .claude/EXTRACTION.md)                   return 0 ;;  # the extraction cut-list
    specs/*/tasks.md | specs/*/spec.md | specs/TASK_INDEX.md)
                                             return 0 ;;  # backlog/spec declaration prose (no execution)
    .claude/hooks/harness-manifest.test.sh | .claude/hooks/harness-manifest-fence.test.sh)
                                             return 0 ;;  # the two manifest harnesses, by exact name — tests run in the required `verify` job, so a *.test.sh glob would let any future test consume the lock unfenced (PR #283)
    *) return 1 ;;
  esac
}

# CI line-scope (the maker-eval-fence.sh idiom). CI is a gate surface (it decides the
# merge), so ci.yml is scanned and each token-bearing line is a violation UNLESS benign:
# a YAML comment (cannot execute), the staleness-check invocation, or a *.test.sh
# harness step. The `$` anchors keep the allowance to the bare invocations — a trailing
# `&& jq . .claude/HARNESS.lock.json` does not match and survives as the breach.
CI_WORKFLOW='.github/workflows/ci.yml'
CI_BENIGN_LINE='^[0-9]+:[[:space:]]*#|^[0-9]+:[[:space:]]*run: python3 \.claude/hooks/harness-manifest\.py --check[[:space:]]*$|^[0-9]+:[[:space:]]*run: bash \.claude/hooks/[a-z0-9-]+\.test\.sh[[:space:]]*$'

# Tracked-tree listing, repo-relative (git when ROOT is a work tree; find fallback so a
# non-git fixture still scans).
list_files() {
  if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "$ROOT" ls-files
  else
    ( cd "$ROOT" && find . -type f -not -path './.git/*' | sed 's#^\./##' )
  fi
}

files="$(list_files | LC_ALL=C sort)"
if [ -z "$files" ]; then
  printf 'harness-manifest-fence: no files to scan under %s — cannot enforce the P5 fence (failing closed).\n' "$ROOT" >&2
  exit 2
fi

violations=0
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  allowed "$rel" && continue
  hits="$(grep -I -nE "$MANIFEST_TOKEN" "$ROOT/$rel" 2>/dev/null)"
  [ -n "$hits" ] || continue
  if [ "$rel" = "$CI_WORKFLOW" ]; then
    hits="$(printf '%s\n' "$hits" | grep -vE "$CI_BENIGN_LINE")"
    [ -n "$hits" ] || continue
  fi
  violations=$((violations + 1))
  printf 'P5 FENCE VIOLATION: %s references the generated harness manifest (HARNESS.lock) — compiled evidence is never authority; no gate/tier/guard/selection/autonomy path may read it (constitution P5):\n' "$rel" >&2
  printf '%s\n' "$hits" | sed 's/^/    /' >&2
done <<EOF
$files
EOF

if [ "$violations" -gt 0 ]; then
  printf 'harness-manifest-fence: %d file(s) outside the generator/declaration/test allowlist reference the lock artifact — P5 (compiled evidence, never authority) breached.\n' "$violations" >&2
  exit 1
fi
printf 'harness-manifest-fence: OK — the harness manifest is referenced only by its generator, declaration surfaces, and tests.\n'
exit 0
