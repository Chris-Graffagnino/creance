#!/usr/bin/env bash
# Drift backstop for the §7 reviewer roster (T602 / issue #64, parent epic #62).
#
# The §7 pre-PR gate's reviewer set used to be hand-synced across workflow and adapter
# surfaces that could silently disagree. T602 collapses membership/tier/dispatch-condition
# into ONE declarative roster table in `gate-loop.md`; this test pins each structural mirror
# exactly for the roster data it owns. Together with gate-loop.test.js's exact behavioral
# dispatch cases, that converts "a reviewer silently fell out of the gate" from a
# model-noticing risk into a deterministic check (constitution P2/P3; the same same-diff
# discipline `guard.test.sh` follows — the backstop ships with the change it guards).
#
# The test is an INDEPENDENT structural oracle: it pins each declared surface's owned
# roster data to a hardcoded canonical set (below), not to whatever the roster currently
# says. A backstop that derived its
# expectation from the very table it checks could not catch a coordinated drift, so the
# canonical set lives here; adding/removing a reviewer is an intentional edit to the
# roster, its mirrors, AND this set (the ratchet that proves the change was deliberate).
# The adapters' manual-fallback [reviewer]→agent maps (next-task and review-response
# SKILL.md) are pinned too (AC7), on membership; the next-task map drifted exactly once
# (PR #186) before being pinned here.
# gate-loop.md's runtime-neutrality (no model IDs in the roster) is covered
# globally by telemetry-docs.test.sh's mech scan and bound here implicitly: a model ID in
# the tier column would break the canonical-set match.
#
# Encodes issue #64 done-when AC1–AC6 (extended for the spec-quality reviewer, T703);
# AC7 adds the adapter maps as pinned membership-only surfaces (PR #186 review):
#   AC1 roster is exactly the canonical set (no extra rows)        → roster_ok
#   AC2 gate-loop.js mirrors it (keys, tiers, both conditionals     → js_ok
#       gated on their input flag)
#   AC3 next-task.md §7 references the same paths + conditions      → prose_ok
#   AC4 each roster reviewer has a workflow/reviewers/<name>.md spec → AC4 loop (all four)
#   AC5 each ADAPTER-BOUND reviewer's agents/<name>.md exists and    → AC5 loop (all four;
#       excludes edit tools (the spec-quality agent binding landed       each with a Claude
#       in T706/US2.AC5)                                                  agent)
#   AC6 retained drop/add/tier/condition/guard mutations FAIL       → AC6 block: temp-copy
#       the owning structural check                                      mutations re-run each
#                                                                         owning predicate
#   AC7 each adapter fallback [reviewer] map (next-task and         → skill_ok /
#       review-response SKILL.md) names every roster reviewer, so      review_response_ok
#       neither manual fallback can omit one                            (+ AC6 mutations)
#
# Run: bash .claude/hooks/reviewer-roster.test.sh
set -u

DIR="$(cd "$(dirname "$0")/.." && pwd)"
GL="$DIR/workflow/gate-loop.md"        # roster source of truth
JS="$DIR/workflows/gate-loop.js"       # orchestrated-run mirror
NT="$DIR/workflow/next-task/07-pre-pr-gate.md" # demand-loaded §7 prose mirror
REVDIR="$DIR/workflow/reviewers"       # reviewer specs (AC4)
AGENTDIR="$DIR/agents"                 # adapter agent files (AC5)
SK="$DIR/skills/next-task/SKILL.md"    # adapter [reviewer]→agent map (AC7)
RR="$DIR/skills/review-response/SKILL.md" # review-response re-gate fallback map (AC7)

pass=0
fail=0

for f in "$GL" "$JS" "$NT" "$SK" "$RR"; do
  if [ ! -f "$f" ]; then
    echo "FAIL: required file missing: $f" >&2
    exit 1
  fi
done

# ── The canonical roster — the known-correct set each structural projection is pinned to.
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

# The JS mirror also owns the tier→model-input relationship. Derive its expectation from
# EXPECTED so membership/tier/condition still have one independent canonical set:
# "<key>|<model-tier>|<tier>|<condition>".
EXPECTED_JS="$(printf '%s\n' "$EXPECTED" \
  | awk -F'|' '{ print $1 "|" $2 "|" $2 "|" $3 }' \
  | sort)"

# The §7 prose deliberately delegates tiers to the roster and owns only reviewer paths +
# dispatch conditions. Derive that exact projection instead of hardcoding another list.
EXPECTED_PROSE="$(printf '%s\n' "$EXPECTED" \
  | awk -F'|' '{ print $1 "|" $3 }' \
  | sort)"

