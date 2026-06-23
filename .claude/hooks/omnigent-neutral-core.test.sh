#!/usr/bin/env bash
# omnigent-neutral-core.test.sh — the paired neutral-core-untouched check for the
# Omnigent adapter (T617, #134; #119 AC4 — load-bearing).
#
# AC4 has two halves; each is PAIRED (the planted violation FAILS, the real tree PASSES),
# the same "machinery proves it is live" discipline as guard.test.sh / reconcile's tests:
#   (A) NEUTRAL CORE clean of Omnigent MECHANISM names — workflow/** surfaces none.
#       Uses the SHARED scanner lib-neutrality-scan.sh (no forked token set — constitution
#       P2); the Omnigent tokens were added to that shared set in T617.
#   (B) MODEL CONFINEMENT — the Omnigent model-table vocabulary appears ONLY in
#       adapters/omnigent/MODELS.md (README step 5: "grep for your model table's
#       vocabulary; exactly one file may match"). Model IDs are extracted FROM MODELS.md
#       at run time (self-syncing — no hardcoded model list to drift), then sought in the
#       rest of the adapter subtree and in workflow/**.
#
# Harness/mechanism names (claude-sdk, codex, openai-agents) in the adapter docs are NOT
# model vocabulary and are expected there — (B) targets concrete model IDs only.
set -u

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=lib-neutrality-scan.sh
. "$ROOT/.claude/hooks/lib-neutrality-scan.sh"

OMNI_DIR="$ROOT/.claude/adapters/omnigent"
MODELS_MD="$OMNI_DIR/MODELS.md"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0
ok() { pass=$((pass + 1)); }
bad() {
  fail=$((fail + 1))
  printf 'FAIL %s\n' "$1" >&2
}

# Extract model IDs from MODELS.md: backticked tokens carrying BOTH a hyphen and a digit
# (a version-bearing model id like claude-opus-4-8 / gpt-5.5), which excludes harness names
# (claude-sdk, openai-agents — hyphen, no digit) and bare words (codex — no hyphen).
extract_model_ids() {
  grep -oE '`[A-Za-z0-9][A-Za-z0-9._-]*`' "$1" 2>/dev/null \
    | tr -d '`' | grep -E '-' | grep -E '[0-9]' | sort -u
}

# Print "<file>:<id>" for each model id (in $MODEL_IDS) found in any of the given files.
scan_files_for_models() {
  local f id
  for f in "$@"; do
    [ -f "$f" ] || continue
    for id in $MODEL_IDS; do
      grep -qF -- "$id" "$f" && printf '%s:%s\n' "$f" "$id"
    done
  done
}

# ── Part A: neutral core clean of Omnigent mechanism names (paired) ──────────────

# A0 sanity: the shared scanner actually carries the Omnigent vocabulary now.
if neutral_mechanism_pattern | grep -q 'omnigent'; then ok
else bad "A0: shared neutral_mechanism_pattern is missing the Omnigent vocabulary"; fi

# A1 (real PASSES): every tracked workflow/**.md scans clean through the shared set.
real_leaks=""
scanned=0
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  scanned=$((scanned + 1))
  l="$(neutral_mechanism_leaks "$ROOT/$rel")"
  [ -z "$l" ] || real_leaks="$real_leaks $rel:{$l}"
done < <(git -C "$ROOT" ls-files .claude/workflow | grep -E '[.]md$')

if [ "$scanned" -gt 0 ]; then ok
else bad "A1: no workflow/**.md files found to scan"; fi

if [ -z "$(printf '%s' "$real_leaks" | tr -d '[:space:]')" ]; then ok
else bad "A1: a mechanism name leaked into the neutral core:$real_leaks"; fi

# A2 (planted FAILS): Omnigent mechanism tokens in a workflow-shaped fixture are caught —
# including sys_os_write, the edit-guard tool the README binds (the whole sys_os_* family
# must be banned, not just shell/edit; #135 Codex P2 / craft #2).
plant="$TMP/neutral-fixture.md"
printf 'This neutral doc wrongly drives omnigent run config.yaml via policy_modules on sys_os_write.\n' > "$plant"
got="$(neutral_mechanism_leaks "$plant")"
if printf '%s' "$got" | grep -qF -- 'omnigent' \
  && printf '%s' "$got" | grep -qF -- 'policy_modules' \
  && printf '%s' "$got" | grep -qF -- 'sys_os_write'; then ok
else bad "A2: planted Omnigent token NOT caught by the shared scanner (got '${got:-<empty>}')"; fi

# ── Part B: model vocabulary confined to MODELS.md (paired) ──────────────────────

if [ -f "$MODELS_MD" ]; then ok
else bad "B: $MODELS_MD missing"; fi

MODEL_IDS="$(extract_model_ids "$MODELS_MD")"

# B0 sanity: extraction yielded at least one model id (else B1 would pass vacuously).
if [ -n "$(printf '%s' "$MODEL_IDS" | tr -d '[:space:]')" ]; then ok
else bad "B0: no model ids extracted from MODELS.md — the confinement check would be vacuous"; fi

# B1a (real PASSES): no model id appears in the adapter subtree OUTSIDE MODELS.md.
subtree_others=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  subtree_others="$subtree_others $f"
done < <(find "$OMNI_DIR" -type f ! -name 'MODELS.md' 2>/dev/null)

# shellcheck disable=SC2086
subtree_hits="$(scan_files_for_models $subtree_others)"
if [ -z "$subtree_hits" ]; then ok
else bad "B1a: model id leaked into the adapter subtree outside MODELS.md:"$'\n'"$subtree_hits"; fi

# B1b (real PASSES): no model id appears anywhere in the neutral core (workflow/**).
wf_files=""
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  wf_files="$wf_files $ROOT/$rel"
done < <(git -C "$ROOT" ls-files .claude/workflow | grep -E '[.]md$')

# shellcheck disable=SC2086
wf_hits="$(scan_files_for_models $wf_files)"
if [ -z "$wf_hits" ]; then ok
else bad "B1b: model id leaked into the neutral core (workflow/**):"$'\n'"$wf_hits"; fi

# B2 (planted FAILS): a model id dropped into a non-MODELS adapter file is caught.
first_id="$(printf '%s\n' $MODEL_IDS | head -1)"
plant_b="$TMP/config.yaml"
printf 'executor:\n  model: %s\n' "$first_id" > "$plant_b"
planted_hits="$(scan_files_for_models "$plant_b")"
if printf '%s' "$planted_hits" | grep -qF -- "$first_id"; then ok
else bad "B2: planted model id '$first_id' NOT caught by the confinement scan"; fi

printf 'omnigent-neutral-core.test.sh: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
