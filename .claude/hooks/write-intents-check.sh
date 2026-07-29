#!/usr/bin/env bash
# write-intents-check.sh — deterministic write-intent / safe-output contract check
# (T636/#232, hardened by #284; constitution P1/P3).
#
# Verifies the closed write-intent role family end-to-end, both directions:
#   1. The contract (workflow/README.md → "Write intents (safe outputs)") defines a
#      non-empty, enumerated family — an empty/unparseable family FAILs loud (P2,
#      never a vacuous pass).
#   2. Every intent the profile declares (PROJECT.md → "Write intents") is a member
#      of the contract family — an unknown/catch-all intent FAILs.
#   3. Every family intent has a row in every discovered adapter mapping table —
#      an unmapped family role FAILs before declaration drift can expose it.
#   4. Every required writing workflow has a declaration row (possibly `none`) — a
#      writing ritual with no declared set FAILs (the authoritative ritual catalog
#      lives in PROJECT.template.md, not as a duplicated checker default).
#   5. No neutral workflow doc names a concrete tracker write command (e.g. a
#      `gh issue comment` form) where an intent role exists (direction b, P1) —
#      the dedicated, adapter-overridable leak scan beside the neutrality scanner.
#
# Surfaces are overridable for fixture-based falsification tests
# (write-intents-check.test.sh); defaults are the live tree read from the repo
# root = CWD (the same CWD contract doc-pointer-check.sh uses).
#
# Run: bash .claude/hooks/write-intents-check.sh
set -u
export LC_ALL=C

CONTRACT="${WIC_CONTRACT:-.claude/workflow/README.md}"
PROFILE="${WIC_PROFILE:-.claude/PROJECT.md}"