# Exact authored shapes for the bounded structural surfaces. These are independent test
# fixtures, not derived from the files they check: every code-bearing row/bullet/use must
# match one of these complete forms, so equivalent syntax cannot hide an extra reviewer.
EXPECTED_ROSTER_ROWS="$(printf '%s\n' \
  '| `reviewers/spec-auditor.md` (acceptance) | cheap | `always` |' \
  '| `reviewers/constitution-auditor.md` | strong | `always` |' \
  '| `reviewers/contract-auditor.md` | cheap | `dispatch-contract` |' \
  '| `reviewers/spec-quality-auditor.md` | strong | `dispatch-spec` |' | sort)"

EXPECTED_PROSE_BULLETS="$(printf '%s\n' \
  '- The **acceptance [reviewer]** (`workflow/reviewers/spec-auditor.md`) — **always**, and pass it the task ID. It returns PASS/FAIL against the `US#` acceptance criteria (implementation AND encoding tests, criterion by criterion).' \
  '- The **constitution [reviewer]** (`workflow/reviewers/constitution-auditor.md`) — **always**. It returns PASS/JUSTIFY/FAIL against the constitution + invariant checklist.' \
  "- The **contract [reviewer]** (\`workflow/reviewers/contract-auditor.md\`) — only on the roster's \`dispatch-contract\` condition: when the change touches a provider interface, monetization, or the data model." \
  '- The **spec-quality [reviewer]** (`workflow/reviewers/spec-quality-auditor.md`) — only on the roster'"'"'s `dispatch-spec` condition: when the diff adds, edits, or renames a `specs/*/spec.md` (git status `A`/`M`/`R`; a pure deletion `D` does not fire). It returns PASS/FAIL against the spec-content quality rubric, dispatched at the **[strong tier]** floor (the spec is the cheapest place to lose a project).')"

EXPECTED_SKILL_SPANS="$(printf '%s\n' \
  '`.claude/agents/`' \
  '`constitution-auditor`' \
  '`contract-auditor`' \
  '`contract-auditor`' \
  '`gate-loop.md`' \
  '`reviewer-roster.test.sh`' \
  '`spec-auditor`' \
  '`spec-auditor`' \
  '`spec-quality-auditor`' \
  '`spec-quality-auditor`' \
  '`specs/*/spec.md`' | sort)"

EXPECTED_REVIEW_RESPONSE_SPANS="$(printf '%s\n' \
  '`.claude/agents/`' \
  '`constitution-auditor`' \
  '`contract-auditor`' \
  '`git diff main..HEAD`' \
  '`spec-auditor`' \
  '`spec-quality-auditor`' | sort)"

EXPECTED_POST_JS_USES="$(printf '%s\n' \
  'reviewers.map(' \
  'const unresolvedTypes = reviewers.filter((_r, i) => probeResults[i] == null).map((r) => r.key);' \
  'notDispatched: reviewers.map((r) => r.key),' \
  "\`Gate dispatch \${fixRoundsUsed + 1}/\${MAX_FIX_ROUNDS + 1}: \${pending.map((r) => r.key).join(', ')}\`," \
  'notDispatched: pending.map((r) => r.key),' \
  'pending.map(' \
  'pending.map((r, i) => ({' \
  'pending.forEach((r, i) => {' \
  'pending.forEach((r, i) => {' \
  "const failing = pending.filter((r, i) => !results[i] || results[i].verdict === 'FAIL');" \
  'noVerdict: pending.filter((r, i) => !results[i]).map((r) => r.key),' \
  '`reviewers, restore the shared working tree to its task branch — a parallel read-only ` +' \
  "\`reviewers re-audit the COMMITTED diff (\${diffCmd}), so an uncommitted fix \` +" \
  'pending = failing; // re-dispatch ONLY the failures')"

ok()   { pass=$((pass + 1)); }
bad() { # bad <message>
  fail=$((fail + 1))
  printf 'FAIL %s\n' "$1" >&2
}

# ── parse_roster <gate-loop.md> — emit "<key>|<tier>|<condition>" for EVERY data row
#    in the roster table, sorted. Scoping to the table boundary makes exactness independent
#    of reviewer naming convention; a row that does not carry a parseable reviewers/<key>.md
#    path emits an invalid key and therefore fails the canonical-set comparison.
parse_roster() {
  awk -F'|' '
    function cell_value(value) {
      sub(/^[[:space:]]*/, "", value)
      sub(/[[:space:]]*$/, "", value)
      if (value ~ /^`[^`]+`$/) {
        sub(/^`/, "", value)
        sub(/`$/, "", value)
      }
      return value
    }
    /^\| Reviewer spec \| Tier \| Dispatch condition \|$/ {
      in_roster=1
      next
    }
    in_roster && /^\|---/ {
      next
    }
    in_roster && /^\|/ {
      key=$2; tier=$3; cond=$4
      sub(/^[[:space:]]*/, "", key)
      sub(/[[:space:]]*$/, "", key)
      if (key ~ /^`reviewers\/[^`\/[:space:]]+\.md`([[:space:]]+\([^)]*\))?$/ &&
          match(key, /reviewers\/[^`\/[:space:]]+\.md/)) {
        key=substr(key, RSTART, RLENGTH)
        sub(/^reviewers\//, "", key)
        sub(/\.md$/, "", key)
      } else {
        key="invalid"
      }
      tier=cell_value(tier)
      cond=cell_value(cond)
      print key "|" tier "|" cond
      next
    }
    in_roster {
      exit
    }
  ' "$1" | sort
}

