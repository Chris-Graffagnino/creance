#!/usr/bin/env bash
# Falsification tests for doc-pointer-check.sh (T1208, spec 007 US8; issue #273).
#
# Two-sided per constitution P2, both existence directions in one suite (US8.AC3):
# a planted DANGLING pointer fails naming surface + path + line — the planted form
# includes the real #272/#273 class (a bare `workflow/…md` that resolves only under
# `.claude/`) AND a held-out bare-nested pointer whose leading segment appears in
# none of the spec's named examples (proving the recognizer is leading-segment-
# agnostic: neither a `workflow/`-keyed implementation nor a fixed allowlist passes)
# — while an ALL-RESOLVE control passes. A containment control asserts the
# non-lexically-repo-relative forms (absolute `/…`, `..` traversal, `scheme://`)
# are neither resolved nor flagged (US8.AC1/AC2/AC3), and a non-path-forms control
# (globs, braces, placeholders, anchors, command tokens) passes (US8.AC2).
#
# Non-vacuity (US8.AC1): the positive-extraction case runs the UNMODIFIED extractor
# (--extract) over the REAL scanned surfaces and compares to a hand-verified
# independent oracle — the COMPLETE shape-matched (surface, path) multiset present
# in them, verified by eye against the surface text, not derived by re-running the
# extractor under test (US4.AC4's oracle discipline). Line numbers are asserted in
# the failure-direction cases (the diagnostics contract), not in the oracle, so an
# unrelated line shift doesn't fail it — adding or removing a pointer does.
#
# Each fixture case builds a throwaway sandbox tree and runs the real check with
# the sandbox as CWD (the compact-packet-drift.test.sh idiom).
# Run: bash .claude/hooks/doc-pointer-check.test.sh
set -u
export LC_ALL=C

HOOKS="$(cd "$(dirname "$0")" && pwd)"
CHECK="$HOOKS/doc-pointer-check.sh"
REPO_ROOT="$(cd "$HOOKS/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
pass=0
fail=0

ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); printf 'FAIL %s\n' "$1" >&2; }

# run_check <dir> [args...] — run the real check with <dir> as CWD; combined
# output in $OUT, exit code in $GOT.
run_check() {
  local d="$1"
  shift
  GOT=0
  OUT="$( (cd "$d" && bash "$CHECK" "$@") 2>&1 )" || GOT=$?
}

# --- A: real-tree control — the default surface set resolves from the repo root
#     (US8.AC4's verify-green invariant; doubles as the US8.AC2 within-tree
#     control: the real surfaces carry globs, braces, placeholders, anchors, and
#     command tokens, and the check passes). ------------------------------------
run_check "$REPO_ROOT"
if [ "$GOT" -eq 0 ]; then ok; else bad "A real-tree control must pass (got $GOT): $OUT"; fi
if printf '%s' "$OUT" | grep -q 'doc-pointer check: OK'; then ok; else bad "A control must report OK"; fi

