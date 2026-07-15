#!/usr/bin/env bash
# write-intents-check.test.sh — two-sided falsification tests for the write-intent
# contract check (T636, issue #232; constitution P3).
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

# --- Direction (a): a declared intent with no adapter mapping row
cat > "$TMP/adapter-missing.md" <<'EOF'
| Intent role | Mechanism |
|------|----------------------|
| **[create-issue output]** | mechanism A |
EOF
expect 1 "planted (a): declared intent without adapter row FAILs" \
  "${FIX[@]}" WIC_ADAPTER="$TMP/adapter-missing.md"
expect_msg "planted (a): diagnostic names the unmapped intent" \
  "[add-pr-comment output]" "${FIX[@]}" WIC_ADAPTER="$TMP/adapter-missing.md"

# --- Direction (a): a mapping row with an empty mechanism/degradation cell maps nothing
cat > "$TMP/adapter-empty-cell.md" <<'EOF'
| Intent role | Mechanism |
|------|----------------------|
| **[create-issue output]** | mechanism A |
| **[add-pr-comment output]** | |
EOF
expect 1 "planted (a): empty adapter mechanism cell FAILs" \
  "${FIX[@]}" WIC_ADAPTER="$TMP/adapter-empty-cell.md"
expect_msg "planted (a): diagnostic names the empty-cell row" \
  "empty mechanism/degradation cell" "${FIX[@]}" WIC_ADAPTER="$TMP/adapter-empty-cell.md"

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