roster_rows() {
  awk '
    /^\| Reviewer spec \| Tier \| Dispatch condition \|$/ {
      in_roster=1
      next
    }
    in_roster && /^\|---/ {
      next
    }
    in_roster && /^\|/ {
      line=$0
      sub(/^[[:space:]]*/, "", line)
      sub(/[[:space:]]*$/, "", line)
      print line
      next
    }
    in_roster {
      exit
    }
  ' "$1" | sort
}

# AC1 — gate-loop.md roster is EXACTLY the canonical set (membership + tier + condition,
#       no extra rows).
roster_ok() {
  [ "$(parse_roster "$1")" = "$EXPECTED" ] &&
    [ "$(roster_rows "$1")" = "$EXPECTED_ROSTER_ROWS" ]
}

# parse_js <gate-loop.js> — emit
# "<key>|<model-tier>|<tier>|<condition>" for every reviewer entry in the executable
# construction block. Array entries are `always`; a push owns a conditional only when it
# is immediately below the matching guard. Any other push is `unguarded`. Parsing every
# key entry (rather than looking only for expected strings) makes unexpected and duplicate
# reviewers visible to the exact-set comparison.
parse_js() {
  awk '
    function emit(line, condition,    key, model, tier) {
      key=""
      model=""
      tier=""

      if (match(line, /key: [^,]+/)) {
        key=substr(line, RSTART, RLENGTH)
        sub(/^key: /, "", key)
        gsub(/\047/, "", key)
      }
      if (match(line, /model: input\.[a-z]+Model/)) {
        model=substr(line, RSTART, RLENGTH)
        sub(/^model: input\./, "", model)
        sub(/Model$/, "", model)
      }
      if (match(line, /tier: [^ }]+/)) {
        tier=substr(line, RSTART, RLENGTH)
        sub(/^tier: /, "", tier)
        gsub(/\047/, "", tier)
      }

      print key "|" model "|" tier "|" condition
    }
    /^const reviewers = \[$/ {
      in_block=1
      in_array=1
      previous=$0
      next
    }
    in_block && in_array && /^];$/ {
      in_array=0
      previous=$0
      next
    }
    in_block && /^let pending = reviewers;$/ {
      in_block=0
      previous=$0
      next
    }
    in_block && in_array {
      if ($0 !~ /^[[:space:]]*$/ && $0 !~ /^[[:space:]]*\/\//) {
        emit($0, "always")
      }
      previous=$0
      next
    }
    in_block && /reviewers/ {
      condition="unguarded"
      if (previous ~ /^[[:space:]]*if \(input\.dispatchContract\) \{[[:space:]]*$/) {
        condition="dispatch-contract"
      } else if (previous ~ /^[[:space:]]*if \(input\.dispatchSpec\) \{[[:space:]]*$/) {
        condition="dispatch-spec"
      }
      emit($0, condition)
      previous=$0
      next
    }
    in_block {
      previous=$0
    }
  ' "$1" | sort
}

post_js_uses() {
  awk '
    /^let pending = reviewers;$/ {
      after_alias=1
      next
    }
    after_alias &&
      $0 !~ /^[[:space:]]*\/\// &&
      $0 ~ /(^|[^[:alnum:]_])(reviewers|pending)([^[:alnum:]_]|$)/ {
        line=$0
        sub(/^[[:space:]]*/, "", line)
        sub(/[[:space:]]*$/, "", line)
        print line
      }
  ' "$1"
}

# AC2 — gate-loop.js is EXACTLY the canonical membership + tier + condition/guard
# relationship, and every tier uses its matching model input. Extra, duplicate, missing,
# malformed, wrongly tiered, or unguarded reviewer entries all change the parsed set.
js_ok() {
  [ "$(parse_js "$1")" = "$EXPECTED_JS" ] &&
    [ "$(post_js_uses "$1")" = "$EXPECTED_POST_JS_USES" ]
}

# AC3 helpers — scope to §7, enumerate EVERY concrete reviewer path, and project each
# reviewer bullet to "<key>|<condition>". A bullet must carry exactly one of `always`,
# `dispatch-contract`, or `dispatch-spec`; ambiguous/missing conditions are emitted as
# `invalid`. Tiers are intentionally absent because §7 delegates them to the roster.
section7() { awk '/^## 7\./{f=1} /^## 8\./{f=0} f' "$1"; }
prose_paths() {
  section7 "$1" \
    | grep -oE '`workflow/reviewers/[^`/[:space:]]+\.md`' \
    | sed 's#^`workflow/reviewers/##; s#\.md`$##' \
    | sort
}
parse_prose() {
  section7 "$1" | awk '
    function emit(    key, condition, count, rest, token, unknown) {
      if (bullet !~ /`workflow\/reviewers\/[^`\/[:space:]]+\.md`/) {
        return
      }
      match(bullet, /`workflow\/reviewers\/[^`\/[:space:]]+\.md`/)
      key=substr(bullet, RSTART, RLENGTH)
      sub(/^`workflow\/reviewers\//, "", key)
      sub(/\.md`$/, "", key)

      condition="invalid"
      count=0
      if (bullet ~ /\*\*always\*\*/) {
        condition="always"
        count++
      }
      rest=bullet
      while (match(rest, /`dispatch-[^`]+`/)) {
        token=substr(rest, RSTART + 1, RLENGTH - 2)
        if (token == "dispatch-contract" || token == "dispatch-spec") {
          condition=token
        } else {
          unknown=1
        }
        count++
        rest=substr(rest, RSTART + RLENGTH)
      }
      if (count != 1 || unknown) {
        condition="invalid"
      }
      print key "|" condition
    }
    /^   - / {
      emit()
      bullet=$0
      next
    }
    /^3\. Run/ {
      emit()
      bullet=""
      exit
    }
    bullet != "" {
      bullet=bullet " " $0
    }
    END {
      emit()
    }
  ' | sort
}

prose_bullets() {
  section7 "$1" | awk '
    function emit() {
      if (bullet ~ /`workflow\/reviewers\//) {
        gsub(/[[:space:]]+/, " ", bullet)
        sub(/^[[:space:]]*/, "", bullet)
        print bullet
      }
    }
    /^   - / {
      emit()
      bullet=$0
      next
    }
    /^3\. Run/ {
      emit()
      bullet=""
      exit
    }
    bullet != "" {
      bullet=bullet " " $0
    }
  '
}

# AC3 — §7 names exactly the canonical reviewer paths and binds each to its canonical
# dispatch condition, while pointing at the roster for membership/tier/condition. An
# unexpected reviewer reference anywhere in §7 changes prose_paths; an extra/missing or
# misconditioned reviewer bullet changes parse_prose.
prose_ok() {
  local f="$1" s r=0
  s="$(section7 "$f" | tr -s '[:space:]' ' ')"
  [ "$(prose_paths "$f")" = "$EXPECTED_KEYS" ] || r=1
  [ "$(parse_prose "$f")" = "$EXPECTED_PROSE" ] || r=1
  [ "$(prose_bullets "$f")" = "$EXPECTED_PROSE_BULLETS" ] || r=1
  # points at the roster as the source of truth
  printf '%s' "$s" | grep -qF "reviewer roster" || r=1
  printf '%s' "$s" | grep -qF "gate-loop.md" || r=1
  printf '%s' "$s" | grep -qF "roster's \`dispatch-contract\` condition: when the change touches a provider interface, monetization, or the data model." || r=1
  printf '%s' "$s" | grep -qF "roster's \`dispatch-spec\` condition: when the diff adds, edits, or renames a \`specs/*/spec.md\`" || r=1
  return $r
}

# AC7 — the adapter fallback maps name every roster reviewer's agent. In either documented
#       fallback (Workflow tool absent → the operator dispatches reviewers via the Agent
#       tool, following the map + §7), a missing reviewer silently under-dispatches the gate
#       — the same "a reviewer fell out" drift class the structural mirrors pin. The
#       next-task map drifted exactly this way once: it still listed only the original three
#       after the spec-quality reviewer landed (PR #186 review). These maps carry agent NAMES
#       only; tier and condition stay single-sourced in the roster + §7, so both sites are
#       pinned on MEMBERSHIP alone (EXPECTED_KEYS), not tier/condition.
skill_row() {
  awk -F'|' '
    $2 ~ /\*\*\[reviewer\]\*\*/ {
      map=$3
      sub(/^[[:space:]]*the[[:space:]]+/, "", map)
      print map
    }
  ' "$1"
}
skill_map() {
  skill_row "$1" \
    | sed 's/[[:space:]]*subagents.*//' \
    | grep -oE '`[^`]+`' \
    | tr -d '`' \
    | sort
}
skill_shape_ok() {
  case "$(skill_row "$1")" in
    *' subagents (`.claude/agents/`), dispatched'*) return 0 ;;
    *) return 1 ;;
  esac
}
skill_spans() {
  skill_row "$1" | grep -oE '`[^`]+`' | sort
}
skill_ok() {
  [ "$(skill_map "$1")" = "$EXPECTED_KEYS" ] &&
    skill_shape_ok "$1" &&
    [ "$(skill_spans "$1")" = "$EXPECTED_SKILL_SPANS" ]
}