# --- B: positive extraction (US8.AC1 non-vacuity) — the unmodified extractor over
#     the real surfaces recovers the COMPLETE hand-verified (surface, path)
#     multiset: 17 in AGENTS.md, 34 in .claude/PROJECT.md, 23 in
#     .claude/PROJECT.compact.md (74 total as of this diff). --------------------
ORACLE="$TMP/oracle.txt"
sort > "$ORACLE" <<'EOF'
AGENTS.md:.claude/DESIGN-NOTES.md
AGENTS.md:.claude/PROJECT.md
AGENTS.md:.claude/PROJECT.md
AGENTS.md:.claude/PROJECT.md
AGENTS.md:.claude/PROJECT.md
AGENTS.md:.claude/PROJECT.md
AGENTS.md:.claude/context-budgets.md
AGENTS.md:.claude/governance-rules.md
AGENTS.md:.claude/workflow/README.md
AGENTS.md:.claude/workflow/README.md
AGENTS.md:.claude/workflow/README.md
AGENTS.md:.claude/workflow/next-task.md
AGENTS.md:.claude/workflow/next-task.md
AGENTS.md:.claude/workflow/next-task.md
AGENTS.md:.claude/workflow/next-task.md
AGENTS.md:.claude/workflow/next-task.md
AGENTS.md:memory/constitution.md
.claude/PROJECT.md:.claude/MODELS.md
.claude/PROJECT.md:.claude/PROJECT.template.md
.claude/PROJECT.md:.claude/adapters/claude-code-probes.md
.claude/PROJECT.md:.claude/hooks/autonomy-mode.sh
.claude/PROJECT.md:.claude/hooks/isolated-workspace.sh
.claude/PROJECT.md:.claude/hooks/isolation-falsification.test.sh
.claude/PROJECT.md:.claude/hooks/shell-lint.sh
.claude/PROJECT.md:.claude/workflow/README.md
.claude/PROJECT.md:.claude/workflow/gate-loop.md
.claude/PROJECT.md:.claude/workflow/maker-eval.md
.claude/PROJECT.md:.claude/workflow/reviewers/evasion-register.md
.claude/PROJECT.md:.claude/workflow/telemetry.md
.claude/PROJECT.md:.github/workflows/ci.yml
.claude/PROJECT.md:memory/constitution.md
.claude/PROJECT.md:memory/constitution.md
.claude/PROJECT.md:memory/constitution.template.md
.claude/PROJECT.md:specs/000-template/tasks.template.md
.claude/PROJECT.md:specs/001-harness-feedback-loop/spec.md
.claude/PROJECT.md:specs/001-harness-feedback-loop/tasks.md
.claude/PROJECT.md:specs/002-spec-quality-gate/spec.md
.claude/PROJECT.md:specs/002-spec-quality-gate/tasks.md
.claude/PROJECT.md:specs/003-maker-eval-corpus/spec.md
.claude/PROJECT.md:specs/003-maker-eval-corpus/tasks.md
.claude/PROJECT.md:specs/004-autonomous-backlog-loop/spec.md
.claude/PROJECT.md:specs/004-autonomous-backlog-loop/tasks.md
.claude/PROJECT.md:specs/005-held-out-acceptance/spec.md
.claude/PROJECT.md:specs/005-held-out-acceptance/tasks.md
.claude/PROJECT.md:specs/006-adoption-context-preservation/spec.md
.claude/PROJECT.md:specs/006-adoption-context-preservation/tasks.md
.claude/PROJECT.md:specs/007-workflow-context-economy/spec.md
.claude/PROJECT.md:specs/007-workflow-context-economy/tasks.md
.claude/PROJECT.md:specs/008-fast-lane-workflow/spec.md
.claude/PROJECT.md:specs/008-fast-lane-workflow/tasks.md
.claude/PROJECT.md:specs/TASK_INDEX.md
.claude/PROJECT.compact.md:.claude/PROJECT.md
.claude/PROJECT.compact.md:.claude/PROJECT.md
.claude/PROJECT.compact.md:.claude/MODELS.md
.claude/PROJECT.compact.md:.claude/hooks/compact-packet-drift.sh
.claude/PROJECT.compact.md:.claude/hooks/shell-lint.sh
.claude/PROJECT.compact.md:.claude/workflow/telemetry.md
.claude/PROJECT.compact.md:memory/constitution.md
.claude/PROJECT.compact.md:specs/001-harness-feedback-loop/spec.md
.claude/PROJECT.compact.md:specs/001-harness-feedback-loop/tasks.md
.claude/PROJECT.compact.md:specs/002-spec-quality-gate/spec.md
.claude/PROJECT.compact.md:specs/002-spec-quality-gate/tasks.md
.claude/PROJECT.compact.md:specs/003-maker-eval-corpus/spec.md
.claude/PROJECT.compact.md:specs/003-maker-eval-corpus/tasks.md
.claude/PROJECT.compact.md:specs/004-autonomous-backlog-loop/spec.md
.claude/PROJECT.compact.md:specs/004-autonomous-backlog-loop/tasks.md
.claude/PROJECT.compact.md:specs/005-held-out-acceptance/spec.md
.claude/PROJECT.compact.md:specs/005-held-out-acceptance/tasks.md
.claude/PROJECT.compact.md:specs/006-adoption-context-preservation/spec.md
.claude/PROJECT.compact.md:specs/006-adoption-context-preservation/tasks.md
.claude/PROJECT.compact.md:specs/007-workflow-context-economy/spec.md
.claude/PROJECT.compact.md:specs/007-workflow-context-economy/tasks.md
.claude/PROJECT.compact.md:specs/008-fast-lane-workflow/spec.md
.claude/PROJECT.compact.md:specs/008-fast-lane-workflow/tasks.md
EOF
GOT_EXTRACT="$( (cd "$REPO_ROOT" && bash "$CHECK" --extract) 2>&1 \
  | sed 's/:[0-9][0-9]*:/:/' | sort )"
