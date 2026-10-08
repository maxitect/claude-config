# Shared state and helpers for the pr-sweep scripts. Source it from inside the target repo.
#
# Layout (nothing is written inside the repo):
#   $SWEEP/                     ~/pr-sweep/<owner>__<repo>
#   $SWEEP/queue.json           last discover.sh result
#   $SWEEP/slots/<k>            lock dir for Supabase slot k, holds the PR number
#   $SWEEP/locks/gates          lock dir serialising typecheck/lint/test/build across PRs
#   $SWEEP/<n>/                 one PR: meta.json, wt/, context.md, gates/, findings.json, ...

set -uo pipefail

SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPTS")"
SHARED="$(dirname "$SKILL_DIR")/_shared"
. "$SHARED/_cap.sh"

MAX_SLOTS="${PR_SWEEP_SLOTS:-3}"
SUPABASE_EXCLUDE="${PR_SWEEP_SUPABASE_EXCLUDE:-studio,imgproxy,vector,logflare,supavisor}"
REVIEW_TIMEOUT="${PR_SWEEP_REVIEW_TIMEOUT:-3600}"
GATE_TIMEOUT="${PR_SWEEP_GATE_TIMEOUT:-900}"

ROOT="$(dirname "$(cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd)")"
SLUG="$(cd "$ROOT" && gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)"
SWEEP="${PR_SWEEP_HOME:-$HOME/pr-sweep}/${SLUG/\//__}"

LOG=""

die() { echo "$1 FAIL: $2${LOG:+ (log: $LOG)}"; exit 1; }

# step <label> <name> <cmd...> — runs a command into $LOG; on failure prints the tail and exits.
step() {
  local label="$1" name="$2"; shift 2
  echo "\$ $*" >> "$LOG"
  if ! "$@" >> "$LOG" 2>&1; then
    echo "$label FAIL: $name (log: $LOG)"
    tail -15 "$LOG"
    exit 1
  fi
}

run_dir() { echo "$SWEEP/$1"; }
wt_dir() { echo "$SWEEP/$1/wt"; }
meta() { jq -r "$2" "$SWEEP/$1/meta.json"; }
dev_port() { echo $((4000 + $1 % 1000)); }
api_port() { echo $((6000 + $1 % 1000)); }
kill_ports() { local p; for p in "$(dev_port "$1")" "$(api_port "$1")"; do lsof -tiTCP:"$p" -sTCP:LISTEN 2>/dev/null | xargs kill 2>/dev/null; done; }
is_supabase() { [ -f "$1/supabase/config.toml" ]; }

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

# DB_URL of whichever Supabase stack the config.toml in <dir> resolves to; empty when down.
supabase_db_url() {
  (cd "$1" && cap 20 supabase status -o env 2>/dev/null) | sed -n 's/^DB_URL="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' | head -1
}

# lock <dir> <timeout-seconds> — mkdir is atomic, so it doubles as a cross-process mutex.
lock() {
  local waited=0
  mkdir -p "$(dirname "$1")"
  until mkdir "$1" 2>/dev/null; do
    [ "$waited" -ge "$2" ] && return 1
    sleep 5; waited=$((waited + 5))
  done
}

# claim_slot <pr> <timeout> — prints the slot number; reuses the PR's slot if it already holds one.
claim_slot() {
  local k waited=0
  mkdir -p "$SWEEP/slots"
  while :; do
    for k in $(seq 1 "$MAX_SLOTS"); do
      [ "$(cat "$SWEEP/slots/$k/pr" 2>/dev/null)" = "$1" ] && echo "$k" && return 0
    done
    for k in $(seq 1 "$MAX_SLOTS"); do
      if mkdir "$SWEEP/slots/$k" 2>/dev/null; then
        echo "$1" > "$SWEEP/slots/$k/pr"
        echo "$k"
        return 0
      fi
    done
    [ "$waited" -ge "$2" ] && return 1
    sleep 30; waited=$((waited + 30))
  done
}

slot_of() {
  local k
  for k in $(seq 1 "$MAX_SLOTS"); do
    [ "$(cat "$SWEEP/slots/$k/pr" 2>/dev/null)" = "$1" ] && echo "$k" && return 0
  done
}

release_slot() {
  local k; k="$(slot_of "$1")"
  [ -n "$k" ] && rm -rf "$SWEEP/slots/$k"
}

# Flags shared by every headless reviewer invocation (first run, validation retry, ask.sh).
reviewer_flags() {
  local run="$1"
  printf '%s\n' \
    --agent pr-reviewer --model opus --permission-mode dontAsk --add-dir "$run" "$HOME/.claude/skills" "$HOME/.claude/commands" \
    --allowedTools "Read,Grep,Glob,Write,Edit,Bash(gh pr view*),Bash(gh pr diff*),Bash(gh issue view*),Bash(gh repo view*),Bash(git diff*),Bash(git log*),Bash(git show*),Bash(git status*),Bash(git blame*),Bash(cat*),Bash(grep*),Bash(ls*),Bash(find*),Bash(head*),Bash(tail*),Bash(wc*),Bash(sed -n*),Bash(curl*),Bash(jq*),Bash(lsof*),Bash(kill*),Bash(sleep*),Bash(pnpm*),Bash(npm*),Bash(npx*),Bash(yarn*),Bash(bun*),Bash(bunx*),Bash(node*),Bash(tsx*),Bash(python*),Bash(pytest*),Bash(mypy*),Bash(ruff*),Bash(poetry*),Bash(uv*),Bash(go*),Bash(cargo*),Bash(docker ps*),Bash(docker logs*),Bash(psql*),Bash(supabase status*),Bash(supabase db lint*),Bash(supabase db advisors*),Bash(supabase gen types*),Bash(supabase migration list*),mcp__playwright,mcp__plugin_playwright_playwright,mcp__claude_ai_monday_com,mcp__claude_ai_Atlassian_Rovo,mcp__claude_ai_Linear,mcp__claude_ai_Google_Drive" \
    --disallowedTools "Bash(git push*),Bash(git commit*),Bash(gh pr review*),Bash(gh pr comment*),Bash(gh pr merge*),Bash(gh pr close*),Bash(gh pr edit*),Bash(gh pr ready*),Bash(gh issue comment*),Bash(gh issue edit*),Bash(supabase stop*),Bash(supabase start*),Bash(supabase db reset*),Bash(supabase db push*),Bash(supabase link*),mcp__supabase"
}
