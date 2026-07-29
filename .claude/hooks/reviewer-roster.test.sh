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
#   AC1 roster is exactly the canonical set and sole authority     → roster table + inventory
#   AC2 gate-loop.js mirrors it (keys, tiers, both conditionals     → JS
#       gated on their input flag)                                     projection + fixture
#   AC3 next-task.md §7 references the same paths + conditions      → prose projections + fixture
#   AC4 each roster reviewer has a workflow/reviewers/<name>.md spec → AC4 loop (all four)
#   AC5 each ADAPTER-BOUND reviewer's agents/<name>.md exists and    → AC5 loop (all four;
#       excludes edit tools (the spec-quality agent binding landed       each with a Claude
#       in T706/US2.AC5)                                                  agent)
#   AC6 retained drop/add/tier/condition/guard mutations FAIL       → AC6 block: temp-copy
#       the owning structural check                                      mutations re-run each
#                                                                         owning predicate
#   AC7 each adapter fallback [reviewer] map (next-task and         → shared fallback extractor,
#       review-response SKILL.md) names every roster reviewer, so      inventory + row/table fixtures
#       neither manual fallback can omit or shadow one                  (+ AC6 mutations)
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

# Exact authored shapes for the bounded structural surfaces. The canonical projections are
# independent expectations; the content digests below are reviewed change-detection ratchets.
# Every code-bearing row/bullet/use must match one of these complete forms, so equivalent
# syntax cannot hide an extra reviewer inside an owned surface.
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

# Fixed SHA-256 digests are compact ratchets for the complete authored source shapes. They
# deliberately do not use Git object IDs: an adopter may initialize the repository with
# SHA-1 or SHA-256 object format, while these content fixtures must remain identical. The JS
# fixture covers the complete executable adapter, including input normalization before
# canonical construction and the reviewer lifecycle after it. The row fixtures cover their
# complete Markdown rows, including plain prose outside code spans. A digest failure prints
# both values; review the authored-surface diff, then replace the expected value with the
# reported actual SHA-256 only when that change is intentional.
EXPECTED_JS_SOURCE_HASH='ce251820c1111fb71ed49582a0eacc8f42618c116abf6404aad9e0a8d7101941'
EXPECTED_PROSE_SOURCE_HASH='5a50b42503fe67233e80b9eec8d9b51b5fd7b4793abd6013112c79d897dcdd97'
EXPECTED_SKILL_ROW_HASH='a8d05822012875516bbb2890407f0bc5fc5f873c0acb353098b8170b09b08272'
EXPECTED_REVIEW_RESPONSE_ROW_HASH='057dfb4bfd25baeddf175032965174a54224ddddf25a3ce1e79d8790abc27f2d'
EXPECTED_SKILL_TABLE_HASH='326efa56f2ca1bdc8458af83ea191dd02347bb963ed21ca6c7e81efe16e837f0'
EXPECTED_REVIEW_RESPONSE_TABLE_HASH='2266ec36fa8801b85e1fc90401623131c8bbfdce5387970f6a237ceb5b93fe5c'

content_hash() {
  python3 -c 'import hashlib, sys; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())'
}

role_mapping_table() {
  awk '
    /^\| Neutral role/ {
      in_table=1
    }
    in_table && /^\|/ {
      print
      next
    }
    in_table {
      exit
    }
  ' "$1"
}

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

# Inventory every concrete reviewer-spec path across the neutral gate document, not only
# inside the first roster table. A second roster table or an out-of-table dispatch path would
# create another reviewer authority and must not be invisible to the table parser.
all_roster_paths() {
  grep -oE '`reviewers/[^`/[:space:]]+\.md`' "$1" \
    | sed 's#^`reviewers/##; s#\.md`$##' \
    | sort
}

roster_table_projection_ok() {
  [ "$(parse_roster "$1")" = "$EXPECTED" ] &&
    [ "$(roster_rows "$1")" = "$EXPECTED_ROSTER_ROWS" ]
}

roster_inventory_ok() {
  [ "$(all_roster_paths "$1")" = "$EXPECTED_KEYS" ]
}