if [ "$GOT_EXTRACT" = "$(cat "$ORACLE")" ]; then
  ok
else
  bad "B positive extraction must recover the complete hand-verified oracle set; diff:"
  diff <(printf '%s\n' "$GOT_EXTRACT") "$ORACLE" >&2 || true
fi

# mkbox <name> — a sandbox tree with a resolving .claude/ area; echoes its path.
mkbox() {
  local d="$TMP/$1"
  mkdir -p "$d/.claude/workflow"
  printf 'x\n' > "$d/.claude/workflow/next-task.md"
  echo "$d"
}

# --- C: planted dangling pointers FAIL naming surface + path + line, per
#     instance (US8.AC3's failure direction; US8.AC5's diagnostics). The planted
#     set includes the REAL #272/#273 shape — `workflow/next-task.md` resolving
#     only under .claude/ — and a second dangler proving per-instance reporting.
C="$(mkbox c)"
cat > "$C/doc.md" <<'EOF'
See `workflow/next-task.md` for the procedure.
A resolving pointer: `.claude/workflow/next-task.md`.
And `missing/nonexistent.md` too.
EOF
run_check "$C" doc.md
if [ "$GOT" -eq 1 ]; then ok; else bad "C planted danglers must exit 1 (got $GOT)"; fi
if printf '%s' "$OUT" | grep -q 'doc.md:1: `workflow/next-task.md`'; then
  ok
else
  bad "C must name surface doc.md, path workflow/next-task.md, and line 1: $OUT"
fi
if printf '%s' "$OUT" | grep -q 'doc.md:3: `missing/nonexistent.md`'; then
  ok
else
  bad "C must name the second dangler with its own line 3 (per-instance): $OUT"
fi
if printf '%s' "$OUT" | grep -q '\.claude/workflow/next-task\.md` does not exist'; then
  bad "C must NOT flag the resolving pointer"
else
  ok
fi

# --- D: held-out bare-nested pointer under a leading segment named nowhere in
#     spec 007 US8 or its enumerations — still flagged, so a `workflow/`-keyed
#     recognizer or a fixed segment allowlist fails this case (US8.AC1/AC3).
D="$(mkbox d)"
mkdir -p "$D/.claude/quokka-lane"
printf 'x\n' > "$D/.claude/quokka-lane/cards.md"
printf 'Read `quokka-lane/cards.md` first.\n' > "$D/doc.md"
run_check "$D" doc.md
if [ "$GOT" -eq 1 ]; then ok; else bad "D held-out segment must be flagged (got $GOT): $OUT"; fi
if printf '%s' "$OUT" | grep -q 'doc.md:1: `quokka-lane/cards.md`'; then
  ok
else
  bad "D must name the held-out dangler with surface/path/line: $OUT"
fi

