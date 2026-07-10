#!/usr/bin/env bash
# T1207 / spec 007 US7 regression tests for the Claude Code runtime-context floor.
set -u

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PROBE="$ROOT/.claude/adapters/runtime-context-floor.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0
ok() { pass=$((pass + 1)); printf 'ok - %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf 'not ok - %s\n' "$1" >&2; }

if ! python3 -c 'import tiktoken' >/dev/null 2>&1; then
  printf 'FAIL: runtime-context-floor tests require python3 + tiktoken (o200k_base).\n' >&2
  exit 1
fi

write_inventory() {
  path="$1"
  long_body="$2"
  cat > "$path" <<EOF
{
  "format": "claude-code-runtime-context/v1",
  "runtime_context": {
    "mcp_servers": [{"name": "fixture-mcp", "instructions": "$long_body"}],
    "skills": [{"name": "fixture-skill", "description": "fixture skill description"}],
    "tools": [{"name": "Read", "deferred": false, "input_schema": {"type": "object", "description": "$long_body"}}],
    "deferred_tools": [{"name": "WebSearch", "catalog_entry": "search the web"}],
    "system_reminders": ["fixture reminder"]
  }
}
EOF
}

write_inventory "$TMP/small.json" "short"
write_inventory "$TMP/large.json" "this fixture body is materially longer and must consume more tokens than short because the total is measured from content"

# RED/GREEN AC1: counts come from the inventory, and equal counts cannot determine total.
python3 "$PROBE" measure "$TMP/small.json" > "$TMP/small.out"
python3 "$PROBE" measure "$TMP/large.json" > "$TMP/large.out"
small_counts="$(jq -c 'del(.runtime_tokens)' "$TMP/small.out")"
large_counts="$(jq -c 'del(.runtime_tokens)' "$TMP/large.out")"
small_total="$(jq -r '.runtime_tokens' "$TMP/small.out")"
large_total="$(jq -r '.runtime_tokens' "$TMP/large.out")"
expected_large="$(python3 - "$TMP/large.json" <<'PY'
import json, sys, tiktoken
with open(sys.argv[1], encoding="utf-8") as source:
    body = json.load(source)["runtime_context"]
encoded = json.dumps(body, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
print(len(tiktoken.get_encoding("o200k_base").encode(encoded)))
PY
)"
if [ "$small_counts" = "$large_counts" ] && [ "$large_total" -gt "$small_total" ] && [ "$large_total" -eq "$expected_large" ]; then
  ok "equal-count inventories use o200k_base content measurement for the total"
else
  bad "equal-count inventories must differ by measured content ($small_counts / $large_counts; $small_total / $large_total / expected $expected_large)"
fi

# AC1 fidelity: an absent category is zero and reduces both inventory count and total.
jq 'del(.runtime_context.mcp_servers)' "$TMP/large.json" > "$TMP/absent.json"
python3 "$PROBE" measure "$TMP/absent.json" > "$TMP/absent.out"
if [ "$(jq -r '.mcp_servers' "$TMP/absent.out")" -eq 0 ] \
  && [ "$(jq -r '.enabled_skills' "$TMP/absent.out")" -eq 1 ] \
  && [ "$(jq -r '.runtime_tokens' "$TMP/absent.out")" -lt "$large_total" ]; then
  ok "absent category reports zero and a smaller measured total"
else
  bad "absent category did not change the per-category count and total"
fi

# AC1 privacy: compact output carries no raw schema, config, instructions, or secret bytes.
secret="T1207_DO_NOT_EMIT_fixture_secret"
sed "s/fixture reminder/$secret/" "$TMP/large.json" > "$TMP/secret.json"
python3 "$PROBE" measure "$TMP/secret.json" > "$TMP/secret.out"
if [ -s "$TMP/secret.out" ] \
  && jq -e 'keys == ["deferred_tools","enabled_skills","mcp_servers","non_deferred_tools","runtime_tokens"]' "$TMP/secret.out" >/dev/null \
  && ! grep -q "$secret" "$TMP/secret.out" \
  && ! grep -q 'input_schema\|instructions\|catalog_entry' "$TMP/secret.out"; then
  ok "output is counts/totals only and emits no runtime body bytes"
else
  bad "output leaked raw inventory structure or secret bytes"
fi

# Unknown element shapes are version drift too: fail open rather than traceback/gate.
jq '.runtime_context.tools = ["future-tool-shape"]' "$TMP/small.json" > "$TMP/unknown-tool.json"
unknown_tool_status=0
python3 "$PROBE" measure "$TMP/unknown-tool.json" > "$TMP/unknown-tool.out" 2> "$TMP/unknown-tool.err" || unknown_tool_status=$?
if [ "$unknown_tool_status" -eq 0 ] && [ ! -s "$TMP/unknown-tool.out" ] \
  && grep -q 'WARN: unrecognized Claude Code runtime context shape' "$TMP/unknown-tool.err"; then
  ok "unknown category element shape also fails open and loud"
else
  bad "unknown category element shape did not fail open/loud"
fi

for marker_shape in missing nonboolean contradictory_true; do
  case "$marker_shape" in
    missing) jq '.runtime_context.tools = [{"name":"future-tool"}]' "$TMP/small.json" > "$TMP/$marker_shape.json" ;;
    nonboolean) jq '.runtime_context.tools = [{"name":"future-tool","deferred":"no"}]' "$TMP/small.json" > "$TMP/$marker_shape.json" ;;
    contradictory_true) jq '.runtime_context.tools = [{"name":"future-tool","deferred":true}]' "$TMP/small.json" > "$TMP/$marker_shape.json" ;;
  esac
  marker_status=0
  python3 "$PROBE" measure "$TMP/$marker_shape.json" > "$TMP/$marker_shape.out" 2> "$TMP/$marker_shape.err" || marker_status=$?
  if [ "$marker_status" -eq 0 ] && [ ! -s "$TMP/$marker_shape.out" ] \
    && grep -q 'WARN: unrecognized Claude Code runtime context shape' "$TMP/$marker_shape.err"; then
    ok "$marker_shape deferred marker fails open and loud"
  else
    bad "$marker_shape deferred marker was silently counted"
  fi
