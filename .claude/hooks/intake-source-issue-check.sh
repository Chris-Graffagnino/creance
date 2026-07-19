#!/usr/bin/env bash
# intake-source-issue-check.sh — reject closing-keyword references to an intake
# conversion PR's source issue (#263).
#
# GitHub-style closing-keyword parsing is negation-blind: "does not close #263"
# still closes issue #263 when the PR merges. This pre-open check accepts the
# composed PR body and source issue number explicitly, then rejects only the
# closing-reference shape for that source issue. References to other issues are
# outside this check's narrow contract.
#
# Run: bash .claude/hooks/intake-source-issue-check.sh --source-issue <n> --source-repository <owner>/<repo> --body-file <path>
set -u
export LC_ALL=C

usage() {
  echo "usage: $0 --source-issue <positive issue number> --source-repository <owner>/<repo> --body-file <path>" >&2
}

source_issue=""
source_repository=""
body_file=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --source-issue)
      if [ -n "$source_issue" ] || [ "$#" -lt 2 ]; then
        usage
        exit 2
      fi
      source_issue="$2"
      shift 2
      ;;
    --body-file)
      if [ -n "$body_file" ] || [ "$#" -lt 2 ]; then
        usage
        exit 2
      fi
      body_file="$2"
      shift 2
      ;;
    --source-repository)
      if [ -n "$source_repository" ] || [ "$#" -lt 2 ]; then
        usage
        exit 2
      fi
      source_repository="$2"
      shift 2
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

if ! [[ "$source_issue" =~ ^[1-9][0-9]*$ ]]; then
  echo "FAIL: --source-issue must be a positive issue number" >&2
  exit 2
fi
if ! [[ "$source_repository" =~ ^[[:alnum:]_.-]+/[[:alnum:]_.-]+$ ]]; then
  echo "FAIL: --source-repository must be an owner/repository name" >&2
  exit 2
fi
if [ -z "$body_file" ] || [ ! -r "$body_file" ]; then
  echo "FAIL: --body-file must name a readable file" >&2
  exit 2
fi

# Match GitHub's closing-keyword family only when it directly precedes the
# explicit source-issue reference. GitHub accepts a colon after the keyword
# and a repository-qualified reference as well as #N. Newlines are whitespace
# too, so flatten the composed body before matching. Only the explicit source
# repository's qualified form is unsafe. The leading boundary avoids treating a
# longer ordinary word as a keyword (for example, "unclosed").
source_repository_pattern="${source_repository//./[.]}"
source_reference="(#${source_issue}([^0-9]|$)|${source_repository_pattern}#${source_issue}([^0-9]|$))"
pattern="(^|[^[:alnum:]_])(close[sd]?|fix(e[sd])?|resolve[sd]?)(:[[:space:]]*|[[:space:]]+)${source_reference}"
if ! body_text="$(tr '\n' ' ' < "$body_file")"; then
  echo "FAIL: could not read --body-file '$body_file'" >&2
  exit 2
fi
matches="$(printf '%s\n' "$body_text" | grep -Ei -- "$pattern")"
grep_status=$?

if [ "$grep_status" -eq 0 ]; then
  echo "FAIL: PR body contains a closing-keyword reference to source issue #$source_issue" >&2
  echo "      Keep #$source_issue away from close/fix/resolve verbs; for example, write 'the source issue (#$source_issue) remains open'." >&2
  printf '%s\n' "$matches" >&2
  exit 1
fi
if [ "$grep_status" -ne 1 ]; then
  echo "FAIL: could not scan --body-file '$body_file'" >&2
  exit 2
fi

echo "source-issue reference check: OK (no closing-keyword reference to #$source_issue)"
