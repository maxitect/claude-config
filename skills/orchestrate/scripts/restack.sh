#!/usr/bin/env bash
# Rebases a stacked ticket branch after its parent changed: onto the parent's new tip when the parent moved
# (a human's review fixes, or the parent's own restack), or onto the parent's base when the parent merged,
# retargeting the PR there. Uses the ticket's worktree if it has one, else a temporary one. Pushes when the
# branch is on origin. Conflicts abort the rebase and fail, for an agent or a human to resolve.
#
# Usage: restack.sh <id>   (from the main checkout)

. "$(dirname "$0")/lib.sh"
load_config
ID="$(normalise_id "${1:-}")"
cd "$ROOT" || exit 1
open_log "$STATE/$ID/restack.log"
T="$(mktemp -t orchestrate)"; TMP_WT=""
trap 'rm -f "$T"; [ -n "$TMP_WT" ] && git -C "$ROOT" worktree remove -f "$TMP_WT" >/dev/null 2>&1' EXIT
build_table "$T"

BRANCH="$(col "$T" "$ID" 3)"; PARENT="$(col "$T" "$ID" 10)"; OLD_BASE="$(col "$T" "$ID" 11)"; PR_TARGET="$(col "$T" "$ID" 9)"
[ -n "$PARENT" ] || die RESTACK "$ID is not stacked on another ticket (PR base ${PR_TARGET:-none})"
WHY="$(needs_restack "$T" "$ID")"
[ -n "$WHY" ] || { echo "RESTACK PASS ($ID already level with $OLD_BASE)"; exit 0; }

NEW_BASE="$OLD_BASE"
if [ "$(col "$T" "$PARENT" 2)" = done ]; then
  NEW_BASE="$(jq -r --arg h "$OLD_BASE" '[.[] | select(.headRefName == $h and .state == "MERGED")][0].baseRefName' <<< "$PRS")"
fi
FORK="$(env_get "$ID" PARENT_TIP)"
[ -n "$FORK" ] || FORK="$(jq -r --arg h "$OLD_BASE" '[.[] | select(.headRefName == $h)][0].headRefOid' <<< "$PRS")"
[ -n "$FORK" ] && [ "$FORK" != null ] || die RESTACK "cannot tell where $BRANCH forked from $OLD_BASE"

WT="$(worktree_of "$BRANCH")"
if [ -z "$WT" ]; then
  TMP_WT="$STATE/$ID/restack-wt"
  step RESTACK "temporary worktree" git worktree add --quiet -B "$BRANCH" "$TMP_WT" "origin/$BRANCH"
  WT="$TMP_WT"
fi

clean() { [ -z "$(git -C "$WT" status --porcelain --untracked-files=no)" ] || { echo "$WT has uncommitted changes: commit them first"; return 1; }; }
rebase() {
  git -C "$WT" rebase --onto "origin/$NEW_BASE" "$FORK" "$BRANCH" && return 0
  git -C "$WT" rebase --abort
  echo "conflicts rebasing $BRANCH onto $NEW_BASE: resolve in a worktree, then push"; return 1
}
push() {
  git ls-remote --exit-code --heads origin "$BRANCH" >/dev/null || { NOTES+=("$BRANCH is not on origin yet: not pushed"); return 0; }
  git -C "$WT" push --force-with-lease origin "$BRANCH"
}
retarget() {
  [ "$NEW_BASE" = "$PR_TARGET" ] && return 0
  gh pr edit "$(col "$T" "$ID" 8)" --base "$NEW_BASE" && NOTES+=("PR #$(col "$T" "$ID" 8) now targets $NEW_BASE")
}

step RESTACK "clean worktree" clean
step RESTACK "rebase onto $NEW_BASE" rebase
step RESTACK "push" push
step RESTACK "retarget" retarget
env_set "$ID" PR_BASE "$NEW_BASE"
env_set "$ID" PARENT_TIP "$(git rev-parse "origin/$NEW_BASE")"
[ "$WT" != "$TMP_WT" ] && NOTES+=("rebased the live worktree $WT: tell its agent before it pushes")

finish RESTACK "$ID onto $NEW_BASE ($WHY)"
