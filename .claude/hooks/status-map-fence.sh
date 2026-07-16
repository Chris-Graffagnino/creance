#!/usr/bin/env bash
# status-map-fence.sh — the deterministic P5 fence over the harness status map (T638,
# issue #234; the maker-eval-fence.sh pattern, kept symmetric with harness-manifest-fence.sh
# so neither observe-only surface can be fenced by documentation alone).
#
# WHAT IT PROVES (constitution P5 — the map observes, never decides): the status map
# (`.claude/hooks/status-map.sh`) is an ORIENTATION surface, never authority. NO gate, tier,
# guard, selection, or autonomy code path may consume it: a reference outside the allowlist
# below means a control-authority path could branch on a best-effort snapshot — several of
# whose fields are explicitly `unknown` when the tracker is down — instead of the
# source-of-truth docs and the deterministic checks that own those decisions. That is
# exactly the hidden-control-path breach issue #234's non-goals forbid ("do not make
# status-map output authoritative over PROJECT.md, workflow docs, or the constitution").
#
# WHY THE TOKEN IS THE NAME: the map writes NO artifact — it prints to stdout and nothing
# else (status-map.sh). So unlike the manifest fence (which keys on the lock file's name,
# the token a reader must carry), the only way to consume this map is to NAME it. The token
# therefore matches BOTH the command form (`status-map`) and the English form
# (`status map`): in a prose-driven harness a rule that says "consult the harness status map
# to decide X" IS an instruction to a decision path — as effective as a shell invocation and
# exactly the class the MODELS.md / SKILL.md plants below treat as the threat. Matching only
# the hyphen would fence the shell form and leave the prose form wide open. It is
# deliberately CASE-SENSITIVE: a title-cased `Status-map` heading (a CI step name, a doc
# heading) names the tool, it does not instruct anything.
#
# Allowlisted: the map itself, this fence, the two status-map test harnesses by exact name
# (never a *.test.sh glob — tests run in the required verify job, so a glob would let any
# future test consume the map unfenced; the PR #283 lesson carried forward), the extraction
# cut-list, the reciprocal manifest-fence surfaces, and the backlog/spec declaration
# surfaces. THREE surfaces are deliberately NOT whole-file trusted but line-scoped in the
# loop below, each because it is a real surface that may name the map only narrowly:
# (1) CI (it RUNS the map's tests but also decides the merge — CI_BENIGN_LINE); (2) the
# shared drift lib (guard/selection source it — DRIFT_LIB_BENIGN_LINE); and (3) the adapter
# README (its `## Orientation` prose is the sanctioned doc pointer, but the SAME file is the
# adapter's binding-contract table — a row like `| [live-state reconciliation] | … checked
# against status-map.sh |` would be a genuine hidden control path, and "it's only prose" is
# no defence: MODELS.md and next-task/SKILL.md are prose too and are planted as violations
# below — README_BENIGN_LINE).
#
# DETERMINISM + FAIL-CLOSED: a plain `grep` over the tracked tree (NOT ripgrep, whose user
# config can silently skip files). An unlistable tree exits LOUD (constitution P2).
#
# Root override: STATUS_MAP_FENCE_ROOT (default: the repo root) so the .test.sh can point
# the scan at a fixture tree with a planted cross-reference.
#
# Run:   bash .claude/hooks/status-map-fence.sh
# Tests: .claude/hooks/status-map-fence.test.sh (wired into CI verify).
set -u

ROOT="${STATUS_MAP_FENCE_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"

# The map's identifying token: the name stem in either the command (`status-map`) or the
# English (`status map`) form. Matching the stem (not the full path) closes the
# relative-reference forms (`../status-map.sh`, a bare `status-map.sh` after a cd) a
# path-anchored pattern would let evade. Portable ERE; case-sensitive by design (above).
MAP_TOKEN='status[ -]map'

