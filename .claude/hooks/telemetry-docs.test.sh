#!/usr/bin/env bash
# Encoding tests for issue #52 / US1.AC5 (T104 — the introducing-change ref on the
# gate-run record).
#
# Like the intake and PR-review procedures, the telemetry record, the gate loop's
# build/append split, and the retrospective's Fact B attribution are runtime-neutral
# prose executed by the engine — the workflow docs (and the next-task skill binding
# that concretely populates the field) ARE the implementation surface. These tests
# encode US1.AC5 against that surface so a later edit that drops the field, the
# observe-only framing, the deterministic Fact B preference, or the dispatcher's
# capture step fails the `verify` CI job (constitution P3: a rule a deterministic
# check can enforce must have that check). The live counterpart is the P-NT
# conformance probe (conformance-probes.md), which checks the field on a real record.
#
# The runtime-neutrality scan below is also the deterministic backstop for the core
# neutral workflow docs it enumerates, including workflow/next-task.md (#109).
#
# Run: bash .claude/hooks/telemetry-docs.test.sh
set -u

DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEL="$DIR/workflow/telemetry.md"
GL="$DIR/workflow/gate-loop.md"
RET="$DIR/workflow/retrospective.md"
NT="$DIR/workflow/next-task.md"
SK="$DIR/skills/next-task/SKILL.md"
JS="$DIR/workflows/gate-loop.js"

pass=0
fail=0

# Normalize whitespace so assertions survive prose re-wrapping.
flat() { tr -s '[:space:]' ' ' < "$1"; }

check() { # check <name> <haystack> <needle (grep -F fixed string)>
  local name="$1" hay="$2" needle="$3"
  if printf '%s' "$hay" | grep -qF -- "$needle"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL %s\n     missing: %s\n' "$name" "$needle" >&2
  fi
}

absent() { # absent <name> <file> <needle> — fails if the needle is PRESENT
  local name="$1" file="$2" needle="$3"
  if grep -qF -- "$needle" "$file"; then
    fail=$((fail + 1))
    printf 'FAIL %s\n     must no longer be present: %s\n' "$name" "$needle" >&2
  else
    pass=$((pass + 1))
  fi
}

for f in "$TEL" "$GL" "$RET" "$NT" "$SK" "$JS"; do
  if [ ! -f "$f" ]; then
    echo "FAIL: required file missing: $f" >&2
    exit 1
  fi
done

TEL_FLAT="$(flat "$TEL")"
GL_FLAT="$(flat "$GL")"
RET_FLAT="$(flat "$RET")"
SK_FLAT="$(flat "$SK")"
JS_FLAT="$(flat "$JS")"

# ── Schema (telemetry.md) — the gate-run record carries the audited-commit ref ──────
check "schema: gate-run record has a commit field tied to the audited diff" "$TEL_FLAT" \
  "head commit of the diff the gate audited"
check "schema: the ref is dispatcher-stamped like the envelope (loop has no filesystem)" "$TEL_FLAT" \
  "Stamped by the dispatcher at append time, like the envelope"
# Observe-only (constitution P5): the ref is read by the retrospective ONLY — no gate,
# tier, or guard ever reads it. The whole point is a measurement field, not a control one.
check "schema: ref is observe-only — never read by gate/reviewer/tier/guard" "$TEL_FLAT" \
  "never by any gate, [reviewer] dispatch, tier resolution, or guard"
# §7-before-§8: no PR number exists at append time, so the field is a commit, not a PR ref.
check "schema: carries the commit, not a PR number (gate precedes PR creation)" "$TEL_FLAT" \
  "not a PR number"

# ── Build/append split (gate-loop.md) — dispatcher stamps the commit after the run ──
check "gate-loop: dispatcher stamps the introducing-commit ref alongside the envelope" "$GL_FLAT" \
  "the introducing-"
check "gate-loop: captured after the run so fix-round commits are the audited head" "$GL_FLAT" \
  "the head of the diff the gate's final round actually audited"

# ── Adapter binding (next-task SKILL.md) — the CONCRETE population step ──────────────
check "binding: dispatcher reads git rev-parse HEAD for the commit ref" "$SK_FLAT" \
  "the head SHA of the audited diff"
check "binding: read after the gate so fix-round commits are included" "$SK_FLAT" \
  "fix-round commits the loop made"

# ── Consumer (retrospective.md §4) — Fact B PREFERS the ref over timing ─────────────
check "retrospective: Fact B prefers the commit ref" "$RET_FLAT" \
  "Prefer the record's"
check "retrospective: ref attribution is deterministic" "$RET_FLAT" \
  "making attribution deterministic"
check "retrospective: squash-merged PR resolves to its head-ref commits" "$RET_FLAT" \
  "squash-merged PR resolves to the commits on its head ref"
# Per-record fallback (Codex PR #58 finding): the timing fallback for a legacy record
# must be judged per record, not gated on whether ANY record for the task ID carries a
# `commit` — else a newer re-gate of a different diff suppresses an older legacy gate of
# the introducing one, misclassifying INCONSISTENT-CATCH as WOULD-HAVE-CAUGHT.
check "retrospective: timing fallback is per-record, not gated on the whole task ID" "$RET_FLAT" \
  "never suppressed by another record"
# The pre-#52 disclaimer ("...outside this workflow's scope") described the ABSENCE of
# this field. Now that it ships, that text must be gone — otherwise the doc contradicts
# the schema it now relies on.
absent "retrospective: stale 'out of scope' disclaimer removed" "$RET" \
  "outside this workflow's scope"

# ── Comment accuracy (gate-loop.js) — the JS payload omits the dispatcher-stamped ref ─
check "gate-loop.js: comment names commit among the dispatcher-stamped fields" "$JS_FLAT" \
  "the audited HEAD"

# ── Runtime-neutral boundary (constitution P1) — runtime-SPECIFIC mechanisms (the GitHub
#    CLI, model IDs, Claude-Code-only tokens) live in the adapter binding ONLY, never in
#    the neutral workflow docs, so `git rev-parse HEAD` for the field-capture step reads as
#    a role here and is named concretely only in skills/next-task/SKILL.md. NOTE: `git`
#    itself is the harness's universal VCS substrate and is NOT a banned mechanism — the
#    project's own neutrality check excludes it (pr-review-docs.test.sh) and neutral docs
#    reference `git rev-parse --show-toplevel` for "the repo root" freely (triage.md,
#    next-task.md); banning `git` here would encode a stricter-than-project invariant. This
#    mirrors pr-review-docs.test.sh's mech scan: strip the allowed `.claude/` profile
#    pointer first so it never false-matches `\bclaude\b`.
for doc in "$TEL" "$GL" "$RET" "$NT"; do
  mech="$(flat "$doc" | sed 's#\.claude/#PROFILEPTR/#g' \
    | grep -oiE '\bgh\b|GitHub[[:space:]]+CLI|\bclaude\b|\bopus\b|\bsonnet\b|\bfable\b|\bhaiku\b|--model|--json|PreToolUse|settings\.json' \
    | sort -u | tr '\n' ' ')"
  if [ -z "$mech" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL neutral boundary: runtime-specific mechanism leaked into %s\n     found: %s\n' "$doc" "$mech" >&2
  fi
done

echo "telemetry docs encoding tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