# --- E: all-resolve control passes (US8.AC3's passing direction). --------------
E="$(mkbox e)"
mkdir -p "$E/docs"
printf 'x\n' > "$E/docs/guide.md"
cat > "$E/doc.md" <<'EOF'
See `.claude/workflow/next-task.md` and `docs/guide.md`.
EOF
run_check "$E" doc.md
if [ "$GOT" -eq 0 ]; then ok; else bad "E all-resolve control must pass (got $GOT): $OUT"; fi

# --- F: non-path forms are not flagged (US8.AC2) — globs, brace-expansions,
#     placeholders, section anchors, command/flag tokens; the fixture carries
#     ONLY such forms and passes. -----------------------------------------------
F="$(mkbox f)"
cat > "$F/doc.md" <<'EOF'
Globs: `specs/*/tasks.md`, `workflow/**`, `.claude/hooks/*.sh`.
Braces: `specs/000-template/{spec,tasks}.md`.
Placeholders: `<triage inbox dir>/creance-telemetry.jsonl`, `docs/evidence/<task-id>/a.md`.
Anchors: `PROJECT.md → "Autonomy"`.
Commands: `gh pr create --body-file x.md`, `git rev-parse --show-toplevel`, `--body-file`.
Bare filenames: `guard.test.sh`, `AGENTS.md`.
EOF
run_check "$F" doc.md
if [ "$GOT" -eq 0 ]; then ok; else bad "F non-path-forms control must pass (got $GOT): $OUT"; fi
run_check "$F" --extract doc.md
if [ -z "$OUT" ]; then ok; else bad "F non-path forms must not even be extracted: $OUT"; fi

# --- G: containment control (US8.AC1/AC2/AC3) — absolute paths, `..` traversal,
#     and scheme:// URIs are out of contract: neither resolved nor flagged, even
#     when the escaping target EXISTS (resolving it would pass silently — absence
#     from the extract output proves it is never consulted at all). -------------
G="$(mkbox g)"
printf 'x\n' > "$TMP/outside.md"   # the ../-escaping target really exists
cat > "$G/doc.md" <<'EOF'
Absolute: `/tmp/file.md` and `/etc/passwd.d/x.sh`.
Traversal: `../outside.md` and `docs/../../outside.md`.
URIs: `https://example.com/file.md`, `scheme://host/path.md`.
EOF
run_check "$G" doc.md
if [ "$GOT" -eq 0 ]; then ok; else bad "G containment control must pass (got $GOT): $OUT"; fi
run_check "$G" --extract doc.md
if [ -z "$OUT" ]; then ok; else bad "G out-of-contract tokens must never be extracted/resolved: $OUT"; fi

# --- H: a missing surface FAILs loud naming it — never a vacuous pass (P2). ----
H="$(mkbox h)"
run_check "$H" absent.md
if [ "$GOT" -eq 1 ] && printf '%s' "$OUT" | grep -q "surface 'absent.md' not found"; then
  ok
else
  bad "H missing surface must FAIL naming it (got $GOT): $OUT"
fi

# --- I: CI wiring (US8.AC5 — wired into standing verification, wiring asserted;
#     the compact-packet-drift.test.sh idiom, verify-job scope). ----------------
CI="$REPO_ROOT/.github/workflows/ci.yml"
verify_steps() { awk '/^  [A-Za-z]/ { inblk = ($0 ~ /^  verify:/) } inblk { print }' "$CI"; }
if verify_steps | grep -qE '^[[:space:]]*run:[[:space:]]+bash[[:space:]]+\.claude/hooks/doc-pointer-check\.sh([[:space:]]|$)'; then
  ok
else
  bad "I wiring: verify must RUN doc-pointer-check.sh (active run: step)"
fi
if verify_steps | grep -qE '^[[:space:]]*run:[[:space:]]+bash[[:space:]]+\.claude/hooks/doc-pointer-check\.test\.sh([[:space:]]|$)'; then
  ok
else
  bad "I wiring: verify must RUN doc-pointer-check.test.sh (active run: step)"
fi

printf 'doc-pointer-check.test.sh: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
