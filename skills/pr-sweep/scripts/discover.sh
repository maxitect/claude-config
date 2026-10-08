#!/usr/bin/env bash
# Lists open PRs, applies the filters and writes the review queue to $SWEEP/queue.json.
#
# Usage: discover.sh [mine] [<pr number>...]
#   mine        only PRs assigned to me (default: every open PR)
#   <number>    queue exactly these PRs; draft/author filters are skipped, the review checks are not
#
# Skipped always: PRs where I already hold a pending review (GitHub allows one per user per PR), and PRs
# whose current head I already reviewed, by a sweep or by hand. A head that moved since my last review is
# queued as a re-review. Skipped unless named: drafts, my own PRs, PRs from forks, PRs labelled no-ai-review.

. "$(dirname "$0")/lib.sh"
[ -n "$SLUG" ] || die DISCOVER "gh cannot resolve a GitHub repo here"
cd "$ROOT" || exit 1
mkdir -p "$SWEEP"

MINE=""
PICKED=()
for a in "$@"; do
  case "$a" in
    mine) MINE=1 ;;
    *[!0-9#]*|'') ;;
    *) PICKED+=("${a#\#}") ;;
  esac
done

FIELDS="number,title,url,isDraft,author,headRefName,headRefOid,baseRefName,isCrossRepository,labels,files"
if [ "${#PICKED[@]}" -gt 0 ]; then
  PRS="$(for n in "${PICKED[@]}"; do gh pr view "$n" --json "$FIELDS,state" || exit 1; done | jq -s '[.[] | select(.state=="OPEN")]')" \
    || die DISCOVER "gh pr view failed for one of: ${PICKED[*]}"
else
  PRS="$(gh pr list --state open --limit 200 ${MINE:+--assignee @me} --json "$FIELDS")" || die DISCOVER "gh pr list failed"
fi

ME="$(gh api user -q .login)" || die DISCOVER "gh api user failed"
# My reviews per PR: whether one is pending, and the head commit my latest submitted one was made against.
MY_REVIEWS="$SWEEP/my-reviews.json"
printf '%s' "$PRS" | jq -r '.[].number' | while read -r n; do
  gh api "repos/$SLUG/pulls/$n/reviews" --paginate --slurp 2>/dev/null | jq --arg me "$ME" --arg n "$n" '
    [.[][] | select(.user.login == $me)] as $mine
    | {($n): {pending: any($mine[]; .state == "PENDING"),
              reviewed_sha: ([$mine[] | select(.state != "PENDING" and .state != "DISMISSED")] | last | .commit_id)}}'
done | jq -s 'add // {}' > "$MY_REVIEWS"

printf '%s' "$PRS" | python3 "$SCRIPTS/discover.py" "$SWEEP" "$ME" "$([ "${#PICKED[@]}" -gt 0 ] && echo 1 || echo 0)" "$MY_REVIEWS"
