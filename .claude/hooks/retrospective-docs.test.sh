#!/usr/bin/env bash
# Encoding tests for issue #72 acceptance criterion (T302 — Claude Code skill
# binding for the retrospective). Owns US3.AC5.
#
# Like the intake/pr-review procedures, the retrospective is runtime-neutral
# prose executed by the engine — `.claude/workflow/retrospective.md` (the doc,
# T301) and `.claude/skills/retrospective/SKILL.md` (this binding, T302) ARE the
# implementation; there is no executable code path to unit-test. This test
# encodes US3.AC5 against the BINDING surface: the read-and-execute handoff, the
# read-only + report-only auditor dispatch, "composes existing roles only / no
# new binding-contract row", the constitution reviewer dispatched at-or-above the
# strong-tier floor WITH the guard (rule 5) enforcing it, the historical-diff
# reconstruction that makes the back-test grade the right surface, and the
# never-edit-a-rule / propose-via-PR write posture. A later edit that drops any of
# them fails the `verify` CI job (constitution P3: a rule a deterministic check
# can enforce must have that check).
#
# Scope: the binding (T302/US3.AC5). The neutral doc's AC1–AC4 prose and its
# runtime-neutrality grep are T301's surface, already covered by
# telemetry-docs.test.sh (Fact B + the neutral-boundary scan over
# retrospective.md); this test does not duplicate them. The live-adapter
# conformance probe (US3.AC6) is T303, not here.
#
# Run: bash .claude/hooks/retrospective-docs.test.sh
set -u

DIR="$(cd "$(dirname "$0")/.." && pwd)"
WF="$DIR/workflow/retrospective.md"
SK="$DIR/skills/retrospective/SKILL.md"

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

for f in "$WF" "$SK"; do
  if [ ! -f "$f" ]; then
    echo "FAIL: required file missing: $f" >&2
    exit 1
  fi
done

WF_FLAT="$(flat "$WF")"
SK_FLAT="$(flat "$SK")"

# ── AC5 — a Claude skill binding exposes the workflow, consistent with siblings ──
check "AC5 binding: points at the neutral doc" "$SK_FLAT" \
  ".claude/workflow/retrospective.md"
check "AC5 binding: read-and-execute handoff (mirrors other skills)" "$SK_FLAT" \
  "read that file now and execute it."
check "AC5 binding: references the single-copy comment marker" "$SK_FLAT" \
  "The [comment marker] concrete form"
check "AC5 binding: references the single-copy environment block" "$SK_FLAT" \
  "This environment's concrete forms"
check "AC5 binding: read-and-propose posture in frontmatter" "$SK_FLAT" \
  "read-and-propose only"

# ── AC5 — composes existing reviewer roles, read-only; NO new binding-contract role ──
check "AC5 binding: no new binding-contract row" "$SK_FLAT" \
  "introduces no new binding-contract row"
# The neutral doc (T301) declares the same property; the binding must not contradict it.
check "AC5 doc: composes existing roles only" "$WF_FLAT" \
  "composes existing roles only"
check "AC5 binding: dispatches the acceptance auditor" "$SK_FLAT" \
  "spec-auditor"
check "AC5 binding: dispatches the constitution auditor" "$SK_FLAT" \
  "constitution-auditor"
check "AC5 binding: dispatches the contract auditor" "$SK_FLAT" \
  "contract-auditor"
check "AC5 binding: auditor dispatch is read-only (no edit tools)" "$SK_FLAT" \
  "no edit tools"
# Report-only fan-out — distinct from the §7 gate's converge-to-PASS loop (the
# retrospective classifies a settled diff, it does not repair it).
check "AC5 binding: report-only — no fix step, no re-dispatch loop" "$SK_FLAT" \
  "no fix step, no re-dispatch loop"

# ── AC5/AC4 — the constitution auditor is dispatched at-or-above the strong floor,
#    and the binding itself is reviewed against the floor (not just the doc) ────────
check "AC4/AC5 binding: constitution reviewer at-or-above the strong-tier floor" "$SK_FLAT" \
  "at-or-above the strong-tier row, never below"
