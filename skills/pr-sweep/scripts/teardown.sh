#!/usr/bin/env bash
# Frees what one PR holds. Default keeps the worktree and sessions so the reviewer can be resumed.
#
# Usage: teardown.sh <pr>          stop its dev server and own Supabase stack, release its slot
#        teardown.sh <pr> --full   also remove the worktree and every artefact (sessions become unresumable)

. "$(dirname "$0")/lib.sh"
N="${1:?usage: teardown.sh <pr> [--full]}"
RUN="$(run_dir "$N")"; WT="$(wt_dir "$N")"

kill_ports "$N"
if [ -n "$(slot_of "$N")" ]; then
  [ -d "$WT" ] && (cd "$WT" && cap 120 supabase stop --no-backup) >/dev/null 2>&1
  release_slot "$N"
fi

if [ "${2:-}" = "--full" ]; then
  [ -d "$WT" ] && git -C "$ROOT" worktree remove --force "$WT" 2>/dev/null
  git -C "$ROOT" worktree prune
  rm -rf "$RUN"
  echo "TEARDOWN PASS #$N (removed)"
else
  echo "TEARDOWN PASS #$N (stack stopped, worktree kept)"
fi
