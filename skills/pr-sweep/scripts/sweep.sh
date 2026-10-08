#!/usr/bin/env bash
# Removes worktrees and artefacts of PRs that are merged or closed, and slots nobody holds.
# Prints one line per thing removed, nothing when clean.
#
# Usage: sweep.sh

. "$(dirname "$0")/lib.sh"
[ -d "$SWEEP" ] || exit 0

for dir in "$SWEEP"/[0-9]*/; do
  [ -d "$dir" ] || continue
  n="$(basename "$dir")"
  state="$(gh pr view "$n" --repo "$SLUG" --json state -q .state 2>/dev/null)"
  case "$state" in
    MERGED|CLOSED) "$SCRIPTS/teardown.sh" "$n" --full >/dev/null && echo "swept #$n ($(printf %s "$state" | tr A-Z a-z))" ;;
  esac
done 2>/dev/null

for slot in "$SWEEP"/slots/*/; do
  [ -d "$slot" ] || continue
  n="$(cat "$slot/pr" 2>/dev/null)"
  [ -n "$n" ] && [ -d "$SWEEP/$n/wt" ] && continue
  rm -rf "$slot" && echo "freed orphan slot $(basename "$slot")"
done
git -C "$ROOT" worktree prune