# AC1 — gate-loop.md has one roster authority and it is EXACTLY the canonical set
# (membership + tier + condition, with no extra reviewer path elsewhere in the document).
roster_ok() {
  roster_table_projection_ok "$1" &&
    roster_inventory_ok "$1"
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

# AC2 — keep the semantic projection and the authored-source ratchet separate so retained
# mutations prove which layer fired. The parser owns membership + tier + guard relationships;
# the digest owns unparsed source-shape changes around input handling and reviewer lifecycle.
js_projection_ok() {
  [ "$(parse_js "$1")" = "$EXPECTED_JS" ]
}

js_fixture_ok() {
  [ "$(content_hash < "$1")" = "$EXPECTED_JS_SOURCE_HASH" ]
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

# AC3 — keep each authored projection independently falsifiable. The complete-card digest
# catches instructions outside the structured reviewer bullets; it does not stand in for
# proving that the path, condition, or bullet extractors remain live.
prose_paths_ok() {
  [ "$(prose_paths "$1")" = "$EXPECTED_KEYS" ]
}

prose_dispatch_projection_ok() {
  [ "$(parse_prose "$1")" = "$EXPECTED_PROSE" ]
}

prose_bullets_ok() {
  [ "$(prose_bullets "$1")" = "$EXPECTED_PROSE_BULLETS" ]
}

prose_pointers_ok() {
  local f="$1" s r=0
  s="$(section7 "$f" | tr -s '[:space:]' ' ')"
  printf '%s' "$s" | grep -qF "reviewer roster" || r=1
  printf '%s' "$s" | grep -qF "gate-loop.md" || r=1
  return $r
}

prose_projection_ok() {
  prose_paths_ok "$1" &&
    prose_dispatch_projection_ok "$1" &&
    prose_bullets_ok "$1" &&
    prose_pointers_ok "$1"
}

prose_fixture_ok() {
  [ "$(content_hash < "$1")" = "$EXPECTED_PROSE_SOURCE_HASH" ]
}

# AC7 — the adapter fallback maps name every roster reviewer's agent. In either documented
#       fallback (Workflow tool absent → the operator dispatches reviewers via the Agent
#       tool, following the map + §7), a missing reviewer silently under-dispatches the gate
#       — the same "a reviewer fell out" drift class the structural mirrors pin. The
#       next-task map drifted exactly this way once: it still listed only the original three
#       after the spec-quality reviewer landed (PR #186 review). These maps carry agent NAMES
#       only; tier and condition stay single-sourced in the roster + §7, so both sites are
#       pinned on MEMBERSHIP alone (EXPECTED_KEYS), not tier/condition.
fallback_config() {
  case "$1" in
    next-task)
      FALLBACK_MARKER='**[reviewer]**'
      FALLBACK_NEEDLE='| **[reviewer]** |'
      FALLBACK_PREFIX='^[[:space:]]*the[[:space:]]+'
      FALLBACK_SHAPE=' subagents (`.claude/agents/`), dispatched'
      ;;
    review-response)
      FALLBACK_MARKER='**[reviewer]s / [orchestrated run]**'
      FALLBACK_NEEDLE='| **[reviewer]s / [orchestrated run]**'
      FALLBACK_PREFIX='^.*; or the[[:space:]]+'
      FALLBACK_SHAPE=' subagents (`.claude/agents/`) dispatched'
      ;;
    *)
      return 1
      ;;
  esac
}

fallback_row() {
  local file="$1" kind="$2"
  fallback_config "$kind" || return 1
  awk -F'|' -v marker="$FALLBACK_MARKER" -v prefix="$FALLBACK_PREFIX" '
    index($2, marker) {
      map=$3
      sub(prefix, "", map)
      print map
    }
  ' "$file"
}

fallback_full_row() {
  local file="$1" kind="$2"
  fallback_config "$kind" || return 1
  awk -v needle="$FALLBACK_NEEDLE" 'index($0, needle) { print }' "$file"
}

fallback_map() {
  fallback_row "$1" "$2" \
    | sed 's/[[:space:]]*subagents.*//' \
    | grep -oE '`[^`]+`' \
    | tr -d '`' \
    | sort
}

fallback_shape_ok() {
  local file="$1" kind="$2"
  fallback_config "$kind" || return 1
  case "$(fallback_row "$file" "$kind")" in
    *"$FALLBACK_SHAPE"*) return 0 ;;
    *) return 1 ;;
  esac
}