markdown_section() { # markdown_section <file> <heading-ERE> [numbered|heading]
  local mode=""
  [ "$#" -lt 3 ] || mode="$3"
  awk -v heading_re="$2" -v mode="$mode" '
    function trim_block_indent(line, indent) {
      indent = 0
      while (indent < 3 && substr(line, indent + 1, 1) == " ") indent++
      return substr(line, indent + 1)
    }
    function normalize_atx_heading(line, rest) {
      match(line, /^#+/)
      atx_level = RLENGTH
      if (atx_level < 1 || atx_level > 6) return 0

      rest = substr(line, atx_level + 1)
      if (rest != "" && rest !~ /^[[:blank:]]/) return 0
      sub(/[[:blank:]]+$/, "", rest)
      sub(/[[:blank:]]+#+$/, "", rest)
      sub(/^[[:blank:]]+/, "", rest)
      sub(/[[:blank:]]+$/, "", rest)

      atx_canonical = substr(line, 1, atx_level)
      if (rest != "") atx_canonical = atx_canonical " " rest
      return 1
    }
    function fence_run(line, indent, marker, run) {
      indent = 0
      while (indent < length(line) && substr(line, indent + 1, 1) == " ") {
        indent++
      }
      if (indent > 3) return 0

      marker = substr(line, indent + 1, 1)
      if (marker != "`" && marker != "~") return 0
      run = 0
      while (substr(line, indent + run + 1, 1) == marker) {
        run++
      }
      if (run < 3) return 0

      candidate_char = marker
      candidate_length = run
      candidate_rest = substr(line, indent + run + 1)
      return 1
    }
    function fence_starts(line) {
      if (!fence_run(line)) return 0
      if (candidate_char == "`" && candidate_rest ~ /`/) return 0
      fence_char = candidate_char
      fence_length = candidate_length
      return 1
    }
    function fence_ends(line) {
      if (!fence_run(line)) return 0
      return candidate_char == fence_char &&
        candidate_length >= fence_length &&
        candidate_rest ~ /^[[:blank:]]*$/
    }
    function tick_run(line, position, run) {
      run = 0
      while (substr(line, position + run, 1) == "`") run++
      return run
    }
    function matching_tick_exists(line, position, needed, i, run) {
      i = position + needed
      while (i <= length(line)) {
        if (substr(line, i, 1) != "`") {
          i++
          continue
        }
        run = tick_run(line, i)
        if (run == needed) return 1
        i += run
      }
      return 0
    }
    function html_comment_start(line, i, run, code_run) {
      code_run = 0
      i = 1
      while (i <= length(line)) {
        if (substr(line, i, 1) == "`") {
          run = tick_run(line, i)
          if (!code_run && matching_tick_exists(line, i, run)) {
            code_run = run
          } else if (code_run == run) {
            code_run = 0
          }
          i += run
          continue
        }
        if (!code_run && substr(line, i, 4) == "<!--") return i
        i++
      }
      return 0
    }
    function strip_html_comments(line, visible, start, end_at) {
      visible = ""
      while (1) {
        if (in_html_comment) {
          end_at = index(line, "-->")
          if (!end_at) return visible
          line = substr(line, end_at + 3)
          in_html_comment = 0
          continue
        }
        start = html_comment_start(line)
        if (!start) return visible line
        visible = visible substr(line, 1, start - 1)
        line = substr(line, start + 4)
        end_at = index(line, "-->")
        if (!end_at) {
          in_html_comment = 1
          return visible
        }
        line = substr(line, end_at + 3)
      }
    }
    {
      if (in_fence) {
        if (fence_ends($0)) in_fence = 0
        next
      }
      line = strip_html_comments($0)
      if (line == "") next
      if (fence_starts(line)) {
        in_fence = 1
        next
      }
      heading_line = trim_block_indent(line)
      is_atx_heading = normalize_atx_heading(heading_line)
      if (is_atx_heading && atx_canonical ~ heading_re) {
        headings++
        if (headings > 1) exit 2
        if (mode == "heading") {
          print line
          next
        }
        inside = 1
        level = atx_level
        next
      }
      if (inside && is_atx_heading && atx_level <= level) {
        inside = 0
        next
      }
      if (inside) {
        if (mode == "numbered") print NR ":" line
        else print line
      }
    }
  ' "$1"
}

if [ -n "${WIC_ADAPTERS+x}" ]; then
  ADAPTERS="$WIC_ADAPTERS"
elif [ -n "${WIC_ADAPTER+x}" ]; then
  ADAPTERS="$WIC_ADAPTER"
else
  ADAPTER_CATALOG="${WIC_ADAPTER_CATALOG:-.claude/PROJECT.template.md}"
  if [ ! -f "$ADAPTER_CATALOG" ]; then
    echo "FAIL: adapter catalog '$ADAPTER_CATALOG' not found from $(pwd) — run from the repo root" >&2
    echo "write-intents check: FAIL (surface missing)" >&2
    exit 1
  fi
  EXPECTED_ADAPTERS="$(sed -nE 's/^[[:space:]]*<!--[[:space:]]*write-intents-check:adapter-tables[[:space:]]+([^>]*)[[:space:]]*-->$/\1/p' "$ADAPTER_CATALOG")"
  if ! printf '%s' "$EXPECTED_ADAPTERS" | grep -qE '[^[:space:]]'; then
    echo "FAIL: adapter catalog '$ADAPTER_CATALOG' has no write-intents-check:adapter-tables marker" >&2
    echo "write-intents check: FAIL (adapter catalog unparseable)" >&2
    exit 1
  fi
  ADAPTER_SEARCH_ROOTS="${WIC_ADAPTER_SEARCH_ROOTS:-.claude/README.md .claude/adapters}"
  adapter_candidates="$(
    for root in $ADAPTER_SEARCH_ROOTS; do
      if [ -f "$root" ]; then
        printf '%s\n' "$root"
      elif [ -d "$root" ]; then
        find "$root" -type f -name '*.md'
      fi
    done | sort -u
  )"
  discovery_status=0
  discovered_adapters="$(
    while IFS= read -r candidate; do
      [ -n "$candidate" ] || continue
      heading_status=0
      heading_match="$(markdown_section "$candidate" '^##+ Write-intent mappings [(]the safe-output roles[)]$' heading)" || heading_status=$?
      if [ "$heading_status" -eq 2 ]; then
        echo "FAIL: duplicate write-intent mapping sections in adapter '$candidate' (repair: keep exactly one named mapping section)" >&2
        echo "write-intents check: FAIL (duplicate adapter mapping sections)" >&2
        exit 1
      fi
      if [ "$heading_status" -ne 0 ]; then
        echo "FAIL: could not parse adapter mapping sections in '$candidate'" >&2
        echo "write-intents check: FAIL (adapter mapping parse error)" >&2
        exit 1
      fi
      if [ -n "$heading_match" ]; then
        printf '%s\n' "$candidate"
      fi
    done <<< "$adapter_candidates"
  )" || discovery_status=$?
  if [ "$discovery_status" -ne 0 ]; then
    exit "$discovery_status"
  fi
  for expected_adapter in $EXPECTED_ADAPTERS; do
    if ! printf '%s\n' $discovered_adapters | grep -qFx "$expected_adapter"; then
      echo "FAIL: cataloged adapter '$expected_adapter' has no discoverable \"Write-intent mappings (the safe-output roles)\" section" >&2
      echo "write-intents check: FAIL (adapter mapping heading missing)" >&2
      exit 1
    fi
  done
  for discovered_adapter in $discovered_adapters; do
    if ! printf '%s\n' $EXPECTED_ADAPTERS | grep -qFx "$discovered_adapter"; then
      echo "FAIL: discovered adapter mapping table '$discovered_adapter' is absent from the adapter catalog '$ADAPTER_CATALOG'" >&2
      echo "write-intents check: FAIL (adapter catalog incomplete)" >&2
      exit 1
    fi
  done
  ADAPTERS="$EXPECTED_ADAPTERS"
fi
if ! printf '%s' "$ADAPTERS" | grep -qE '[^[:space:]]'; then
  echo "FAIL: adapter surface list is empty — at least one write-intent mapping table is required" >&2
  echo "write-intents check: FAIL (adapter surface list empty)" >&2
  exit 1
fi
WORKFLOW_DIR="${WIC_WORKFLOW_DIR:-.claude/workflow}"
WORKFLOW_CATALOG="${WIC_WORKFLOW_CATALOG:-.claude/PROJECT.template.md}"
if [ -n "${WIC_REQUIRED_WORKFLOWS+x}" ]; then
  REQUIRED_WORKFLOWS="$WIC_REQUIRED_WORKFLOWS"
else
  if [ ! -f "$WORKFLOW_CATALOG" ]; then
    echo "FAIL: workflow catalog '$WORKFLOW_CATALOG' not found from $(pwd) — run from the repo root" >&2
    echo "write-intents check: FAIL (surface missing)" >&2
    exit 1
  fi
  REQUIRED_WORKFLOWS="$(sed -nE 's/^[[:space:]]*<!--[[:space:]]*write-intents-check:required-workflows[[:space:]]+([^>]*)[[:space:]]*-->$/\1/p' "$WORKFLOW_CATALOG")"
  if [ -z "$REQUIRED_WORKFLOWS" ]; then
    echo "FAIL: workflow catalog '$WORKFLOW_CATALOG' has no write-intents-check:required-workflows marker" >&2
    echo "write-intents check: FAIL (workflow catalog unparseable)" >&2
    exit 1
  fi
fi
if ! printf '%s' "$REQUIRED_WORKFLOWS" | grep -qE '[^[:space:]]'; then
  echo "FAIL: required workflow list is empty — declaration coverage cannot be disabled" >&2
  echo "write-intents check: FAIL (required workflow list empty)" >&2
  exit 1
fi

failures=0
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}

