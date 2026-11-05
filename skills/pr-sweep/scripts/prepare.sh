#!/usr/bin/env bash
# Builds one PR's review environment: worktree at the PR head, env files, its own Supabase stack when the
# PR touches the schema (base stack otherwise), install, gates, and the rendered review context.
#
# Usage: prepare.sh <pr>
# Writes $SWEEP/<pr>/{meta.json,wt/,context.md,gates/,prepare.log}. Install, gate and stack failures are
# recorded in context.md as evidence rather than aborting: a migration that won't apply is a finding.

. "$(dirname "$0")/lib.sh"
N="${1:?usage: prepare.sh <pr>}"
RUN="$(run_dir "$N")"; WT="$(wt_dir "$N")"
mkdir -p "$RUN/gates"
LOG="$RUN/prepare.log"; : > "$LOG"
cd "$ROOT" || exit 1

# --- metadata --------------------------------------------------------------------------------------
if ! jq -e ".[] | select(.number==$N)" "$SWEEP/queue.json" > "$RUN/meta.json" 2>/dev/null; then
  gh pr view "$N" --json number,title,url,headRefOid,headRefName,baseRefName \
    -q '{number,title,url,sha:.headRefOid,head:.headRefName,base:.baseRefName,mig:false,rereview:false}' \
    > "$RUN/meta.json" || die PREPARE "PR #$N not found"
fi
SHA="$(meta "$N" .sha)"; BASE="$(meta "$N" .base)"; HEAD="$(meta "$N" .head)"; MIG="$(meta "$N" .mig)"
PORT="$(dev_port "$N")"; API_PORT="$(api_port "$N")"
APP_PORTS="3000 $PORT
5173 $PORT
8000 $API_PORT"

# --- worktree at the PR head -----------------------------------------------------------------------
step PREPARE "fetch" git fetch --quiet origin "$BASE" "pull/$N/head"
if [ -d "$WT/.git" ] || [ -f "$WT/.git" ]; then
  step PREPARE "checkout $SHA" git -C "$WT" checkout --quiet --force --detach "$SHA"
  step PREPARE "clean worktree" git -C "$WT" clean -fdq
else
  step PREPARE "worktree add" git worktree add --quiet --detach "$WT" "$SHA"
fi

# untracked config the build needs: local env files (never production/remote ones), wrangler secrets, generated types
git ls-files --others --ignored --exclude-standard --directory 2>/dev/null \
  | grep -E '(^|/)(\.env(\.local|\.development[^/]*|\.test[^/]*)?|\.dev\.vars|[^/]*\.d\.ts)$' | grep -v node_modules \
  | while read -r f; do mkdir -p "$WT/$(dirname "$f")"; cp "$f" "$WT/$f"; done

# remap ':<old port>' -> ':<new port>' in every copied env file
remap_env() {
  local map="$1" f
  git -C "$WT" ls-files --others --ignored --exclude-standard --directory 2>/dev/null | grep -E '(^|/)\.env[^/]*$' | grep -v node_modules \
    | while read -r f; do
        printf '%s\n' "$map" | while read -r old new; do
          [ -n "$old" ] && sed -i '' -E "s/:${old}([^0-9]|\$)/:${new}\1/g" "$WT/$f"
        done
      done
}

# --- database stack --------------------------------------------------------------------------------
STACK_NOTE=""
if [ "$MIG" = "true" ]; then
  SLOT="$(claim_slot "$N" 3600)" || die PREPARE "no supabase slot free after 60 minutes (max $MAX_SLOTS)"
  MAP="$(python3 "$SCRIPTS/patch_supabase.py" "$WT/supabase/config.toml" "$SLOT" "$N" "$PORT")" \
    || die PREPARE "could not patch supabase/config.toml"
  remap_env "$MAP
$APP_PORTS"
  (cd "$WT" && cap 120 supabase stop --no-backup) >> "$LOG" 2>&1
  START_OUT="$(cd "$WT" && cap 600 supabase start -x "$SUPABASE_EXCLUDE" 2>&1)"
  START_RC=$?
  printf '%s\n' "$START_OUT" >> "$LOG"
  if [ "$START_RC" -ne 0 ]; then
    STACK_NOTE="\`supabase start\` on a fresh stack with this PR's migrations and seed FAILED (exit $START_RC). That is a 🔴 finding in itself; this is its evidence:
$(printf '%s\n' "$START_OUT" | tail -25 | sed 's/^/  | /')"
  fi
else
  remap_env "$APP_PORTS"
fi
DB_URL=""
is_supabase "$WT" && DB_URL="$(supabase_db_url "$WT")"

# --- install: a repo can carry both a JS and a Python toolchain -------------------------------------
NODE_PM="$(node_pm_of "$WT")"; PY_PM="$(py_pm_of "$WT")"
INSTALLS=()
case "$NODE_PM" in
  pnpm) INSTALLS+=("pnpm install --frozen-lockfile") ;;
  yarn) INSTALLS+=("yarn install --frozen-lockfile") ;;
  bun) INSTALLS+=("bun install --frozen-lockfile") ;;
  npm) INSTALLS+=("npm ci") ;;
esac
case "$PY_PM" in
  uv) INSTALLS+=("uv sync") ;;
  poetry) INSTALLS+=("poetry install --no-interaction") ;;