fallback_spans() {
  fallback_row "$1" "$2" | grep -oE '`[^`]+`' | sort
}

# Compare every reviewer-like agent identifier in the skill with those in the declared
# fallback row. This catches a second out-of-table dispatch/skip instruction without freezing
# unrelated skill prose. Occurrence counts are retained, so repeating a canonical reviewer
# outside the row is visible as well as introducing a new reviewer name.
reviewer_names() {
  grep -oE '[a-z0-9-]+-(auditor|reviewer)' | sort
}

fallback_inventory_ok() {
  [ "$(reviewer_names < "$1")" = "$(fallback_row "$1" "$2" | reviewer_names)" ]
}

fallback_projection_ok() {
  [ "$(fallback_map "$1" "$2")" = "$EXPECTED_KEYS" ] &&
    fallback_shape_ok "$1" "$2" &&
    [ "$(fallback_spans "$1" "$2")" = "$3" ]
}

fallback_row_fixture_ok() {
  [ "$(fallback_full_row "$1" "$2" | content_hash)" = "$3" ]
}

fallback_table_fixture_ok() {
  [ "$(role_mapping_table "$1" | content_hash)" = "$2" ]
}

skill_map() { fallback_map "$1" next-task; }
review_response_map() { fallback_map "$1" review-response; }
skill_projection_ok() {
  fallback_projection_ok "$1" next-task "$EXPECTED_SKILL_SPANS"
}
review_response_projection_ok() {
  fallback_projection_ok "$1" review-response "$EXPECTED_REVIEW_RESPONSE_SPANS"
}
skill_inventory_ok() { fallback_inventory_ok "$1" next-task; }
review_response_inventory_ok() { fallback_inventory_ok "$1" review-response; }
fallback_row_fixture_ok_next_task() {
  fallback_row_fixture_ok "$1" next-task "$EXPECTED_SKILL_ROW_HASH"
}
fallback_row_fixture_ok_review_response() {
  fallback_row_fixture_ok "$1" review-response "$EXPECTED_REVIEW_RESPONSE_ROW_HASH"
}
fallback_table_fixture_ok_next_task() {
  fallback_table_fixture_ok "$1" "$EXPECTED_SKILL_TABLE_HASH"
}
fallback_table_fixture_ok_review_response() {
  fallback_table_fixture_ok "$1" "$EXPECTED_REVIEW_RESPONSE_TABLE_HASH"
}

check_digest() { # check_digest <label> <surface> <expected> <actual>
  if [ "$3" = "$4" ]; then
    ok
  else
    bad "$1: $2 changed
     expected SHA-256: $3
     actual SHA-256:   $4
     review that authored-surface diff, then replace its EXPECTED_*_HASH value with the
     reported actual digest only when the change is intentional"
  fi
}

# ── Run the structural surface checks against the live tree ─────────────────────────
roster_ok "$GL" \
  && ok \
  || bad "AC1 roster: gate-loop.md roster is not exactly the canonical set
     expected:
$(printf '%s\n' "$EXPECTED" | sed 's/^/       /')
     got table:
$(parse_roster "$GL" | sed 's/^/       /')
     all reviewer paths:
$(all_roster_paths "$GL" | sed 's/^/       /')"

js_projection_ok "$JS" \
  && ok \
  || bad "AC2 js projection: gate-loop.js reviewers array/push does not mirror the roster
     (expected spec=cheap, constitution=strong, contract=cheap gated on dispatchContract,
     spec-quality=strong gated on dispatchSpec)"

check_digest "AC2 js fixture" "complete gate-loop.js source" \
  "$EXPECTED_JS_SOURCE_HASH" "$(content_hash < "$JS")"

prose_projection_ok "$NT" \
  && ok \
  || bad "AC3 prose projection: next-task.md §7 step 2 does not reference the roster's four specs
     with conditions always / always / contract-conditional / spec-conditional, or omits
     the roster pointer"

check_digest "AC3 prose fixture" "complete §7 stage card" \
  "$EXPECTED_PROSE_SOURCE_HASH" "$(content_hash < "$NT")"

skill_projection_ok "$SK" \
  && ok \
  || bad "AC7 skill-map: next-task SKILL.md [reviewer] map does not name exactly the roster
     reviewers (a reviewer would silently drop off the manual-fallback dispatch)
     expected:
$(printf '%s\n' "$EXPECTED_KEYS" | sed 's/^/       /')
     got:
$(skill_map "$SK" | sed 's/^/       /')"

skill_inventory_ok "$SK" \
  && ok \
  || bad "AC7 skill inventory: next-task SKILL.md contains a reviewer-like agent identifier
     outside its declared [reviewer] fallback row"

check_digest "AC7 skill row fixture" "next-task [reviewer] row" \
  "$EXPECTED_SKILL_ROW_HASH" \
  "$(fallback_full_row "$SK" next-task | content_hash)"
check_digest "AC7 skill table fixture" "next-task Neutral role table" \
  "$EXPECTED_SKILL_TABLE_HASH" \
  "$(role_mapping_table "$SK" | content_hash)"

review_response_projection_ok "$RR" \
  && ok \
  || bad "AC7 review-response-map: review-response SKILL.md fallback map does not name
     exactly the roster reviewers (a reviewer would silently drop off its §7 re-gate)
     expected:
$(printf '%s\n' "$EXPECTED_KEYS" | sed 's/^/       /')
     got:
$(review_response_map "$RR" | sed 's/^/       /')"

review_response_inventory_ok "$RR" \
  && ok \
  || bad "AC7 review-response inventory: review-response SKILL.md contains a reviewer-like
     agent identifier outside its declared re-gate fallback row"

check_digest "AC7 review-response row fixture" "review-response re-gate row" \
  "$EXPECTED_REVIEW_RESPONSE_ROW_HASH" \
  "$(fallback_full_row "$RR" review-response | content_hash)"
check_digest "AC7 review-response table fixture" "review-response Neutral role table" \
  "$EXPECTED_REVIEW_RESPONSE_TABLE_HASH" \
  "$(role_mapping_table "$RR" | content_hash)"

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
#       are proven by js_projection_ok + gate-loop.test.js.)
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
mut_fail "roster parser drop-reviewer" roster_table_projection_ok "$TMP/gl-drop.md"

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
mut_fail "roster parser add-unlisted-reviewer" roster_table_projection_ok "$TMP/gl-add-unlisted.md"

# Roster site — flip a tier (spec cheap → strong).
sed '/reviewers\/spec-auditor\.md/ s/| cheap |/| strong |/' "$GL" > "$TMP/gl-tier.md"
mut_fail "roster parser flip-tier" roster_table_projection_ok "$TMP/gl-tier.md"

# Roster site — flip a condition (contract dispatch-contract → always).
sed '/reviewers\/contract-auditor\.md/ s/dispatch-contract/always/' "$GL" > "$TMP/gl-cond.md"
mut_fail "roster parser flip-condition" roster_table_projection_ok "$TMP/gl-cond.md"

# Roster site — malformed digit-bearing tier/condition cells must not normalize back to
# their canonical values. Only Markdown formatting is stripped from the source cells.
sed '/reviewers\/spec-auditor\.md/ s/| cheap |/| che2ap |/' \
  "$GL" > "$TMP/gl-malformed-tier.md"
mut_fail "roster parser malformed-tier" roster_table_projection_ok "$TMP/gl-malformed-tier.md"

sed '/reviewers\/contract-auditor\.md/ s/dispatch-contract/dispatch2-contract/' \
  "$GL" > "$TMP/gl-malformed-condition.md"
mut_fail "roster parser malformed-condition" roster_table_projection_ok "$TMP/gl-malformed-condition.md"

# Roster site — the reviewer spec must be the complete code-span path, not a canonical
# substring inside a wrong directory name.
sed 's#`reviewers/spec-auditor.md`#`not-reviewers/spec-auditor.md`#' \
  "$GL" > "$TMP/gl-wrong-path.md"
mut_fail "roster parser wrong-path-prefix" roster_table_projection_ok "$TMP/gl-wrong-path.md"

# Roster site — a second reviewer path hidden in the acceptance label's parenthetical
# is still an unexpected reviewer-bearing code span, even though the first path is valid.
sed 's#`reviewers/spec-auditor.md` (acceptance)#`reviewers/spec-auditor.md` (acceptance; `reviewers/security2-reviewer.md`)#' \
  "$GL" > "$TMP/gl-add-parenthetical-path.md"