review_response_row() {
  awk -F'|' '
    $2 ~ /\*\*\[reviewer\]s \/ \[orchestrated run\]\*\*/ {
      map=$3
      sub(/^.*; or the[[:space:]]+/, "", map)
      print map
    }
  ' "$1"
}
review_response_map() {
  review_response_row "$1" \
    | sed 's/[[:space:]]*subagents.*//' \
    | grep -oE '`[^`]+`' \
    | tr -d '`' \
    | sort
}
review_response_shape_ok() {
  case "$(review_response_row "$1")" in
    *' subagents (`.claude/agents/`) dispatched'*) return 0 ;;
    *) return 1 ;;
  esac
}
review_response_spans() {
  review_response_row "$1" | grep -oE '`[^`]+`' | sort
}
review_response_ok() {
  [ "$(review_response_map "$1")" = "$EXPECTED_KEYS" ] &&
    review_response_shape_ok "$1" &&
    [ "$(review_response_spans "$1")" = "$EXPECTED_REVIEW_RESPONSE_SPANS" ]
}

# ── Run the structural surface checks against the live tree ─────────────────────────
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

review_response_ok "$RR" \
  && ok \
  || bad "AC7 review-response-map: review-response SKILL.md fallback map does not name
     exactly the roster reviewers (a reviewer would silently drop off its §7 re-gate)
     expected:
