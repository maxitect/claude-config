#!/usr/bin/env bash
# Verifies the machine can run a sweep and that the repo's base local stack is up (starting it if
# not). Prints PREFLIGHT PASS plus notes, or PREFLIGHT FAIL: <step>.
#
# Usage: preflight.sh

. "$(dirname "$0")/lib.sh"

[ -n "$ROOT" ] && [ -d "$ROOT" ] || die PREFLIGHT "not inside a git repository"
[ -n "$SLUG" ] || die PREFLIGHT "gh cannot resolve a GitHub repo here (gh auth status, or no github remote)"
for bin in gh git jq python3 perl claude docker; do
  command -v "$bin" >/dev/null || die PREFLIGHT "$bin not on PATH"
done

mkdir -p "$SWEEP/slots" "$SWEEP/locks"
LOG="$SWEEP/preflight.log"; : > "$LOG"
cd "$ROOT" || exit 1
NOTES=()

step PREFLIGHT "gh auth" gh auth status
step PREFLIGHT "docker running" docker info
step PREFLIGHT "git fetch" git fetch origin --prune --quiet

MEM_GB=$(( $(docker info --format '{{.MemTotal}}' 2>/dev/null || echo 0) / 1073741824 ))
[ "$MEM_GB" -lt 10 ] && NOTES+=("docker memory ${MEM_GB}GB: keep PR_SWEEP_SLOTS at ${MAX_SLOTS} or lower")

if is_supabase "$ROOT"; then
  command -v supabase >/dev/null || die PREFLIGHT "supabase CLI not on PATH (repo has supabase/config.toml)"
  command -v psql >/dev/null || die PREFLIGHT "psql not on PATH (needed for database probes)"
  DB_URL="$(supabase_db_url "$ROOT")"
  if [ -z "$DB_URL" ]; then
    step PREFLIGHT "supabase start (base stack)" cap 600 supabase start -x "$SUPABASE_EXCLUDE"
    DB_URL="$(supabase_db_url "$ROOT")"
    [ -n "$DB_URL" ] || die PREFLIGHT "base supabase stack did not come up"
    NOTES+=("started the base supabase stack")
  fi

  DEFAULT="$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)"
  APPLIED="$(cap 20 psql "$DB_URL" -At -c 'select version from supabase_migrations.schema_migrations' 2>/dev/null | sort)"
  ON_BASE="$(git ls-tree --name-only "origin/$DEFAULT" supabase/migrations/ 2>/dev/null | sed -n 's@.*/\([0-9]\{1,\}\)_.*@\1@p' | sort)"
  MISSING="$(comm -13 <(printf '%s\n' "$APPLIED") <(printf '%s\n' "$ON_BASE") | grep -c .)"
  [ "$MISSING" -gt 0 ] && NOTES+=("base stack lacks $MISSING migration(s) from origin/$DEFAULT: non-migration PRs are probed against an older schema (supabase migration up in $ROOT to fix)")
elif ls "$ROOT"/{docker-compose,compose}.y*ml >/dev/null 2>&1; then
  step PREFLIGHT "docker compose up" cap 300 docker compose up -d --wait
fi

SWEPT="$("$SCRIPTS/sweep.sh" 2>&1)"
[ -n "$SWEPT" ] && NOTES+=("$SWEPT")

for n in "${NOTES[@]+"${NOTES[@]}"}"; do echo "note: $n"; done
echo "PREFLIGHT PASS ($SLUG, state in $SWEEP)"