mut_fail "roster parser add-parenthetical-reviewer-path" roster_table_projection_ok "$TMP/gl-add-parenthetical-path.md"

# Neutral-document inventory — a second table or an out-of-table reviewer path must not
# create another dispatch authority beyond the canonical roster.
awk '
  { print }
  END {
    print ""
    print "| Reviewer spec | Tier | Dispatch condition |"
    print "|---|---|---|"
    print "| `reviewers/security2-reviewer.md` | cheap | `always` |"
  }
' "$GL" > "$TMP/gl-second-roster.md"
mut_fail "roster inventory second-table-reviewer" roster_inventory_ok "$TMP/gl-second-roster.md"

awk '
  { print }
  END {
    print "Also dispatch `reviewers/security2-reviewer.md` every round."
  }
' "$GL" > "$TMP/gl-outside-reviewer.md"
mut_fail "roster inventory out-of-table-reviewer" roster_inventory_ok "$TMP/gl-outside-reviewer.md"

# JS site (gate-loop.js) — drop the gated contract push.
grep -vF "reviewers.push({ key: 'contract-auditor'" "$JS" > "$TMP/js-drop.js"
mut_fail "js parser drop-reviewer" js_projection_ok "$TMP/js-drop.js"

# JS site — add an unlisted reviewer to the unconditional array.
awk '
  /key: '\''constitution-auditor'\''/ {
    print
    print "  { key: '\''security-reviewer'\'', model: input.cheapModel, tier: '\''cheap'\'' },"
    next
  }
  { print }
' "$JS" > "$TMP/js-add-unlisted.js"
mut_fail "js parser add-unlisted-reviewer" js_projection_ok "$TMP/js-add-unlisted.js"

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
mut_fail "js parser add-opaque-spread" js_projection_ok "$TMP/js-add-spread.js"

# JS site — add an unlisted reviewer after verdict storage is declared but before the
# roster is consumed. The inventory must remain open through `let pending = reviewers`.
awk '
  /^let pending = reviewers;$/ {
    print "reviewers.push({ key: '\''security2-reviewer'\'', model: input.cheapModel, tier: '\''cheap'\'' });"
  }
  { print }
' "$JS" > "$TMP/js-add-late-reviewer.js"
mut_fail "js parser add-late-reviewer" js_projection_ok "$TMP/js-add-late-reviewer.js"