for f in "$CONTRACT" "$PROFILE" $ADAPTERS; do
  if [ ! -f "$f" ]; then
    echo "FAIL: surface '$f' not found from $(pwd) — run from the repo root" >&2
    echo "write-intents check: FAIL (surface missing)" >&2
    exit 1
  fi
done

# --- 1. The contract family: role-defining table rows (`| **[<op> output]** | ...`)
# in the contract surface. Row-anchored so prose references elsewhere don't count.
contract_section_status=0
contract_section="$(markdown_section "$CONTRACT" '^### Write intents [(]safe outputs[)]')" || contract_section_status=$?
if [ "$contract_section_status" -eq 2 ]; then
  fail "contract surface '$CONTRACT' has duplicate \"Write intents (safe outputs)\" sections (repair: keep exactly one named contract section)"
elif [ "$contract_section_status" -ne 0 ]; then
  fail "could not parse the write-intent contract section in '$CONTRACT'"
fi
contract_roles="$(printf '%s\n' "$contract_section" | grep -oE '^ {0,3}\|[[:blank:]]*\*\*\[[a-z][a-z-]* output\]\*\*' | grep -oE '\[[a-z][a-z-]* output\]')" || contract_roles=""
duplicate_contract_roles="$(printf '%s\n' "$contract_roles" | sort | uniq -d)"
while IFS= read -r role; do
  [ -n "$role" ] || continue
  fail "duplicate contract rows for '$role' in '$CONTRACT' (repair: keep exactly one definition per family role)"
done <<< "$duplicate_contract_roles"
family="$(printf '%s\n' "$contract_roles" | sort -u)"
if [ -z "$family" ]; then
  fail "contract surface '$CONTRACT' defines no write-intent role rows — the closed family is empty or unparseable (repair: restore the \"Write intents (safe outputs)\" table)"
fi

