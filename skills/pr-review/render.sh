#!/usr/bin/env bash
# Renders only the repo context relevant to this review, so unrelated stack and
# ticket-tracker guidance never enters the prompt.
#
# Usage: render.sh [any args] — recognised tokens are picked out, everything else ignored.
#   stack:  typescript|ts python|py pnpm npm yarn bun poetry|poe uv
#           supabase postgres|pg mongo|mongodb
#   ticket: monday github|gh|issues jira|atlassian linear none|noticket
#   target: local | <pr number>
# Detection, fragments and the gh helpers live in ../_shared.

set -uo pipefail

# pr-sweep renders this context in prepare.sh (with the PR's environment block) before the reviewer runs
# the skill; re-rendering would repeat the database checks against a detached checkout.
if [ -n "${PR_SWEEP_CONTEXT:-}" ] && [ -f "$PR_SWEEP_CONTEXT" ]; then cat "$PR_SWEEP_CONTEXT"; exit 0; fi

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../_shared/gh.sh"
. "$DIR/../_shared/stack.sh"

parse_args "$@"
detect_stack
detect_ticket
print_repo_facts

PR_FIELDS="number,title,url,state,isDraft,baseRefName,headRefName,labels,body,closingIssuesReferences"
PR_JSON=""
PR_BASE=""

if [ "$TARGET" != "local" ] && command -v gh >/dev/null 2>&1; then
  PR_JSON="$(gh_json pr view $TARGET --json "$PR_FIELDS")"
fi

if [ -n "$PR_JSON" ]; then
  PR_BASE="$(printf '%s' "$PR_JSON" | gh_jq '.baseRefName')"
  echo "### Pull request"
  echo
  echo "#$(printf '%s' "$PR_JSON" | gh_jq '.number') $(printf '%s' "$PR_JSON" | gh_jq '.title')"
  echo "$(printf '%s' "$PR_JSON" | gh_jq '.url')"
  echo "State: $(printf '%s' "$PR_JSON" | gh_jq '.state')$(printf '%s' "$PR_JSON" | gh_jq 'if .isDraft then " (draft)" else "" end')  ·  $(printf '%s' "$PR_JSON" | gh_jq '.headRefName') -> $(printf '%s' "$PR_JSON" | gh_jq '.baseRefName')"
  LABELS="$(printf '%s' "$PR_JSON" | gh_jq '[.labels[].name] | join(", ")')"
  [ -n "$LABELS" ] && echo "Labels: $LABELS"
  echo
  echo "Description (verbatim — this is the author's stated intent, do not re-fetch it):"
  echo
  printf '%s' "$PR_JSON" | gh_jq '.body' | sed 's/^/  | /' | head -200
  echo
  LINKED="$(printf '%s' "$PR_JSON" | gh_jq '.closingIssuesReferences[] | "#\(.number) \(.url)"' 2>/dev/null)"
  if [ -n "$LINKED" ]; then
    echo "Closing issue references (gh-parsed):"
    printf '%s\n' "$LINKED" | sed 's/^/  /'
    echo
  fi
  THREADS="$(gh_t pr view $TARGET --comments | head -120)"
  if [ -n "$THREADS" ]; then
    echo "Existing review comments (first 120 lines — reviewer concerns already raised):"
    printf '%s\n' "$THREADS" | sed 's/^/  | /'
    echo
  fi
elif [ "$TARGET" = "local" ]; then
  echo "### Branch-diff mode (requested)"
  echo
  echo "PR lookup skipped. There is no PR description and no review thread — intent comes from the ticket (§2)"
  echo "and the branch's commit messages. Label the report header branch-diff mode."
  echo
elif [ -n "$TARGET" ]; then
  echo "### PR #$TARGET did not resolve"
  echo
  echo "A specific PR was asked for and \`gh\` returned nothing: wrong number, wrong repo, or \`gh\` unavailable."
  echo "Stop and tell the user. Do not review the current branch instead — that is a different diff than the one"
  echo "they asked about."
  echo
  exit 0
else
  echo "### No PR for this branch — reviewing the branch diff instead"
  echo
  echo "No PR is open for \`$HEAD_BRANCH\` (or \`gh\` is unavailable). Continuing in branch-diff mode against the"
  echo "base below. There is no PR description and no review thread, so intent comes from the ticket (§2) and the"
  echo "branch's commit messages. Say so in the report header and in Issue Coverage — don't let it read as though"
  echo "a PR was reviewed."
  echo
fi

[ -n "$PR_JSON" ] && align_head_ref "$(printf '%s' "$PR_JSON" | gh_jq '.headRefName')"
resolve_base_ref "$PR_BASE"
if [ -n "$PR_JSON" ]; then
  print_diff_scope
else
  print_diff_scope with-commits
fi

print_ticket_block "$PR_JSON"
print_stack_fragments || exit 0
maybe_db_check

exit 0
