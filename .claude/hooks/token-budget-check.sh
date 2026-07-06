#!/usr/bin/env bash
# Context token-budget check (T1201, spec 007 US1; epic #166).
#
# Measures the named context artifacts/bundles in .claude/context-budgets.md
# (the owner-ratified registry — budgets, gating, and composition live THERE,
# never here; the tooling reads budgets, it never chooses them, US1.AC1) and
# reports per-file and per-bundle token counts. A surface whose row is gating
# `active` FAILs when it exceeds its budget; a `deferred` surface is measured
# and reported only (US1.AC1's deferred-activation rule — each of US2-US5's AC1
# activates its own gate in the diff that lands/restructures its surface).
#
# Counter identity (a project/adapter fact, documented beside the budgets in
# the registry, never in workflow/**): tiktoken, o200k_base encoding, via
# python3 — the counter the #166 baselines used. When the counter is
# unavailable the check fails OPEN locally (loud warning, exit 0) like the
# other tool-dependent hooks; CI passes --require-counter so an unmeasured run
# can never go silently green there (the silently-dead-guard class, P2).
#
# Resolves paths relative to CWD (the same CWD contract the other repo checks
# use; CI runs it from the repo root).
# Run: bash .claude/hooks/token-budget-check.sh [--require-counter]
# Seams: TOKEN_BUDGET_PYTHON overrides the python interpreter (tests use it to
# simulate a missing counter).
set -u

REGISTRY=".claude/context-budgets.md"
PYTHON="${TOKEN_BUDGET_PYTHON:-python3}"
REQUIRE_COUNTER=0

for arg in "$@"; do
  case "$arg" in
    --require-counter) REQUIRE_COUNTER=1 ;;
    *)
      echo "usage: bash .claude/hooks/token-budget-check.sh [--require-counter]" >&2
      exit 2
      ;;
  esac
done

if [ ! -f "$REGISTRY" ]; then
  echo "FAIL: $REGISTRY not found in $(pwd) — run the check from the repo root" >&2
  echo "      (repair: restore the registry, or fix the CWD; the budgets live in $REGISTRY)" >&2
  exit 1
fi

if ! "$PYTHON" -c 'import tiktoken' >/dev/null 2>&1; then
  if [ "$REQUIRE_COUNTER" -eq 1 ]; then
    echo "FAIL: token counter unavailable ($PYTHON with tiktoken, o200k_base — identity per $REGISTRY)." >&2
    echo "      --require-counter forbids the fail-open path (repair: install tiktoken for $PYTHON)." >&2
    exit 1
  fi
  echo "WARN: token counter unavailable ($PYTHON with tiktoken) — skipping the budget check (fail-open)." >&2
  echo "      CI runs this check with --require-counter, so the budgets are still enforced there." >&2
  exit 0
fi

# count_files <listfile>: newline-separated file paths in <listfile> ->
# "<tokens>\t<path>" per line on stdout. The list travels as an argv file, not
# stdin — the heredoc carrying the program already occupies stdin.
count_files() {
  "$PYTHON" - "$1" <<'PYEOF'
import sys
import tiktoken
enc = tiktoken.get_encoding("o200k_base")
with open(sys.argv[1], "r", encoding="utf-8") as listing:
    paths = [ln.rstrip("\n") for ln in listing]
for path in paths:
    if not path:
        continue
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        text = fh.read()
    print(f"{len(enc.encode(text))}\t{path}")
PYEOF
}

# first_token <cell>: the first `backticked` token in a table cell (empty if none).
first_token() {
  printf '%s\n' "$1" | sed -n 's/[^`]*`\([^`]*\)`.*/\1/p'
}

# expand_paths <token>: existing files the token matches, one per line. `*` is
# the only glob syntax expanded (the registry's documented composition grammar);
# any other token is a literal path.
expand_paths() {
  if [ "${1#*"*"}" != "$1" ]; then
    compgen -G "$1" || true
  else
    if [ -f "$1" ]; then printf '%s\n' "$1"; fi
  fi
}

failures=0
surfaces=0

while IFS= read -r line; do
  case "$line" in
    '| `'*) ;;
    *) continue ;;
  esac

  IFS='|' read -r _ c_surface c_mode c_budget c_gating c_composition _ <<EOF