in_family() { # in_family <[role]> -> 0/1
  printf '%s\n' "$family" | grep -qFx "$1"
}

# --- 3. Adapter mapping rows (same row-anchored shape). A mapping row
# must carry a non-empty mechanism/degradation cell — a bare role row maps nothing
# (the binding contract requires a concrete mechanism or a documented degradation).
# Every adapter spec carrying this table must map the complete closed family.
for adapter in $ADAPTERS; do
  adapter_section_status=0
  adapter_section="$(markdown_section "$adapter" '^##+ Write-intent mappings [(]the safe-output roles[)]$' numbered)" || adapter_section_status=$?
  if [ "$adapter_section_status" -eq 2 ]; then
    fail "duplicate write-intent mapping sections in adapter '$adapter' (repair: keep exactly one named mapping section)"
  elif [ "$adapter_section_status" -ne 0 ]; then
    fail "could not parse the write-intent mapping section in adapter '$adapter'"
  fi
  adapter_row_lines="$(printf '%s\n' "$adapter_section" | grep -E '^[0-9]+: {0,3}\|[[:blank:]]*\*\*\[[a-z][a-z-]* output\]\*\*[[:blank:]]*\|')" || adapter_row_lines=""
  adapter_rows=""
  while IFS= read -r numbered; do
    [ -n "$numbered" ] || continue
    lineno="${numbered%%:*}"
    row="${numbered#*:}"
    role="$(printf '%s' "$row" | grep -oE '\[[a-z][a-z-]* output\]' | head -n 1)"
    cell="$(printf '%s' "$row" | sed -E 's/^ {0,3}\|[[:blank:]]*\*\*\[[a-z][a-z-]* output\]\*\*[[:blank:]]*\|(.*)\|[[:space:]]*$/\1/')"
    if [ "$cell" = "$row" ] || ! printf '%s' "$cell" | grep -qE '[^[:space:]]'; then
      fail "adapter mapping row for '$role' ($adapter:$lineno) has an empty mechanism/degradation cell — a bare role row maps nothing (repair: name the concrete mechanism, or the documented degradation)"
    fi
    adapter_rows="$adapter_rows$role
"
  done <<< "$adapter_row_lines"
  duplicate_adapter_roles="$(printf '%s' "$adapter_rows" | sort | uniq -d)"
  while IFS= read -r role; do
    [ -n "$role" ] || continue
    fail "duplicate mapping rows for '$role' in adapter '$adapter' (repair: keep exactly one row per family role)"
  done <<< "$duplicate_adapter_roles"
  adapter_rows="$(printf '%s' "$adapter_rows" | sort -u)"
  while IFS= read -r role; do
    [ -n "$role" ] || continue
    if ! in_family "$role"; then
      fail "adapter '$adapter' maps out-of-family role '$role' (repair: remove it, or add the role to the reviewed contract family)"
    fi
  done <<< "$adapter_rows"
  while IFS= read -r intent; do
    [ -n "$intent" ] || continue
    if ! printf '%s\n' "$adapter_rows" | grep -qFx "$intent"; then
      fail "contract family intent '$intent' has no mapping row in adapter '$adapter' (repair: add its intent→mechanism row or a documented degradation)"
    fi
  done <<< "$family"
done

# --- 2 + 3 + 4. The profile declaration table: rows shaped `| `<workflow>` | ... |`.
# NOTE: backticks are NOT backslash-escaped in these EREs — GNU grep/sed treat
# `\`` as a start-of-buffer anchor (BSD treats it as a literal), so escaping
# silently empties every match on Linux (caught by CI on PR #285).
profile_section_status=0
profile_section="$(markdown_section "$PROFILE" '^## Write intents$')" || profile_section_status=$?
if [ "$profile_section_status" -eq 2 ]; then
  fail "profile surface '$PROFILE' has duplicate \"Write intents\" sections (repair: keep exactly one named declaration section)"
elif [ "$profile_section_status" -ne 0 ]; then
  fail "could not parse the write-intent declaration section in '$PROFILE'"
fi
decl_rows="$(printf '%s\n' "$profile_section" | grep -E '^ {0,3}\|[[:blank:]]*`[a-z][a-z-]*`[[:blank:]]*\|')" || decl_rows=""
if [ -z "$decl_rows" ]; then
  fail "profile surface '$PROFILE' carries no write-intent declaration rows (repair: restore the \"Write intents\" table)"
fi