done

# AC3 two-sided fail-open: unknown shape is loud/non-failing; supported shape reports.
printf '{"format":"future-runtime/v9","runtime_context":{}}\n' > "$TMP/unknown.json"
unknown_status=0
python3 "$PROBE" measure "$TMP/unknown.json" > "$TMP/unknown.out" 2> "$TMP/unknown.err" || unknown_status=$?
if [ "$unknown_status" -eq 0 ] && [ ! -s "$TMP/unknown.out" ] \
  && grep -q 'WARN: unrecognized Claude Code runtime context shape' "$TMP/unknown.err" \
  && jq -e '.non_deferred_tools == 1' "$TMP/small.out" >/dev/null; then
  ok "unknown shape fails open and loud while supported control reports counts"
else
  bad "fail-open/control proof failed (status $unknown_status)"
fi

# AC2: the measure command produces the named non-gating baseline; report consumes it.
python3 "$PROBE" measure "$TMP/large.json" --write-baseline "$TMP/baseline.json" --runtime-version "fixture-1.0" >/dev/null
python3 "$PROBE" report --authored-tokens 1200 --baseline "$TMP/baseline.json" > "$TMP/report.out"
if jq -e --argjson total "$large_total" '
    .name == "claude-code-fresh-session-runtime-floor"
    and .counter == "tiktoken/o200k_base"
    and .runtime_floor_tokens == $total
    and .gating == "none"
    and .runtime_version == "fixture-1.0"
  ' "$TMP/baseline.json" >/dev/null \
  && grep -qx 'authored surface = 1200 tokens' "$TMP/report.out" \
  && grep -qx "runtime floor = $large_total tokens" "$TMP/report.out" \
  && grep -qx "real resident = $((1200 + large_total)) tokens" "$TMP/report.out"; then
  ok "generated baseline renders authored + floor = resident"
else
  bad "baseline/report contract failed"
fi

# P5/P1 boundary: neither neutral workflow docs nor decisional paths consume the baseline.
if ! rg -n 'runtime-context-floor-baseline' "$ROOT/.claude/workflow" "$ROOT/.github" \
    "$ROOT/.claude/hooks" "$ROOT/.claude/workflows" "$ROOT/.claude/MODELS.md" \
    "$ROOT/specs/TASK_INDEX.md" >/dev/null; then
  ok "runtime floor baseline is absent from workflow/gate/tier/selection paths"
else
  bad "runtime floor baseline leaked into a neutral or decisional path"
fi

# The landed baseline is command-produced and remains explicitly non-gating.
LANDED_BASELINE="$ROOT/.claude/adapters/runtime-context-floor-baseline.json"
if jq -e '
    .name == "claude-code-fresh-session-runtime-floor"
    and .counter == "tiktoken/o200k_base"
    and .gating == "none"
    and (.runtime_floor_tokens | type == "number" and . > 0)
    and (.generated_by | contains("runtime-context-floor.py measure"))
  ' "$LANDED_BASELINE" >/dev/null; then
  ok "landed runtime floor is a named command-produced non-gating baseline"
else
  bad "landed runtime floor baseline is missing or not traceable/non-gating"
fi

# The adapter contract is documented locally and its tests are live in verify.
DOC="$ROOT/.claude/adapters/claude-code-probes.md"
CI="$ROOT/.github/workflows/ci.yml"
if grep -qF 'runtime-context-floor.py measure' "$DOC" \
  && grep -qF 'claude-code-runtime-context/v1' "$DOC" \
  && grep -qF 'fails open' "$DOC" \
  && grep -qE '^[[:space:]]*run:[[:space:]]+bash[[:space:]]+\.claude/adapters/runtime-context-floor\.test\.sh([[:space:]]|$)' "$CI"; then
  ok "adapter usage/shape/fail-open contract is documented and tested in verify"
else
  bad "adapter documentation or verify wiring is missing"
fi

printf 'runtime-context-floor.test.sh: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