$line
EOF
  surface="$(first_token "$c_surface")"
  mode="$(first_token "$c_mode")"
  budget="$(first_token "$c_budget")"
  gating="$(first_token "$c_gating")"

  surfaces=$((surfaces + 1))

  case "$mode" in
    total|each) ;;
    *)
      echo "FAIL: surface '$surface': unknown mode '$mode' in $REGISTRY (repair: set the row's mode to total or each)" >&2
      failures=$((failures + 1)); continue
      ;;
  esac
  case "$gating" in
    active|deferred) ;;
    *)
      echo "FAIL: surface '$surface': unknown gating '$gating' in $REGISTRY (repair: set the row's gating to active or deferred)" >&2
      failures=$((failures + 1)); continue
      ;;
  esac
  case "$budget" in
    ''|*[!0-9]*)
      echo "FAIL: surface '$surface': non-numeric budget '$budget' in $REGISTRY (repair: set the row's budget to a token count)" >&2
      failures=$((failures + 1)); continue
      ;;
  esac

  files=""
  unmatched=""
  comp_tokens="$(printf '%s\n' "$c_composition" | grep -o '`[^`]*`' | tr -d '\140')"
  while IFS= read -r tok; do
    [ -n "$tok" ] || continue
    matched="$(expand_paths "$tok")"
    if [ -n "$matched" ]; then
      files="$files$matched
"
    else
      unmatched="$unmatched $tok"
    fi
  done <<EOF
$comp_tokens
EOF

  echo "surface $surface (mode: $mode, budget: $budget tokens, gating: $gating)"

  # An active surface may not silently under-count: ANY composition token that
  # matches no file (a renamed artifact, a typo'd path) FAILs loud rather than
  # letting the remaining files pass a gate the full surface might not.
  if [ -n "$unmatched" ]; then
    if [ "$gating" = "active" ]; then
      echo "FAIL: surface '$surface': gating is active but composition token(s)$unmatched match no files (repair: fix the row's composition in $REGISTRY, or land the artifact)" >&2
      failures=$((failures + 1))
    else
      echo "  (unmatched composition token(s)$unmatched — registered, not yet landed)"
    fi
  fi

  if [ -z "$files" ]; then
    if [ "$gating" != "active" ]; then
      echo "  (not yet landed — registered, no matching files)"
    fi
    continue
  fi

  listfile="$(mktemp)"
  printf '%s' "$files" > "$listfile"
  # A counting failure past the import probe (encoding fetch/load failure, an
  # unreadable matched file) is a broken MEASUREMENT, not an unavailable
  # counter: it FAILs hard on every surface — never a silent `total: 0` that
  # lets --require-counter go green unmeasured.
  count_status=0
  counts="$(count_files "$listfile")" || count_status=$?
  rm -f "$listfile"
  if [ "$count_status" -ne 0 ]; then
    echo "FAIL: surface '$surface': token counting failed (exit $count_status) — the surface is unmeasured, not empty (see the counter's error above; identity per $REGISTRY)." >&2
    failures=$((failures + 1))
    continue
  fi
  total=0
  while IFS="$(printf '\t')" read -r n path; do
    [ -n "$n" ] || continue
    echo "  $n	$path"
    total=$((total + n))
    if [ "$mode" = "each" ] && [ "$n" -gt "$budget" ]; then
      if [ "$gating" = "active" ]; then
        echo "FAIL: surface '$surface': $path measured $n tokens, over the $budget-token per-file budget." >&2
        echo "      Trim $path, or raise the budget in $REGISTRY via an owner-ratified PR (the override path)." >&2
        failures=$((failures + 1))
      else
        echo "  note: $path is $n tokens, over the registered (deferred) $budget-token per-file budget — the gate activates with the owning task's diff"
      fi
    fi
  done <<EOF
$counts
EOF

  echo "  total: $total tokens"
  if [ "$mode" = "total" ] && [ "$total" -gt "$budget" ]; then
    if [ "$gating" = "active" ]; then
      echo "FAIL: surface '$surface' measured $total tokens, over its $budget-token budget." >&2
      echo "      Trim the composition file(s) named above, or raise the budget in $REGISTRY via an owner-ratified PR (the override path)." >&2
      failures=$((failures + 1))
    else
      echo "  note: over the registered (deferred) budget — the gate activates with the owning task's diff"
    fi
  fi
done < "$REGISTRY"

if [ "$surfaces" -eq 0 ]; then
  echo "FAIL: no surface rows parsed from $REGISTRY (repair: restore the registry's surfaces table)" >&2
  exit 1
fi

if [ "$failures" -gt 0 ]; then
  echo "token budgets: FAIL ($failures failure(s) across $surfaces surface(s))" >&2
  exit 1
fi
echo "token budgets: OK ($surfaces surface(s) measured)"
