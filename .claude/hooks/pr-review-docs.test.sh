#!/usr/bin/env bash
# Encoding tests for issue #53 acceptance criteria (T601 — verified PR-review skill).
#
# Like the intake/triage procedures, the PR-review procedure is runtime-neutral
# prose executed by the engine — `.claude/workflow/pr-review.md` (and its Claude
# binding `.claude/skills/pr-review/SKILL.md`) ARE the implementation; there is no
# executable code path to unit-test. These tests therefore encode each acceptance
# criterion against that surface: the role-neutrality posture, the grounding gate
# (no "no findings" without adjudicating every inline comment AND grounding each
# finding to current source), the reconciliation-not-duplication with the review
# standard + §7 gate, and the binding's inline-comment fetch + additive-write
# posture must be present and stated as hard bounds, so a later edit that drops
# any of them fails the `verify` CI job (constitution P3: a rule a deterministic
# check can enforce must have that check).
#
# Extended by issue #96: the binding's inline-comment fetch must enumerate-then-
# filter (list all comments first, identify authors second) and match bots by their
# `[bot]` login suffix, so a bot-login mismatch (e.g. `chatgpt-codex-connector[bot]`
# vs a `chatgpt-codex-connector` filter) can never silently yield "no findings" —
# the fetch mechanism the neutral doc's grounding-gate policy depends on.
#
# Extended by T629 (#192, US8.AC3): pr-review's §5 output enumerates the enabled review
# passes that ran and DISTINGUISHES the two not-run cases — a disabled (or condition-not-
# met) pass is silent, an enabled-but-mechanism-absent pass is loud (named unavailable),
# never silently dropped. AC3's runtime pin is the AC6 probe (T631); these encode the doc
# contract so flattening the two cases back together fails `verify` (constitution P3).
#
# Run: bash .claude/hooks/pr-review-docs.test.sh
set -u

DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib-neutrality-scan.sh
. "$DIR/hooks/lib-neutrality-scan.sh"
WF="$DIR/workflow/pr-review.md"
SK="$DIR/skills/pr-review/SKILL.md"

pass=0
fail=0

# Normalize whitespace so assertions survive prose re-wrapping.
flat() { tr -s '[:space:]' ' ' < "$1"; }

check() { # check <name> <haystack> <needle (grep -F fixed string)>
  local name="$1" hay="$2" needle="$3"
  if printf '%s' "$hay" | grep -qF -- "$needle"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL %s\n     missing: %s\n' "$name" "$needle" >&2
  fi
}

for f in "$WF" "$SK"; do
  if [ ! -f "$f" ]; then
    echo "FAIL: required file missing: $f" >&2
    exit 1
  fi
done

WF_FLAT="$(flat "$WF")"
SK_FLAT="$(flat "$SK")"

# ── AC1 — neutral procedure in workflow/**, [role] language, composes roles ─────
check "AC1 neutral: composes existing roles only" "$WF_FLAT" \
  "composes existing roles only"
check "AC1 neutral: no new binding-contract row" "$WF_FLAT" \
  "introduces no new binding-contract row"
# Neutrality is also enforced negatively: no concrete runtime mechanism (a CLI
# name, tool name, or model ID) may appear in the neutral doc. The `.claude/`
# path prefix is the allowed profile pointer every neutral doc uses, so strip it
# before scanning (matches how contract-auditor reads the boundary). `git` is
# deliberately absent from the banned set below — it is the harness's assumed VCS
# substrate, exempt per constitution P1 / PROJECT.md "Invariant checklist".
mech="$(neutral_mechanism_leaks "$WF")"
if [ -z "$mech" ]; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  printf 'FAIL AC1 neutral: concrete runtime mechanism leaked into the neutral doc\n     found: %s\n' "$mech" >&2
fi

# ── AC2 — Claude skill binding, consistent with existing skills ─────────────────
check "AC2 binding: points at the neutral doc" "$SK_FLAT" \
  ".claude/workflow/pr-review.md"
