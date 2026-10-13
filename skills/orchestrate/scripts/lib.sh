# Shared state and helpers for the orchestrate scripts. Source it from inside the target repo: the main
# checkout or a ticket worktree.
#
# Layout (nothing is written inside the repo except agent worktrees under .claude/worktrees/):
#   $STATE/                     ~/orchestrate/<owner>__<repo>
#   $STATE/run.env              written by preflight: ORCH_TICKETS (repo-relative) and ORCH_MODE_ARG
#   $STATE/HANDOVER.md          the orchestrator's notes for the next session
#   $STATE/parked               one "<id> <reason>" line per parked ticket
#   $STATE/slots/<k>            lock dir for Supabase slot k, holds the ticket id
#   $STATE/locks/gates          lock dir serialising gates machine-wide (builds are memory-hungry)
#   $STATE/<id>/                one ticket: env (PORT, DB_URL, PR_BASE, PARENT_TIP...), gates.ok, logs, artefacts

set -uo pipefail

SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPTS")"
SHARED="$(dirname "$SKILL_DIR")/_shared"
PATCH_SUPABASE="$(dirname "$SKILL_DIR")/pr-sweep/scripts/patch_supabase.py"
. "$SHARED/_cap.sh"

ROOT="$(dirname "$(cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd)")"
TOP="$(git rev-parse --show-toplevel 2>/dev/null)"
SLUG="$(cd "$ROOT" 2>/dev/null && gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)"
STATE="${ORCH_HOME:-$HOME/orchestrate}/${SLUG/\//__}"

ORCH_TICKETS="${ORCH_TICKETS:-}"
[ -z "$ORCH_TICKETS" ] && [ -f "$STATE/run.env" ] && . "$STATE/run.env"

load_config() {
  local cfg="$ROOT/$ORCH_TICKETS/orchestrate.env"
  # shellcheck disable=SC1090
  [ -n "$ORCH_TICKETS" ] && [ -f "$cfg" ] && . "$cfg"
  ORCH_BASE="${ORCH_BASE:-$(cd "$ROOT" && gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null)}"
  ORCH_MODE="${ORCH_MODE_ARG:-${ORCH_MODE:-team}}"
  case "$ORCH_MODE" in team|solo) ;; *) die CONFIG "ORCH_MODE must be team or solo, got $ORCH_MODE" ;; esac
  ORCH_PARALLEL="${ORCH_PARALLEL:-3}"
  ORCH_SESSION_TICKETS="${ORCH_SESSION_TICKETS:-6}"
  ORCH_SLOTS="${ORCH_SLOTS:-2}"
  ORCH_PREFLIGHT_GATES="${ORCH_PREFLIGHT_GATES:-1}"
  ORCH_SETUP="${ORCH_SETUP:-}"
  ORCH_GATES="${ORCH_GATES:-}"
  ORCH_NEON_PROJECT="${ORCH_NEON_PROJECT:-}"
  ORCH_MIGRATION_PATHS="${ORCH_MIGRATION_PATHS:-supabase/migrations/ drizzle/ migrations/ alembic/ prisma/migrations/}"
  ORCH_SEED_PATHS="${ORCH_SEED_PATHS:-supabase/seed supabase/seeds/}"
  ORCH_PROD_PATHS="${ORCH_PROD_PATHS:-}"
  ORCH_CHECK_TIMEOUT="${ORCH_CHECK_TIMEOUT:-1200}"
  ORCH_GATE_TIMEOUT="${ORCH_GATE_TIMEOUT:-1200}"
  ORCH_SUPABASE_EXCLUDE="${ORCH_SUPABASE_EXCLUDE:-studio,imgproxy,vector,logflare,supavisor}"
}

LOG=""
NOTES=()

die() { echo "$1 FAIL: $2${LOG:+ (log: $LOG)}"; exit 1; }

open_log() { mkdir -p "$(dirname "$1")"; LOG="$1"; : > "$LOG"; }

