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
COST="$(jq -r '.total_cost_usd // 0 | . * 100 | round / 100' "$RUN/followup.json")"

# From here the PR is a normal sweep at its new head: archive the old review's artefacts, then ask the same
# session for the open items as findings, and let run.sh validate, comment (summary + inline) and post them.
OLD="$(meta "$N" .sha)"
mkdir -p "$RUN/history/${OLD:0:7}"
for f in findings.json findings.sha review.json review.md anchors.json comments.json commenter.json payload.json posted.json "pr-$N-review.md"; do
  [ -e "$RUN/$f" ] && mv "$RUN/$f" "$RUN/history/${OLD:0:7}/"
done
jq --arg sha "$SHA" '.sha = $sha' "$RUN/meta.json" > "$RUN/meta.json.new" && mv "$RUN/meta.json.new" "$RUN/meta.json"
echo "$SHA" > "$RUN/prepare.ok"

cat > "$RUN/followup-prompt.md" <<EOF2
Now return the findings for the follow-up review, as the JSON the schema asks for, from the report you just wrote.

- Every point in your report that asks the dev to change something is a finding, whatever the report called it: my points still open, claimed but not done, or declined with a reason that does not hold; anything new the response commits introduced; and defects you found that were never in my submitted review (including ones your report marked "not blocking"). One finding each, anchored to its line. Nothing already fixed, no praise.
- Same rules as the first review: \`line\` is the line in the PR head version (side RIGHT), \`suggestion\` only when the fix is contiguous and certain, an \`evidence\` line on every critical and warning (the command and its decisive output, or UNVERIFIED with the reason).
- \`summary\`: what the dev's response did (what was addressed, what is left). \`notes\`: only what is not a code change (a description inaccuracy, a scope remark); never a defect, which belongs in \`findings\`.
- \`issue_coverage\`, \`refuted_count\` and \`ui_changed\` as for a full review; an empty \`findings\` array is right when nothing is outstanding.
EOF2
"$SCRIPTS/review.sh" "$N" --prompt "$RUN/followup-prompt.md" || exit 1
echo "$SHA" > "$RUN/followup.sha"
echo "$VERDICT" > "$RUN/followup.verdict"
echo "FOLLOWUP PASS #$N $VERDICT (\$$COST)"