# JS site — a task-specific pre-construction input rewrite can change the effective
# condition while leaving the canonical guards untouched. The complete-source fixture
# must cover input acquisition/normalization as well as the downstream lifecycle.
awk '
  /^const reviewers = \[$/ {
    print "if (input.taskId === '\''UNTESTED'\'') input.dispatchContract = true;"
  }
  { print }
' "$JS" > "$TMP/js-rewrite-condition-input.js"
mut_fail "js fixture rewrite-condition-input-before-construction" js_fixture_ok "$TMP/js-rewrite-condition-input.js"

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
mut_fail "js fixture add-post-consumption-reviewer" js_fixture_ok "$TMP/js-add-post-consumption-reviewer.js"

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
mut_fail "js fixture parenthesized-post-consumption-alias" js_fixture_ok "$TMP/js-parenthesized-alias.js"

awk '
  { print }
  /^let pending = reviewers;$/ {
    print "pending['\''push'\'']({ key: '\''security2-reviewer'\'', model: input.cheapModel, tier: '\''cheap'\'' });"
  }
' "$JS" > "$TMP/js-bracket-push.js"
mut_fail "js fixture bracket-push-post-consumption" js_fixture_ok "$TMP/js-bracket-push.js"

awk '
  { print }
  /^let pending = reviewers;$/ {
    print "if (input.taskId === '\''UNTESTED'\'') pending = [...pending, { key: '\''security2-reviewer'\'', model: input.cheapModel, tier: '\''cheap'\'' }];"
  }
' "$JS" > "$TMP/js-one-line-reassignment.js"
mut_fail "js fixture one-line-post-consumption-reassignment" js_fixture_ok "$TMP/js-one-line-reassignment.js"

# JS site — `failing` is the next-round roster, and callback `r` values are reviewer
# objects. Mutating either path changes reviewer membership even without naming pending
# on the mutation line; the complete lifecycle fixture must reject both.
awk '
  { print }
  /^  const failing = pending\.filter/ {
    print "  if (input.taskId === '\''UNTESTED'\'') {"
    print "    failing.push({ key: '\''security2-reviewer'\'', model: input.cheapModel, tier: '\''cheap'\'' });"
    print "  }"
  }
' "$JS" > "$TMP/js-mutate-failing.js"
mut_fail "js fixture mutate-next-round-failing-roster" js_fixture_ok "$TMP/js-mutate-failing.js"

awk '
  { print }
  /^  pending\.forEach\(\(r, i\) => \{$/ && !inserted {
    print "    if (input.taskId === '\''UNTESTED'\'') r.key = '\''security2-reviewer'\'';"
    inserted=1
  }
' "$JS" > "$TMP/js-mutate-callback-reviewer.js"
mut_fail "js fixture mutate-callback-reviewer-key" js_fixture_ok "$TMP/js-mutate-callback-reviewer.js"

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
mut_fail "js fixture reassign-post-consumption-reviewers" js_fixture_ok "$TMP/js-reassign-post-consumption.js"

awk '
  { print }
  /^let pending = reviewers;$/ {
    print "if (input.taskId === '\''UNTESTED'\'') {"
    print "  pending[pending.length] = { key: '\''security2-reviewer'\'', model: input.cheapModel, tier: '\''cheap'\'' };"
    print "}"
  }
' "$JS" > "$TMP/js-index-post-consumption.js"
mut_fail "js fixture index-post-consumption-reviewers" js_fixture_ok "$TMP/js-index-post-consumption.js"

# JS site — flip a tier (spec cheap → strong).
sed "s/key: 'spec-auditor', model: input.cheapModel, tier: 'cheap'/key: 'spec-auditor', model: input.cheapModel, tier: 'strong'/" "$JS" > "$TMP/js-tier.js"
mut_fail "js parser flip-tier" js_projection_ok "$TMP/js-tier.js"

# Prose site (next-task.md) — drop a reviewer reference.
grep -vF 'reviewers/spec-auditor.md' "$NT" > "$TMP/nt-drop.md"
mut_fail "prose path parser drop-reviewer" prose_paths_ok "$TMP/nt-drop.md"

# Prose site — add an unlisted always-dispatched reviewer bullet.
awk '
  /^3\. Run/ {
    print "   - The **security [reviewer]** (`workflow/reviewers/security2-reviewer.md`) — **always**."
  }
  { print }
' "$NT" > "$TMP/nt-add-unlisted.md"
mut_fail "prose dispatch parser add-unlisted-reviewer" prose_dispatch_projection_ok "$TMP/nt-add-unlisted.md"

# Prose site — an unexpected dispatch instruction written as an unformatted bullet has
# no canonical path token for the projection parser to inventory. The complete stage-card
# source fixture must still reject it.
awk '
  /^3\. Run/ {
    print "   - Dispatch security2-reviewer — **always**."
  }
  { print }
' "$NT" > "$TMP/nt-add-plain-dispatch-bullet.md"
mut_fail "prose fixture add-plain-dispatch-bullet" prose_fixture_ok "$TMP/nt-add-plain-dispatch-bullet.md"

# Prose site — reject a canonical reviewer basename embedded in a wrong path prefix and
# any extra dispatch-* condition token alongside the canonical condition.
sed 's#workflow/reviewers/spec-auditor.md#workflow/not-reviewers/spec-auditor.md#' \
  "$NT" > "$TMP/nt-wrong-path.md"
mut_fail "prose path parser wrong-path-prefix" prose_paths_ok "$TMP/nt-wrong-path.md"

sed '/roster'\''s `dispatch-contract` condition:/ s/condition:/condition plus `dispatch-security`:/' \
  "$NT" > "$TMP/nt-add-condition.md"
mut_fail "prose dispatch parser add-unlisted-condition" prose_dispatch_projection_ok "$TMP/nt-add-condition.md"

# Prose site — exact bullet text also rejects semantic condition drift written as
# ordinary prose rather than a dispatch-* code token.
sed '/monetization, or the data model\./ s/$/ The dispatch-security condition also applies./' \
  "$NT" > "$TMP/nt-add-plain-condition.md"
mut_fail "prose bullet fixture add-plain-condition" prose_bullets_ok "$TMP/nt-add-plain-condition.md"

# ── The spec-quality reviewer (T703) is pinned on each structural projection it appears in:
#    dropping its row/push/reference must trip that projection's check. ──

# Roster site — drop the spec-quality row.
grep -vF 'reviewers/spec-quality-auditor.md' "$GL" > "$TMP/gl-drop-sq.md"
mut_fail "roster parser drop-spec-quality" roster_table_projection_ok "$TMP/gl-drop-sq.md"

# JS site — drop the gated spec-quality push.
grep -vF "reviewers.push({ key: 'spec-quality-auditor'" "$JS" > "$TMP/js-drop-sq.js"
mut_fail "js parser drop-spec-quality" js_projection_ok "$TMP/js-drop-sq.js"

# Prose site — drop the spec-quality reviewer reference.
grep -vF 'reviewers/spec-quality-auditor.md' "$NT" > "$TMP/nt-drop-sq.md"
mut_fail "prose path parser drop-spec-quality" prose_paths_ok "$TMP/nt-drop-sq.md"

# Skill-map site (next-task SKILL.md) — drop the spec-quality agent from the [reviewer]
# map (the exact PR #186 drift: the map listed only the original three). Removing the name
# leaves the map enumerating three reviewers, so the shared fallback projection must trip.
sed 's/spec-quality-auditor//g' "$SK" > "$TMP/sk-drop-sq.md"
mut_fail "skill parser drop-spec-quality" skill_projection_ok "$TMP/sk-drop-sq.md"

# Skill-map site — add an unlisted, digit-bearing fallback agent outside the unenforced
# `*-auditor` convention. Membership-only exactness must reject it too.
sed 's#`spec-auditor` /#`spec-auditor` / `security2-reviewer` /#' \
  "$SK" > "$TMP/sk-add-unlisted.md"
mut_fail "skill parser add-unlisted-reviewer" skill_projection_ok "$TMP/sk-add-unlisted.md"

sed 's#subagents (`.claude/agents/`)#subagents plus `security2-reviewer` (`.claude/agents/`)#' \
  "$SK" > "$TMP/sk-add-after-subagents.md"
mut_fail "skill parser add-reviewer-after-subagents" skill_projection_ok "$TMP/sk-add-after-subagents.md"

awk '
  index($0, "| **[reviewer]** |") {
    sub(/[[:space:]]*\|[[:space:]]*$/, "; also dispatch `security2-reviewer` |")
    print
    next
  }
  { print }
' "$SK" > "$TMP/sk-add-row-tail.md"
mut_fail "skill parser add-reviewer-at-row-tail" skill_projection_ok "$TMP/sk-add-row-tail.md"

sed 's/dispatched via the Agent tool/dispatched with security2-reviewer via the Agent tool/' \
  "$SK" > "$TMP/sk-add-plain-reviewer.md"
mut_fail "skill row fixture add-plain-reviewer" \
  "fallback_row_fixture_ok_next_task" "$TMP/sk-add-plain-reviewer.md"

awk '
  { print }
  index($0, "| **[reviewer]** |") {
    print "| *(continued)* | When Workflow is unavailable, also dispatch security2-reviewer |"
  }
' "$SK" > "$TMP/sk-add-continuation-row.md"
mut_fail "skill inventory add-reviewer-continuation-row" skill_inventory_ok "$TMP/sk-add-continuation-row.md"

# An out-of-table instruction is a second mapping authority even though the declared row
# remains unchanged.
awk '
  { print }
  END {
    print "When Workflow is unavailable, also dispatch the `security2-reviewer` subagent at §7."
  }
' "$SK" > "$TMP/sk-add-outside-dispatch.md"
mut_fail "skill inventory add-outside-dispatch" skill_inventory_ok "$TMP/sk-add-outside-dispatch.md"

# The table fixture has its own falsification: a non-reviewer row wording change should
# trip the table digest, not masquerade as reviewer-membership drift.
awk '
  index($0, "| **[headless run]** |") {
    sub(/[[:space:]]*\|[[:space:]]*$/, " (fixture mutation) |")
  }
  { print }
' "$SK" > "$TMP/sk-change-non-reviewer-row.md"
mut_fail "skill table fixture change-non-reviewer-row" \
  fallback_table_fixture_ok_next_task "$TMP/sk-change-non-reviewer-row.md"

# review-response fallback map — both omission and a digit-bearing unexpected reviewer
# must fail exact membership just as they do in the primary next-task fallback map.
sed 's# / `spec-quality-auditor` subagents# subagents#' \
  "$RR" > "$TMP/rr-drop-sq.md"
mut_fail "review-response parser drop-spec-quality" review_response_projection_ok "$TMP/rr-drop-sq.md"

sed 's#`spec-quality-auditor` subagents#`spec-quality-auditor` / `security2-reviewer` subagents#' \
  "$RR" > "$TMP/rr-add-unlisted.md"
mut_fail "review-response parser add-unlisted-reviewer" review_response_projection_ok "$TMP/rr-add-unlisted.md"

sed 's#subagents (`.claude/agents/`)#subagents plus `security2-reviewer` (`.claude/agents/`)#' \
  "$RR" > "$TMP/rr-add-after-subagents.md"
mut_fail "review-response parser add-reviewer-after-subagents" review_response_projection_ok "$TMP/rr-add-after-subagents.md"

awk '
  index($0, "| **[reviewer]s / [orchestrated run]**") {
    sub(/[[:space:]]*\|[[:space:]]*$/, "; also dispatch `security2-reviewer` |")
    print
    next
  }
  { print }
' "$RR" > "$TMP/rr-add-row-tail.md"
mut_fail "review-response parser add-reviewer-at-row-tail" review_response_projection_ok "$TMP/rr-add-row-tail.md"

sed 's/) dispatched via the Agent tool/) dispatched with security2-reviewer via the Agent tool/' \
  "$RR" > "$TMP/rr-add-plain-reviewer.md"
mut_fail "review-response row fixture add-plain-reviewer" \
  "fallback_row_fixture_ok_review_response" "$TMP/rr-add-plain-reviewer.md"

awk '
  { print }
  index($0, "| **[reviewer]s / [orchestrated run]**") {
    print "| *(continued)* | When Workflow is unavailable, also dispatch security2-reviewer |"
  }
' "$RR" > "$TMP/rr-add-continuation-row.md"
mut_fail "review-response inventory add-reviewer-continuation-row" \
  review_response_inventory_ok "$TMP/rr-add-continuation-row.md"

awk '
  { print }
  END {
    print "When Workflow is unavailable, also dispatch the `security2-reviewer` subagent at §7."
  }
' "$RR" > "$TMP/rr-add-outside-dispatch.md"
mut_fail "review-response inventory add-outside-dispatch" \
  review_response_inventory_ok "$TMP/rr-add-outside-dispatch.md"

awk '
  index($0, "| **[headless run]** |") {
    sub(/[[:space:]]*\|[[:space:]]*$/, " (fixture mutation) |")
  }
  { print }
' "$RR" > "$TMP/rr-change-non-reviewer-row.md"
mut_fail "review-response table fixture change-non-reviewer-row" \
  fallback_table_fixture_ok_review_response "$TMP/rr-change-non-reviewer-row.md"

# ── A gated push must stay STRUCTURALLY under its `if (input.dispatchX)` guard, not merely
#    appear somewhere in the file. Lifting one out makes its reviewer unconditional — a diff
#    touching no contract/spec would still dispatch it, breaking US2.AC2. Each mutation swaps
#    a guard line with the push beneath it (the push now runs unconditionally); BOTH the push
#    string and the `if (input.dispatchX)` string survive, so every "appears somewhere" check
#    stays green and the exact JS projection must report the guard relationship as unguarded. ──

# JS site — lift the contract push out from under its guard (swap guard ↔ push).
awk '/if \(input\.dispatchContract\)/ { g=$0; getline b; print b; print g; next } { print }' \
  "$JS" > "$TMP/js-ungate-contract.js"
mut_fail "js parser ungate-contract" js_projection_ok "$TMP/js-ungate-contract.js"

# JS site — lift the spec-quality push out from under its guard (swap guard ↔ push).
awk '/if \(input\.dispatchSpec\)/ { g=$0; getline b; print b; print g; next } { print }' \
  "$JS" > "$TMP/js-ungate-sq.js"
mut_fail "js parser ungate-spec-quality" js_projection_ok "$TMP/js-ungate-sq.js"

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