# step <label> <name> <cmd...>: runs a command into $LOG; on failure prints the tail and exits 1.
step() {
  local label="$1" name="$2" start; shift 2
  echo "\$ $*" >> "$LOG"
  start=$(( $(wc -l < "$LOG") + 1 ))
  if ! "$@" >> "$LOG" 2>&1; then
    echo "$label FAIL: $name (log: $LOG)"
    tail -n +"$start" "$LOG" | tail -15
    exit 1
  fi
}

# finish <label> <summary>: prints the notes and the PASS line.
finish() {
  local n
  for n in "${NOTES[@]+"${NOTES[@]}"}"; do echo "note: $n"; done
  echo "$1 PASS ($2)"
}

# --- tickets -----------------------------------------------------------------------------------------
# A ticket is <ticket dir>/<id>-<slug>.md with YAML frontmatter; <id> is letters then digits (T07, OZ12).

ticket_dir() { echo "$ROOT/$ORCH_TICKETS"; }

ticket_files() {
  local f
  for f in "$1"/*.md; do
    [[ "$(basename "$f")" =~ ^[A-Za-z]+[0-9]+-.+\.md$ ]] && echo "$f"
  done
}

ticket_id_of() { local b; b="$(basename "$1" .md)"; echo "${b%%-*}"; }

normalise_id() {
  [[ "${1:-}" =~ ^[A-Za-z]+[0-9]+$ ]] || die TICKET "expected a ticket id like T07, got \"${1:-}\""
  echo "$1" | tr '[:lower:]' '[:upper:]'
}

# ticket_file <id> [dir]
ticket_file() {
  local dir="${2:-$(ticket_dir)}" f
  for f in $(ticket_files "$dir"); do
    [ "$(ticket_id_of "$f")" = "$1" ] && echo "$f" && return 0
  done
  die TICKET "no ticket file for $1 in $dir"
}

# fm <file> <key>: the raw frontmatter value.
fm() {
  awk -v k="$2" 'NR==1 && /^---$/ {f=1; next} f && /^---$/ {exit}
    f { split($0, kv, ":"); if (kv[1] == k) { sub("^[^:]*:[ \t]*", ""); print; exit } }' "$1"
}

# fm_list <file> <key>: a [a, b] or "a b" frontmatter list as space-separated words.
fm_list() { fm "$1" "$2" | tr -d '[]",'"'" | tr -s ' ' | sed 's/^ //; s/ $//'; }

fm_true() { [ "$(fm "$1" "$2")" = "true" ]; }

ticket_branch() { echo "ticket/$(basename "$(ticket_file "$1" "${2:-}")" .md)"; }

id_from_branch() { [[ "$1" =~ ^ticket/([A-Za-z]+[0-9]+)- ]] && echo "${BASH_REMATCH[1]}"; }

id_num() { echo $((10#$(echo "$1" | tr -dc '0-9'))); }

dev_port() { echo $((5000 + $(id_num "$1") % 1000)); }

# Reports live beside the tickets in the main checkout, never in a ticket branch: the ticket dir may be
# local-only (untracked), and a report is orchestration evidence, not part of the change.
report_path() { echo "$ROOT/$ORCH_TICKETS/reports/$1.md"; }

# --- git ---------------------------------------------------------------------------------------------

worktree_of() {
  git -C "$ROOT" worktree list --porcelain | awk -v b="refs/heads/$1" '/^worktree /{p=substr($0,10)} $0=="branch "b{print p}'
}

# Git tree id of the working tree as it stands (tracked and untracked), without touching the index.
working_tree() {
  local index; index="$(cd "$1" && git rev-parse --absolute-git-dir)/orchestrate-index"
  (cd "$1" && GIT_INDEX_FILE="$index" git read-tree HEAD && GIT_INDEX_FILE="$index" git add -A \
    && GIT_INDEX_FILE="$index" git write-tree)
}

# True when nothing outside docs and markdown differs between a recorded tree and HEAD.
code_unchanged_since() {
  git -C "$2" diff --quiet "$1" HEAD -- . ':(exclude)docs' ':(exclude)*.md'
}

# Every PR whose head is a ticket branch, as JSON.
ticket_prs() {
  (cd "$ROOT" && gh pr list --state all --limit 300 --json number,state,isDraft,headRefName,baseRefName,headRefOid,mergeCommit,title,url \
    | jq '[.[] | select(.headRefName | startswith("ticket/"))]')
}

# --- stack -------------------------------------------------------------------------------------------

node_pm_of() {
  if [ -f "$1/pnpm-lock.yaml" ]; then echo pnpm
  elif [ -f "$1/yarn.lock" ]; then echo yarn
  elif [ -f "$1/bun.lockb" ] || [ -f "$1/bun.lock" ]; then echo bun
  elif [ -f "$1/package-lock.json" ]; then echo npm
  fi
}

py_pm_of() {
  if [ -f "$1/uv.lock" ]; then echo uv
  elif [ -f "$1/poetry.lock" ]; then echo poetry
  fi
}

install_cmds() {
  case "$(node_pm_of "$1")" in
    pnpm) echo "pnpm install --frozen-lockfile" ;;
    yarn) echo "yarn install --frozen-lockfile" ;;
    bun) echo "bun install --frozen-lockfile" ;;
    npm) echo "npm ci" ;;
  esac
  case "$(py_pm_of "$1")" in
    uv) echo "uv sync" ;;
    poetry) echo "poetry install --no-interaction" ;;
  esac
}

# gate_cmds <dir>: "<name> <command>" lines. ORCH_GATES ("name=cmd;name=cmd") overrides detection.
gate_cmds() {
  local dir="$1"
  if [ -n "$ORCH_GATES" ]; then
    printf '%s\n' "$ORCH_GATES" | tr ';' '\n' | sed -E 's/^ *([^=]+)=/\1 /' | grep .
    return
  fi
  if [ -f "$dir/package.json" ]; then
    local pm run s; pm="$(node_pm_of "$dir")"; run="${pm:-npm} run"
    has() { jq -e --arg s "$1" '.scripts[$s] // empty | select(test("no test specified") | not)' "$dir/package.json" >/dev/null 2>&1; }
    has build && echo "build $run build"   # first: frameworks generate types (Next's PageProps) that tsc needs
    for s in typecheck type-check check-types types tsc check; do has "$s" && echo "typecheck $run $s" && break; done
    has lint && echo "lint $run lint"
    for s in test:unit test; do has "$s" && echo "test $run $s" && break; done
  fi
  local py; py="$(py_pm_of "$dir")"
  if [ -n "$py" ] && grep -q '\[tool\.poe\.tasks\]' "$dir/pyproject.toml" 2>/dev/null; then
    local poe="$py run poe" s
    for s in typecheck mypy; do grep -qE "^$s[[:space:]]*=" "$dir/pyproject.toml" && echo "py-typecheck $poe $s" && break; done
    for s in lint test; do grep -qE "^$s[[:space:]]*=" "$dir/pyproject.toml" && echo "py-$s $poe $s"; done
  elif [ -n "$py" ]; then
    echo "py-test $py run pytest -q"
  fi
}

is_supabase() { [ -f "$1/supabase/config.toml" ]; }

has_compose() { ls "$1"/{docker-compose,compose}.y*ml >/dev/null 2>&1; }

# DB_URL of whichever Supabase stack the config.toml in <dir> resolves to; empty when down.
supabase_db_url() {
  (cd "$1" && cap 20 supabase status -o env 2>/dev/null) | sed -n 's/^DB_URL="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' | head -1
}

touches() {  # touches "<prefixes>" <files...>: prints the files under any prefix
  local prefixes="$1" f p; shift
  for f in "$@"; do for p in $prefixes; do [[ "$f" == "$p"* ]] && echo "$f" && break; done; done
}

# --- locks and slots ---------------------------------------------------------------------------------

lock() {  # lock <dir> <timeout-seconds>: mkdir is atomic, so it doubles as a cross-process mutex
  local waited=0
  mkdir -p "$(dirname "$1")"
  until mkdir "$1" 2>/dev/null; do
    [ "$waited" -ge "$2" ] && return 1
    sleep 5; waited=$((waited + 5))
  done
}

claim_slot() {  # claim_slot <id> <timeout>: prints the slot number; reuses the ticket's slot if it holds one
  local k waited=0
  mkdir -p "$STATE/slots"
  while :; do
    for k in $(seq 1 "$ORCH_SLOTS"); do
      [ "$(cat "$STATE/slots/$k/id" 2>/dev/null)" = "$1" ] && echo "$k" && return 0
    done
    for k in $(seq 1 "$ORCH_SLOTS"); do
      if mkdir "$STATE/slots/$k" 2>/dev/null; then echo "$1" > "$STATE/slots/$k/id"; echo "$k"; return 0; fi
    done
    [ "$waited" -ge "$2" ] && return 1
    sleep 30; waited=$((waited + 30))
  done
}

release_slot() {
  local k
  for k in $(seq 1 "$ORCH_SLOTS"); do
    [ "$(cat "$STATE/slots/$k/id" 2>/dev/null)" = "$1" ] && rm -rf "$STATE/slots/$k"
  done
}

kill_port() { lsof -tiTCP:"$(dev_port "$1")" -sTCP:LISTEN 2>/dev/null | xargs kill 2>/dev/null; }

attribution_in() { grep -qiE 'Generated with \[?Claude|Co-Authored-By: Claude' <<< "$1"; }

# --- per-ticket env ----------------------------------------------------------------------------------

env_get() { sed -n "s/^$2=//p" "$STATE/$1/env" 2>/dev/null | tail -1; }

env_set() {  # env_set <id> <key> <value>
  mkdir -p "$STATE/$1"; touch "$STATE/$1/env"
  grep -v "^$2=" "$STATE/$1/env" > "$STATE/$1/env.tmp"; echo "$2=$3" >> "$STATE/$1/env.tmp"
  mv "$STATE/$1/env.tmp" "$STATE/$1/env"
}

# --- review and CI checks shared by ready.sh and merge.sh ---------------------------------------------

verdict_clear() {  # verdict_clear <id>: the ticket's report says ALL CLEAR
  grep -qE '^Verdict:[[:space:]]*ALL CLEAR' "$(report_path "$1")" 2>/dev/null
}

checks_green() {  # checks_green <pr>: waits for pending checks up to ORCH_CHECK_TIMEOUT
  local deadline=$(( $(date +%s) + ORCH_CHECK_TIMEOUT )) buckets failed
  sleep 10
  while :; do
    buckets="$(cd "$ROOT" && gh pr checks "$1" --json name,bucket 2>/dev/null || echo '[]')"
    failed="$(jq -r '.[] | select(.bucket == "fail") | .name' <<< "$buckets" | paste -sd, -)"
    [ -n "$failed" ] && { echo "failed checks: $failed"; return 1; }
    jq -e '.[] | select(.bucket == "pending")' <<< "$buckets" >/dev/null || return 0
    [ "$(date +%s)" -gt "$deadline" ] && { echo "checks still pending after ${ORCH_CHECK_TIMEOUT}s; rerun later"; return 1; }
    sleep 30
  done
}

# --- ticket table: status of every ticket, derived from git and GitHub ---------------------------------
# Columns: id|status|branch|depends_on|serial|flags|title|pr number|pr base|parent ticket|parent branch
# The parent is the ticket branch the PR stacks on, or, once GitHub retargets it after a merge, the one
# setup.sh recorded as PR_BASE.
# Status: done (PR merged) · cleared (team: PR ready for review with ALL CLEAR) · in-flight · parked · todo

build_table() {  # build_table <file>
  local f id branch serial flags st pr num base parent pbranch
  : > "$1"
  PRS="$(ticket_prs)"
  git -C "$ROOT" fetch origin --prune --quiet 2>/dev/null
  for f in $(ticket_files "$(ticket_dir)"); do
    id="$(ticket_id_of "$f")"; branch="ticket/$(basename "$f" .md)"
    serial="$(fm_list "$f" serial)"; fm_true "$f" migrations && serial="$serial migrations"
    flags=""; fm_true "$f" requires_human && flags=HUMAN
    pr="$(jq -c --arg h "$branch" '[.[] | select(.headRefName == $h and .state == "OPEN")][0] // empty' <<< "$PRS")"
    num=""; base=""; pbranch=""
    if [ -n "$pr" ]; then
      num="$(jq -r .number <<< "$pr")"; base="$(jq -r .baseRefName <<< "$pr")"
      pbranch="$base"; [ -n "$(id_from_branch "$pbranch")" ] || pbranch="$(env_get "$id" PR_BASE)"
    fi
    parent="$(id_from_branch "$pbranch")"; [ -n "$parent" ] || pbranch=""
    if jq -e --arg h "$branch" '.[] | select(.headRefName == $h and .state == "MERGED")' <<< "$PRS" >/dev/null; then st=done
    elif grep -q "^$id " "$STATE/parked" 2>/dev/null; then st=parked
    elif [ -n "$pr" ] && [ "$ORCH_MODE" = team ] && [ "$(jq -r .isDraft <<< "$pr")" = false ] && verdict_clear "$id"; then st=cleared
    elif [ -n "$pr" ] || [ -n "$(worktree_of "$branch")" ] || git -C "$ROOT" show-ref --quiet "refs/heads/$branch"; then st=in-flight
    else st=todo
    fi
    echo "$id|$st|$branch|$(fm_list "$f" depends_on)|$(echo $serial)|$flags|$(fm "$f" title)|$num|$base|$parent|$pbranch" >> "$1"
  done
}

col() { awk -F'|' -v id="$2" -v c="$3" '$1 == id {print $c}' "$1"; }   # col <table> <id> <column>
ids_with() { awk -F'|' -v s="$2" '$2 == s {print $1}' "$1"; }         # ids_with <table> <status>

merge_oid() { jq -r --arg h "$1" '[.[] | select(.headRefName == $h and .state == "MERGED")][0].mergeCommit.oid // empty' <<< "$PRS"; }

# needs_restack <table> <id>: why an open stacked PR must rebase onto its parent, or nothing.
needs_restack() {
  local parent pbranch tip
  parent="$(col "$1" "$2" 10)"; [ -n "$parent" ] || return 0
  pbranch="$(col "$1" "$2" 11)"
  if [ "$(col "$1" "$parent" 2)" = done ]; then echo "parent $parent merged"; return; fi
  tip="$(env_get "$2" PARENT_TIP)"
  [ -n "$tip" ] || tip="$(git -C "$ROOT" merge-base "origin/$pbranch" "origin/$(col "$1" "$2" 3)" 2>/dev/null)"
  [ "$tip" = "$(git -C "$ROOT" rev-parse "origin/$pbranch" 2>/dev/null)" ] || echo "parent $parent moved"
}

# stack_base <table> <id>: "base <branch>", "on <branch> <parent id>", or "wait <reason>".
# Every dependency must be done or cleared. At most one may be cleared but unmerged: the ticket stacks on it.
stack_base() {
  local d st cleared="" pending="" b why oid
  for d in $(col "$1" "$2" 4); do
    st="$(col "$1" "$d" 2)"
    case "$st" in
      done) ;;
      cleared) cleared="$cleared $d" ;;
      *) pending="$pending $d" ;;
    esac
  done
  [ -n "$pending" ] && { echo "wait on$pending"; return; }
  set -- "$1" "$2" $cleared
  case $# in
    2) echo "base $ORCH_BASE" ;;
    3)
      b="$(col "$1" "$3" 3)"
      why="$(needs_restack "$1" "$3")"
      [ -n "$why" ] && { echo "wait on restack of $3 ($why)"; return; }
      for d in $(col "$1" "$2" 4); do
        [ "$(col "$1" "$d" 2)" = done ] || continue
        oid="$(merge_oid "$(col "$1" "$d" 3)")"
        [ -n "$oid" ] && ! git -C "$ROOT" merge-base --is-ancestor "$oid" "origin/$b" 2>/dev/null \
          && { echo "wait on restack of $3 (lacks merged $d)"; return; }
      done
      echo "on $b $3" ;;
    *) echo "wait on a human merging all but one of$cleared (a PR has one base)" ;;
  esac
}
