#!/usr/bin/env bash
# Removes every merged ticket's dev server, Supabase stack and slot, worktree, local branch and state. In team
# mode it also frees cleared tickets (ready for review) the same way, keeping their state for restack.sh. Deletes
# empty ticket branches; frees orphan slots; and, with ORCH_NEON_PROJECT set, deletes merged tickets' Neon
# preview branches. Prints one line per thing removed, nothing when clean.
#
# Usage: sweep.sh

. "$(dirname "$0")/lib.sh"
load_config
[ -n "$ROOT" ] || exit 0
PRS="$(ticket_prs)"
merged() { jq -e --arg h "$1" '.[] | select(.headRefName == $h and .state == "MERGED")' <<< "$PRS" >/dev/null; }
cleared() {
  [ "$ORCH_MODE" = team ] && [ -n "$ORCH_TICKETS" ] || return 1
  jq -e --arg h "$1" '.[] | select(.headRefName == $h and .state == "OPEN" and .isDraft == false)' <<< "$PRS" >/dev/null \
    && verdict_clear "$(id_from_branch "$1")"
}

remove_ticket() {  # remove_ticket <branch> [worktree] [keep-state]
  local branch="$1" wt="${2:-}" keep="${3:-}" id; id="$(id_from_branch "$branch")"
  [ -n "$id" ] && kill_port "$id"
  if [ -n "$wt" ]; then
    [ -n "$id" ] && [ -n "$(cat "$STATE/$id/env" 2>/dev/null | sed -n 's/^SLOT=//p')" ] \
      && (cd "$wt" && cap 120 supabase stop --no-backup) >/dev/null 2>&1
    git -C "$ROOT" worktree unlock "$wt" 2>/dev/null
    git -C "$ROOT" worktree remove -f -f "$wt"
  fi
  git -C "$ROOT" branch -D "$branch" >/dev/null 2>&1
  [ -n "$id" ] && release_slot "$id"
  [ -n "$id" ] && [ -z "$keep" ] && rm -rf "${STATE:?}/$id"
  return 0
}

git -C "$ROOT" worktree list --porcelain | awk '/^worktree /{p=substr($0,10)} /^branch refs\/heads\/ticket\//{print p "|" substr($0,19)}' \
  | while IFS='|' read -r wt branch; do
      if merged "$branch"; then remove_ticket "$branch" "$wt" && echo "removed merged worktree $branch"
      elif cleared "$branch"; then remove_ticket "$branch" "$wt" keep && echo "removed worktree of $branch (ready for review)"
      fi
    done

in_use="$(git -C "$ROOT" worktree list --porcelain | sed -n 's@^branch refs/heads/@@p')"
git -C "$ROOT" for-each-ref --format='%(refname:short)' refs/heads/ticket/ | while read -r branch; do
  grep -qxF "$branch" <<< "$in_use" && continue
  if merged "$branch"; then
    remove_ticket "$branch" && echo "deleted merged branch $branch"
  elif cleared "$branch"; then
    remove_ticket "$branch" "" keep && echo "deleted local branch $branch (ready for review)"
  elif [ -z "$(git -C "$ROOT" log "origin/$ORCH_BASE..$branch" --oneline 2>/dev/null)" ] \
    && ! git -C "$ROOT" ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1; then
    remove_ticket "$branch" && echo "deleted empty branch $branch"
  fi
done

for slot in "$STATE"/slots/*/; do
  [ -d "$slot" ] || continue
  id="$(cat "$slot/id" 2>/dev/null)"
  [ -n "$id" ] && [ -f "$STATE/$id/env" ] && [ -d "$(sed -n 's/^WORKTREE=//p' "$STATE/$id/env")" ] && continue
  rm -rf "$slot" && echo "freed orphan slot $(basename "$slot")"
done

if [ -n "$ORCH_NEON_PROJECT" ] && command -v neonctl >/dev/null; then
  neonctl branches list --project-id "$ORCH_NEON_PROJECT" --output json 2>/dev/null \
    | jq -r '.[] | select(.name | test("^(preview/)?ticket/")) | "\(.id) \(.name)"' \
    | while read -r nid name; do
        head="${name#preview/}"
        merged "$head" || continue
        pr="$(jq -r --arg h "$head" '.[] | select(.headRefName == $h) | .number' <<< "$PRS" | head -1)"
        if (cd "$ROOT" && gh pr checks "$pr" --json bucket -q '.[].bucket' 2>/dev/null) | grep -q pending; then
          echo "neon: kept $name (PR #$pr checks still running)"; continue
        fi
        neonctl branches delete "$nid" --project-id "$ORCH_NEON_PROJECT" >/dev/null 2>&1 \
          && echo "neon: deleted $name" || echo "neon: failed to delete $name"
      done
fi

git -C "$ROOT" worktree prune