$(printf '%s\n' "$EXPECTED_KEYS" | sed 's/^/       /')
     got:
$(review_response_map "$RR" | sed 's/^/       /')"

# AC4 — every canonical reviewer has a workflow/reviewers/<name>.md spec. The spec-quality
#       reviewer's spec landed in T701, so it is checked here alongside the original three.
for key in spec-auditor constitution-auditor contract-auditor spec-quality-auditor; do
  if [ -f "$REVDIR/$key.md" ]; then
    ok
  else
    bad "AC4 spec: missing reviewer spec $REVDIR/$key.md"
  fi
done

# AC5 — each ADAPTER-BOUND reviewer has an agent file granting NO edit tools
#       (Edit/Write/MultiEdit/NotebookEdit) AND NO shell (Bash/PowerShell) — read-only BY
#       CONSTRUCTION, the STRUCTURAL half of maker≠checker as a CI invariant. Before #188 the
#       reviewers also granted `Bash`, so read-only was only a behavioral contract (the shell
#       could `sed -i`/`echo >`/`tee`; PR #186 craft finding). #188 chose Option 2 — drop the
#       shell — so the reviewer now CANNOT write at all: the deterministic proof that a reviewer
#       shell-write is blocked is that no shell tool is granted. The [orchestrated run] hands the
#       reviewer the committed diff in its prompt instead of it running `git` (gate-loop.js /
#       gate-loop.test.js). The spec-quality reviewer's Claude agent binding landed in T706
#       (US2.AC5), so all four roster reviewers ship a no-edit, no-shell agent file. (Its
#       gate-loop.js dispatch is gated on dispatchSpec; the conditional push and the strong tier
#       are proven by js_ok + gate-loop.test.js.)
#
# Predicate — an agent file's `tools:` line grants EXACTLY the read-only set {Read, Grep, Glob}.
# An ALLOWLIST, not a denylist (PR #200 review): the invariant is "Read/Grep/Glob only", so the
# check parses the tools line into a token set and compares it to the exact allowed set — a
# future write-capable tool whose name matches no denylist pattern (or a lost read tool) fails
# the same way a re-granted Bash/Edit does. Returns 0 (exactly the read-only set) / nonzero
# (any other set, or no tools: line to constrain — fail closed). Reused by the AC6 drift cases.
agent_readonly_ok() { # <agent-file>
  local tl got
  tl="$(grep -E '^tools:' "$1" 2>/dev/null || true)"
  [ -n "$tl" ] || return 1                       # no tools: line → not provably read-only
  got="$(printf '%s\n' "$tl" \
    | sed 's/^tools:[[:space:]]*//' \
    | tr ',' '\n' \
    | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' \
    | grep -v '^$' \
    | sort -u)"
  [ "$got" = "$(printf 'Glob\nGrep\nRead')" ]
}
for key in spec-auditor constitution-auditor contract-auditor spec-quality-auditor; do
  af="$AGENTDIR/$key.md"
  if [ ! -f "$af" ]; then
    bad "AC5 agent: missing agent file $af"
  elif agent_readonly_ok "$af"; then
    ok
  else
    bad "AC5 agent: $af is not read-only by construction — its tools: line must be Read/Grep/Glob only, granting no edit or shell tool (#188): $(grep -E '^tools:' "$af" || echo '(no tools: line)')"
  fi
done

# ── AC6 — the enumerated structural drifts must FAIL their owning checks. Demonstrated on
#         temp copies so each claimed mutation is CI-verified, not asserted by hand: every
#         retained mutation must flip its predicate from OK (0) to drift (nonzero). ──
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

