#!/usr/bin/env bash
# Drift backstop for the §7 reviewer roster (T602 / issue #64, parent epic #62).
#
# The §7 pre-PR gate's reviewer set used to be hand-synced across three places that
# could silently disagree: the prose (`next-task.md` §7 step 2), the pseudocode
# (`gate-loop.md` "The loop"), and the orchestrated-run array (`gate-loop.js`). T602
# collapses membership/tier/dispatch-condition into ONE declarative roster table in
# `gate-loop.md` and this test FAILs `verify` CI whenever any of the three sites drifts
# from it — converting "a reviewer silently fell out of the gate" from a model-noticing
# risk into a deterministic check (constitution P2/P3; the same same-diff discipline
# `guard.test.sh` follows — the backstop ships with the change it guards).
#
# The test is an INDEPENDENT oracle: it pins all three sites to a hardcoded canonical
# set (below), not to whatever the roster currently says. A backstop that derived its
# expectation from the very table it checks could not catch a coordinated drift, so the
# canonical set lives here; adding/removing a reviewer is an intentional edit to the
# roster, its two mirror sites, AND this set (the ratchet that proves the change was
# deliberate). gate-loop.md's runtime-neutrality (no model IDs in the roster) is covered
# globally by telemetry-docs.test.sh's mech scan and bound here implicitly: a model ID in
# the tier column would break the canonical-set match.
#
# Encodes issue #64 done-when AC1–AC6:
#   AC1 roster is exactly the canonical set (no extra rows)        → roster_ok
#   AC2 gate-loop.js mirrors it (keys, tiers, contract gated)       → js_ok
#   AC3 next-task.md §7 references the same paths + conditions      → prose_ok
#   AC4 each roster reviewer has a workflow/reviewers/<name>.md spec → specs_agents_ok
#   AC5 each agents/<name>.md exists and excludes edit tools         → specs_agents_ok
#   AC6 drift in any one site (drop a reviewer / flip a tier or      → AC6 block: temp-copy
#       condition) FAILs the check                                       mutations re-run the
#                                                                         site checks and assert
#                                                                         each one trips
#
# Run: bash .claude/hooks/reviewer-roster.test.sh
set -u

DIR="$(cd "$(dirname "$0")/.." && pwd)"
GL="$DIR/workflow/gate-loop.md"        # roster source of truth
JS="$DIR/workflows/gate-loop.js"       # orchestrated-run mirror
NT="$DIR/workflow/next-task.md"        # prose mirror
REVDIR="$DIR/workflow/reviewers"       # reviewer specs (AC4)
AGENTDIR="$DIR/agents"                 # adapter agent files (AC5)

pass=0
fail=0

for f in "$GL" "$JS" "$NT"; do
  if [ ! -f "$f" ]; then
    echo "FAIL: required file missing: $f" >&2
    exit 1
  fi
done

# ── The canonical roster — the known-correct set this backstop pins every site to.
#    "<key>|<tier>|<condition>", one per reviewer; sorted so order never matters. ──
EXPECTED="$(printf '%s\n' \
  'spec-auditor|cheap|always' \
  'constitution-auditor|strong|always' \
  'contract-auditor|cheap|dispatch-contract' | sort)"

ok()   { pass=$((pass + 1)); }
bad() { # bad <message>
  fail=$((fail + 1))
  printf 'FAIL %s\n' "$1" >&2
}

# ── parse_roster <gate-loop.md> — emit "<key>|<tier>|<condition>" per roster table row,
#    sorted. A roster row is a markdown table row naming a reviewers/<stem>-auditor.md
#    spec; the header and the |---| delimiter never match, and gate-loop.md's prose
#    mentions `reviewers/` only generically (no `-auditor.md`), so only the data rows hit.
parse_roster() {
  awk -F'|' '
    /reviewers\/[a-z]+-auditor\.md/ {
      key=$2; tier=$3; cond=$4
      match(key, /[a-z]+-auditor/); key=substr(key, RSTART, RLENGTH)
      gsub(/[^a-z-]/, "", tier)   # cheap | strong
      gsub(/[^a-z-]/, "", cond)   # always | dispatch-contract
      print key "|" tier "|" cond
    }
  ' "$1" | sort
}

# AC1 — gate-loop.md roster is EXACTLY the canonical set (membership + tier + condition,
#       no extra rows).
roster_ok() { [ "$(parse_roster "$1")" = "$EXPECTED" ]; }

# AC2 — gate-loop.js names the three keys with matching tiers (constitution=strong;
#       spec+contract=cheap) and gates contract on dispatchContract (a guarded .push,
#       never the unconditional array literal). Exact fixed-string matches on the
#       authored shape (two literals + a conditional push, per #62's carry-forward note).
js_ok() {
  local f="$1" r=0
  grep -qF "key: 'spec-auditor', model: input.cheapModel, tier: 'cheap'" "$f" || r=1
  grep -qF "key: 'constitution-auditor', model: input.strongModel, tier: 'strong'" "$f" || r=1
  grep -qF "reviewers.push({ key: 'contract-auditor', model: input.cheapModel, tier: 'cheap' })" "$f" || r=1
  grep -qF "if (input.dispatchContract)" "$f" || r=1
  # contract must be gated: it may appear ONLY on a push line, never in the
  # unconditional array literal. A contract line without `push` is drift.
  if grep -F "key: 'contract-auditor'" "$f" | grep -vqF "push"; then r=1; fi
  return $r
}