esac
INSTALL_FAIL=""
for cmd in "${INSTALLS[@]+"${INSTALLS[@]}"}"; do
  if ! (cd "$WT" && CI=1 cap 900 sh -c "$cmd") >> "$RUN/gates/install.log" 2>&1; then
    INSTALL_FAIL="$cmd"; break
  fi
done

# --- gates (one PR at a time machine-wide: builds are memory-hungry) ---------------------------------
gate_cmds() {
  if [ -f "$WT/package.json" ]; then
    local run="${NODE_PM:-npm} run"
    has() { jq -e --arg s "$1" '.scripts[$s] // empty | select(test("no test specified") | not)' "$WT/package.json" >/dev/null 2>&1; }
    has build && echo "build $run build"   # first: frameworks generate types (Next's PageProps) that tsc needs
    for s in typecheck type-check check-types types tsc check; do has "$s" && echo "typecheck $run $s" && break; done
    has lint && echo "lint $run lint"
    for s in test:unit test; do has "$s" && echo "test $run $s" && break; done
  fi
  if [ -n "$PY_PM" ] && grep -q '\[tool\.poe\.tasks\]' "$WT/pyproject.toml"; then
    local poe="$PY_PM run poe"
    for s in typecheck mypy; do grep -qE "^$s[[:space:]]*=" "$WT/pyproject.toml" && echo "py-typecheck $poe $s" && break; done
    for s in lint test; do grep -qE "^$s[[:space:]]*=" "$WT/pyproject.toml" && echo "py-$s $poe $s"; done
  fi
}

GATES=""
if [ -z "$INSTALL_FAIL" ]; then
  lock "$SWEEP/locks/gates" 7200 || die PREPARE "gates lock held for 2h ($SWEEP/locks/gates): stale? remove it"
  trap 'rm -rf "$SWEEP/locks/gates"' EXIT
  while read -r name cmd; do
    [ -n "$name" ] || continue
    if (cd "$WT" && CI=1 NO_COLOR=1 FORCE_COLOR=0 cap "$GATE_TIMEOUT" sh -c "$cmd") 2>&1 \
      | perl -pe 's/\e\[[0-9;]*[A-Za-z]//g' > "$RUN/gates/$name.log"; then
      GATES="$GATES
- \`$cmd\`: PASS"
    else
      GATES="$GATES
- \`$cmd\`: FAIL (full log $RUN/gates/$name.log)
$(tail -20 "$RUN/gates/$name.log" | sed 's/^/  | /')"
    fi
  done <<< "$(gate_cmds)"
  rm -rf "$SWEEP/locks/gates"; trap - EXIT
fi

# --- rendered review context -----------------------------------------------------------------------
{
  (cd "$WT" && PR_HEAD_BRANCH="$HEAD" cap 300 "$SKILL_DIR/../pr-review/render.sh" "$N")
  echo
  echo "### Sweep environment"
  echo
  echo "Worktree (your cwd, detached at $SHA): $WT"
  echo "Your ports: app $PORT, API $API_PORT. Env files had :3000 and :5173 rewritten to :$PORT and :8000 to :$API_PORT,"
  echo "so start servers on these ports (e.g. \`--port $PORT\`, \`uvicorn ... --port $API_PORT\`), in the background. Other reviewers run"
  echo "concurrently on their own ports: never use the defaults. Kill your servers before you finish."
  if [ "$MIG" = "true" ]; then
    echo "Database: this PR's own Supabase stack (slot $SLOT), fresh from its migrations and seed. DB_URL=$DB_URL"
    echo "It is yours alone: write whatever rows a probe needs, and \`supabase db reset\` (from your cwd) rebuilds it from the migrations and seed when a probe leaves it dirty or you change a migration."
  elif [ -n "$DB_URL" ]; then
    echo "Database: the SHARED base Supabase stack (this PR changes no schema). DB_URL=$DB_URL"
    echo "Other reviewers use it concurrently. Wrap every probe that writes in BEGIN; ... ROLLBACK; and never create users or rows outside one."
  fi
  echo "Use \`psql \"\$DB_URL\"\` for SQL, never the Supabase MCP (it points at a remote project, not this branch)."
  echo "Write your full report to $RUN/review.md."
  echo
  [ -n "$STACK_NOTE" ] && echo "$STACK_NOTE" && echo
  echo "### Gates (already run on this head: quote these as CONFIRMED evidence, do not re-run them)"
  if [ -n "$INSTALL_FAIL" ]; then
    echo
    echo "\`$INSTALL_FAIL\` FAILED, so no gate ran:"
    tail -20 "$RUN/gates/install.log" | sed 's/^/  | /'
  elif [ -z "$GATES" ]; then
    echo
    echo "No typecheck/lint/test/build scripts detected."
  else
    echo "$GATES"
    echo
    echo "A FAIL may pre-date this PR: check the base before attributing it."
  fi
} > "$RUN/context.md" 2>&1

echo "$SHA" > "$RUN/prepare.ok"
STACK="base stack"; [ "$MIG" = "true" ] && STACK="own stack, slot $SLOT"
echo "PREPARE PASS #$N ($STACK, port $PORT, wt $WT)"
