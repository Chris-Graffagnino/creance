#!/usr/bin/env bash
# Regression tests for status-map.sh — the read-only, observe-only harness status map
# (T638, issue #234).
#
# Every case runs the REAL map against a throwaway git repo fixture and asserts on THAT
# case's own output (issue #234 criterion 4: a single fixed-string-anywhere assertion does
# not satisfy the per-case requirement — so each axis below is driven to BOTH of its
# states and the two outputs are asserted to differ in the specific field).
#
# The two degradations are proven two-sided (criterion 2): with `gh` present and answering,
# the REAL pr number must render (a build that always prints `unknown` fails here); with
# `gh` genuinely absent from PATH, or present-but-failing, the field must read `unknown`
# with exit 0 and the local static summary intact (a build that hard-errors offline fails
# here). Lock-present vs lock-absent is proven the same way.
#
# The fixture lock carries DISTINCTIVE values (`fixture-verify`, `/fixture/telemetry.jsonl`)
# that appear in no real repo doc, so "static facts come from the lock" (criterion 3) is
# proven by the value's provenance rather than by a string that PROJECT.md would satisfy too.
#
# Bash + git only, <5s; wired into the `verify` CI job.
# Run: bash .claude/hooks/status-map.test.sh
set -u

DIR="$(cd "$(dirname "$0")" && pwd)"
MAP="$DIR/status-map.sh"
REPO_ROOT="$(cd "$DIR/../.." && pwd)"
CI="$REPO_ROOT/.github/workflows/ci.yml"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
pass=0
fail=0

# The documented output budget (status-map.sh header + .claude/README.md). The map is an
# orientation surface: it must stay one screen, never grow into a dashboard (#234 non-goals).
BUDGET_LINES=60

ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); printf 'FAIL %s\n' "$1" >&2; }

# has <file> <needle> <name> — assert THIS case's output contains <needle>.
# `--` before the pattern is load-bearing: every field assertion below starts with the
# Markdown list dash, which grep would otherwise parse as an option bundle.
has() {
  if grep -qF -- "$2" "$1"; then ok; else
    bad "$3 — output does not contain: $2"
    sed -n '1,12p' "$1" | sed 's/^/      | /' >&2
  fi
}
# hasnt <file> <needle> <name> — assert THIS case's output does NOT contain <needle>.
hasnt() {
  if grep -qF -- "$2" "$1"; then bad "$3 — output unexpectedly contains: $2"; else ok; fi
}

# mkrepo <dir> [nolock] — a throwaway repo: origin remote, a tasks file, a seed commit on
# `main`, and (unless `nolock`) a HARNESS.lock.json carrying distinctive fixture values.
mkrepo() {
  local d="$1" lock="${2:-lock}"
  mkdir -p "$d/.claude" "$d/specs/001-x"
  git init -q -b main "$d"
  git -C "$d" config user.email t@example.com
  git -C "$d" config user.name test
  git -C "$d" remote add origin git@github.com:acme/widgets.git
  printf -- '- [ ] T900 [strong] an unchecked task\n' > "$d/specs/001-x/tasks.md"
  if [ "$lock" = lock ]; then
    cat > "$d/.claude/HARNESS.lock.json" <<'JSON'
{
  "schema_version": 7,
  "profile": {
    "base_branch": "main",
    "required_check": "fixture-verify",
    "merge_gate": "fixture-gate",
    "constitution_path": "memory/fixture-constitution.md",
    "spec_paths": ["specs/001-x/spec.md", "specs/002-y/spec.md"],
    "tasks_paths": ["specs/001-x/tasks.md"]
  },
  "autonomy": {"opt_in": "disabled"},
  "review_passes": [
    {"role": "[code-review pass]", "enabled": "true", "condition": "always"},
    {"role": "[off pass]", "enabled": "false", "condition": "always"}
  ],
  "edit_time_checks": [{"glob": "*.sh", "checker": ".claude/hooks/fixture-lint.sh"}],
  "observe_only_channels": {"telemetry": {"path": "/fixture/telemetry.jsonl"}}
}
JSON
  fi
  git -C "$d" add -A
  git -C "$d" commit -qm "chore: seed"
}