# Roster site — add an unlisted reviewer whose name does not follow the current
# `*-auditor` convention and contains a digit. Exactness must not depend on an
# unenforced naming grammar.
awk '
  /reviewers\/contract-auditor\.md/ {
    print
    print "| `reviewers/security2-reviewer.md` | cheap | `always` |"
    next
  }
  { print }
' "$GL" > "$TMP/gl-add-unlisted.md"
mut_fail "roster add-unlisted-reviewer" roster_ok "$TMP/gl-add-unlisted.md"

# Roster site — flip a tier (spec cheap → strong).
sed '/reviewers\/spec-auditor\.md/ s/| cheap |/| strong |/' "$GL" > "$TMP/gl-tier.md"
mut_fail "roster flip-tier" roster_ok "$TMP/gl-tier.md"

# Roster site — flip a condition (contract dispatch-contract → always).
sed '/reviewers\/contract-auditor\.md/ s/dispatch-contract/always/' "$GL" > "$TMP/gl-cond.md"
mut_fail "roster flip-condition" roster_ok "$TMP/gl-cond.md"

# Roster site — malformed digit-bearing tier/condition cells must not normalize back to
# their canonical values. Only Markdown formatting is stripped from the source cells.
sed '/reviewers\/spec-auditor\.md/ s/| cheap |/| che2ap |/' \
  "$GL" > "$TMP/gl-malformed-tier.md"
mut_fail "roster malformed-tier" roster_ok "$TMP/gl-malformed-tier.md"

sed '/reviewers\/contract-auditor\.md/ s/dispatch-contract/dispatch2-contract/' \
  "$GL" > "$TMP/gl-malformed-condition.md"
mut_fail "roster malformed-condition" roster_ok "$TMP/gl-malformed-condition.md"

# Roster site — the reviewer spec must be the complete code-span path, not a canonical
# substring inside a wrong directory name.
sed 's#`reviewers/spec-auditor.md`#`not-reviewers/spec-auditor.md`#' \
  "$GL" > "$TMP/gl-wrong-path.md"
mut_fail "roster wrong-path-prefix" roster_ok "$TMP/gl-wrong-path.md"

# Roster site — a second reviewer path hidden in the acceptance label's parenthetical
# is still an unexpected reviewer-bearing code span, even though the first path is valid.
sed 's#`reviewers/spec-auditor.md` (acceptance)#`reviewers/spec-auditor.md` (acceptance; `reviewers/security2-reviewer.md`)#' \
  "$GL" > "$TMP/gl-add-parenthetical-path.md"
mut_fail "roster add-parenthetical-reviewer-path" roster_ok "$TMP/gl-add-parenthetical-path.md"

# JS site (gate-loop.js) — drop the gated contract push.
grep -vF "reviewers.push({ key: 'contract-auditor'" "$JS" > "$TMP/js-drop.js"
mut_fail "js drop-reviewer" js_ok "$TMP/js-drop.js"

# JS site — add an unlisted reviewer to the unconditional array.
awk '
  /key: '\''constitution-auditor'\''/ {
    print
    print "  { key: '\''security-reviewer'\'', model: input.cheapModel, tier: '\''cheap'\'' },"
    next
  }
  { print }
' "$JS" > "$TMP/js-add-unlisted.js"
mut_fail "js add-unlisted-reviewer" js_ok "$TMP/js-add-unlisted.js"

# JS site — add an opaque spread entry to the unconditional array. The structural
# parser must reject an entry it cannot inventory, not silently accept the alias.
awk '
  /key: '\''constitution-auditor'\''/ {
    print
    print "  ...extraReviewers,"
    next
  }
  { print }
' "$JS" > "$TMP/js-add-spread.js"
mut_fail "js add-opaque-spread" js_ok "$TMP/js-add-spread.js"

# JS site — add an unlisted reviewer after verdict storage is declared but before the
# roster is consumed. The inventory must remain open through `let pending = reviewers`.
awk '
  /^let pending = reviewers;$/ {
    print "reviewers.push({ key: '\''security2-reviewer'\'', model: input.cheapModel, tier: '\''cheap'\'' });"
  }
  { print }
' "$JS" > "$TMP/js-add-late-reviewer.js"
mut_fail "js add-late-reviewer" js_ok "$TMP/js-add-late-reviewer.js"

# JS site — `pending` aliases the mutable reviewer array. A task-specific push after that
# assignment must remain visible even when fixed runtime test inputs do not enter its branch.
awk '
  { print }
  /^let pending = reviewers;$/ {
    print "if (input.taskId === '\''UNTESTED'\'') {"
    print "  pending.push({ key: '\''security2-reviewer'\'', model: input.cheapModel, tier: '\''cheap'\'' });"
    print "}"
  }
' "$JS" > "$TMP/js-add-post-consumption-reviewer.js"
mut_fail "js add-post-consumption-reviewer" js_ok "$TMP/js-add-post-consumption-reviewer.js"

