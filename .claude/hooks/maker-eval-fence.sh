#!/usr/bin/env bash
# maker-eval-fence.sh — the deterministic P5 fence over the maker-eval channel
# (T804, spec 003 US2.AC3). The runtime-neutral doc (.claude/workflow/maker-eval.md →
# "Observe-only") states the boundary; this is the deterministic CI assertion that
# enforces it, rather than leaving P5 to reviewer judgment (a deliberate strengthening
# over spec-001 telemetry, whose P5 enforcement is judgment-only). Adapter-side, so it
# may name concrete files — it is NOT a `workflow/**` neutral doc.
#
# WHAT IT PROVES (constitution P5 — telemetry/evaluation observes, never decides):
#   The eval-record path (`records.jsonl`), the transcript-packet storage under it
#   (`packets/`), and the interval-snapshot trajectory storage (`trajectory/` — the
#   US3.AC4 extension, T808) — together with the channel access seam (the `MAKER_EVAL_DIR` /
#   `MAKER_EVAL_ROOT` env override and the `<repo>-maker-eval` channel dir name) — are
#   READ/RESOLVED only by the eval WRITER (hooks/maker-eval-emit.sh) and the triage READER
#   (skills/triage/SKILL.md), and by NO gate, tier, guard, or selection code path. The eval
#   RUN binding (skills/maker-eval/SKILL.md) may only DRIVE the writer (`maker-eval-emit record`)
#   or recompute the fingerprint (`maker-eval-emit fingerprint`, no channel I/O)
#   — it is the maker-eval analog of CI: a real execution surface that is NOT whole-file
#   trusted but line-scoped below, so a writer drive / fingerprint recompute in it is benign
#   while a channel READ/RESOLVE — a record-path/packet/seam token OR the emitter's channel-
#   reading `complete` subcommand — still FAILs (PR #164; spec 003 US2.AC3 scopes the record
#   path + packet store to the writer and the reader). A reference anywhere outside the allowlist/line-scope
#   below means a control-authority path can read or write the observe-only channel — exactly
#   the P5 breach this fences against. (The non-executable declaration / manifest / probe-doc /
#   test surface in Tier 2 names the channel by nature, not to act on it.)
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

