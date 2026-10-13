#!/usr/bin/env bash
# Team mode's last step for a cleared ticket: checks the review verdict, attribution, that nothing is
# unpushed, and any CI that runs on drafts, then marks the PR ready for review, waits for the checks that
# start only then (post-ready ACs), and sweeps the ticket's
# worktree. Groups a linear parent-child pair on GitHub with gh stack link. Dependents can then stack on its
# branch. Never merges.
#
# Usage: ready.sh <id>   (from the main checkout; may wait up to ORCH_CHECK_TIMEOUT for checks)

. "$(dirname "$0")/lib.sh"
load_config
ID="$(normalise_id "${1:-}")"
cd "$ROOT" || exit 1
[ "$ORCH_MODE" = team ] || die READY "mode is $ORCH_MODE: use merge.sh"
open_log "$STATE/$ID/ready.log"
git fetch origin --prune --quiet

PR_JSON="$(ticket_prs | jq -c --arg b "$(ticket_branch "$ID")" '[.[] | select(.headRefName == $b and .state == "OPEN")][0] // empty')"
[ -n "$PR_JSON" ] || die READY "no open PR for $ID"
PR="$(jq -r .number <<< "$PR_JSON")"; BRANCH="$(jq -r .headRefName <<< "$PR_JSON")"

review_verdict() { verdict_clear "$ID" || { echo "$(report_path "$ID") has no 'Verdict: ALL CLEAR': the reviewer has not cleared it"; return 1; }; }
no_attribution() { ! attribution_in "$(gh pr view "$PR" --json body -q .body)" || { echo "PR description carries AI attribution: gh pr edit --body-file"; return 1; }; }
nothing_unpushed() {
  git show-ref --verify --quiet "refs/heads/$BRANCH" || return 0
  [ -z "$(git log "origin/$BRANCH..$BRANCH" --oneline)" ] || { echo "unpushed commits on $BRANCH: the reviewer must push them"; return 1; }
}
add_labels() {
  [ -n "$ORCH_PR_LABELS" ] || return 0
  gh pr edit "$PR" --add-label "$ORCH_PR_LABELS"
}
mark_ready() {
  [ "$(jq -r .isDraft <<< "$PR_JSON")" = true ] || { NOTES+=("PR #$PR was already ready for review"); return 0; }
  gh pr ready "$PR"
}
# A linear pair (the parent has no other open stacked child) is grouped on GitHub with gh-stack. Branching
# stacks stay as plain base-chained PRs: gh-stack allows one child per parent.
stack_link() {
  local base; base="$(jq -r .baseRefName <<< "$PR_JSON")"
  [ -n "$(id_from_branch "$base")" ] || return 0
  if ! grep -q 'gh-stack' <<< "$(gh extension list 2>/dev/null)"; then NOTES+=("gh-stack not installed: $BRANCH not grouped with $base"); return 0; fi
  local siblings; siblings="$(gh pr list --state open --base "$base" --json number -q 'length')"
  if [ "$siblings" -gt 1 ]; then NOTES+=("$base has $siblings stacked children: not grouped (gh-stack stacks are linear)"); return 0; fi
  local out rc; out="$(gh stack link "$base" "$BRANCH" 2>&1)"; rc=$?
  case "$rc" in
    0) NOTES+=("grouped $base <- $BRANCH with gh stack link") ;;
    9) NOTES+=("stacked PRs are not enabled on this repo: $BRANCH not grouped") ;;
    *) NOTES+=("gh stack link failed (exit $rc), PR still chained by base: $(tail -1 <<< "$out")") ;;
  esac
  return 0
}
# Many repos skip CI on drafts, so the real checks (and any preview deploy) only start now. Wait for them to
# register, then for them to pass: post-ready ACs are proved here.
post_ready_checks() {
  local i
  for i in $(seq 1 12); do
    [ "$(gh pr checks "$PR" --json name -q 'length' 2>/dev/null || echo 0)" -gt 0 ] && break
    sleep 10
  done
  checks_green "$PR" || { echo "PR #$PR is ready for review but its checks failed: send the reviewer the failure (it may set the PR back to draft with gh pr ready --undo while it fixes)"; return 1; }
}
after_ready() {
  local swept; swept="$("$SCRIPTS/sweep.sh" 2>&1)"; [ -n "$swept" ] && NOTES+=("$swept")
  NOTES+=("dependents of $ID now stack on $BRANCH")
  return 0
}

step READY "review verdict" review_verdict
step READY "no AI attribution" no_attribution
step READY "nothing unpushed" nothing_unpushed
step READY "labels" add_labels
step READY "checks" checks_green "$PR"
step READY "ready for review #$PR" mark_ready
step READY "stack link" stack_link
step READY "checks after ready" post_ready_checks
step READY "cleanup" after_ready

finish READY "$ID #$PR ready for review → $(jq -r .baseRefName <<< "$PR_JSON")"
