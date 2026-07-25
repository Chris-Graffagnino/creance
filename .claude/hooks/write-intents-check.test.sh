#!/usr/bin/env bash
# write-intents-check.test.sh — two-sided falsification tests for the write-intent
# contract check (T636/#232, hardened by #284; constitution P3).
#
# Planted positives prove the check FAILs on each defect class it claims to catch
# (a check with no planted positive is not trusted); the passing control proves the
# live tree satisfies the contract. Fixtures are built in a temp dir and injected
# through the check's WIC_* surface overrides — the check script runs unmodified.
set -u
export LC_ALL=C

CHECK=".claude/hooks/write-intents-check.sh"
pass=0
fail=0

expect() { # expect <want-exit> <name> [WIC_VAR=val ...]
  local want="$1" name="$2" got=0
  shift 2
  ( env "$@" bash "$CHECK" >/dev/null 2>&1 ) || got=$?
  if [ "$got" -eq "$want" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL %-60s want exit %s, got %s\n' "$name" "$want" "$got" >&2
  fi
}

expect_msg() { # expect_msg <name> <needle> [WIC_VAR=val ...]
  local name="$1" needle="$2" out
  shift 2
  out="$(env "$@" bash "$CHECK" 2>&1)" || true
  if printf '%s' "$out" | grep -qF "$needle"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL %-60s diagnostic missing %s\n' "$name" "$needle" >&2
  fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- Fixture surfaces: a minimal contract / profile / adapter / neutral-doc tree
# that satisfies the check (the fixture control), then per-case mutations.
mkdir -p "$TMP/workflow"

cat > "$TMP/contract.md" <<'EOF'
### Write intents (safe outputs)
| Intent role | Inputs | Outputs | Constraints |
|------|--------|---------|-------------|
| **[create-issue output]** | t | o | c |
| **[add-pr-comment output]** | t | o | c |
EOF

cat > "$TMP/profile.md" <<'EOF'
## Write intents
| workflow | allowed intents |
|---|---|
| `next-task` | `[create-issue output]`, `[add-pr-comment output]` |
| `pr-review` | `[add-pr-comment output]` |
| `triage` | none |
EOF

cat > "$TMP/adapter.md" <<'EOF'
### Write-intent mappings (the safe-output roles)
| Intent role | Mechanism |
|------|----------------------|
| **[create-issue output]** | mechanism A |
| **[add-pr-comment output]** | mechanism B |
EOF

cat > "$TMP/workflow/clean.md" <<'EOF'
A neutral doc: post the plan via the [add-pr-comment output] intent.
Local git commit / git push guidance stays under the git exception.
EOF

FIX=(WIC_CONTRACT="$TMP/contract.md" WIC_PROFILE="$TMP/profile.md" \
     WIC_ADAPTER="$TMP/adapter.md" WIC_WORKFLOW_DIR="$TMP/workflow" \
     WIC_REQUIRED_WORKFLOWS="next-task pr-review triage")

# --- Controls (the PASS half)
expect 0 "live tree passes (real surfaces, real declarations)"
expect 0 "fixture control passes" "${FIX[@]}"

# --- Named-section scoping: row-shaped prose/tables elsewhere are not contract data
cat > "$TMP/contract-section-scope.md" <<'EOF'
### Write intents (safe outputs)
| Intent role | Inputs | Outputs | Constraints |
|------|--------|---------|-------------|
| **[create-issue output]** | t | o | c |
| **[add-pr-comment output]** | t | o | c |

### Worked example
| **[shadow-write output]** | not part of the closed family |
EOF
cat > "$TMP/profile-section-scope.md" <<'EOF'
## Write intents
| workflow | allowed intents |
|---|---|
| `next-task` | `[create-issue output]`, `[add-pr-comment output]` |
| `pr-review` | `[add-pr-comment output]` |
| `triage` | none |

## Worked example
| `shadow-workflow` | `[shadow-write output]` |
EOF
cat > "$TMP/adapter-section-scope.md" <<'EOF'
### Write-intent mappings (the safe-output roles)
| Intent role | Mechanism |
|------|----------------------|
| **[create-issue output]** | mechanism A |
| **[add-pr-comment output]** | mechanism B |

### Worked example
| **[shadow-write output]** | |
EOF
expect 0 "row-shaped content outside named sections is ignored" \
  "${FIX[@]}" WIC_CONTRACT="$TMP/contract-section-scope.md" \
  WIC_PROFILE="$TMP/profile-section-scope.md" \
  WIC_ADAPTER="$TMP/adapter-section-scope.md"

# --- Direction (a): a declared intent with no adapter mapping row
cat > "$TMP/adapter-missing.md" <<'EOF'
### Write-intent mappings (the safe-output roles)
| Intent role | Mechanism |
|------|----------------------|
| **[create-issue output]** | mechanism A |
EOF
expect 1 "planted (a): declared intent without adapter row FAILs" \
  "${FIX[@]}" WIC_ADAPTER="$TMP/adapter-missing.md"
expect_msg "planted (a): diagnostic names the unmapped intent" \
  "[add-pr-comment output]" "${FIX[@]}" WIC_ADAPTER="$TMP/adapter-missing.md"

# Every closed-family role needs an adapter mapping, even before a workflow starts
# declaring it.
cat > "$TMP/contract-undeclared-role.md" <<'EOF'
### Write intents (safe outputs)
| Intent role | Inputs | Outputs | Constraints |
|------|--------|---------|-------------|
| **[create-issue output]** | t | o | c |
| **[add-pr-comment output]** | t | o | c |
| **[update-pr output]** | t | o | c |
EOF
expect 1 "planted (a): undeclared family role without adapter row FAILs" \
  "${FIX[@]}" WIC_CONTRACT="$TMP/contract-undeclared-role.md"
expect_msg "planted (a): diagnostic names the uncovered family role" \
  "[update-pr output]" "${FIX[@]}" \
  WIC_CONTRACT="$TMP/contract-undeclared-role.md"

# Every adapter specification carrying the mapping table is checked, not only the
# active Claude adapter.
expect 1 "planted (a): second adapter missing a family row FAILs" \
  "${FIX[@]}" WIC_ADAPTERS="$TMP/adapter.md $TMP/adapter-missing.md"
expect_msg "planted (a): diagnostic names the drifting second adapter" \
  "$TMP/adapter-missing.md" "${FIX[@]}" \
  WIC_ADAPTERS="$TMP/adapter.md $TMP/adapter-missing.md"
mkdir -p "$TMP/discovered-adapters"
cp "$TMP/adapter.md" "$TMP/discovered-adapters/complete.md"
cp "$TMP/adapter-missing.md" "$TMP/discovered-adapters/drifted.md"
printf '<!-- write-intents-check:adapter-tables %s %s -->\n' \
  "$TMP/discovered-adapters/complete.md" \
  "$TMP/discovered-adapters/drifted.md" > "$TMP/adapter-catalog.md"
expect 1 "planted (a): newly discovered adapter-table drift FAILs" \
  WIC_CONTRACT="$TMP/contract.md" WIC_PROFILE="$TMP/profile.md" \
  WIC_WORKFLOW_DIR="$TMP/workflow" \
  WIC_REQUIRED_WORKFLOWS="next-task pr-review triage" \
  WIC_ADAPTER_CATALOG="$TMP/adapter-catalog.md" \
  WIC_ADAPTER_SEARCH_ROOTS="$TMP/discovered-adapters"
expect_msg "planted (a): diagnostic names the discovered drifting adapter" \
  "$TMP/discovered-adapters/drifted.md" \
  WIC_CONTRACT="$TMP/contract.md" WIC_PROFILE="$TMP/profile.md" \
  WIC_WORKFLOW_DIR="$TMP/workflow" \
  WIC_REQUIRED_WORKFLOWS="next-task pr-review triage" \
  WIC_ADAPTER_CATALOG="$TMP/adapter-catalog.md" \
  WIC_ADAPTER_SEARCH_ROOTS="$TMP/discovered-adapters"
mkdir -p "$TMP/heading-loss-adapters"
cp "$TMP/adapter.md" "$TMP/heading-loss-adapters/complete.md"
cat > "$TMP/heading-loss-adapters/lost-heading.md" <<'EOF'
### Renamed write mappings
| Intent role | Mechanism |
|------|----------------------|
| **[create-issue output]** | mechanism A |
| **[add-pr-comment output]** | mechanism B |
EOF
printf '<!-- write-intents-check:adapter-tables %s %s -->\n' \
  "$TMP/heading-loss-adapters/complete.md" \
  "$TMP/heading-loss-adapters/lost-heading.md" > "$TMP/heading-loss-catalog.md"
expect 1 "planted (a): cataloged adapter with lost heading FAILs" \
  WIC_CONTRACT="$TMP/contract.md" WIC_PROFILE="$TMP/profile.md" \
  WIC_WORKFLOW_DIR="$TMP/workflow" \
  WIC_REQUIRED_WORKFLOWS="next-task pr-review triage" \
  WIC_ADAPTER_CATALOG="$TMP/heading-loss-catalog.md" \
  WIC_ADAPTER_SEARCH_ROOTS="$TMP/heading-loss-adapters"
expect_msg "planted (a): lost-heading diagnostic names the adapter" \
  "$TMP/heading-loss-adapters/lost-heading.md" \
  WIC_CONTRACT="$TMP/contract.md" WIC_PROFILE="$TMP/profile.md" \
  WIC_WORKFLOW_DIR="$TMP/workflow" \
  WIC_REQUIRED_WORKFLOWS="next-task pr-review triage" \
  WIC_ADAPTER_CATALOG="$TMP/heading-loss-catalog.md" \
  WIC_ADAPTER_SEARCH_ROOTS="$TMP/heading-loss-adapters"
mkdir -p "$TMP/uncataloged-adapters"
cp "$TMP/adapter.md" "$TMP/uncataloged-adapters/cataloged.md"
cp "$TMP/adapter.md" "$TMP/uncataloged-adapters/new-table.md"
printf '<!-- write-intents-check:adapter-tables %s -->\n' \
  "$TMP/uncataloged-adapters/cataloged.md" > "$TMP/uncataloged-catalog.md"
expect 1 "planted (a): discovered but uncataloged adapter table FAILs" \
  WIC_CONTRACT="$TMP/contract.md" WIC_PROFILE="$TMP/profile.md" \
  WIC_WORKFLOW_DIR="$TMP/workflow" \
  WIC_REQUIRED_WORKFLOWS="next-task pr-review triage" \
  WIC_ADAPTER_CATALOG="$TMP/uncataloged-catalog.md" \
  WIC_ADAPTER_SEARCH_ROOTS="$TMP/uncataloged-adapters"
expect 1 "planted (a): empty adapter list FAILs loud" \
  "${FIX[@]}" WIC_ADAPTERS=""
expect_msg "planted (a): empty adapter-list diagnostic is explicit" \
  "adapter surface list is empty" "${FIX[@]}" WIC_ADAPTERS=""

# --- Direction (a): a mapping row with an empty mechanism/degradation cell maps nothing
cat > "$TMP/adapter-empty-cell.md" <<'EOF'
### Write-intent mappings (the safe-output roles)
| Intent role | Mechanism |
|------|----------------------|
| **[create-issue output]** | mechanism A |
| **[add-pr-comment output]** | |
EOF
expect 1 "planted (a): empty adapter mechanism cell FAILs" \
  "${FIX[@]}" WIC_ADAPTER="$TMP/adapter-empty-cell.md"
expect_msg "planted (a): diagnostic names the empty-cell row" \
  "empty mechanism/degradation cell" "${FIX[@]}" WIC_ADAPTER="$TMP/adapter-empty-cell.md"
expect_msg "planted (a): adapter diagnostic uses the source line" \
  "$TMP/adapter-empty-cell.md:5" "${FIX[@]}" \
  WIC_ADAPTER="$TMP/adapter-empty-cell.md"

# --- Direction (b): a neutral workflow doc naming a concrete tracker write command
mkdir -p "$TMP/workflow-leak"
cp "$TMP/workflow/clean.md" "$TMP/workflow-leak/clean.md"
cat > "$TMP/workflow-leak/leaky.md" <<'EOF'
Then run gh issue comment 7 --body-file plan.md to post the plan.
EOF
expect 1 "planted (b): tracker write command in neutral doc FAILs" \
  "${FIX[@]}" WIC_WORKFLOW_DIR="$TMP/workflow-leak"
expect_msg "planted (b): diagnostic names the leaking doc" \
  "leaky.md" "${FIX[@]}" WIC_WORKFLOW_DIR="$TMP/workflow-leak"

# Destructive / stateful tracker verbs are covered even when they are not used by
# today's adapter mappings.
for verb in delete transfer pin unlock; do
  mkdir -p "$TMP/workflow-leak-$verb"
  printf 'Then run gh issue %s 7.\n' "$verb" > "$TMP/workflow-leak-$verb/leaky.md"
  expect 1 "planted (b): gh issue $verb in neutral doc FAILs" \
    "${FIX[@]}" WIC_WORKFLOW_DIR="$TMP/workflow-leak-$verb"
done

# Non-GitHub adapters can inject their concrete tracker command vocabulary.
mkdir -p "$TMP/workflow-custom-leak"
cat > "$TMP/workflow-custom-leak/leaky.md" <<'EOF'
Then run tracker ticket destroy 7.
EOF
expect 1 "planted (b): adapter-supplied leak pattern FAILs" \
  "${FIX[@]}" WIC_WORKFLOW_DIR="$TMP/workflow-custom-leak" \
  WIC_LEAK_PATTERN='tracker[[:space:]]+ticket[[:space:]]+destroy'
expect 1 "planted (b): invalid adapter-supplied leak pattern FAILs loud" \
  "${FIX[@]}" WIC_LEAK_PATTERN='['
expect_msg "planted (b): invalid leak-pattern diagnostic is explicit" \
  "WIC_LEAK_PATTERN is not a valid extended regular expression" \
  "${FIX[@]}" WIC_LEAK_PATTERN='['

# --- An undeclared / out-of-family intent is rejected (closed set)
cat > "$TMP/profile-unknown.md" <<'EOF'
## Write intents
| workflow | allowed intents |
|---|---|
| `next-task` | `[frob-widget output]` |
| `pr-review` | `[add-pr-comment output]` |
| `triage` | none |
EOF
expect 1 "planted: out-of-family declared intent FAILs" \
  "${FIX[@]}" WIC_PROFILE="$TMP/profile-unknown.md"
expect_msg "planted: diagnostic names the unknown intent" \
  "[frob-widget output]" "${FIX[@]}" WIC_PROFILE="$TMP/profile-unknown.md"

# --- A writing workflow with no declaration row is a defect, not an implicit empty set
cat > "$TMP/profile-missing-wf.md" <<'EOF'
## Write intents
| workflow | allowed intents |
|---|---|
| `next-task` | `[create-issue output]` |
| `triage` | none |
EOF
expect 1 "planted: missing required-workflow row FAILs" \
  "${FIX[@]}" WIC_PROFILE="$TMP/profile-missing-wf.md"
expect_msg "planted: diagnostic names the missing workflow" \
  "'pr-review' has no declaration row" "${FIX[@]}" WIC_PROFILE="$TMP/profile-missing-wf.md"

# The required-writing-workflow set comes from one catalog marker rather than a
# second hard-coded list in the checker.
cat > "$TMP/workflow-catalog-extra.md" <<'EOF'
<!-- write-intents-check:required-workflows next-task pr-review review-response triage intake retrospective release -->
EOF
expect 1 "planted: catalog-added writing workflow without declaration FAILs" \
  WIC_WORKFLOW_CATALOG="$TMP/workflow-catalog-extra.md"
expect_msg "planted: diagnostic names the catalog-added workflow" \
  "'release' has no declaration row" \
  WIC_WORKFLOW_CATALOG="$TMP/workflow-catalog-extra.md"
expect 1 "planted: empty required-workflow override FAILs loud" \
  "${FIX[@]}" WIC_REQUIRED_WORKFLOWS=""
expect 1 "planted: whitespace-only required-workflow override FAILs loud" \
  "${FIX[@]}" WIC_REQUIRED_WORKFLOWS="   "
expect_msg "planted: empty required-workflow diagnostic is explicit" \
  "required workflow list is empty" \
  "${FIX[@]}" WIC_REQUIRED_WORKFLOWS=""

# A workflow has exactly one declaration; duplicate rows cannot silently union or
# override one another.
cat > "$TMP/profile-duplicate-wf.md" <<'EOF'
## Write intents
| workflow | allowed intents |
|---|---|
| `next-task` | `[create-issue output]` |
| `next-task` | `[add-pr-comment output]` |
| `pr-review` | `[add-pr-comment output]` |
| `triage` | none |
EOF
expect 1 "planted: duplicate workflow declaration rows FAIL" \
  "${FIX[@]}" WIC_PROFILE="$TMP/profile-duplicate-wf.md"
expect_msg "planted: duplicate diagnostic names the workflow" \
  "duplicate declaration rows for workflow 'next-task'" \
  "${FIX[@]}" WIC_PROFILE="$TMP/profile-duplicate-wf.md"

# --- A row that is neither intents nor the literal `none` is rejected
cat > "$TMP/profile-vague.md" <<'EOF'
## Write intents
| workflow | allowed intents |
|---|---|
| `next-task` | whatever it needs |
| `pr-review` | `[add-pr-comment output]` |
| `triage` | none |
EOF
expect 1 "planted: non-'none' empty/vague intent cell FAILs" \
  "${FIX[@]}" WIC_PROFILE="$TMP/profile-vague.md"

# Markdown allows trailing whitespace after the closing pipe; it must not change a
# literal `none` declaration into an invalid cell.
printf '%s\n' \
  '## Write intents' \
  '| workflow | allowed intents |' \
  '|---|---|' \
  '| `next-task` | `[create-issue output]`, `[add-pr-comment output]` |' \
  '| `pr-review` | `[add-pr-comment output]` |' \
  '| `triage` | none |   ' > "$TMP/profile-none-trailing-space.md"
expect 0 "trailing whitespace after a literal-none row is accepted" \
  "${FIX[@]}" WIC_PROFILE="$TMP/profile-none-trailing-space.md"

# --- An empty contract family is a loud FAIL, never a vacuous pass (P2)
cat > "$TMP/contract-empty.md" <<'EOF'
### Write intents (safe outputs)
(no table yet)
EOF
expect 1 "planted: empty contract family FAILs loud" \
  "${FIX[@]}" WIC_CONTRACT="$TMP/contract-empty.md"

# --- A missing surface fails loud
expect 1 "missing profile surface FAILs loud" \
  "${FIX[@]}" WIC_PROFILE="$TMP/does-not-exist.md"

# --- CI wiring: verify runs both the check and this suite (a test that exists but
# is never run is a silently dead guard).
for needle in "write-intents-check.sh" "write-intents-check.test.sh"; do
  if grep -q "$needle" .github/workflows/ci.yml; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL CI wiring: %s not run by ci.yml\n' "$needle" >&2
  fi
done

echo "write-intents-check tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
