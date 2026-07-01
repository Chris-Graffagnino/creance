#!/usr/bin/env bash
# Drift + fence backstop for the configurable review-pass set (T630 / issue #194; US8.AC4+AC5).
#
# T628 turned the skill-backed review passes ([code-review pass] / [security-review pass] /
# [craft-review pass]) into an owner-editable `## Review passes` table in the profile
# (.claude/PROJECT.md), and T629 made the selection surfaces (pr-review.md, the review
# standard, next-task.md §7 step 3) read "the profile's review-pass set" instead of a
# hardcoded enumeration. That move CREATES a silent-drop hole: once every surface reads the
# list, a pass omitted from the list — or mistyped, duplicated, or pointed at a law-bearing
# auditor — disappears from every surface with nothing else to catch it (the very failure the
# story exists to prevent — testing "a workflow runs a pass the list omits" cannot, since the
# workflow now reads the list). This test is the deterministic backstop (constitution P2/P3),
# the direct sibling of reviewer-roster.test.sh: same independent-oracle discipline, same
# flag-the-defect / pass-the-clean-control shape, same temp-copy mutation proof.
#
# Like reviewer-roster.test.sh, the oracle is HARDCODED here (EXPECTED_PASSES), not derived
# from the files it checks — a backstop that read its expectation from the profile or the
# adapter map could not catch a COORDINATED drop from both. Adding/removing a shipped pass is
# an intentional edit to the adapter map (README role->mechanism table), the profile row, AND
# this set (the ratchet that proves the change was deliberate).
#
# Sources pinned:
#   - the adapter role->mechanism table  .claude/README.md             (the shipped pass set)
#   - the profile review-pass rows       .claude/PROJECT.md            (US8.AC1)
#   - the §7 reviewer roster             .claude/workflow/gate-loop.md (AC5 fence source)
#
# Encodes US8.AC4 (five planted defects FAIL + clean roster PASS) and US8.AC5 (a row
# naming/disabling any roster auditor REJECTED + a skill-only list ACCEPTED):
#   AC4(1) enabled profile row with no adapter mapping  -> parity_no_orphan_ok trips
#   AC4(2) adapter-mapped pass with no profile row      -> parity_no_drop_ok trips
#   AC4(3) duplicate row for a pass role                -> dups_ok trips
#   AC4(4) off-enum condition / applies-to              -> enums_ok trips
#   AC4(5) off-domain pass (role): a bogus or disabled  -> roles_closed_ok trips (closes the
#          row not naming a canonical pass role             `pass (role)` column domain, so a
#                                                           disabled or non-pass-shaped row is
#                                                           visible too — parity_no_orphan_ok
#                                                           inspects ENABLED rows only)
#   AC5    a profile row naming a roster [reviewer]      -> fence_ok trips (rejected set
#          (acceptance/constitution/contract/spec-quality)   derived from the roster, so a
#                                                             future reviewer is fenced too)
# Plus: adapter_canonical_ok pins the adapter map to the oracle (coordinated-drift guard),
# and a self-wiring assertion proves CI verify actually RUNS this test (P2 "machinery proves
# it is live", same posture as autonomy-mode.test.sh). BSD/GNU-portable: POSIX ERE only, no
# awk regex intervals (shell-lint.sh denylist / the edit guard).
#
# Run: bash .claude/hooks/review-pass-roster.test.sh
set -u

DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROFILE="$DIR/PROJECT.md"               # owner-editable review-pass rows (US8.AC1)
ADAPTER="$DIR/README.md"                # adapter role->mechanism map (the shipped pass set)
ROSTER="$DIR/workflow/gate-loop.md"     # §7 reviewer roster (AC5 fence source)
CI="$DIR/../.github/workflows/ci.yml"   # self-wiring assertion target

pass=0
fail=0
ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); printf 'FAIL %s\n' "$1" >&2; }

for f in "$PROFILE" "$ADAPTER" "$ROSTER" "$CI"; do
  if [ ! -f "$f" ]; then
    echo "FAIL: required file missing: $f" >&2
    exit 1
  fi
done

# ── The canonical shipped skill-backed pass set — the INDEPENDENT oracle. ──
EXPECTED_PASSES="$(printf '%s\n' code-review security-review craft-review | sort)"

