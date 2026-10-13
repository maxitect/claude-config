#!/usr/bin/env bash
# Verifies the machine and repo can run an orchestrated build of a ticket set, sweeps merged tickets, and
# records the ticket set as the active run. Prints PREFLIGHT PASS plus notes, or PREFLIGHT FAIL: <step>.
#
# Usage: preflight.sh <ticket dir, relative to the repo root> [team|solo] [<n>]
#   team (default): draft PRs, marked ready for review once cleared; dependents stack on cleared parents
#   solo: the orchestrator squash-merges cleared PRs into the base; dependents start from the base
#   <n>: tickets to take this session (overrides ORCH_SESSION_TICKETS; 0 = no cap)

ORCH_TICKETS=""; MODE=""; SESSION=""
for a in "$@"; do case "$a" in team|solo) MODE="$a" ;; *[!0-9]*|"") ORCH_TICKETS="$a" ;; *) SESSION="$a" ;; esac; done
. "$(dirname "$0")/lib.sh"

[ -n "$ROOT" ] && [ -d "$ROOT" ] || die PREFLIGHT "not inside a git repository"
if [ -z "$ORCH_TICKETS" ] && [ -f "$STATE/run.env" ]; then . "$STATE/run.env"; fi
ORCH_MODE_ARG="$MODE"
ORCH_SESSION_ARG="$SESSION"
[ -n "$ORCH_TICKETS" ] || die PREFLIGHT "no ticket dir: /orchestrate <dir with <id>-<slug>.md tickets>"
ORCH_TICKETS="${ORCH_TICKETS%/}"
[ -d "$ROOT/$ORCH_TICKETS" ] || die PREFLIGHT "$ORCH_TICKETS is not a directory under $ROOT"
[ -n "$(ticket_files "$ROOT/$ORCH_TICKETS")" ] || die PREFLIGHT "no <id>-<slug>.md tickets in $ORCH_TICKETS"
[ -n "$SLUG" ] || die PREFLIGHT "gh cannot resolve a GitHub repo here (gh auth status, or no github remote)"
for bin in git gh jq perl lsof; do command -v "$bin" >/dev/null || die PREFLIGHT "$bin not on PATH"; done

load_config
mkdir -p "$STATE/slots" "$STATE/locks"
printf 'ORCH_TICKETS=%s\nORCH_MODE_ARG=%s\nORCH_SESSION_ARG=%s\n' "$ORCH_TICKETS" "$ORCH_MODE_ARG" "$ORCH_SESSION_ARG" > "$STATE/run.env"
open_log "$STATE/preflight.log"
cd "$ROOT" || exit 1

base_clean() {
  [ "$(git branch --show-current)" = "$ORCH_BASE" ] || { echo "main checkout is on $(git branch --show-current), not $ORCH_BASE"; return 1; }
  git fetch origin --prune --quiet || return 1
  git rev-parse --verify --quiet "origin/$ORCH_BASE" >/dev/null || { echo "origin/$ORCH_BASE does not exist: push it first"; return 1; }
  [ -z "$(git status --porcelain --untracked-files=no)" ] || { git status --short --untracked-files=no; echo "uncommitted changes on $ORCH_BASE"; return 1; }
  git merge --ff-only --quiet "origin/$ORCH_BASE" || { echo "$ORCH_BASE cannot fast-forward to origin/$ORCH_BASE"; return 1; }
  [ "$(git rev-parse HEAD)" = "$(git rev-parse "origin/$ORCH_BASE")" ] || { echo "$ORCH_BASE is ahead of origin: push it"; return 1; }
}

worktrees_ignored() {
  git check-ignore -q .claude/worktrees/probe || { echo "add .claude/worktrees/ to .gitignore"; return 1; }
}

step PREFLIGHT "gh auth" gh auth status
step PREFLIGHT "$ORCH_BASE clean and synced" base_clean
step PREFLIGHT ".claude/worktrees ignored" worktrees_ignored

if is_supabase "$ROOT"; then
  for bin in docker supabase psql; do command -v "$bin" >/dev/null || die PREFLIGHT "$bin not on PATH (repo has supabase/config.toml)"; done
  step PREFLIGHT "docker running" docker info
  if [ -z "$(supabase_db_url "$ROOT")" ]; then
    step PREFLIGHT "supabase start" cap 600 supabase start -x "$ORCH_SUPABASE_EXCLUDE"
    NOTES+=("started the base supabase stack")
  fi
  if ! OUT="$(cap 300 supabase migration up 2>&1)"; then
    printf '%s\n' "$OUT" >> "$LOG"
    grep -q LegacyMigrationMissingLocalError <<< "$OUT" \
      && die PREFLIGHT "the local database has migrations that are not on $ORCH_BASE (applied from another branch). Run 'supabase db reset' in $ROOT: it wipes local data and rebuilds from $ORCH_BASE's migrations and seed"
    die PREFLIGHT "supabase migration up"
  fi
elif has_compose "$ROOT"; then
  command -v docker >/dev/null || die PREFLIGHT "docker not on PATH (repo has a compose file)"
  step PREFLIGHT "docker compose up" cap 300 docker compose up -d --wait
fi

if [ -n "$ORCH_NEON_PROJECT" ]; then
  command -v neonctl >/dev/null || die PREFLIGHT "neonctl not on PATH (ORCH_NEON_PROJECT is set)"
  step PREFLIGHT "neonctl auth" neonctl me --output json
fi

SWEPT="$("$SCRIPTS/sweep.sh" 2>&1)"
[ -n "$SWEPT" ] && NOTES+=("$SWEPT")

while read -r cmd; do
  [ -n "$cmd" ] && step PREFLIGHT "$cmd" cap 900 env CI=1 sh -c "$cmd"
done <<< "$(install_cmds "$ROOT")"
[ -n "$ORCH_SETUP" ] && step PREFLIGHT "$ORCH_SETUP" cap 600 sh -c "$ORCH_SETUP"

if [ "$ORCH_PREFLIGHT_GATES" = "1" ]; then
  while read -r name cmd; do
    [ -n "$name" ] && step PREFLIGHT "$name ($cmd)" cap "$ORCH_GATE_TIMEOUT" env CI=1 NO_COLOR=1 sh -c "$cmd"
  done <<< "$(gate_cmds "$ROOT")"
fi

finish PREFLIGHT "$SLUG, tickets $ORCH_TICKETS, mode $ORCH_MODE, session $ORCH_SESSION_TICKETS tickets, base $ORCH_BASE, state $STATE"