# run_map <root> <outfile> [PATH-override] — run the REAL map; echo its exit code.
run_map() {
  local root="$1" out="$2" pathv="${3:-$PATH}" rc=0
  PATH="$pathv" STATUS_MAP_ROOT="$root" bash "$MAP" > "$out" 2>"$out.err" || rc=$?
  printf '%s' "$rc"
}

# stub_gh <dir> <mode> — a PATH dir whose `gh` either answers with a PR number (ok) or
# fails like an unauthenticated/offline CLI (fail).
stub_gh() {
  local d="$1" mode="$2"
  mkdir -p "$d"
  if [ "$mode" = ok ]; then
    printf '#!/bin/sh\necho 4242\n' > "$d/gh"
  else
    printf '#!/bin/sh\necho "gh: could not connect to github.com" >&2\nexit 1\n' > "$d/gh"
  fi
  chmod +x "$d/gh"
}

# path_without_gh <dir> — a PATH holding symlinks to exactly the tools the map needs and
# deliberately NO gh, so `command -v gh` genuinely fails. This is TRUE absence, which
# exercises the `command -v` guard; the failing stub above exercises the error branch —
# the two unavailability modes are distinct paths through the map, so both are tested.
# `bash`/`env` are in the list because run_map's `PATH=... bash "$MAP"` resolves the
# interpreter through this very PATH.
path_without_gh() {
  local d="$1" t src
  mkdir -p "$d"
  for t in bash env git python3 sed grep sort head cut tr wc cat dirname uname; do
    src="$(command -v "$t" 2>/dev/null)" && ln -sf "$src" "$d/$t"
  done
  # Guard the guard: if gh leaked in, the "absent" case would silently test nothing.
  [ ! -e "$d/gh" ] || bad "path_without_gh: the fixture PATH unexpectedly contains gh"
}

# ---------------------------------------------------------------------------------
# base branch vs feature branch — the SAME repo, driven to both states
# ---------------------------------------------------------------------------------
mkrepo "$TMP/base"
stub_gh "$TMP/ghok" ok
GHOK="$TMP/ghok:$PATH"

rc="$(run_map "$TMP/base" "$TMP/base.out" "$GHOK")"
[ "$rc" = 0 ] && ok || bad "base branch: want exit 0, got $rc"
has "$TMP/base.out" '- current branch: main'   'base branch'
has "$TMP/base.out" '- on base branch: yes'    'base branch'
has "$TMP/base.out" '- issue: unknown'         'base branch (no issue# in a base branch name)'

git -C "$TMP/base" switch -qc chore/234-harness-status-map
rc="$(run_map "$TMP/base" "$TMP/feat.out" "$GHOK")"
[ "$rc" = 0 ] && ok || bad "feature branch: want exit 0, got $rc"
has "$TMP/feat.out" '- current branch: chore/234-harness-status-map' 'feature branch'
has "$TMP/feat.out" '- on base branch: no'                           'feature branch'
# The issue number is parsed from the branch name — a LOCAL read that survives an outage.
has "$TMP/feat.out" '- issue: #234'                                  'feature branch'

# The two runs must actually DIFFER in the field under test (not a constant string).
if grep -qF -- '- on base branch: yes' "$TMP/feat.out"; then
  bad "base-vs-feature: the on-base field is constant across branches"
else ok; fi

# The task id is read from the branch's own commit subjects, bracket-anchored.
git -C "$TMP/base" commit -q --allow-empty -m 'chore: [T900] do the thing'
run_map "$TMP/base" "$TMP/task.out" "$GHOK" >/dev/null
has "$TMP/task.out" '- task id: T900' 'task id from the branch commit subject'

