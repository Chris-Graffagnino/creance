#!/usr/bin/env bash
# spec-lint.sh — deterministic spec-content lint over specs/*/spec.md
# (spec 002 US2.AC3, task T704).
#
# The spec-quality gate splits in two: a JUDGMENT [reviewer]
# (.claude/workflow/reviewers/spec-quality-auditor.md, T701/T703) owns the subtle
# forms — untestability, gameability, undocumented trade-offs — and THIS lint owns
# the unambiguously-mechanizable smells, so a model never carries the load-bearing
# decision a deterministic check can make (constitution P3, "add the backstop";
# the same AGENTS.md-residency pattern: a blunt deterministic floor, the auditor
# owning the rest). Three smells, scoped per user story:
#   * empty-ac     — an `- AC#:` bullet whose criterion text (after the label,
#                    across wrapped continuation lines) is whitespace-only.
#   * zero-acs     — a `### US#` story with no AC bullet at all.
#   * duplicate-ac — two AC bullets in the SAME story whose whitespace-normalized
#                    text is identical (AC3 "verbatim", read as normalized — see
#                    norm(); cross-story repeats do not fire — within a story).
#
# Prints ONE diagnostic per line to stdout (the shell-lint.sh format):
#     <file>:<line>: <rule>: <detail>
# Exit 1 when any diagnostic is printed, 0 when clean. Skips a missing file arg
# (like shell-lint.sh), so a stray glob is not a hard error.
#
# Consumed by CI `verify`: `bash .claude/hooks/spec-lint.sh specs/*/spec.md` is a
# standing gate over the live specs; the .test.sh (spec-lint.test.sh) is the P2
# liveness proof that it FIRES on each planted smell and does NOT false-fire on a
# clean spec. This file must itself stay BSD/GNU-portable — it is linted by
# shell-lint.sh over .claude/hooks/*.sh in CI — so the awk parser below uses NO
# regex intervals ({n}/{n,m}); only +/*/? quantifiers and character classes.
#
# The spec format it parses (all live specs follow it): user stories are `### US#`
# headings; acceptance criteria are column-0 `- AC#: <text>` bullets that may wrap
# onto indented continuation lines. A story runs from its `### US#` heading to the
# next heading (any `#`-led line) or EOF.
set -u

rc=0
for f in "$@"; do
  [ -f "$f" ] || continue

  awk -v F="$f" '
    # Normalize an AC for duplicate comparison: collapse internal whitespace
    # runs (so reflowed / rewrapped copy-paste still matches) and trim the ends.
    # This is the owner-ratified reading of AC3 "verbatim" (PR #153): a duplicate
    # is whitespace-NORMALIZED, not byte-exact. Byte-exact cannot compare wrapped
    # multi-line ACs at all and would miss reflowed duplicates; normalized is
    # strictly broader, so it never false-positives on genuinely distinct text
    # (confirmed: rc 0 on every live spec). Do not narrow this to byte-exact
    # without re-confirming the decision — dup_norm.md in the .test.sh pins it.
    function norm(s,   r) {
      r = s
      gsub(/[ \t]+/, " ", r)
      sub(/^ /, "", r)
      sub(/ $/, "", r)
      return r
    }
    # Close out the AC currently being accumulated: flag it empty, or record it
    # for within-story dedup (and flag a verbatim duplicate of an earlier one).
    function finalize_ac(   t, k) {
      if (!have_ac) return
      have_ac = 0
      t = norm(actext)
      if (t == "") {
        printf "%s:%d: empty-ac: %s.%s is empty (no criterion text)\n", F, acline, curus, aclabel
        n++
        return
      }
      k = curus SUBSEP t
      if (k in seen) {
        printf "%s:%d: duplicate-ac: %s.%s duplicates %s.%s verbatim\n", F, acline, curus, aclabel, curus, seen[k]
        n++
      } else {
        seen[k] = aclabel
      }
    }
    # Close out the current story: finalize its last AC, then flag zero ACs.
    function finalize_story() {
      if (curus == "") return
      finalize_ac()
      if (account == 0) {
        printf "%s:%d: zero-acs: %s has no acceptance criteria\n", F, ushdrline, curus
        n++
      }
    }
    BEGIN { curus = ""; have_ac = 0; account = 0; n = 0 }
    {
      line = $0
      sub(/\r$/, "", line)

      # Any heading ends the current story; a `### US#` heading opens a new one.
      if (line ~ /^#/) {
        finalize_story()
        if (line ~ /^### US[0-9]/) {
          h = line
          sub(/^#+[ \t]+/, "", h)
          match(h, /^US[0-9]+/)
          curus = substr(h, RSTART, RLENGTH)
          ushdrline = NR
        } else {
          curus = ""
        }
        have_ac = 0
        account = 0
        next
      }

      # A column-0 `- AC#:` bullet starts a new acceptance criterion.
      if (line ~ /^- AC[0-9]+:/) {
        finalize_ac()
        have_ac = 1
        acline = NR
        account++
        match(line, /^- AC[0-9]+/)
        aclabel = substr(line, 3, RLENGTH - 2)
        txt = line
        sub(/^- AC[0-9]+:[ \t]*/, "", txt)
        actext = txt
        next
      }

      # Any other column-0 list item, or a blank line, ends the current AC.
      if (line ~ /^- / || line ~ /^[ \t]*$/) {
        finalize_ac()
        next
      }

      # An INDENTED non-blank line is a wrapped continuation of the AC in
      # progress (the spec grammar indents continuations under the bullet;
      # blank/whitespace-only lines were already consumed above, so a line
      # reaching here with leading whitespace carries real continuation text).
      if (have_ac && line ~ /^[ \t]/) {
        cont = line
        sub(/^[ \t]+/, "", cont)
        actext = actext " " cont
        next
      }

      # Any other column-0 (unindented) line — ordinary prose — is NOT a
      # continuation: it ends the current AC, just like a blank line or a new
      # bullet. This keeps an empty `- AC#:` followed by unindented prose
      # caught as empty-ac instead of masked by the prose joining its text.
      finalize_ac()
    }
    END { finalize_story(); exit (n > 0 ? 1 : 0) }
  ' "$f" || rc=1
done

exit "$rc"
