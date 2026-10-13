#!/usr/bin/env bash
# Prepares one ticket's worktree: names the branch ticket/<id>-<slug> and, on first run, starts it from the
# right base (the run's base, or in team mode the cleared parent it stacks on), copies the main checkout's local env
# files (remapping :3000 to the ticket's port), gives the ticket its own Supabase stack when it has
# migrations: true or own_db: true, installs, and runs the repo's setup command. Idempotent: re-run it to resume.
#
# Usage: setup.sh <id>   (run inside the ticket's worktree, never the main checkout)

. "$(dirname "$0")/lib.sh"
load_config
ID="$(normalise_id "${1:-}")"
[ -n "$TOP" ] && [ "$TOP" != "$ROOT" ] || die SETUP "run inside the ticket's worktree, not the main checkout"
[ -n "$ORCH_TICKETS" ] || die SETUP "no active run: the orchestrator's preflight has not run"

TICKET="$(ticket_file "$ID")"
BRANCH="$(ticket_branch "$ID")"
PORT="$(dev_port "$ID")"
RUN="$STATE/$ID"
mkdir -p "$RUN/artefacts"
open_log "$RUN/setup.log"
cd "$TOP" || exit 1

checkout_branch() {
  local current; current="$(git branch --show-current)"
  [ "$current" = "$BRANCH" ] && return 0
  if git show-ref --verify --quiet "refs/heads/$BRANCH"; then git switch "$BRANCH"
  else git branch -m "$BRANCH"; fi
}

# First run only: start the branch from origin/<PR base>, unless it already has commits of its own.
start_from_base() {
  [ -n "$(env_get "$ID" PR_BASE)" ] && return 0
  git fetch origin --quiet || return 1
  local table sb; table="$(mktemp -t orchestrate)"; build_table "$table"; sb="$(stack_base "$table" "$ID")"; rm -f "$table"
  case "$sb" in
    base*) PR_BASE="$ORCH_BASE" ;;
    on*) PR_BASE="$(echo "$sb" | awk '{print $2}')" ;;
    *) echo "not ready: $sb"; return 1 ;;
  esac
  [ -z "$(git log "origin/$ORCH_BASE..HEAD" --oneline)" ] || { echo "branch already has commits; refusing to move it onto $PR_BASE"; return 1; }
  git reset --hard "origin/$PR_BASE" || return 1
  env_set "$ID" PR_BASE "$PR_BASE"
  env_set "$ID" PARENT_TIP "$(git rev-parse "origin/$PR_BASE")"
}

# Local env files the build needs (never production ones), wrangler secrets and generated types.
copy_env() {
  (cd "$ROOT" && git ls-files --others --ignored --exclude-standard --directory) \
    | grep -E '(^|/)(\.env(\.local|\.development[^/]*|\.test[^/]*)?|\.dev\.vars|[^/]*\.d\.ts)$' | grep -v node_modules \
    | while read -r f; do
        [ -e "$TOP/$f" ] && continue
        mkdir -p "$TOP/$(dirname "$f")"
        cp "$ROOT/$f" "$TOP/$f"
        case "$f" in *.env*|*.dev.vars) remap "$TOP/$f" "3000 $PORT
$MAP" ;; esac
      done
}

remap() {  # remap <file> "<old new>" lines: ':<old>' becomes ':<new>'
  printf '%s\n' "$2" | while read -r old new; do
    [ -n "$old" ] && sed -i '' -E "s/:${old}([^0-9]|\$)/:${new}\1/g" "$1"
  done
}

MAP=""
SLOT=""
if is_supabase "$TOP" && { fm_true "$TICKET" migrations || fm_true "$TICKET" own_db; }; then
  SLOT="$(claim_slot "$ID" 3600)" || die SETUP "no supabase slot free after 60 minutes (ORCH_SLOTS=$ORCH_SLOTS)"
  if ! git ls-files -v supabase/config.toml | grep -q '^S'; then
    MAP="$(python3 "$PATCH_SUPABASE" supabase/config.toml "$SLOT" "$(id_num "$ID")" "$PORT")" || die SETUP "could not patch supabase/config.toml"
    git update-index --skip-worktree supabase/config.toml
    printf '%s\n' "$MAP" > "$RUN/port-map"
  else
    MAP="$(cat "$RUN/port-map" 2>/dev/null)"
  fi
fi

step SETUP "branch $BRANCH" checkout_branch
step SETUP "start from base" start_from_base
step SETUP "env files" copy_env
if [ -n "$SLOT" ] && [ -z "$(supabase_db_url "$TOP")" ]; then
  step SETUP "supabase start (own stack, slot $SLOT)" cap 900 supabase start -x "$ORCH_SUPABASE_EXCLUDE"
fi
while read -r cmd; do
  [ -n "$cmd" ] && step SETUP "$cmd" env CI=1 cap 900 sh -c "$cmd"
done <<< "$(install_cmds "$TOP")"
[ -n "$ORCH_SETUP" ] && step SETUP "$ORCH_SETUP" cap 600 sh -c "$ORCH_SETUP"

DB_URL=""
is_supabase "$TOP" && DB_URL="$(supabase_db_url "$TOP")"
DB="none"
if [ -n "$SLOT" ]; then DB="own supabase stack, slot $SLOT: write freely"
elif [ -n "$DB_URL" ]; then DB="SHARED base supabase stack: wrap writes in BEGIN; ... ROLLBACK; or use rows only you created"
fi
for kv in "ID=$ID" "BRANCH=$BRANCH" "WORKTREE=$TOP" "PORT=$PORT" "DB_URL=$DB_URL" "SLOT=$SLOT"; do env_set "$ID" "${kv%%=*}" "${kv#*=}"; done
PR_BASE="$(env_get "$ID" PR_BASE)"
DRAFT=""; [ "$ORCH_MODE" = team ] && DRAFT=" draft"

mkdir -p "$(dirname "$(report_path "$ID")")"
finish SETUP "$ID mode=$ORCH_MODE report=$(report_path "$ID") branch=$BRANCH pr-base=$PR_BASE (open the PR with /pr-prep $PR_BASE$DRAFT) port=$PORT db=${DB_URL:-none} ($DB) artefacts=$RUN/artefacts"