# AC3 — next-task.md §7 step 2 references the same three reviewer spec paths with the
#       same conditions (always / always / contract-conditional) and points at the
#       roster. Scoped to §7 and whitespace-flattened so prose re-wrapping can't break it;
#       the needles are distinctive authored prose, bound to each reviewer's condition.
section7() { awk '/^## 7\./{f=1} /^## 8\./{f=0} f' "$1"; }
prose_ok() {
  local f="$1" s r=0
  s="$(section7 "$f" | tr -s '[:space:]' ' ')"
  # spec — always, identified by its unique task-id prose
  printf '%s' "$s" | grep -qF "reviewers/spec-auditor.md" || r=1
  printf '%s' "$s" | grep -qF "**always**, and pass it the task ID" || r=1
  # constitution — always, identified by its unique return-type prose
  printf '%s' "$s" | grep -qF "reviewers/constitution-auditor.md" || r=1
  printf '%s' "$s" | grep -qF "**always**. It returns PASS/JUSTIFY/FAIL against the constitution" || r=1
  # contract — the dispatch-contract condition
  printf '%s' "$s" | grep -qF "reviewers/contract-auditor.md" || r=1
  printf '%s' "$s" | grep -qF "dispatch-contract" || r=1
  printf '%s' "$s" | grep -qF "provider interface, monetization, or the data model" || r=1
  # points at the roster as the source of truth
  printf '%s' "$s" | grep -qF "reviewer roster" || r=1
  printf '%s' "$s" | grep -qF "gate-loop.md" || r=1
  return $r
}

# ── Run the four site checks against the live tree ──────────────────────────────────
roster_ok "$GL" \
  && ok \
  || bad "AC1 roster: gate-loop.md roster is not exactly the canonical set
     expected:
$(printf '%s\n' "$EXPECTED" | sed 's/^/       /')
     got:
$(parse_roster "$GL" | sed 's/^/       /')"

js_ok "$JS" \
  && ok \
  || bad "AC2 js: gate-loop.js reviewers array/push does not mirror the roster
     (expected spec=cheap, constitution=strong, contract=cheap gated on dispatchContract)"

prose_ok "$NT" \
  && ok \
  || bad "AC3 prose: next-task.md §7 step 2 does not reference the roster's three specs
     with conditions always / always / contract-conditional, or omits the roster pointer"

# AC4 + AC5 — each canonical reviewer has a spec, and an agent file that excludes edit
#            tools (maker≠checker's "no edit tools by construction" as a CI invariant).
for key in spec-auditor constitution-auditor contract-auditor; do
  if [ -f "$REVDIR/$key.md" ]; then
    ok
  else
    bad "AC4 spec: missing reviewer spec $REVDIR/$key.md"
  fi

  af="$AGENTDIR/$key.md"
  if [ ! -f "$af" ]; then
    bad "AC5 agent: missing agent file $af"
    continue
  fi
  tools_line="$(grep -E '^tools:' "$af" || true)"
  if [ -z "$tools_line" ]; then
    bad "AC5 agent: $af has no 'tools:' line to constrain"
  elif printf '%s' "$tools_line" | grep -Eq 'Edit|Write|NotebookEdit'; then
    bad "AC5 agent: $af grants an edit tool (a reviewer must be read-only): $tools_line"
  else
    ok
  fi
done

# ── AC6 — drift in ANY one site must FAIL the check. Demonstrated on temp copies so the
#         property is itself CI-verified, not asserted by hand: each mutation must flip
#         the corresponding site check from OK (0) to drift (nonzero). ──
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mut_fail() { # mut_fail <name> <check-fn> <mutated-file>
  if "$2" "$3"; then
    bad "AC6 $1: mutation did NOT trip $2 — drift would go undetected"
  else
    ok
  fi
}

# Roster site (gate-loop.md) — drop a reviewer.
grep -vF 'reviewers/contract-auditor.md' "$GL" > "$TMP/gl-drop.md"
mut_fail "roster drop-reviewer" roster_ok "$TMP/gl-drop.md"

# Roster site — flip a tier (spec cheap → strong).
sed '/reviewers\/spec-auditor\.md/ s/| cheap |/| strong |/' "$GL" > "$TMP/gl-tier.md"
mut_fail "roster flip-tier" roster_ok "$TMP/gl-tier.md"

# Roster site — flip a condition (contract dispatch-contract → always).
sed '/reviewers\/contract-auditor\.md/ s/dispatch-contract/always/' "$GL" > "$TMP/gl-cond.md"
mut_fail "roster flip-condition" roster_ok "$TMP/gl-cond.md"

# JS site (gate-loop.js) — drop the gated contract push.
grep -vF "reviewers.push({ key: 'contract-auditor'" "$JS" > "$TMP/js-drop.js"
mut_fail "js drop-reviewer" js_ok "$TMP/js-drop.js"

# JS site — flip a tier (spec cheap → strong).
sed "s/key: 'spec-auditor', model: input.cheapModel, tier: 'cheap'/key: 'spec-auditor', model: input.cheapModel, tier: 'strong'/" "$JS" > "$TMP/js-tier.js"
mut_fail "js flip-tier" js_ok "$TMP/js-tier.js"

# Prose site (next-task.md) — drop a reviewer reference.
grep -vF 'reviewers/spec-auditor.md' "$NT" > "$TMP/nt-drop.md"
mut_fail "prose drop-reviewer" prose_ok "$TMP/nt-drop.md"

echo "reviewer-roster encoding tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