# Files permitted to name the status map. Everything here is either the map itself, its
# fence/tests, or a non-executable declaration surface (prose naming the tool by nature).
# Anything NOT matched here or line-scoped below — guard.sh, gate-loop.{js,md},
# autonomy-mode.sh, the reconcile-*/announce-* selection hooks, backlog-loop-*, MODELS.md,
# any future code path — is a gate/tier/guard/selection/autonomy surface, and a reference
# there is the P5 violation.
allowed() {
  case "$1" in
    .claude/hooks/status-map.sh)            return 0 ;;  # the map itself (the surface being fenced)
    .claude/hooks/status-map-fence.sh)      return 0 ;;  # this fence (names the token to scan)
    .claude/hooks/status-map.test.sh | .claude/hooks/status-map-fence.test.sh)
                                            return 0 ;;  # the two status-map harnesses, by exact name — tests run in the required `verify` job, so a *.test.sh glob would let a future test consume the map unfenced (the PR #283 lesson)
    .claude/EXTRACTION.md)                  return 0 ;;  # the extraction cut-list
    # The manifest fence names the map in its ALLOWLIST (the map reads the generated harness
    # manifest for its static facts, so T637's fence must sanction it by name) and its test
    # plants the same name as a fixture. A fence only ever greps: it decides nothing about
    # gates, tiers, selection, or autonomy, and naming a file in a `case` pattern is not
    # consuming its output. Both by exact name — never a hooks/ glob.
    # (This comment says "the generated harness manifest" rather than the lock's filename on
    # purpose: that filename is T637's own fenced token, and this fence never reads it.)
    .claude/hooks/harness-manifest-fence.sh | .claude/hooks/harness-manifest-fence.test.sh)
                                            return 0 ;;  # the reciprocal fence allowlist + its fixture (declaration, no execution)
    specs/*/tasks.md | specs/*/spec.md | specs/TASK_INDEX.md)
                                            return 0 ;;  # backlog/spec declaration prose (no execution)
    *) return 1 ;;
  esac
}

# lib-tasks-drift.sh is deliberately NOT whole-file trusted above but line-scoped below,
# for the same reason CI is: it is a real execution surface with control authority. It is
# SOURCED by guard.sh rule 8 and the reconcile-*/announce-* selection hooks, so an
# executable map invocation added to it would put the map's best-effort output inside a
# decision path transitively — the exact P5 breach, laundered through a shared library. Its
# only sanctioned reference is the header's consumer list (the map SOURCES the lib; the
# dependency never points back), so a `#` comment line is benign and anything else FIRES.
DRIFT_LIB='.claude/hooks/lib-tasks-drift.sh'
DRIFT_LIB_BENIGN_LINE='^[0-9]+:[[:space:]]*#'

# The adapter README is likewise line-scoped rather than whole-file trusted. It is TWO
# things in one file: the `## Orientation` section (the sanctioned doc pointer this task
# adds — narrative prose that tells a human the tool exists) and the binding-contract table
# (`| **[role]** | mechanism |`), which is where a role is bound to a concrete mechanism. A
# contract ROW naming the map would bind a decision role to it — a hidden control path — so
# rows FIRE and everything else is benign. Anchored on the leading table pipe.
README_DOC='.claude/README.md'
README_BENIGN_LINE='^[0-9]+:[[:space:]]*[^|]'

# CI line-scope (the maker-eval-fence.sh idiom). CI is a gate surface (it decides the
# merge), so ci.yml is scanned and each token-bearing line is a violation UNLESS benign: a
# YAML comment (cannot execute), or a bare `bash .claude/hooks/<name>.sh|.test.sh` step.
# The `$` anchors keep the allowance to the bare invocations — a trailing
# `| grep -q 'autonomy: enabled'` does not match and survives as the breach.
CI_WORKFLOW='.github/workflows/ci.yml'
CI_BENIGN_LINE='^[0-9]+:[[:space:]]*#|^[0-9]+:[[:space:]]*run: bash \.claude/hooks/[a-z0-9-]+(\.test)?\.sh[[:space:]]*$'

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
  printf 'status-map-fence: no files to scan under %s — cannot enforce the P5 fence (failing closed).\n' "$ROOT" >&2
  exit 2
fi

violations=0
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  allowed "$rel" && continue
  hits="$(grep -I -nE "$MAP_TOKEN" "$ROOT/$rel" 2>/dev/null)"
  [ -n "$hits" ] || continue
  if [ "$rel" = "$CI_WORKFLOW" ]; then
    hits="$(printf '%s\n' "$hits" | grep -vE "$CI_BENIGN_LINE")"
    [ -n "$hits" ] || continue
  fi
  if [ "$rel" = "$DRIFT_LIB" ]; then
    hits="$(printf '%s\n' "$hits" | grep -vE "$DRIFT_LIB_BENIGN_LINE")"
    [ -n "$hits" ] || continue
  fi
  if [ "$rel" = "$README_DOC" ]; then
    hits="$(printf '%s\n' "$hits" | grep -vE "$README_BENIGN_LINE")"
    [ -n "$hits" ] || continue
  fi
  violations=$((violations + 1))
  printf 'P5 FENCE VIOLATION: %s references the harness status map (status-map) — the map is orientation, never authority; no gate/tier/guard/selection/autonomy path may consume it (constitution P5):\n' "$rel" >&2
  printf '%s\n' "$hits" | sed 's/^/    /' >&2
done <<EOF
$files
EOF

if [ "$violations" -gt 0 ]; then
  printf 'status-map-fence: %d file(s) outside the map/declaration/test allowlist reference the status map — P5 (observes, never decides) breached.\n' "$violations" >&2
  exit 1
fi
printf 'status-map-fence: OK — the status map is referenced only by itself, its declaration surfaces, and its tests.\n'
exit 0