# ---------------------------------------------------------------------------------
# clean vs dirty worktree — same repo, both states, count asserted
# ---------------------------------------------------------------------------------
mkrepo "$TMP/clean"
run_map "$TMP/clean" "$TMP/clean.out" "$GHOK" >/dev/null
has "$TMP/clean.out" '- worktree: clean' 'clean worktree'

printf 'edit\n' >> "$TMP/clean/specs/001-x/tasks.md"
printf 'new\n'  >  "$TMP/clean/untracked.txt"
run_map "$TMP/clean" "$TMP/dirty.out" "$GHOK" >/dev/null
has "$TMP/dirty.out" '- worktree: dirty (2 file(s))' 'dirty worktree names the count'
hasnt "$TMP/dirty.out" '- worktree: clean'           'dirty worktree'

# ---------------------------------------------------------------------------------
# tracker degradation — BOTH directions (issue #234 criterion 2)
# ---------------------------------------------------------------------------------
mkrepo "$TMP/gh"
git -C "$TMP/gh" switch -qc chore/77-thing

# (a) tracker AVAILABLE: the real value renders. An always-`unknown` build fails here.
run_map "$TMP/gh" "$TMP/ghup.out" "$GHOK" >/dev/null
has "$TMP/ghup.out" '- open PR: #4242'  'gh available renders the real PR number'
has "$TMP/ghup.out" '- tracker: reachable' 'gh available marks the tracker reachable'

# (b) tracker PRESENT BUT FAILING (unauthenticated / offline): unknown, exit 0.
stub_gh "$TMP/ghbad" fail
rc="$(run_map "$TMP/gh" "$TMP/ghdown.out" "$TMP/ghbad:$PATH")"
[ "$rc" = 0 ] && ok || bad "gh failing: want exit 0 (never a crash), got $rc"
has "$TMP/ghdown.out" '- open PR: unknown' 'gh failing degrades the PR field'
hasnt "$TMP/ghdown.out" '- open PR: #4242' 'gh failing must not guess a PR'
# ...and the LOCAL static summary is still fully present (never needs the network).
has "$TMP/ghdown.out" '- current branch: chore/77-thing' 'gh failing keeps local branch state'
has "$TMP/ghdown.out" '- required check: fixture-verify' 'gh failing keeps static profile facts'
has "$TMP/ghdown.out" '## Observe-only channels'         'gh failing keeps the full map'

# (c) tracker genuinely ABSENT from PATH: same explicit degradation, exit 0.
path_without_gh "$TMP/nogh"
rc="$(run_map "$TMP/gh" "$TMP/nogh.out" "$TMP/nogh")"
[ "$rc" = 0 ] && ok || bad "gh absent: want exit 0 (no network needed for static), got $rc"
has "$TMP/nogh.out" '- open PR: unknown'                'gh absent degrades the PR field'
has "$TMP/nogh.out" '- current branch: chore/77-thing'  'gh absent keeps local branch state'
has "$TMP/nogh.out" '- slug: acme/widgets'              'gh absent still derives the slug from git'

# ---------------------------------------------------------------------------------
# the lock is the source of static facts (criterion 3) — and its absence degrades
# ---------------------------------------------------------------------------------
mkrepo "$TMP/lock"
run_map "$TMP/lock" "$TMP/lock.out" "$GHOK" >/dev/null
# Distinctive fixture values: these exist in no real doc, so a hit proves the LOCK was read.
has "$TMP/lock.out" '- required check: fixture-verify'             'lock read: required check'
has "$TMP/lock.out" '- merge gate: fixture-gate'                   'lock read: merge gate'
has "$TMP/lock.out" '- constitution: memory/fixture-constitution.md' 'lock read: constitution path'
has "$TMP/lock.out" '.claude/hooks/fixture-lint.sh'                'lock read: edit-time checks'
has "$TMP/lock.out" '/fixture/telemetry.jsonl'                     'lock read: telemetry path'
has "$TMP/lock.out" '- harness manifest: present (schema 7)'       'lock read: schema version'
has "$TMP/lock.out" 'specs: 2 | tasks files: 1'                    'lock read: spec/tasks counts'
# Only the ENABLED passes render.
has "$TMP/lock.out"   '[code-review pass] (always)' 'lock read: enabled review pass'
hasnt "$TMP/lock.out" '[off pass]'                  'lock read: a disabled pass is filtered out'

