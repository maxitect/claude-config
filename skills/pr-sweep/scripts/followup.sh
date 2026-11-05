#!/usr/bin/env bash
# Follow-up on a PR a sweep already reviewed: moves its worktree to the new head, brings its stack back and
# resumes the SAME reviewer session headless with /pr-followup. Posts nothing.
#
# Usage: followup.sh <pr>
# Needs the PR in $SWEEP/queue.json (discover.sh). Writes $SWEEP/<pr>/{followup.md,followup.sha,followup.verdict}.

. "$(dirname "$0")/lib.sh"
N="${1:?usage: followup.sh <pr>}"
RUN="$(run_dir "$N")"; WT="$(wt_dir "$N")"
LOG="$RUN/followup.log"; : > "$LOG"
SID="$(cat "$RUN/reviewer.sid" 2>/dev/null)"
[ -n "$SID" ] && [ -d "$WT" ] || die FOLLOWUP "#$N has no reviewer session or worktree: pr-sweep teardown $N --full, then re-run for a fresh review"
SHA="$(jq -r ".[] | select(.number==$N) | .sha" "$SWEEP/queue.json")"
[ -n "$SHA" ] || die FOLLOWUP "#$N is not in the queue"
MIG="$(meta "$N" .mig)"
[ "$(jq -r ".[] | select(.number==$N) | .mig" "$SWEEP/queue.json")" != true ] || [ "$MIG" = true ] \
  || die FOLLOWUP "#$N now touches the schema: pr-sweep teardown $N --full, then re-run for a fresh review"
cd "$ROOT" || exit 1

step FOLLOWUP "fetch" git fetch --quiet origin "pull/$N/head"
step FOLLOWUP "checkout $SHA" git -C "$WT" checkout --quiet --force --detach "$SHA"
step FOLLOWUP "clean worktree" git -C "$WT" clean -fdq

if [ "$MIG" = "true" ]; then
  SLOT="$(claim_slot "$N" 3600)" || die FOLLOWUP "no supabase slot free after 60 minutes (max $MAX_SLOTS)"
  python3 "$SCRIPTS/patch_supabase.py" "$WT/supabase/config.toml" "$SLOT" "$N" "$(dev_port "$N")" > /dev/null \
    || die FOLLOWUP "could not patch supabase/config.toml"
  (cd "$WT" && cap 120 supabase stop --no-backup) >> "$LOG" 2>&1
  (cd "$WT" && cap 600 supabase start -x "$SUPABASE_EXCLUDE") >> "$LOG" 2>&1 || die FOLLOWUP "#$N supabase start failed on the new head"
fi

NODE_PM="$(node_pm_of "$WT")"; PY_PM="$(py_pm_of "$WT")"
for cmd in "${NODE_PM:+$NODE_PM install --frozen-lockfile}" "${PY_PM:+$PY_PM sync}"; do
  [ -n "$cmd" ] || continue
  [ "$cmd" = "npm install --frozen-lockfile" ] && cmd="npm ci"
  [ "$cmd" = "poetry sync" ] && cmd="poetry install --no-interaction"
  (cd "$WT" && CI=1 cap 900 sh -c "$cmd") >> "$RUN/gates/install.log" 2>&1 || echo "install FAILED: $cmd (probes may not run)" >> "$RUN/followup.notes"
done

# The reviewer's GitHub write ban stays intact (no gh api): hand it the review data instead.
ME="$(gh api user -q .login)" || die FOLLOWUP "gh api user failed"
OWNER="${SLUG%/*}"; REPO="${SLUG#*/}"
REVIEWS="$(gh api "repos/$SLUG/pulls/$N/reviews" --paginate --slurp | jq --arg me "$ME" '[.[][] | select(.user.login == $me) | {id, state, commit_id, submitted_at, body}]')" \
  || die FOLLOWUP "could not fetch reviews"
THREADS="$(gh api graphql --paginate --slurp -F owner="$OWNER" -F repo="$REPO" -F pr="$N" -f query='
query($owner:String!, $repo:String!, $pr:Int!, $endCursor:String) {
  repository(owner:$owner, name:$repo) { pullRequest(number:$pr) {
    reviewThreads(first:50, after:$endCursor) {
      pageInfo { hasNextPage endCursor }
      nodes { isResolved isOutdated path line originalLine
        comments(first:30) { nodes { author { login } body createdAt } } } } } } }' \
  | jq '[.[].data.repository.pullRequest.reviewThreads.nodes[]]')" || die FOLLOWUP "could not fetch review threads"
