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
# The test is an INDEPENDENT oracle: it pins every site to a hardcoded canonical
# set (below), not to whatever the roster currently says. A backstop that derived its
# expectation from the very table it checks could not catch a coordinated drift, so the
# canonical set lives here; adding/removing a reviewer is an intentional edit to the
# roster, its two mirror sites, AND this set (the ratchet that proves the change was
# deliberate). The adapter's manual-fallback [reviewer]→agent map (next-task SKILL.md) is
# pinned too (AC7), on membership — it is a fourth site that enumerates the reviewer set,
# and it drifted exactly once (PR #186) before being pinned here.
# gate-loop.md's runtime-neutrality (no model IDs in the roster) is covered
# globally by telemetry-docs.test.sh's mech scan and bound here implicitly: a model ID in
# the tier column would break the canonical-set match.
#
# Encodes issue #64 done-when AC1–AC6 (extended for the spec-quality reviewer, T703);
# AC7 adds the adapter map as a fourth pinned site (PR #186 review):
#   AC1 roster is exactly the canonical set (no extra rows)        → roster_ok
#   AC2 gate-loop.js mirrors it (keys, tiers, both conditionals     → js_ok
#       gated on their input flag)
#   AC3 next-task.md §7 references the same paths + conditions      → prose_ok
#   AC4 each roster reviewer has a workflow/reviewers/<name>.md spec → AC4 loop (all four)
#   AC5 each ADAPTER-BOUND reviewer's agents/<name>.md exists and    → AC5 loop (all four;
#       excludes edit tools (the spec-quality agent binding landed       each with a Claude
#       in T706/US2.AC5)                                                  agent)
#   AC6 drift in any one site (drop a reviewer / flip a tier or      → AC6 block: temp-copy
#       condition) FAILs the check — incl. the spec-quality              mutations re-run the
#       reviewer on every site                                           site checks and assert
#                                                                         each one trips
#   AC7 the adapter [reviewer]→agent map (next-task SKILL.md) names  → skill_ok (+ an AC6
#       every roster reviewer, so the manual fallback can't omit one     drop mutation)
#
# Run: bash .claude/hooks/reviewer-roster.test.sh
set -u

DIR="$(cd "$(dirname "$0")/.." && pwd)"
GL="$DIR/workflow/gate-loop.md"        # roster source of truth
JS="$DIR/workflows/gate-loop.js"       # orchestrated-run mirror
NT="$DIR/workflow/next-task.md"        # prose mirror
REVDIR="$DIR/workflow/reviewers"       # reviewer specs (AC4)
AGENTDIR="$DIR/agents"                 # adapter agent files (AC5)
SK="$DIR/skills/next-task/SKILL.md"    # adapter [reviewer]→agent map (AC7)

pass=0
fail=0

for f in "$GL" "$JS" "$NT" "$SK"; do
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
  'contract-auditor|cheap|dispatch-contract' \
  'spec-quality-auditor|strong|dispatch-spec' | sort)"

# The reviewer KEYS alone, derived from the canonical set above (one source, never a second
# hardcoded list) — for the membership-only sites that carry no tier/condition column: the
# AC5 agent files and the AC7 adapter [reviewer]→agent map.
EXPECTED_KEYS="$(printf '%s\n' "$EXPECTED" | cut -d'|' -f1 | sort -u)"

ok()   { pass=$((pass + 1)); }
bad() { # bad <message>
  fail=$((fail + 1))
  printf 'FAIL %s\n' "$1" >&2
}

# ── parse_roster <gate-loop.md> — emit "<key>|<tier>|<condition>" per roster table row,
#    sorted. A roster row is a markdown table row naming a reviewers/<stem>-auditor.md
#    spec; the header and the |---| delimiter never match, and gate-loop.md's prose
#    mentions `reviewers/` only generically (no `-auditor.md`), so only the data rows hit.
#    The stem class is [a-z-]+ (not [a-z]+) so a multi-segment stem like
#    spec-quality-auditor parses as one key, not just its trailing quality-auditor segment.
parse_roster() {
  awk -F'|' '
    /reviewers\/[a-z-]+-auditor\.md/ {
      key=$2; tier=$3; cond=$4
      match(key, /[a-z-]+-auditor/); key=substr(key, RSTART, RLENGTH)
      gsub(/[^a-z-]/, "", tier)   # cheap | strong
      gsub(/[^a-z-]/, "", cond)   # always | dispatch-contract | dispatch-spec
      print key "|" tier "|" cond
    }
  ' "$1" | sort
}