mkrepo "$TMP/nolock" nolock
rc="$(run_map "$TMP/nolock" "$TMP/nolock.out" "$GHOK")"
[ "$rc" = 0 ] && ok || bad "lock absent: want exit 0 (soft dependency), got $rc"
has "$TMP/nolock.out" '- harness manifest: absent' 'lock absent is stated'
has "$TMP/nolock.out" '- required check: unknown'  'lock absent degrades static facts'

# `absent` and `unknown` are DIFFERENT claims: a lock that is present but unparseable was
# never established to be absent, so reporting `absent` there would be the map asserting a
# fact it does not have — the one thing its `unknown` contract forbids.
mkrepo "$TMP/badlock"
printf 'this is not json {{{\n' > "$TMP/badlock/.claude/HARNESS.lock.json"
rc="$(run_map "$TMP/badlock" "$TMP/badlock.out" "$GHOK")"
[ "$rc" = 0 ] && ok || bad "lock unparseable: want exit 0 (never a crash), got $rc"
has "$TMP/badlock.out"   '- harness manifest: unknown — present but unparseable' \
  'an unreadable lock reports unknown, never absent'
hasnt "$TMP/badlock.out" '- harness manifest: absent' \
  'an unreadable lock must not be reported as absent'
has "$TMP/badlock.out"   '- required check: unknown' 'an unreadable lock degrades static facts'
has "$TMP/badlock.out"   '- current branch: main'    'an unreadable lock keeps local repo state'
# ...but the map still carries its independent value (T638 soft-depends T637).
has "$TMP/nolock.out" '- current branch: main'     'lock absent keeps local repo state'
has "$TMP/nolock.out" '## Observe-only channels'   'lock absent keeps the full map'

# ---------------------------------------------------------------------------------
# observe-only channels are rendered AS observe-only (criterion 4)
# ---------------------------------------------------------------------------------
for chan in 'telemetry: /fixture/telemetry.jsonl — observes, never decides' \
            'maker-eval: see `.claude/PROJECT.md` § Paths — observes, never decides' \
            'this map: observes, never decides'
do
  has "$TMP/lock.out" "$chan" 'observe-only rendering'
done
has "$TMP/lock.out" 'Orientation only — never authority' 'the map disclaims authority'
has "$TMP/lock.out" 'no gate, tier, guard, selection, or autonomy path' 'the map states the P5 fence'

# ---------------------------------------------------------------------------------
# output budget (criterion 4) + Markdown shape
# ---------------------------------------------------------------------------------
lines="$(wc -l < "$TMP/lock.out" | tr -d ' ')"
if [ "$lines" -le "$BUDGET_LINES" ]; then ok; else
  bad "output budget: $lines lines exceeds the documented ceiling of $BUDGET_LINES"
fi
has "$TMP/lock.out" '# Harness status map' 'Markdown: the map has an H1'
# Nothing may leak to stderr on a healthy run (the map is a pipeable stdout artifact).
if [ -s "$TMP/lock.out.err" ]; then
  bad "healthy run wrote to stderr: $(head -1 "$TMP/lock.out.err")"
else ok; fi

