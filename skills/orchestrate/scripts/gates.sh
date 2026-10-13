#!/usr/bin/env bash
# Runs the repo's gates (typecheck, lint, test, build, or ORCH_GATES) in the current worktree, one worktree
# at a time machine-wide, and records the tree they passed on so stop-check and merge can tell whether code
# changed since. Prints GATES PASS, or GATES FAIL: <gate> and its tail.
#
# Usage: gates.sh

. "$(dirname "$0")/lib.sh"
load_config
ID="$(id_from_branch "$(git branch --show-current)")"
RUN="$STATE/${ID:-local}"
open_log "$RUN/gates.log"
cd "$TOP" || exit 1

CMDS="$(gate_cmds "$TOP")"
[ -n "$CMDS" ] || die GATES "no gates detected: set ORCH_GATES in $ORCH_TICKETS/orchestrate.env"

lock "$STATE/locks/gates" 7200 || die GATES "gates lock held for 2h ($STATE/locks/gates): stale? remove it"
trap 'rm -rf "$STATE/locks/gates"' EXIT
rm -f "$RUN/gates.ok"
while read -r name cmd; do
  [ -n "$name" ] && step GATES "$name ($cmd)" cap "$ORCH_GATE_TIMEOUT" env CI=1 NO_COLOR=1 FORCE_COLOR=0 sh -c "$cmd"
done <<< "$CMDS"
working_tree "$TOP" > "$RUN/gates.ok"

finish GATES "$(printf '%s\n' "$CMDS" | awk '{print $1}' | paste -sd, -)"
