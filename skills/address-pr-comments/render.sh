#!/usr/bin/env bash
# Gathers everything needed to work through a PR's review comments: the repo's stack and
# probe commands, the PR, the diff scope, the ticket, and the unresolved review threads.
#
# Usage: render.sh [any args] — recognised tokens are picked out, everything else ignored.
#   stack:  typescript|ts python|py pnpm npm yarn bun poetry|poe uv
#           supabase postgres|pg mongo|mongodb
#   ticket: monday github|gh|issues jira|atlassian linear none|noticket
#   target: <pr number>
# Detection, fragments and the gh helpers live in ../_shared.

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../_shared/gh.sh"
. "$DIR/../_shared/stack.sh"

parse_args "$@"
detect_stack
detect_ticket
print_repo_facts

PR_FIELDS="number,title,url,state,isDraft,baseRefName,headRefName,body,closingIssuesReferences"
PR_JSON=""
command -v gh >/dev/null 2>&1 && PR_JSON="$(gh_json pr view $TARGET --json "$PR_FIELDS")"

if [ -z "$PR_JSON" ]; then
  echo "### No PR resolved — stop here"
  echo
  if [ -n "$TARGET" ]; then
    echo "PR #$TARGET did not resolve: wrong number, wrong repo, or \`gh\` is unavailable."
  else
    echo "No PR is open for \`${HEAD_BRANCH:-this branch}\` (or \`gh\` is unavailable)."
  fi
  echo
  echo "This skill addresses reviewer comments, and without a PR there are none. Tell the user and stop —"
  echo "do not substitute a self-review of the branch. If they wanted that, /pr-review is the skill."
  echo
  exit 0
fi

PR_NUM="$(printf '%s' "$PR_JSON" | gh_jq '.number')"
PR_BASE="$(printf '%s' "$PR_JSON" | gh_jq '.baseRefName')"

echo "### Pull request"
echo
echo "#$PR_NUM $(printf '%s' "$PR_JSON" | gh_jq '.title')"
echo "$(printf '%s' "$PR_JSON" | gh_jq '.url')"
echo "State: $(printf '%s' "$PR_JSON" | gh_jq '.state')$(printf '%s' "$PR_JSON" | gh_jq 'if .isDraft then " (draft)" else "" end')  ·  $(printf '%s' "$PR_JSON" | gh_jq '.headRefName') -> $PR_BASE"
echo
echo "Description (verbatim — the author's stated intent, do not re-fetch it):"
echo
printf '%s' "$PR_JSON" | gh_jq '.body' | sed 's/^/  | /' | head -120
echo

align_head_ref "$(printf '%s' "$PR_JSON" | gh_jq '.headRefName')"
resolve_base_ref "$PR_BASE"
print_diff_scope
print_ticket_block "$PR_JSON"
print_stack_fragments
maybe_db_check

# --- review threads --------------------------------------------------------------------------------
# GraphQL, not the REST comments endpoint: only GraphQL exposes isResolved/isOutdated, and a
# resolved thread is work already done. Filtering runs through `gh api --jq` (gh's built-in jq)
# so this works on machines with no system jq.
SLUG="$(gh_repo_slug)"
OWNER="${SLUG%%/*}"
REPO="${SLUG##*/}"

GQL='query($owner:String!,$repo:String!,$pr:Int!){
  repository(owner:$owner,name:$repo){
    pullRequest(number:$pr){
      reviewThreads(first:100){
        nodes{
          id isResolved isOutdated path line originalLine
          comments(first:25){nodes{ author{login} body createdAt url diffHunk }}
        }
      }
      reviews(first:50){
        nodes{ author{login} state body submittedAt url }
      }
    }
  }
}'

gql() { gh_t api graphql -f query="$GQL" -F owner="$OWNER" -F repo="$REPO" -F pr="$PR_NUM" --jq "$1"; }

META=""
[ -n "$OWNER" ] && [ -n "$REPO" ] && META="$(gql '
  .data.repository.pullRequest as $pr
  | ($pr.reviewThreads.nodes) as $t
  | "@@COUNTS \([$t[] | select(.isResolved == false)] | length) \($t | length) \([$t[] | select(.isResolved)] | length)",
    ($pr.reviews.nodes | map(select((.body // "") != "")) | .[]
      | "  [\(.author.login // "unknown") · \(.state) · \(.submittedAt[0:10])] \(.body)")
')"

case "$META" in
  @@COUNTS*) ;;
  *)
    echo "### Review comments — could not be fetched"
    echo
    echo "The GraphQL call for \`$SLUG\` PR #$PR_NUM returned nothing (no access, or \`gh\` unavailable)."
    echo "Fetch them yourself before starting, and say which call you used:"
    echo
    echo '  gh api repos/{owner}/{repo}/pulls/<N>/comments --jq ".[] | {path, line, user: .user.login, body}"'
    echo '  gh pr view <N> --json reviews'
    echo
    exit 0
    ;;
esac

set -- $(printf '%s\n' "$META" | head -1)
OPEN_N="${2:-0}"; TOTAL_N="${3:-0}"; RESOLVED_N="${4:-0}"

echo "### Review comments: $OPEN_N unresolved thread(s) of $TOTAL_N ($RESOLVED_N already resolved, not shown)"
echo
if [ "$OPEN_N" = "0" ]; then
  echo "Nothing unresolved is left on this PR. Say so and stop — don't invent work from the resolved threads."
  echo
else
  echo "This is the agenda, in order. Work one thread at a time (§3); do not batch."
  echo "\`id=\` is the GraphQL thread id — it is what a reply or a resolve needs."
  echo
  gql '
    .data.repository.pullRequest.reviewThreads.nodes
    | map(select(.isResolved == false))
    | to_entries[]
    | "--- Thread \(.key + 1) · \(.value.path // "(no file)"):\(.value.line // .value.originalLine // "?") · id=\(.value.id)\(if .value.isOutdated then "  ·  OUTDATED — the code under this comment moved after it was written; re-read the file, do not trust the hunk below" else "" end)",
      "  code the comment was left on:",
      ((.value.comments.nodes[0].diffHunk // "") | split("\n") | .[-14:] | map("    " + .) | join("\n")),
      "",
      (.value.comments.nodes[] | "  [\(.author.login // "unknown") \(.createdAt[0:10])] \(.body)"),
      ""
  '
  echo
fi

REVIEWS="$(printf '%s\n' "$META" | tail -n +2)"
if [ -n "$(printf '%s' "$REVIEWS" | tr -d '[:space:]')" ]; then
  echo "### Review-level comments (not attached to a line — these often carry the reviewer's headline concern)"
  echo
  printf '%s\n' "$REVIEWS" | head -150
  echo
fi

exit 0