CONVO="$(gh api "repos/$SLUG/issues/$N/comments" --paginate --slurp | jq '[.[][] | {author: .user.login, created: .created_at, body}]')" \
  || die FOLLOWUP "could not fetch conversation comments"
jq -n --arg me "$ME" --arg repo "$SLUG" --arg sha "$SHA" --argjson reviews "$REVIEWS" --argjson threads "$THREADS" --argjson convo "$CONVO" \
  '{login: $me, nameWithOwner: $repo, headRefOid: $sha, reviews: $reviews, reviewThreads: $threads, issueComments: $convo}' \
  > "$RUN/followup-input.json"

PROMPT="/pr-followup $N

Sweep overrides for the command's §0 and §1:
- The GitHub data (my login, repo, my submitted reviews, review threads, conversation comments) is pre-fetched in $RUN/followup-input.json. Read it instead of calling gh api.
- Your cwd is a detached checkout of the PR head $SHA, already fetched and verified: skip the branch, fetch and HEAD checks.
- The review baseline is the earliest commit_id among my reviews in that file.
$(cat "$RUN/followup.notes" 2>/dev/null)
Report only, post nothing. Reply with the full report, the bold APPROVE / DO NOT APPROVE verdict first."

FLAGS=()
while IFS= read -r f; do FLAGS+=("$f"); done < <(reviewer_flags "$RUN")
cd "$WT" || exit 1
cap "$REVIEW_TIMEOUT" claude -p --resume "$SID" "${FLAGS[@]}" --output-format json "$PROMPT" < /dev/null > "$LOG" 2>&1
RC=$?
grep '^{' "$LOG" | tail -1 > "$RUN/followup.json"
kill_ports "$N"
rm -f "$RUN/followup.notes"

[ "$RC" -eq 124 ] && die FOLLOWUP "#$N timed out after ${REVIEW_TIMEOUT}s (resume: cd $WT && $CLAUDE_HINT --resume $SID)"
jq -r '.result // empty' "$RUN/followup.json" > "$RUN/followup.md" 2>/dev/null
VERDICT="$(head -5 "$RUN/followup.md" | grep -m1 -oE 'DO NOT APPROVE|APPROVE')"
[ -n "$VERDICT" ] || die FOLLOWUP "#$N report has no verdict line (see $RUN/followup.json)"
echo "$SHA" > "$RUN/followup.sha"
echo "$VERDICT" > "$RUN/followup.verdict"
COST="$(jq -r '.total_cost_usd // 0 | . * 100 | round / 100' "$RUN/followup.json")"

# The summary comment: the commenter turns the report into the body of a PENDING review for me to edit and submit.
OLD="$(meta "$N" .sha)"
mkdir -p "$RUN/history/${OLD:0:7}"
for f in payload.json posted.json "pr-$N-review.md"; do [ -e "$RUN/$f" ] && mv "$RUN/$f" "$RUN/history/${OLD:0:7}/"; done
CSID="$(uuidgen | tr '[:upper:]' '[:lower:]')"
echo "$CSID" > "$RUN/followup-commenter.sid"
cap 900 claude -p --session-id "$CSID" --name "pr-$N followup summary" \
  --agent pr-commenter --model sonnet --permission-mode dontAsk --add-dir "$HOME/.claude/commands" --allowedTools "Read,Grep,Glob" \
  --output-format json --json-schema "$(cat "$SCRIPTS/comments.schema.json")" \
  "Write the body of a FOLLOW-UP review per your protocol, with no inline comments: return \`comments\` as an empty array and put everything in \`summary\`.
Source: the follow-up report below, written after the dev responded to my earlier review. Cover, in my voice and for the dev: each of my points that is still open, claimed but not done, or declined with a reason that does not hold (dotted \`path:line\` item each, with the fix); anything new the response commits introduced; one short line for what was addressed. Do not state the verdict word or report process. Do not restate items that are fine one by one.

$(cat "$RUN/followup.md")" < /dev/null >> "$RUN/followup-comment.log" 2>&1
BODY="$(grep '^{' "$RUN/followup-comment.log" | tail -1 | jq -r '.structured_output.summary // empty' | sed -E 's/ *— */ - /g')"
[ -n "$BODY" ] || die FOLLOWUP "#$N commenter returned no summary (log: $RUN/followup-comment.log)"
jq -n --arg sha "$SHA" --arg body "$BODY" '{commit_id: $sha, body: $body, threads: []}' > "$RUN/payload.json"
python3 "$SCRIPTS/post.py" "$RUN" "$SLUG" "$N" || exit 1
echo "FOLLOWUP PASS #$N $VERDICT (\$$COST) · summary comment in pending review, report $RUN/followup.md"