# AC1 — gate-loop.md roster is EXACTLY the canonical set (membership + tier + condition,
#       no extra rows).
roster_ok() { [ "$(parse_roster "$1")" = "$EXPECTED" ]; }

# AC2 — gate-loop.js names the four keys with matching tiers (constitution + spec-quality
#       = strong; spec + contract = cheap) and gates BOTH conditional reviewers on their
#       input flag (a guarded .push, never the unconditional array literal): contract on
#       dispatchContract, spec-quality on dispatchSpec. Exact fixed-string matches on the
#       authored shape (two literals + two conditional pushes).
js_ok() {
  local f="$1" r=0
  grep -qF "key: 'spec-auditor', model: input.cheapModel, tier: 'cheap'" "$f" || r=1
  grep -qF "key: 'constitution-auditor', model: input.strongModel, tier: 'strong'" "$f" || r=1
  grep -qF "reviewers.push({ key: 'contract-auditor', model: input.cheapModel, tier: 'cheap' })" "$f" || r=1
  grep -qF "if (input.dispatchContract)" "$f" || r=1
  grep -qF "reviewers.push({ key: 'spec-quality-auditor', model: input.strongModel, tier: 'strong' })" "$f" || r=1
  grep -qF "if (input.dispatchSpec)" "$f" || r=1
  # the conditional reviewers must be gated: each may appear ONLY on a push line, never in
  # the unconditional array literal. A contract/spec-quality line without `push` is drift.
  if grep -F "key: 'contract-auditor'" "$f" | grep -vqF "push"; then r=1; fi
  if grep -F "key: 'spec-quality-auditor'" "$f" | grep -vqF "push"; then r=1; fi
  # …and each gated push must sit DIRECTLY under its own `if (input.dispatchX)` guard — not
  # merely somewhere in the file. Without this, lifting a push out of its block (while an
  # `if (input.dispatchX)` line survives elsewhere) passes every check above yet dispatches
  # the reviewer UNCONDITIONALLY — breaking the no-dispatch-on-non-matching-diff contract
  # (US2.AC2 for spec-quality; Codex P2, PR #151). `grep -A1` (BSD + GNU) pins each push to
  # its guard's immediate next line.
  grep -A1 -F "if (input.dispatchContract)" "$f" | grep -qF "reviewers.push({ key: 'contract-auditor'" || r=1
  grep -A1 -F "if (input.dispatchSpec)" "$f" | grep -qF "reviewers.push({ key: 'spec-quality-auditor'" || r=1
  return $r
}

# AC3 — next-task.md §7 step 2 references the same four reviewer spec paths with the
#       same conditions (always / always / contract-conditional / spec-conditional) and
#       points at the roster. Scoped to §7 and whitespace-flattened so prose re-wrapping
#       can't break it; the needles are distinctive authored prose, bound to each
#       reviewer's condition.
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
  # spec-quality — the dispatch-spec condition
  printf '%s' "$s" | grep -qF "reviewers/spec-quality-auditor.md" || r=1
  printf '%s' "$s" | grep -qF "dispatch-spec" || r=1
  printf '%s' "$s" | grep -qF "adds, edits, or renames a" || r=1
  # points at the roster as the source of truth
  printf '%s' "$s" | grep -qF "reviewer roster" || r=1
  printf '%s' "$s" | grep -qF "gate-loop.md" || r=1
  return $r
}

# AC7 — the adapter's [reviewer]→agent map (next-task SKILL.md) names every roster
#       reviewer's agent. In the documented fallback (Workflow tool absent → the operator
#       dispatches reviewers via the Agent tool, following this map + §7), a map missing a
#       reviewer silently under-dispatches the gate — the same "a reviewer fell out" drift
#       class the three gate sites are pinned against, on the FALLBACK path. The map drifted
#       exactly this way once: it still listed only the original three after the spec-quality
#       reviewer landed (PR #186 review). The map carries agent NAMES only; tier and
#       condition stay single-sourced in the roster + §7 (which the fallback also follows),
#       so this site is pinned on MEMBERSHIP alone (EXPECTED_KEYS), not tier/condition.
skill_map() { grep -F '**[reviewer]**' "$1" | grep -oE '[a-z-]+-auditor' | sort -u; }
skill_ok()  { [ "$(skill_map "$1")" = "$EXPECTED_KEYS" ]; }

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
     (expected spec=cheap, constitution=strong, contract=cheap gated on dispatchContract,
     spec-quality=strong gated on dispatchSpec)"