check "AC2 binding: read-and-execute handoff (mirrors other skills)" "$SK_FLAT" \
  "read that file now and execute it."
check "AC2 binding: references the single-copy comment marker" "$SK_FLAT" \
  "The [comment marker] concrete form"
check "AC2 binding: read-then-comment posture in frontmatter" "$SK_FLAT" \
  "Read-then-comment only"

# ── AC3 — the no-"no findings" rule, encoded explicitly in the procedure ────────
check "AC3 gate: header forbids unverified no-findings" "$WF_FLAT" \
  'never "no findings" unverified'
check "AC3 gate: (a) every inline comment adjudicated" "$WF_FLAT" \
  "every inline comment has been enumerated and adjudicated"
check "AC3 gate: (b) each finding grounded to current file:line" "$WF_FLAT" \
  'grounded to a current `file:line`'
check "AC3 gate: bot/automated inline findings in scope (the Codex case)" "$WF_FLAT" \
  "bot/automated inline findings"

# ── AC2/AC3 mechanism — the binding actually fetches inline (line-anchored) comments ──
# `gh pr view --comments` returns only timeline comments; without the pulls
# endpoints the grounding gate's "every inline comment" clause is unsatisfiable.
check "AC3 mech: fetches inline review comments endpoint" "$SK_FLAT" \
  "pulls/<n>/comments"
check "AC3 mech: fetches review-summaries endpoint (some bots post here)" "$SK_FLAT" \
  "pulls/<n>/reviews"
check "AC3 mech: names the timeline-view gap it closes" "$SK_FLAT" \
  "timeline (issue-level)"

# ── issue #96 — enumerate-then-filter: a bot-login mismatch must not silently
#    yield "no findings". The binding lists all comments first and identifies
#    authors second; bots match by their `[bot]` suffix; an empty filtered set is
#    suspicious, so a login-string mismatch can't masquerade as a clean PR. The
#    policy ("no 'no findings' unverified") already lives in the neutral doc above;
#    these guard the binding's *fetch mechanism* that policy depends on. ──────────
check "#96 fetch: enumerate first, filter second (list all, identify authors second)" "$SK_FLAT" \
  "Enumerate first, filter second"
check "#96 fetch: bots matched by their [bot] login suffix, not an exact string" "$SK_FLAT" \
  '`[bot]` login suffix'
check "#96 fetch: the concrete login that bit us is the worked example" "$SK_FLAT" \
  "chatgpt-codex-connector[bot]"
check "#96 fetch: an empty filtered set is suspicious (login mismatch != clean PR)" "$SK_FLAT" \
  "empty filtered set as suspicious"
check "#96 fetch: no-findings needs the unfiltered count to be zero / all adjudicated" "$SK_FLAT" \
  "unfiltered comment count"
# Post-open review (PR #99 — Codex `[bot]` inline + owner relay): every source the
# no-findings count names must actually be fetched. The binding counted `timeline` but
# the PR-reads row's `gh pr view --json` list omitted `comments`, so a run could tally
# timeline as complete without ever fetching it — the same silent-clean defect.
check "#96 fetch: timeline/issue-level comments are fetched too (the third count source)" "$SK_FLAT" \
  "url,comments"
check "#96 fetch: every counted source must actually be fetched (no tallying an unfetched source)" "$SK_FLAT" \
  "Fetch every source you count"

# ── AC4 — reconciliation with the review standard + §7 gate, no duplication ──────
check "AC4 reconcile: applies the review standard's priority order" "$WF_FLAT" \
  "review standard's priority order"
check "AC4 reconcile: reuses reviewer specs, no restatement" "$WF_FLAT" \
  "rather than restating them"
check "AC4 reconcile: does not fork the auditors" "$WF_FLAT" \
  "it does not fork them"
check "AC4 reconcile: changes no §7 gate semantics" "$WF_FLAT" \
  "changes no pre-PR gate semantics"
# The shared review standard names pr-review.md as the open-PR application, so the
# reconciliation is visible from both sides (not just self-asserted in the new doc).
check "AC4 reconcile: review standard cross-links pr-review.md" \
  "$(flat "$DIR/workflow/README.md")" "which is the \`pr-review.md\` ritual"

