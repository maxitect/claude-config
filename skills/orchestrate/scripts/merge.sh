#!/usr/bin/env bash
# Solo mode's last step: merges one cleared ticket into the run's base. It checks the review verdict, attribution, unpushed code and
# staleness (rebasing in the worktree and re-running gates when the base changed files the PR touches), waits
# for mergeability and checks, squash-merges, syncs the base checkout, carries unpushed reviewer docs over
# for the orchestrator's commit, sweeps, and names open ticket PRs that must rebase.
#
# Usage: merge.sh <id>   (from the main checkout; may wait up to ORCH_CHECK_TIMEOUT for checks)

. "$(dirname "$0")/lib.sh"
load_config
ID="$(normalise_id "${1:-}")"
cd "$ROOT" || exit 1
[ "$ORCH_MODE" = solo ] || die MERGE "mode is $ORCH_MODE: team mode never merges, use ready.sh"
[ "$(git branch --show-current)" = "$ORCH_BASE" ] || die MERGE "the main checkout is not on $ORCH_BASE"
open_log "$STATE/$ID/merge.log"
git fetch origin --prune --quiet

PR_JSON="$(ticket_prs | jq -c --arg b "$(ticket_branch "$ID")" '[.[] | select(.headRefName == $b and .state == "OPEN")][0] // empty')"
[ -n "$PR_JSON" ] || die MERGE "no open PR for $ID"
PR="$(jq -r .number <<< "$PR_JSON")"; BRANCH="$(jq -r .headRefName <<< "$PR_JSON")"; REMOTE="origin/$BRANCH"
[ "$(jq -r .baseRefName <<< "$PR_JSON")" = "$ORCH_BASE" ] || die MERGE "PR #$PR targets $(jq -r .baseRefName <<< "$PR_JSON"), not $ORCH_BASE"
WT="$(worktree_of "$BRANCH")"
PR_FILES=()
UNPUSHED_DOCS=()

changed() { git diff --name-only "$1" "$2"; }

review_verdict() { verdict_clear "$ID" || { echo "$(report_path "$ID") has no 'Verdict: ALL CLEAR': the reviewer has not cleared it"; return 1; }; }

no_attribution() {
  ! attribution_in "$(gh pr view "$PR" --json body -q .body)" || { echo "PR description carries AI attribution: gh pr edit --body-file"; return 1; }
}