prose_ok "$NT" \
  && ok \
  || bad "AC3 prose: next-task.md §7 step 2 does not reference the roster's four specs
     with conditions always / always / contract-conditional / spec-conditional, or omits
     the roster pointer"

skill_ok "$SK" \
  && ok \
  || bad "AC7 skill-map: next-task SKILL.md [reviewer] map does not name exactly the roster
     reviewers (a reviewer would silently drop off the manual-fallback dispatch)
     expected:
$(printf '%s\n' "$EXPECTED_KEYS" | sed 's/^/       /')
     got:
$(skill_map "$SK" | sed 's/^/       /')"

# AC4 — every canonical reviewer has a workflow/reviewers/<name>.md spec. The spec-quality
#       reviewer's spec landed in T701, so it is checked here alongside the original three.
for key in spec-auditor constitution-auditor contract-auditor spec-quality-auditor; do
  if [ -f "$REVDIR/$key.md" ]; then
    ok
  else
    bad "AC4 spec: missing reviewer spec $REVDIR/$key.md"
  fi
done

# AC5 — each ADAPTER-BOUND reviewer has an agent file that excludes edit tools
#       (maker≠checker's "no edit tools by construction" as a CI invariant). The
#       spec-quality reviewer's Claude agent binding landed in T706 (US2.AC5), so it joins
#       the original three here: all four roster reviewers now have a read-only agent file.
#       (Its gate-loop.js dispatch is gated on dispatchSpec; the conditional push and the
#       strong tier are proven by js_ok + gate-loop.test.js.)
for key in spec-auditor constitution-auditor contract-auditor spec-quality-auditor; do
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

# ── The spec-quality reviewer (T703) is drift-protected on every site too: dropping its
#    row/push/reference must trip the corresponding site check, exactly like the originals. ──

# Roster site — drop the spec-quality row.
grep -vF 'reviewers/spec-quality-auditor.md' "$GL" > "$TMP/gl-drop-sq.md"
mut_fail "roster drop-spec-quality" roster_ok "$TMP/gl-drop-sq.md"

# JS site — drop the gated spec-quality push.
grep -vF "reviewers.push({ key: 'spec-quality-auditor'" "$JS" > "$TMP/js-drop-sq.js"
mut_fail "js drop-spec-quality" js_ok "$TMP/js-drop-sq.js"

# Prose site — drop the spec-quality reviewer reference.
grep -vF 'reviewers/spec-quality-auditor.md' "$NT" > "$TMP/nt-drop-sq.md"
mut_fail "prose drop-spec-quality" prose_ok "$TMP/nt-drop-sq.md"

# Skill-map site (next-task SKILL.md) — drop the spec-quality agent from the [reviewer]
# map (the exact PR #186 drift: the map listed only the original three). Removing the name
# leaves the map enumerating three reviewers, so skill_ok must trip.
sed 's/spec-quality-auditor//g' "$SK" > "$TMP/sk-drop-sq.md"
mut_fail "skill drop-spec-quality" skill_ok "$TMP/sk-drop-sq.md"

# ── A gated push must stay STRUCTURALLY under its `if (input.dispatchX)` guard, not merely
#    appear somewhere in the file. Lifting one out makes its reviewer unconditional — a diff
#    touching no contract/spec would still dispatch it, breaking US2.AC2. Each mutation swaps
#    a guard line with the push beneath it (the push now runs unconditionally); BOTH the push
#    string and the `if (input.dispatchX)` string survive, so every "appears somewhere" check
#    stays green and ONLY js_ok's immediate-adjacency check trips (Codex P2, PR #151 — CI must
#    catch a reviewer becoming unconditional, not just being dropped). ──

# JS site — lift the contract push out from under its guard (swap guard ↔ push).
awk '/if \(input\.dispatchContract\)/ { g=$0; getline b; print b; print g; next } { print }' \
  "$JS" > "$TMP/js-ungate-contract.js"
mut_fail "js ungate-contract" js_ok "$TMP/js-ungate-contract.js"

# JS site — lift the spec-quality push out from under its guard (swap guard ↔ push).
awk '/if \(input\.dispatchSpec\)/ { g=$0; getline b; print b; print g; next } { print }' \
  "$JS" > "$TMP/js-ungate-sq.js"
mut_fail "js ungate-spec-quality" js_ok "$TMP/js-ungate-sq.js"

echo "reviewer-roster encoding tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