# ── parsers ───────────────────────────────────────────────────────────────────────────
# profile_rows <profile> — data rows of the `## Review passes` table (section-scoped; the
# header and the |---| separator dropped). A data row keeps a non-separator cell right after
# the first pipe, so the separator's all-dash first cell is the discriminator.
profile_rows() {
  awk '/^## Review passes/{f=1; next} /^## /{if (f) f=0} f' "$1" \
    | grep -E '^\|' \
    | grep -vE '^\|[[:space:]:-]+\|' \
    | grep -viE 'pass \(role\)'
}

# profile_pass_rows <profile> — "<role>|<enabled>" per row whose pass column names a
# `[<stem> pass]` role (a row naming something else — e.g. an AC5 auditor mutation — is not a
# pass and is handled by fence_ok, not here).
profile_pass_rows() {
  profile_rows "$1" | awk -F'|' '
    $2 ~ /[a-z-]+ pass/ {
      role=$2; en=$3
      match(role, /[a-z-]+ pass/); role=substr(role, RSTART, RLENGTH); sub(/ pass/, "", role)
      gsub(/[^a-z-]/, "", en)
      print role "|" en
    }'
}

# profile_passes <profile> — the set of pass roles in the table (sorted, deduped).
profile_passes() { profile_pass_rows "$1" | cut -d'|' -f1 | sort -u; }

# adapter_passes <adapter> — the skill-backed pass roles the adapter maps, scoped to the
# role->mechanism table so a stray prose mention elsewhere can't inflate the set.
adapter_passes() {
  awk '/^\| *Role *\|.*[Mm]echanism *\|/{f=1} /^###? /{f=0} f' "$1" \
    | grep -oE '\[[a-z-]+ pass\]' \
    | sed -E 's/\[([a-z-]+) pass\]/\1/' | sort -u
}

# roster_auditors <roster> — the §7 roster reviewer stems (the AC5 rejected set), DERIVED
# from the roster table so a future reviewer is fenced without editing this test.
roster_auditors() {
  grep -oE 'reviewers/[a-z-]+-auditor\.md' "$1" \
    | sed -E 's#reviewers/([a-z-]+-auditor)\.md#\1#' | sort -u
}

# ── site checks (each returns 0 = clean, nonzero = drift) ───────────────────────────────
# adapter_canonical_ok <adapter> — the adapter maps EXACTLY the canonical set.
adapter_canonical_ok() { [ "$(adapter_passes "$1")" = "$EXPECTED_PASSES" ]; }

# parity_no_drop_ok <profile> <adapter> — every adapter-mapped pass has a profile row
# (US8.AC4 defect 2: the silent-drop parity gap).
parity_no_drop_ok() {
  local pall p
  pall="$(profile_passes "$1")"
  while read -r p; do
    [ -n "$p" ] || continue
    printf '%s\n' "$pall" | grep -qxF "$p" || return 1
  done <<EOF
$(adapter_passes "$2")
EOF
  return 0
}

# parity_no_orphan_ok <profile> <adapter> — every ENABLED profile row's role is adapter-
# mapped (US8.AC4 defect 1: an enabled pass with no adapter mapping).
parity_no_orphan_ok() {
  local aset role en
  aset="$(adapter_passes "$2")"
  while IFS='|' read -r role en; do
    [ "$en" = "true" ] || continue
    printf '%s\n' "$aset" | grep -qxF "$role" || return 1
  done <<EOF
$(profile_pass_rows "$1")
EOF
  return 0
}

# dups_ok <profile> — each pass role appears in at most one row (US8.AC4 defect 3).
dups_ok() {
  local d
  d="$(profile_pass_rows "$1" | cut -d'|' -f1 | sort | uniq -d)"
  [ -z "$d" ]
}

# enums_ok <profile> — every pass row's enabled/condition/applies-to is on its closed enum
# (US8.AC4 defect 4).
enums_ok() {
  profile_rows "$1" | awk -F'|' '
    $2 ~ /[a-z-]+ pass/ {
      en=$3; cond=$4; app=$5
      gsub(/[^a-z-]/, "", en); gsub(/[^a-z-]/, "", cond); gsub(/[^a-z-]/, "", app)
      if (en != "true" && en != "false") bad=1
      if (cond != "always" && cond != "sensitive-diff") bad=1
      if (app != "gate" && app != "pr-review" && app != "both") bad=1
    }
    END { exit (bad ? 1 : 0) }'
}