unpushed_docs_only() {
  git show-ref --verify --quiet "refs/heads/$BRANCH" || return 0
  local f code=()
  while read -r f; do
    [ -n "$f" ] || continue
    case "$f" in docs/*|*.md) UNPUSHED_DOCS+=("$f") ;; *) code+=("$f") ;; esac
  done <<< "$(changed "$REMOTE" "$BRANCH")"
  [ "${#code[@]}" -eq 0 ] || { echo "unpushed code on $BRANCH: ${code[*]}"; return 1; }
}

up_to_date() {
  local base main_files overlap mig_main mig_pr
  base="$(git merge-base "origin/$ORCH_BASE" "$REMOTE")"
  PR_FILES=($(changed "$base" "$REMOTE"))
  main_files=($(changed "$base" "origin/$ORCH_BASE"))
  mig_main="$(touches "$ORCH_MIGRATION_PATHS" "${main_files[@]+"${main_files[@]}"}")"
  mig_pr="$(touches "$ORCH_MIGRATION_PATHS" "${PR_FILES[@]+"${PR_FILES[@]}"}")"
  overlap="$(comm -12 <(printf '%s\n' "${PR_FILES[@]+"${PR_FILES[@]}"}" | sort) <(printf '%s\n' "${main_files[@]+"${main_files[@]}"}" | sort) | grep .)"
  [ -n "$mig_main" ] && [ -n "$mig_pr" ] && overlap="${overlap:+$overlap }(migrations)"
  [ -z "$overlap" ] && return 0
  rebase_onto_base "$overlap"
}

rebase_onto_base() {
  local why="$ORCH_BASE changed files this PR touches: $(echo $1)"
  [ -n "$WT" ] || { echo "$why. No worktree for $BRANCH: rebase, run gates, push"; return 1; }
  [ -z "$(git -C "$WT" status --porcelain --untracked-files=no)" ] || { echo "$why. $WT has uncommitted changes"; return 1; }
  if ! git -C "$WT" rebase "origin/$ORCH_BASE"; then
    git -C "$WT" rebase --abort
    echo "$why. Rebase conflicts: resolve in $WT, run gates, push"; return 1
  fi
  (cd "$WT" && "$SCRIPTS/gates.sh") || { echo "$why. Gates fail after rebase in $WT"; return 1; }
  git -C "$WT" push --force-with-lease origin "$BRANCH" || return 1
  NOTES+=("rebased $BRANCH onto $ORCH_BASE, gates passed, pushed")
  UNPUSHED_DOCS=()
  git fetch origin --prune --quiet
  PR_FILES=($(changed "$(git merge-base "origin/$ORCH_BASE" "$REMOTE")" "$REMOTE"))
  sleep 20
}

mergeable() {
  local i state
  for i in 1 2 3 4 5 6; do
    state="$(gh pr view "$PR" --json mergeable -q .mergeable)"
    [ "$state" = MERGEABLE ] && return 0
    [ "$state" = CONFLICTING ] && { echo "PR conflicts with $ORCH_BASE: rebase needed"; return 1; }
    sleep 5
  done
  echo "GitHub has not computed mergeability; retry shortly"; return 1
}

add_labels() { [ -z "$ORCH_PR_LABELS" ] || gh pr edit "$PR" --add-label "$ORCH_PR_LABELS"; }

squash_merge() {
  gh pr merge "$PR" --squash --subject "$(jq -r .title <<< "$PR_JSON") (#$PR)" --body "" || return 1
  git push origin --delete "$BRANCH" 2>/dev/null
  return 0
}

sync_base() {
  git pull --ff-only --quiet origin "$ORCH_BASE" || return 1
  local cmd
  while read -r cmd; do [ -n "$cmd" ] && { CI=1 sh -c "$cmd" || return 1; }; done <<< "$(install_cmds "$ROOT")"
  if is_supabase "$ROOT" && [ -n "$(touches "$ORCH_MIGRATION_PATHS $ORCH_SEED_PATHS" "${PR_FILES[@]+"${PR_FILES[@]}"}")" ]; then
    cap 300 supabase migration up || return 1
    NOTES+=("applied new migrations to the base supabase stack")
  fi
}

carry_unpushed_docs() {
  [ "${#UNPUSHED_DOCS[@]}" -eq 0 ] && return 0
  git checkout "$BRANCH" -- "${UNPUSHED_DOCS[@]}" || return 1
  NOTES+=("staged unpushed reviewer docs on $ORCH_BASE: ${UNPUSHED_DOCS[*]}. Commit them with your status commit")
}

after_merge() {
  local swept other files shared prod
  swept="$("$SCRIPTS/sweep.sh" 2>&1)"; [ -n "$swept" ] && NOTES+=("$swept")
  local mig; mig="$(touches "$ORCH_MIGRATION_PATHS" "${PR_FILES[@]+"${PR_FILES[@]}"}")"
  for other in $(ticket_prs | jq -r --arg b "$ORCH_BASE" '.[] | select(.state == "OPEN" and .baseRefName == $b) | "\(.number):\(.headRefName)"'); do
    files="$(gh pr view "${other%%:*}" --json files -q '.files[].path')"
    shared="$(comm -12 <(printf '%s\n' "${PR_FILES[@]+"${PR_FILES[@]}"}" | sort) <(sort <<< "$files") | paste -sd, -)"
    if [ -n "$mig" ] && [ -n "$(touches "$ORCH_MIGRATION_PATHS" $files)" ]; then
      NOTES+=("notify ${other#*:} (#${other%%:*}): $ORCH_BASE gained a migration; rebase before its push")
    elif [ -n "$shared" ]; then
      NOTES+=("notify ${other#*:} (#${other%%:*}): shares $shared; rebase before its push")
    fi
  done
  prod="$(touches "$ORCH_PROD_PATHS" "${PR_FILES[@]+"${PR_FILES[@]}"}" | head -5 | paste -sd, -)"
  [ -n "$ORCH_PROD_PATHS" ] && [ -n "$prod" ] && NOTES+=("check the deployed build and runtime logs (touches $prod)")
  return 0
}

step MERGE "review verdict" review_verdict
step MERGE "no AI attribution" no_attribution
step MERGE "no unpushed code" unpushed_docs_only
step MERGE "up to date with $ORCH_BASE" up_to_date
step MERGE "mergeable" mergeable
step MERGE "labels" add_labels
step MERGE "checks" checks_green "$PR"
step MERGE "squash-merge #$PR" squash_merge
step MERGE "sync $ORCH_BASE" sync_base
step MERGE "carry unpushed docs" carry_unpushed_docs
step MERGE "cleanup" after_merge

finish MERGE "$ID #$PR into $ORCH_BASE"