duplicate_workflows="$(printf '%s\n' "$decl_rows" | sed -E 's/^ {0,3}\|[[:blank:]]*`([a-z][a-z-]*)`[[:blank:]]*\|.*/\1/' | sort | uniq -d)"
while IFS= read -r wf; do
  [ -n "$wf" ] || continue
  fail "duplicate declaration rows for workflow '$wf' in '$PROFILE' (repair: keep exactly one row per workflow)"
done <<< "$duplicate_workflows"

declared_workflows=""
while IFS= read -r row; do
  [ -n "$row" ] || continue
  row="$(printf '%s' "$row" | sed -E 's/[[:space:]]+$//')"
  wf="$(printf '%s' "$row" | sed -E 's/^ {0,3}\|[[:blank:]]*`([a-z][a-z-]*)`[[:blank:]]*\|.*/\1/')"
  cell="$(printf '%s' "$row" | sed -E 's/^ {0,3}\|[[:blank:]]*`[a-z][a-z-]*`[[:blank:]]*\|(.*)\|$/\1/')"
  declared_workflows="$declared_workflows $wf"
  intents="$(printf '%s' "$cell" | grep -oE '\[[a-z][a-z-]* output\]')" || intents=""
  if [ -z "$intents" ]; then
    # An empty intent list is legal ONLY as the literal `none`.
    if ! printf '%s' "$cell" | grep -qE '^[[:space:]]*none[[:space:]]*$'; then
      fail "workflow '$wf' declares neither an intent role nor the literal 'none' in '$PROFILE' (repair: declare its allowed intents, or 'none' for a read-only posture)"
    fi
    continue
  fi
  while IFS= read -r intent; do
    [ -n "$intent" ] || continue
    if ! in_family "$intent"; then
      fail "workflow '$wf' declares '$intent', which is not in the contract's closed family ('$CONTRACT') (repair: use a family role, or add the role there by reviewed PR)"
    fi
  done <<< "$intents"
done <<< "$decl_rows"

for wf in $declared_workflows; do
  if ! printf '%s\n' $REQUIRED_WORKFLOWS | grep -qFx "$wf"; then
    fail "profile workflow '$wf' is absent from the required-workflow catalog (repair: add it to the authoritative catalog by reviewed change, or remove the declaration)"
  fi
done

for wf in $REQUIRED_WORKFLOWS; do
  if ! printf '%s\n' $declared_workflows | grep -qFx "$wf"; then
    fail "writing workflow '$wf' has no declaration row in '$PROFILE' — a missing row is a defect, not an implicit empty set (repair: add its row, 'none' if it writes nothing)"
  fi
done

# --- 5. Leak scan (direction b): neutral workflow docs must not name concrete
# tracker write commands — an intent role exists for each of these operations.
LEAK_PATTERN="${WIC_LEAK_PATTERN:-\bgh[[:space:]]+(issue|pr)[[:space:]]+(create|comment|edit|close|reopen|delete|transfer|pin|merge|review|ready|lock|unlock)\b|\bgh[[:space:]]+api\b}"
printf '' | grep -E "$LEAK_PATTERN" >/dev/null 2>&1
leak_pattern_status=$?
if [ "$leak_pattern_status" -gt 1 ]; then
  fail "WIC_LEAK_PATTERN is not a valid extended regular expression (repair: provide an ERE accepted by grep -E)"
  LEAK_PATTERN='a^'
fi
if [ -n "${WIC_WORKFLOW_DIR+x}" ]; then
  docs="$(find "$WORKFLOW_DIR" -name '*.md' -type f | sort)"
else
  docs="$(git ls-files "$WORKFLOW_DIR" | grep -E '[.]md$')" || docs=""
fi
if [ -z "$docs" ]; then
  fail "no neutral workflow docs found under '$WORKFLOW_DIR' — the leak scan has nothing to cover (P2, never a vacuous pass)"
fi
while IFS= read -r doc; do
  [ -n "$doc" ] || continue
  hits="$(grep -nE "$LEAK_PATTERN" "$doc")" || hits=""
  if [ -n "$hits" ]; then
    while IFS= read -r hit; do
      fail "concrete tracker write command in neutral doc $doc:${hit%%:*} — name the write-intent role instead (P1): ${hit#*:}"
    done <<< "$hits"
  fi
done <<< "$docs"

if [ "$failures" -gt 0 ]; then
  echo "write-intents check: FAIL ($failures finding(s))" >&2
  exit 1
fi
family_n="$(printf '%s\n' "$family" | grep -c .)"
echo "write-intents check: OK (closed family of $family_n intent role(s); adapter catalog/discovery agree and every table maps the family; no neutral-doc write-command leak)"