# ---------------------------------------------------------------------------------
# read-only: running the map leaves the tree exactly as it was (criterion 1)
# ---------------------------------------------------------------------------------
mkrepo "$TMP/ro"
before="$(git -C "$TMP/ro" status --porcelain; git -C "$TMP/ro" rev-parse HEAD)"
run_map "$TMP/ro" "$TMP/ro.out" "$GHOK" >/dev/null
after="$(git -C "$TMP/ro" status --porcelain; git -C "$TMP/ro" rev-parse HEAD)"
if [ "$before" = "$after" ]; then ok; else bad "the map is not read-only: it changed the tree"; fi

# ---------------------------------------------------------------------------------
# the ONE hard failure: a local-repo error making even static status impossible
# ---------------------------------------------------------------------------------
mkdir -p "$TMP/notgit"
rc="$(run_map "$TMP/notgit" "$TMP/notgit.out")"
[ "$rc" = 2 ] && ok || bad "a non-git tree must exit 2 loud, got $rc"
rc="$(run_map "$TMP/does-not-exist" "$TMP/missing.out")"
[ "$rc" = 2 ] && ok || bad "an unreadable root must exit 2 loud, got $rc"

# ---------------------------------------------------------------------------------
# reuse, never fork (criterion 3, constitution P2)
# ---------------------------------------------------------------------------------
# BEHAVIOURAL, not a source grep: a fixture that is genuinely drifted by the SHARED lib's
# definition (an unchecked `- [ ] T900` box AND a reachable commit carrying `[T900]`) must
# make the map render that id. Only sourcing lib-tasks-drift.sh and running its functions
# produces this line, so a map that forked or dropped the lib cannot satisfy it.
# (A `grep 'lib-tasks-drift.sh' "$MAP"` here would be the vacuous shape §5 forbids — the
# header comment alone would satisfy it while the code sourced something else entirely.)
mkrepo "$TMP/drift"
git -C "$TMP/drift" commit -q --allow-empty -m 'chore: [T900] landed work for an unchecked box'
run_map "$TMP/drift" "$TMP/drift.out" "$GHOK" >/dev/null
has "$TMP/drift.out" '- tasks drift: done-but-unchecked: T900 (' \
  'drift line: the shared lib flags the id whose box is unchecked but whose work landed'
has "$TMP/drift.out" 'unchecked tasks: 1' 'unchecked count comes from the shared lib'

# ...and the mirror case: no landed commit for the unchecked box means no drift, so the
# line is not a constant either.
mkrepo "$TMP/nodrift"
run_map "$TMP/nodrift" "$TMP/nodrift.out" "$GHOK" >/dev/null
has "$TMP/nodrift.out"   '- tasks drift: none' 'drift line: an unchecked box with no landed work is not drift'
hasnt "$TMP/nodrift.out" 'done-but-unchecked'  'drift line is not a constant'
# The unchecked-box regex is the drift definition's own — a copy here would be the fork
# criterion 3 forbids (the id-from-subject read is a different question; guard.sh rule 8
# reads the same commit-subject convention at the same seam).
if grep -qE '\- \\\[ \\\]|\^\- \\\[ \\\] T' "$MAP"; then
  bad "the map carries a forked unchecked-box drift regex — source the shared lib instead"
else ok; fi

# The real tree renders a drift line sourced from the shared lib.
run_map "$REPO_ROOT" "$TMP/real.out" >/dev/null
has "$TMP/real.out" '- tasks drift:' 'real tree: the drift line renders from the shared lib'

# ---------------------------------------------------------------------------------
# CI wiring: the map's tests run in verify (constitution P2 — no silently dead checks)
# ---------------------------------------------------------------------------------
for step in \
  'run: bash \.claude/hooks/status-map\.test\.sh' \
  'run: bash \.claude/hooks/status-map-fence\.sh' \
  'run: bash \.claude/hooks/status-map-fence\.test\.sh'
do
  if grep -qE "^ +$step[[:space:]]*$" "$CI"; then ok; else
    bad "CI wiring: no active step matching $step in ci.yml"
  fi
done

# ---------------------------------------------------------------------------------
echo "status-map tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