# roles_closed_ok <profile> — every `## Review passes` data row names a canonical pass role
# (US8.AC4: the `pass (role)` column is a CLOSED domain — spec.md AC1 / PROJECT.template.md,
# "an off-enum value is a defect the review-pass roster test rejects"). Iterates EVERY row (not
# just the pass-shaped ones enums_ok inspects), so it catches a disabled off-domain pass
# (`[perf-review pass]`, which evades the enabled-only parity_no_orphan_ok) and a non-pass
# token (`[not-a-pass]`, which the `[<stem> pass]` filters skip entirely). A roster `[reviewer]`
# row is off-domain here too, and separately rejected by fence_ok (AC5).
roles_closed_ok() {
  local cell role
  while IFS= read -r cell; do
    [ -n "$cell" ] || continue
    role="$(printf '%s\n' "$cell" | grep -oE '\[[a-z-]+ pass\]' | sed -E 's/\[([a-z-]+) pass\]/\1/')"
    [ -n "$role" ] || return 1                                       # not a `[<stem> pass]` token
    printf '%s\n' "$EXPECTED_PASSES" | grep -qxF "$role" || return 1 # off the canonical set
  done <<EOF
$(profile_rows "$1" | awk -F'|' '{print $2}')
EOF
  return 0
}

# fence_ok <profile> <roster> — no profile row names a §7 roster auditor. The rejected set is
# DERIVED from the roster (US8.AC5: the maker≠checker / constitution-as-law boundary cannot be
# edited away through the profile, and a future reviewer is fenced too).
fence_ok() {
  local col a
  col="$(profile_rows "$1" | awk -F'|' '{print $2}')"
  while read -r a; do
    [ -n "$a" ] || continue
    printf '%s\n' "$col" | grep -qF "$a" && return 1
  done <<EOF
$(roster_auditors "$2")
EOF
  return 0
}

# ── live tree: every check must be clean (the pass-the-clean-control half) ───────────────
adapter_canonical_ok "$ADAPTER" && ok || bad "adapter map (README) does not map exactly the canonical pass set
     expected:
$(printf '%s\n' "$EXPECTED_PASSES" | sed 's/^/       /')
     got:
$(adapter_passes "$ADAPTER" | sed 's/^/       /')"

parity_no_drop_ok   "$PROFILE" "$ADAPTER" && ok || bad "AC4(2) parity: an adapter-mapped pass has no profile row (silent-drop gap)"
parity_no_orphan_ok "$PROFILE" "$ADAPTER" && ok || bad "AC4(1) parity: an enabled profile row's pass has no adapter mapping"
dups_ok             "$PROFILE"            && ok || bad "AC4(3) dups: a pass role appears in more than one profile row"
enums_ok            "$PROFILE"            && ok || bad "AC4(4) enums: a profile row has an off-enum enabled/condition/applies-to"
roles_closed_ok     "$PROFILE"            && ok || bad "AC4(5) role domain: a profile row names a non-canonical pass (role)"
fence_ok            "$PROFILE" "$ROSTER"  && ok || bad "AC5 fence: a profile row names a §7 roster auditor (not configurable here)"

# ── mutations: each planted defect must flip exactly its site check OK -> drift, on a temp
#    copy, so the flag-the-defect half is itself CI-verified (the reviewer-roster.test.sh
#    idiom). ──────────────────────────────────────────────────────────────────────────────
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mut_trips() { # mut_trips <name> <check-fn> [args...] — assert the check returns NONZERO.
  local name="$1"; shift
  if "$@"; then
    bad "mutation '$name' did NOT trip its check — the defect would go undetected"
  else
    ok
  fi
}

# insert_after_craft <src> <new-row> <dst> — append a row right after the craft-review table
# row (so it lands inside the `## Review passes` table, not after the section).
insert_after_craft() {
  awk -v row="$2" '
    { print }
    /^\|.*\[craft-review pass\]/ && !ins { print row; ins=1 }
  ' "$1" > "$3"
}

# AC4 defect 1 — an ENABLED pass row with no adapter mapping (perf-review is unmapped).
insert_after_craft "$PROFILE" '| `[perf-review pass]` | true | always | both |' "$TMP/d1.md"
mut_trips "AC4(1) enabled-orphan row" parity_no_orphan_ok "$TMP/d1.md" "$ADAPTER"

# AC4 defect 2 — an adapter-mapped pass (craft-review) dropped from the profile table.
grep -vE '^\|.*\[craft-review pass\]' "$PROFILE" > "$TMP/d2.md"
mut_trips "AC4(2) dropped adapter-mapped pass" parity_no_drop_ok "$TMP/d2.md" "$ADAPTER"