# The eval channel's path/IO surface, split into the two reference KINDS the fence
# distinguishes (so the run binding can be line-scoped below, PR #164):
#
#   CHANNEL_READ_TOKENS — reaching INTO the channel: the eval-record path leaf
#   (`records.jsonl`), the transcript-packet storage dir (`packets`), the TRAJECTORY
#   storage dir (`trajectory` — the interval-snapshot store the US3.AC4 extension scopes,
#   matched as a path segment exactly like `packets`, so prose about "trajectory storage"
#   or a "Trajectory measurement" heading never fires while `$chan/trajectory` and
#   `trajectory/<run>` do), the env access seam
#   (`MAKER_EVAL_DIR` / `MAKER_EVAL_ROOT`), and the channel dir-name suffix (`-maker-eval`).
#   Naming any of these reads channel contents or resolves the channel location directly —
#   per spec 003 US2.AC3 only the eval writer and the triage reader may. The packet dir is
#   matched as a PATH SEGMENT — adjacent to a `/` or a quote on either side — so all
#   reference forms fire (`packets/`, `$channel/packets` with no trailing slash, the pathlib
#   `… / "packets"`, `'packets'`) while the bare English plural in prose (".. transcript
#   packets are ..") does not. Matching only `packets/` let the no-trailing-slash forms
#   evade (PR #162 Codex P2). The dir-name suffix is likewise matched as TERMINAL — the
#   channel dir is `<repo>-maker-eval` exactly, so the token must be followed by a
#   non-name character (`/`, a quote, whitespace) or end-of-line. A name that merely
#   CONTAINS the words and continues (`specs/003-maker-eval-corpus/…` — a live spec
#   directory every paths-listing artifact must be able to name) is not a channel
#   reference and must not fire (T1203: the compact project packet's spec-path list was
#   this exact false positive).
#
#   WRITER_INVOCATION — DRIVING the writer (`maker-eval-emit`): asking the emitter to append
#   a record. This is the run binding's sanctioned job; it is NOT a read of the channel, so
#   the run binding's line-scope (below) treats it as benign while a CHANNEL_READ_TOKENS
#   reference there still fires.
#
# The fence scans for EITHER kind. ERE; portable constructs only — char classes and '+'/'*',
# no awk-style {n} interval (shell-lint.sh, #97).
CHANNEL_READ_TOKENS='records\.jsonl|[/"'\'']packets|packets[/"'\'']|[/"'\'']trajectory|trajectory[/"'\'']|MAKER_EVAL_DIR|MAKER_EVAL_ROOT|-maker-eval([^-A-Za-z0-9_]|$)'
WRITER_INVOCATION='maker-eval-emit'
CHANNEL_TOKENS="$CHANNEL_READ_TOKENS|$WRITER_INVOCATION"

# The emitter's CHANNEL-READING subcommand. Driving the writer to APPEND (`record`) or
# recomputing the maker-behavior fingerprint (`fingerprint`, which reads only the model
# table + the maker surfaces, never the channel) is the run binding's sanctioned job — both
# are benign there. But `complete` RESOLVES the channel and READS records.jsonl to count a
# run's records, so naming it in the line-scoped run binding is a channel READ, not a writer
# drive — exactly the read the binding may not do (the triage reader's job, spec 003 US2.AC3).
# The whole-emitter line-scope this replaces let `complete` pass because it carries no explicit
# CHANNEL_READ token (PR #164 Codex P2). `complete` is the emitter's ONLY SURFACING read —
# a subcommand whose channel-derived value exists to be consumed outside the write pipeline;
# a new such subcommand must be added here with a paired test. (`snapshot-run` — T807 —
# internally counts its own trajectory writes to decide
# the trajectory-incomplete marking, but exposes no channel-derived value to the caller: it
# returns only the wrapped maker command's exit, so driving it from the binding stays a
# sanctioned WRITE, like `record`. `grade-snapshots` — T808, US3.AC3 — DOES read the
# trajectory storage, but inside the fence-trusted writer and only to hand the run binding
# the per-interval verdicts it immediately appends back via `record --trajectory`: a
# WRITE-PIPELINE read whose output feeds nothing but the observe-only record, so driving it
# from the binding is sanctioned like `record` — while naming the trajectory path itself
# there, or anywhere else outside the allowlist, still FIRES on CHANNEL_READ_TOKENS.)
# Matched over
# LOGICAL lines: the run-binding scan folds shell backslash-continuations first
# (fold_continuations below), so a `maker-eval-emit.sh \<newline> complete` wrap is one line
# here too — not a writer drive split from a tokenless `complete` (PR #164 craft). Portable ERE.
EMITTER_READ_SUBCOMMAND='maker-eval-emit(\.sh)?[[:space:]]+complete'

# Files permitted to carry the channel tokens. Tier 1 is the AC's "eval writer and
# triage reader" — the only two control-authority code paths sanctioned to touch the
# channel. Tier 2 is the non-executable / non-control surface that must name the path by
# its nature: the profile declaration, the extraction manifest, every test harness (tests
# exercise the channel but carry no runtime authority), and the fence itself. Two surfaces are
# deliberately NOT blanket-allowed but scanned LINE-BY-LINE in the loop below, because each is
# a real execution surface that may touch the channel only narrowly: (1) CI (it RUNS the
# channel's tests but is also a gate that decides the merge — see CI_BENIGN_LINE), and (2) the
# run binding (it may DRIVE the writer but never read the channel — see SKILL_BINDING). Anything
# NOT matched here or line-scoped below — guard.sh, gate-loop.{js,md}, MODELS.md, the
# reconcile-*/announce-* selection hooks, next-task.md, and any future code path — is a
# gate/tier/guard/selection path, and a reference there is the P5 violation.
allowed() {
  case "$1" in
    # Tier 1 — the channel's two whole-file-trusted CODE paths: the writer and the reader.
    # Neither carries gate/tier/guard/selection authority — they ARE the eval write/read
    # surface, so they may name any channel token. The run binding is deliberately NOT here:
    # it may only DRIVE the writer, never read the channel, so it is line-scoped in the loop
    # below (like CI), not whole-file trusted — PR #164; spec 003 US2.AC3 scopes the record
    # path + packet store to the writer and the reader.
    .claude/hooks/maker-eval-emit.sh)       return 0 ;;  # the eval WRITER (appends the record)
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

# Run-binding line-scope. The maker-eval RUN binding (skills/maker-eval/SKILL.md) is NOT in
# allowed() above: like ci.yml it is a real execution surface, so it is scanned and each
# token-bearing line is a violation UNLESS it is benign. Benign = the line only DRIVES the
# writer (`maker-eval-emit record`) or recomputes the fingerprint (`maker-eval-emit
# fingerprint`, no channel I/O); a line that names the record path, the packet store, or the
# channel seam/dir — OR invokes the emitter's channel-reading `complete` subcommand — is the
# binding reaching INTO the channel, a read/resolve the run binding may not do (that is the
# triage reader's job, spec 003 US2.AC3), and survives as a violation. Implemented by keeping
# the CHANNEL_READ_TOKENS and EMITTER_READ_SUBCOMMAND hits below (the whole-file allowlist this
# replaces let `complete` and any direct read pass — PR #164 craft/Codex).
SKILL_BINDING='.claude/skills/maker-eval/SKILL.md'

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

# Fold shell line-continuations into ONE logical line for the run-binding scan, emitted as
# `grep -n`-style "<start-lineno>:<text>" (the number is where the logical line BEGINS). A
# trailing backslash joins the next physical line exactly as the shell would, so a
# `maker-eval-emit.sh \<newline> complete` wrap becomes one line that matches
# EMITTER_READ_SUBCOMMAND — instead of a benign writer drive on line 1 split from a tokenless
# `complete` on line 2, which the per-physical-line scan cleared (PR #164 craft). POSIX awk
# (no {n} interval, no `awk` token on a continuation line — shell-lint.sh, #97).
fold_continuations() {
  awk '
    { buf = buf $0 }
    start == 0 { start = NR }
    /\\$/ { sub(/\\$/, "", buf); next }
    { print start ":" buf; buf = ""; start = 0 }
    END { if (start != 0) print start ":" buf }
  ' "$1"
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
  # Extract the channel-token hits as `grep -n`-style "<lineno>:<text>". The run binding is
  # scanned over LOGICAL lines (shell backslash-continuations folded into one) so a
  # `maker-eval-emit.sh \<newline> complete` wrap cannot split the writer-drive token from its
  # channel-reading `complete` subcommand across two physical lines and clear both in the
  # line-scope below (PR #164 craft). Every other file keeps the binary-safe per-physical-line
  # grep -I scan: there, ANY channel token is already a violation, so folding would not change
  # a verdict (and only the line-scoped run binding benign-filters a `complete` invocation).
  if [ "$rel" = "$SKILL_BINDING" ]; then
    hits="$(fold_continuations "$ROOT/$rel" | grep -E "$CHANNEL_TOKENS")"
  else
    hits="$(grep -I -nE "$CHANNEL_TOKENS" "$ROOT/$rel" 2>/dev/null)"
  fi
  [ -n "$hits" ] || continue
  # CI is scanned, not wholly allowlisted (it is a gate surface): drop the benign lines
  # (comment / sanctioned *.test.sh wiring) and treat only what survives as a violation.
  if [ "$rel" = "$CI_WORKFLOW" ]; then
    hits="$(printf '%s\n' "$hits" | grep -vE "$CI_BENIGN_LINE")"
    [ -n "$hits" ] || continue
  fi
  # The run binding is scanned, not whole-file allowlisted (it is a real execution surface):
  # keep as violations the channel-READ/seam references AND the emitter's channel-reading
  # subcommand (`complete`) — a bare writer DRIVE (`record`) or fingerprint recompute is the
  # binding's sanctioned job and drops out (see SKILL_BINDING / EMITTER_READ_SUBCOMMAND above).
  if [ "$rel" = "$SKILL_BINDING" ]; then
    hits="$(printf '%s\n' "$hits" | grep -E "$CHANNEL_READ_TOKENS|$EMITTER_READ_SUBCOMMAND")"
    [ -n "$hits" ] || continue
  fi
  violations=$((violations + 1))
  printf 'P5 FENCE VIOLATION: %s references the observe-only maker-eval channel (eval-record path / transcript packets / trajectory storage) — only the eval writer and the triage reader may, never a gate/tier/guard/selection path (constitution P5):\n' "$rel" >&2
  printf '%s\n' "$hits" | sed 's/^/    /' >&2
done <<EOF
$files
EOF

if [ "$violations" -gt 0 ]; then
  printf 'maker-eval-fence: %d file(s) outside the writer/reader allowlist reference the eval channel — P5 (observe-only) breached.\n' "$violations" >&2
  exit 1
fi
printf 'maker-eval-fence: OK — the maker-eval channel (records.jsonl + packets/ + trajectory/) is referenced only by the eval writer and the triage reader.\n'
exit 0