# ── PR-diff scoping (review fix for PR #54 / codex finding) — the lens passes must
#    grade the PR's own diff, not the reviewer's branch. Root stated neutrally in
#    pr-review.md; the binding makes it concrete with a checkout step. ─────────────
check "scoping (neutral): every lens grades this PR's diff, not the reviewer's branch" "$WF_FLAT" \
  "Every lens grades *this PR's* diff, not the reviewer's branch"
check "scoping (binding): check out the PR head before the lens passes" "$SK_FLAT" \
  "Check out the PR head before the lens passes"
check "scoping (binding): concrete checkout mechanism" "$SK_FLAT" \
  "gh pr checkout <n>"
check "scoping (binding): names the non-main-base caveat" "$SK_FLAT" \
  "not based on \`main\`"

# ── Allowlist + MCP guidance (review fix for PR #54 / codex finding) — the gh api
#    reads are read-scoped (write-incapable) and owner-applied; MCP needs none. ────
check "allowlist (binding): read-scoped gh api form" "$SK_FLAT" \
  "gh api --method GET"
check "allowlist (binding): owner adds the entry; harness cannot self-grant" "$SK_FLAT" \
  "The harness cannot add these itself"
check "allowlist (binding): GitHub MCP server is the no-allowlist alternative" "$SK_FLAT" \
  "GitHub MCP server"

# ── Write posture — additive only; never merge/close/push (Out of scope) ────────
check "posture: never merges" "$WF_FLAT" \
  "never merges"
check "posture: opens no merge and closes nothing" "$WF_FLAT" \
  "closes nothing"
check "posture (binding): never merge/close the PR" "$SK_FLAT" \
  "\`gh pr merge\`, never \`gh pr close\`"

# ── US8.AC3 (T629) — pr-review honors the enabled review-pass set, and its §5 output
#    ENUMERATES the passes that ran while DISTINGUISHING the two not-run cases: a
#    disabled (or condition-not-met) pass is silent (no line), an enabled-but-mechanism-
#    absent pass is loud (named unavailable/degraded), never silently dropped. AC3's
#    *runtime* pin is the AC6 per-enabled-pass conformance probe (T631); these encode the
#    *doc contract* so a later edit that flattens the two not-run cases back together (all
#    silent, or all loud) fails `verify` (constitution P3: a rule a deterministic check
#    can enforce must have that check). ────────────────────────────────────────────────
check "US8.AC3 select: pr-review filters the set by applies-to + condition" "$WF_FLAT" \
  'whose `applies-to` includes `pr-review` (`pr-review`/`both`), each run on its `condition`'
check "US8.AC3 select: intro defers the output contract to §5" "$WF_FLAT" \
  'is the §5 output contract below'
check "US8.AC3 §5: a Review-passes-run element exists" "$WF_FLAT" \
  '**Review passes run** — each **enabled** pass'
check "US8.AC3 §5: enumerates each enabled pass run with its outcome" "$WF_FLAT" \
  'whose `applies-to` includes `pr-review` and whose `condition` held, **named with its outcome**'
check "US8.AC3 §5: disabled / condition-not-met pass is silent (no line)" "$WF_FLAT" \
  'a **disabled** pass — or an enabled one whose `condition` did not hold — produces **no** line (silent, a project choice)'
check "US8.AC3 §5: enabled-but-mechanism-absent pass is named loudly" "$WF_FLAT" \
  'an **enabled** pass whose backing mechanism is **absent** is named here **loudly** as **unavailable/degraded**'
check "US8.AC3 §5: cites the degradation rule (loud, never silently dropped)" "$WF_FLAT" \
  '"Note the degradation in the PR" rule'
check "US8.AC3 §5: flattening the two not-run cases together is rejected" "$WF_FLAT" \
  'Listing both cases the same way — all silent, or all loud — does not satisfy this'

echo "pr-review docs encoding tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