check "AC4/AC5 binding: model passed explicitly, never inherited from the session" "$SK_FLAT" \
  "never inherited from the session"
# The floor is not merely asserted in prose: the guard enforces it on every
# constitution-auditor dispatch (the same guarded path the gate uses).
check "AC5 binding: the guard (rule 5) enforces the floor" "$SK_FLAT" \
  "rule 5"
check "AC5 binding: same guarded path the gate uses" "$SK_FLAT" \
  "the same guarded path"

# ── AC1 fidelity (binding mechanism) — auditors grade the HISTORICAL TREE, not the live checkout ──
# "exactly as the gate would have" (AC1) is only true if the auditors see the
# introducing change against its parent AND read surrounding files from the tree
# as it was then — not the live base branch. The auditor specs all read
# neighbouring files (constitution/contract/spec), so a diff range alone is not
# enough: the binding materializes the historical tree (worktree) and forbids
# live-tree reads. (Codex P2 finding on PR #73.)
check "binding: materializes the historical tree via worktree, not just the diff" "$SK_FLAT" \
  "git worktree add --detach"
check "binding: the reconstruction row/note is tree-scoped" "$SK_FLAT" \
  "historical-tree reconstruction"
check "binding: forbids live-tree reads (read context only within the worktree)" "$SK_FLAT" \
  "never the live repo root"
check "binding: explicit historical range (parent..introducing-commit)" "$SK_FLAT" \
  "<parent>..<introducing-commit>"
check "binding: names the wrong default it overrides" "$SK_FLAT" \
  "git diff main..HEAD"

# ── AC3 / P4 — never edits a rule directly; tightenings travel issue→branch→gate→PR ──
check "binding: never edits a rule directly (P4)" "$SK_FLAT" \
  "never edits a rule directly"
# The proposed rule/invariant edit is itself gated (the standard next-task PR
# flow) — it is never written to the protected files directly.
check "binding: the drafted edit is itself gated, not written directly" "$SK_FLAT" \
  "the drafted reviewer-spec / invariant-row edit is itself gated"
check "binding: the owner merges to apply" "$SK_FLAT" \
  "owner merges to apply"

# ── P5 — telemetry read as evidence, never a control input ───────────────────────
check "binding: telemetry read-only, never a control input (P5)" "$SK_FLAT" \
  "never as a control input"

# ── Write posture — read-and-propose, never a second gate / retroactive sweep ────
check "binding: changes no gate semantics, never a second gate" "$SK_FLAT" \
  "never a second gate"

# ── US3.AC6 (T303) — the live-adapter P-RT probe encodes its expected observations ─
# Mirrors the P-IN pointer in intake-docs.test.sh: the probe specification is the
# testable surface for "passes on the live adapter, with results recorded". These
# checks ground the probe's expected-observation claims in the neutral checklist so a
# later edit that drops a required observation fails the `verify` CI job.
PROBES="$DIR/workflow/conformance-probes.md"
if [ ! -f "$PROBES" ]; then
  echo "FAIL: required file missing: $PROBES" >&2
  exit 1
fi
PROBES_FLAT="$(flat "$PROBES")"
check "P-RT: probe defined in the neutral checklist" "$PROBES_FLAT" \
  "### P-RT — retrospective back-test"
check "P-RT (a): auditors grade the historical tree, not the live base branch" "$PROBES_FLAT" \
  "the auditors grade the **historical tree**, not the live base branch"
check "P-RT (b): classification into exactly one bucket" "$PROBES_FLAT" \
  "the run classifies into **exactly one** bucket"
check "P-RT (c): write posture holds — protected rule files byte-identical" "$PROBES_FLAT" \
  "the reviewer specs, the invariant checklist, and the guard are **byte-identical** after the run"
check "P-RT (e): telemetry read, not written — no gate-run record appended" "$PROBES_FLAT" \
  "**telemetry was read, not written** — the run appends"

echo "retrospective docs encoding tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
