#!/usr/bin/env bash
# Prints the state of the active ticket set, derived from git and GitHub (no status file to keep in sync).
#
#   IN FLIGHT  being built or reviewed: PR, report status, verdict, worktree, and any restack needed
#   CLEARED    team mode: ready for review, waiting on humans; flags stacked PRs whose parent moved or merged
#   READY      every dependency merged (or, in team mode, cleared): where it would branch from, and any hold
#   PARKED     set aside by the orchestrator
#
# Usage: status.sh

. "$(dirname "$0")/lib.sh"
[ -n "$ORCH_TICKETS" ] || { echo "STATUS FAIL: no active run: run preflight.sh <ticket dir> first"; exit 1; }
load_config
T="$(mktemp -t orchestrate)"; trap 'rm -f "$T"' EXIT
build_table "$T"

held_by() {  # the in-flight ticket holding one of <id>'s serial tags
  local tag other
  for tag in $(col "$T" "$1" 5); do
    for other in $(ids_with "$T" in-flight); do
      [[ " $(col "$T" "$other" 5) " == *" $tag "* ]] && echo "$other ($tag)" && return
    done
  done
}

pr_label() { local n; n="$(col "$T" "$1" 8)"; [ -n "$n" ] && echo "PR #$n → $(col "$T" "$1" 9)" || echo "no PR"; }

echo "MODE $ORCH_MODE · base $ORCH_BASE · parallel $ORCH_PARALLEL · session $ORCH_SESSION_TICKETS tickets · tickets $ORCH_TICKETS"

echo "IN FLIGHT"
for id in $(ids_with "$T" in-flight); do
  branch="$(col "$T" "$id" 3)"; wt="$(worktree_of "$branch")"
  report="$(report_path "$id")"; [ -f "$report" ] || report=/dev/null
  rstatus="$(sed -n 's/^Status:[[:space:]]*//p' "$report" | head -1)"
  verdict="$(sed -n 's/^Verdict:[[:space:]]*//p' "$report" | head -1)"
  where="no worktree (branch only)"
  [ -n "$wt" ] && where="worktree ${wt#"$ROOT"/} ($(git -C "$wt" rev-list --count "origin/$ORCH_BASE..HEAD" 2>/dev/null) commits)"
  restack="$(needs_restack "$T" "$id")"
  echo "  $id · $(pr_label "$id") · report ${rstatus:-none} · ${verdict:-no review} · $where${restack:+ · RESTACK: $restack}"
done

if [ "$ORCH_MODE" = team ]; then
  echo "CLEARED (ready for review)"
  for id in $(ids_with "$T" cleared); do
    restack="$(needs_restack "$T" "$id")"
    echo "  $id · $(pr_label "$id") · $(col "$T" "$id" 7)${restack:+ · RESTACK: $restack}"
  done
fi

echo "READY"
for id in $(ids_with "$T" todo); do
  base="$(stack_base "$T" "$id")"
  pending=0; for d in $(col "$T" "$id" 4); do case "$(col "$T" "$d" 2)" in done|cleared) ;; *) pending=1 ;; esac; done
  [ "$pending" = 1 ] && continue
  tags="$(col "$T" "$id" 5)"; flags="$(col "$T" "$id" 6)"; held="$(held_by "$id")"
  case "$base" in
    base*) from="from $ORCH_BASE" ;;
    on*) from="stacks on $(echo "$base" | awk '{print $3}')" ;;
    wait*) from="${base}" ;;
  esac
  [ -n "$held" ] && from="$from · waits on $held"
  echo "  $id ${flags:+$flags }${tags:+[${tags// /, }] }$(col "$T" "$id" 7) · $from"
done

echo "PARKED"
[ -f "$STATE/parked" ] && sed 's/^/  /' "$STATE/parked"

echo "DONE $(ids_with "$T" done | grep -c .)/$(grep -c . "$T")$([ "$ORCH_MODE" = team ] && echo " merged, $(ids_with "$T" cleared | grep -c .) cleared")"