# JS site — equivalent alias/mutation syntax remains closed: parenthesizing the alias,
# bracket-selecting a mutator, or compressing a reassignment onto one line cannot evade
# the inventory of every post-alias reviewers/pending use.
awk '
  { print }
  /^let pending = reviewers;$/ {
    print "const rosterAlias = (pending);"
    print "rosterAlias.push({ key: '\''security2-reviewer'\'', model: input.cheapModel, tier: '\''cheap'\'' });"
  }
' "$JS" > "$TMP/js-parenthesized-alias.js"
mut_fail "js parenthesized-post-consumption-alias" js_ok "$TMP/js-parenthesized-alias.js"

awk '
  { print }
  /^let pending = reviewers;$/ {
    print "pending['\''push'\'']({ key: '\''security2-reviewer'\'', model: input.cheapModel, tier: '\''cheap'\'' });"
  }
' "$JS" > "$TMP/js-bracket-push.js"
mut_fail "js bracket-push-post-consumption" js_ok "$TMP/js-bracket-push.js"

awk '
  { print }
  /^let pending = reviewers;$/ {
    print "if (input.taskId === '\''UNTESTED'\'') pending = [...pending, { key: '\''security2-reviewer'\'', model: input.cheapModel, tier: '\''cheap'\'' }];"
  }
' "$JS" > "$TMP/js-one-line-reassignment.js"
mut_fail "js one-line-post-consumption-reassignment" js_ok "$TMP/js-one-line-reassignment.js"

# JS site — direct reconstruction and indexed writes through the `pending` alias must fail
# closed too; neither depends on a named mutating method.
awk '
  { print }
  /^let pending = reviewers;$/ {
    print "if (input.taskId === '\''UNTESTED'\'') {"
    print "  pending = [...pending, { key: '\''security2-reviewer'\'', model: input.cheapModel, tier: '\''cheap'\'' }];"
    print "}"
  }
' "$JS" > "$TMP/js-reassign-post-consumption.js"
mut_fail "js reassign-post-consumption-reviewers" js_ok "$TMP/js-reassign-post-consumption.js"

awk '
  { print }
  /^let pending = reviewers;$/ {
    print "if (input.taskId === '\''UNTESTED'\'') {"
    print "  pending[pending.length] = { key: '\''security2-reviewer'\'', model: input.cheapModel, tier: '\''cheap'\'' };"
    print "}"
  }
' "$JS" > "$TMP/js-index-post-consumption.js"
mut_fail "js index-post-consumption-reviewers" js_ok "$TMP/js-index-post-consumption.js"

# JS site — flip a tier (spec cheap → strong).
sed "s/key: 'spec-auditor', model: input.cheapModel, tier: 'cheap'/key: 'spec-auditor', model: input.cheapModel, tier: 'strong'/" "$JS" > "$TMP/js-tier.js"
mut_fail "js flip-tier" js_ok "$TMP/js-tier.js"

# Prose site (next-task.md) — drop a reviewer reference.
grep -vF 'reviewers/spec-auditor.md' "$NT" > "$TMP/nt-drop.md"
mut_fail "prose drop-reviewer" prose_ok "$TMP/nt-drop.md"

# Prose site — add an unlisted always-dispatched reviewer bullet.
awk '
  /^3\. Run/ {
    print "   - The **security [reviewer]** (`workflow/reviewers/security2-reviewer.md`) — **always**."
  }
  { print }
' "$NT" > "$TMP/nt-add-unlisted.md"
mut_fail "prose add-unlisted-reviewer" prose_ok "$TMP/nt-add-unlisted.md"

# Prose site — reject a canonical reviewer basename embedded in a wrong path prefix and
# any extra dispatch-* condition token alongside the canonical condition.
sed 's#workflow/reviewers/spec-auditor.md#workflow/not-reviewers/spec-auditor.md#' \
  "$NT" > "$TMP/nt-wrong-path.md"
mut_fail "prose wrong-path-prefix" prose_ok "$TMP/nt-wrong-path.md"

sed '/roster'\''s `dispatch-contract` condition:/ s/condition:/condition plus `dispatch-security`:/' \
  "$NT" > "$TMP/nt-add-condition.md"
mut_fail "prose add-unlisted-condition" prose_ok "$TMP/nt-add-condition.md"

# Prose site — exact bullet text also rejects semantic condition drift written as
# ordinary prose rather than a dispatch-* code token.
sed '/monetization, or the data model\./ s/$/ The dispatch-security condition also applies./' \
  "$NT" > "$TMP/nt-add-plain-condition.md"
mut_fail "prose add-plain-condition" prose_ok "$TMP/nt-add-plain-condition.md"

# ── The spec-quality reviewer (T703) is pinned on each structural projection it appears in:
#    dropping its row/push/reference must trip that projection's check. ──

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