# AC4 defect 3 — a duplicate row for an existing pass role.
insert_after_craft "$PROFILE" '| `[code-review pass]` | true | always | both |' "$TMP/d3.md"
mut_trips "AC4(3) duplicate pass row" dups_ok "$TMP/d3.md"

# AC4 defect 4a — an off-enum condition value.
sed -E '/^\|.*\[craft-review pass\]/ s/\| always \|/| sometimes |/' "$PROFILE" > "$TMP/d4a.md"
mut_trips "AC4(4) off-enum condition" enums_ok "$TMP/d4a.md"

# AC4 defect 4b — an off-enum applies-to value.
sed -E '/^\|.*\[code-review pass\]/ s/\| both \|$/| everywhere |/' "$PROFILE" > "$TMP/d4b.md"
mut_trips "AC4(4) off-enum applies-to" enums_ok "$TMP/d4b.md"

# AC4 defect 5a — an off-domain but pass-shaped role (perf-review is not a shipped pass),
# DISABLED so it slips past the enabled-only parity_no_orphan_ok; roles_closed_ok is the check
# that makes it visible.
insert_after_craft "$PROFILE" '| `[perf-review pass]` | false | always | both |' "$TMP/d5a.md"
mut_trips "AC4(5) off-domain disabled pass role" roles_closed_ok "$TMP/d5a.md"

# AC4 defect 5b — a row whose pass column is not even `[<stem> pass]`-shaped.
insert_after_craft "$PROFILE" '| `[not-a-pass]` | false | always | both |' "$TMP/d5b.md"
mut_trips "AC4(5) non-pass-shaped row" roles_closed_ok "$TMP/d5b.md"

# AC5 — a profile row naming/disabling a roster auditor (constitution-auditor).
insert_after_craft "$PROFILE" '| `[constitution-auditor]` | false | always | both |' "$TMP/ac5.md"
mut_trips "AC5 roster-auditor row" fence_ok "$TMP/ac5.md" "$ROSTER"

# AC5 future-proofing — the rejected set is roster-DERIVED, not a hardcoded list of today's
# four: add a hypothetical reviewer to a ROSTER copy AND a matching profile row, then assert
# the fence (reading the patched roster) rejects it.
cp "$ROSTER" "$TMP/roster-plus.md"
printf '%s\n' '| `reviewers/security-auditor.md` | strong | `always` |' >> "$TMP/roster-plus.md"
insert_after_craft "$PROFILE" '| `[security-auditor]` | false | always | both |' "$TMP/ac5-future.md"
mut_trips "AC5 future roster reviewer fenced" fence_ok "$TMP/ac5-future.md" "$TMP/roster-plus.md"

# AC5 accept-control — a skill-only list (the real profile) is ACCEPTED (the both-directions
# requirement; the live fence_ok above already asserts this, restated as the explicit ACCEPT).
fence_ok "$PROFILE" "$ROSTER" && ok || bad "AC5 accept: the real skill-only profile list must be accepted"

# Coordinated-drift guard — drop a pass from the adapter map too; the hardcoded oracle still
# flags it (a backstop deriving its expectation from the adapter could not).
grep -vE '^\|.*\[craft-review pass\]' "$ADAPTER" > "$TMP/adapter-drop.md"
mut_trips "adapter coordinated drop" adapter_canonical_ok "$TMP/adapter-drop.md"

# ── self-wiring: CI verify must RUN this test (P2 machinery-proves-it-is-live) ───────────
# Lines belonging to the `verify:` job: from its 2-space-indented key to the next
# 2-space-indented job key (or EOF). No awk interval syntax (portable to BSD awk).
verify_steps() { awk '/^  [A-Za-z]/ { inblk = ($0 ~ /^  verify:/) } inblk { print }' "$CI"; }
# 0 iff an active (uncommented) `run: bash <path>` step invokes $1 within verify.
runs_in_verify() { verify_steps | grep -qE "^[[:space:]]*run:[[:space:]]+bash[[:space:]]+$1([[:space:]]|\$)"; }
if runs_in_verify '\.claude/hooks/review-pass-roster\.test\.sh'; then ok; else bad "verify must RUN review-pass-roster.test.sh (active run: step)"; fi

echo "review-pass-roster encoding tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
