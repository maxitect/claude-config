#!/usr/bin/env bash
# Brings a reviewed PR's environment back (own Supabase stack for migration PRs) and prints the command
# that resumes its reviewer session interactively.
#
# Usage: open.sh <pr>

. "$(dirname "$0")/lib.sh"
N="${1:?usage: open.sh <pr>}"
RUN="$(run_dir "$N")"; WT="$(wt_dir "$N")"
SID="$(cat "$RUN/reviewer.sid" 2>/dev/null)"
[ -n "$SID" ] && [ -d "$WT" ] || die OPEN "#$N has no reviewer session or worktree (swept, or never reviewed)"

if [ "$(meta "$N" .mig)" = "true" ] && [ -z "$(supabase_db_url "$WT")" ]; then
  claim_slot "$N" 0 >/dev/null || die OPEN "all $MAX_SLOTS supabase slots busy: teardown.sh another PR first"
  (cd "$WT" && cap 600 supabase start -x "$SUPABASE_EXCLUDE") > "$RUN/open.log" 2>&1 \
    || { LOG="$RUN/open.log"; die OPEN "#$N supabase start failed"; }
fi
echo "OPEN PASS #$N: cd $WT && $CLAUDE_HINT --resume $SID"
echo "(close it with pr-sweep teardown $N when done; don't pr-sweep ask it while it's open)"