# Skill-map site — add an unlisted, digit-bearing fallback agent outside the unenforced
# `*-auditor` convention. Membership-only exactness must reject it too.
sed 's#`spec-auditor` /#`spec-auditor` / `security2-reviewer` /#' \
  "$SK" > "$TMP/sk-add-unlisted.md"
mut_fail "skill add-unlisted-reviewer" skill_ok "$TMP/sk-add-unlisted.md"

sed 's#subagents (`.claude/agents/`)#subagents plus `security2-reviewer` (`.claude/agents/`)#' \
  "$SK" > "$TMP/sk-add-after-subagents.md"
mut_fail "skill add-reviewer-after-subagents" skill_ok "$TMP/sk-add-after-subagents.md"

awk '
  index($0, "| **[reviewer]** |") {
    sub(/[[:space:]]*\|[[:space:]]*$/, "; also dispatch `security2-reviewer` |")
    print
    next
  }
  { print }
' "$SK" > "$TMP/sk-add-row-tail.md"
mut_fail "skill add-reviewer-at-row-tail" skill_ok "$TMP/sk-add-row-tail.md"

# review-response fallback map — both omission and a digit-bearing unexpected reviewer
# must fail exact membership just as they do in the primary next-task fallback map.
sed 's# / `spec-quality-auditor` subagents# subagents#' \
  "$RR" > "$TMP/rr-drop-sq.md"
mut_fail "review-response drop-spec-quality" review_response_ok "$TMP/rr-drop-sq.md"

sed 's#`spec-quality-auditor` subagents#`spec-quality-auditor` / `security2-reviewer` subagents#' \
  "$RR" > "$TMP/rr-add-unlisted.md"
mut_fail "review-response add-unlisted-reviewer" review_response_ok "$TMP/rr-add-unlisted.md"

sed 's#subagents (`.claude/agents/`)#subagents plus `security2-reviewer` (`.claude/agents/`)#' \
  "$RR" > "$TMP/rr-add-after-subagents.md"
mut_fail "review-response add-reviewer-after-subagents" review_response_ok "$TMP/rr-add-after-subagents.md"

awk '
  index($0, "| **[reviewer]s / [orchestrated run]**") {
    sub(/[[:space:]]*\|[[:space:]]*$/, "; also dispatch `security2-reviewer` |")
    print
    next
  }
  { print }
' "$RR" > "$TMP/rr-add-row-tail.md"
mut_fail "review-response add-reviewer-at-row-tail" review_response_ok "$TMP/rr-add-row-tail.md"

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

# ── AC6 extension — the reviewer-binding read-only site (#188). Drift here = a reviewer binding
#    that re-grants a write-capable tool. The whole point of Option 2 is that a reviewer holds no
#    shell, so a `tools:` line with Bash (the shell-write vector this issue closed) or an edit tool
#    must trip agent_readonly_ok. Demonstrated on temp copies of real bindings, like the sites above. ──

# A reviewer that re-grants Bash — the exact #188 shell-write vector — must trip the check.
sed 's/^tools: Read, Grep, Glob$/tools: Read, Grep, Glob, Bash/' \
  "$AGENTDIR/spec-auditor.md" > "$TMP/agent-add-bash.md"
mut_fail "agent add-bash (shell-write vector, #188)" agent_readonly_ok "$TMP/agent-add-bash.md"

# A reviewer that re-grants an edit tool must trip the check (the pre-#188 half still holds).
sed 's/^tools: Read, Grep, Glob$/tools: Read, Grep, Glob, Edit/' \
  "$AGENTDIR/constitution-auditor.md" > "$TMP/agent-add-edit.md"
mut_fail "agent add-edit-tool" agent_readonly_ok "$TMP/agent-add-edit.md"

# A reviewer that grants ANY tool beyond the exact read-only set must trip the check, even one
# no edit/shell denylist pattern would match — this is the allowlist property (PR #200 review):
# the invariant is "Read/Grep/Glob only", not "nothing that looks like a write tool".
sed 's/^tools: Read, Grep, Glob$/tools: Read, Grep, Glob, WebFetch/' \
  "$AGENTDIR/contract-auditor.md" > "$TMP/agent-add-unlisted.md"
mut_fail "agent add-unlisted-tool (allowlist, not denylist)" agent_readonly_ok "$TMP/agent-add-unlisted.md"

# A reviewer that LOSES a read tool must trip too — the exact-set claim cuts both ways, so a
# silently narrowed binding (a reviewer that can no longer Grep) is surfaced as drift as well.
sed 's/^tools: Read, Grep, Glob$/tools: Read, Glob/' \
  "$AGENTDIR/spec-quality-auditor.md" > "$TMP/agent-drop-grep.md"
mut_fail "agent drop-read-tool (exact set, not superset)" agent_readonly_ok "$TMP/agent-drop-grep.md"

echo "reviewer-roster encoding tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
