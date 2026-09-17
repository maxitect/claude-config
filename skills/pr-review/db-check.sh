#!/usr/bin/env bash
# Deterministic database checks, run only when a Supabase project's migrations changed in this diff.
#
# Applies pending migrations locally, regenerates types/schema, and runs the lints — then reports
# only what came back bad. A clean run prints nothing but the reference docs.
#
# Usage: db-check.sh <changed-files-file>

set -uo pipefail

CHANGED="${1:-}"
[ -f "$CHANGED" ] || exit 0
grep -q 'supabase/migrations/' "$CHANGED" || exit 0

BUDGET=100          # seconds; the whole injection is killed at 120
SECONDS=0
left() { [ "$SECONDS" -lt "$BUDGET" ]; }
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_cap.sh"

echo "### Database (migrations changed in this diff)"
echo

# --- reference docs -------------------------------------------------------------------------------
SCHEMA_DOC="$(find docs -maxdepth 3 -iname 'schema.sql' 2>/dev/null | head -1)"
DB_DOC="$(find docs -maxdepth 3 -iname 'DATABASE.md' 2>/dev/null | head -1)"
if [ -n "$SCHEMA_DOC" ] || [ -n "$DB_DOC" ]; then
  echo "Read these for the schema as it stands — don't reconstruct it from the migration files:"
  [ -n "$SCHEMA_DOC" ] && echo "  $SCHEMA_DOC — full dumped schema"
  [ -n "$DB_DOC" ] && echo "  $DB_DOC — schema documentation"
  echo
fi

# --- is the local stack up? -----------------------------------------------------------------------
STATUS="$(cap 20 supabase status --output env)"
DB_URL="$(printf '%s\n' "$STATUS" | grep '^DB_URL=' | head -1 | sed 's/^DB_URL="\{0,1\}//; s/"\{0,1\}$//')"

if [ -z "$DB_URL" ]; then
  echo "Local Supabase stack is down, so migrations were not applied and no lint could run."
  echo "Every database finding in this review is UNVERIFIED unless you start it (\`supabase start\`) and probe."
  echo
  exit 0
fi

# --- apply pending migrations ---------------------------------------------------------------------
if left; then
  MIG="$(cap 60 supabase migration up)"
  if [ $? -ne 0 ] || printf '%s' "$MIG" | grep -qiE 'error|failed'; then
    echo "\`supabase migration up\` did not apply cleanly — this is the first thing to look at:"
    printf '%s\n' "$MIG" | tail -20 | sed 's/^/  | /'
    echo
    echo "Nothing below this line can be trusted until it applies."
    echo
    exit 0
  fi
fi

# --- regenerate types/schema: a dirty tree afterwards means the PR didn't ---------------------------
# tracked modifications only — untracked build output (node_modules, caches) is not evidence
dirty_tracked() { { git diff --name-only; git diff --cached --name-only; } 2>/dev/null | sort -u; }
DIRTY_BEFORE="$(dirty_tracked)"

GEN_CMD=""
if [ -f package.json ]; then
  for t in db:gen db:types gen:types types:gen; do
    grep -q "\"$t\"[[:space:]]*:" package.json && GEN_CMD="pnpm $t" && break
  done
  [ -n "$GEN_CMD" ] && [ ! -f pnpm-lock.yaml ] && GEN_CMD="npm run ${GEN_CMD#pnpm }"
elif [ -f pyproject.toml ] && grep -q '\[tool\.poe\.tasks\]' pyproject.toml; then
  for t in db-gen db_gen db:gen; do
    grep -q "^$t[[:space:]]*=" pyproject.toml && GEN_CMD="poetry run poe $t" && break
  done
fi

if [ -n "$GEN_CMD" ] && left; then
  GEN_OUT="$(cap 90 sh -c "$GEN_CMD")"
  GEN_RC=$?
  DIRTY_AFTER="$(dirty_tracked)"
  NEW_DIRTY="$(comm -13 <(printf '%s\n' "$DIRTY_BEFORE") <(printf '%s\n' "$DIRTY_AFTER"))"

  if [ "$GEN_RC" -ne 0 ]; then
    echo "\`$GEN_CMD\` failed:"
    printf '%s\n' "$GEN_OUT" | tail -15 | sed 's/^/  | /'
    echo
  elif [ -n "$NEW_DIRTY" ]; then
    echo "\`$GEN_CMD\` changed committed files, so the generated types/schema in this PR are stale —"
    echo "they don't match its own migrations. 🔴, with this as the evidence line:"
    printf '%s\n' "$NEW_DIRTY" | sed 's/^/  /'
    echo
    # leave the tree as the author had it; only revert what was clean before this script ran
    printf '%s\n' "$NEW_DIRTY" | while read -r f; do [ -n "$f" ] && git checkout -- "$f" 2>/dev/null; done
    echo "(Those tracked files were restored; anything the command left untracked was not touched.)"
    echo
  fi
fi

# --- lints: report only what comes back ------------------------------------------------------------
if left; then
  LINT="$(cap 45 supabase db lint --schema public --level warning)"
  if [ -n "$(printf '%s' "$LINT" | grep -viE '^\s*$|no schema errors found|Linting schema')" ]; then
    echo "plpgsql linter (local, post-migration):"
    printf '%s\n' "$LINT" | head -40 | sed 's/^/  | /'
    echo
  fi
fi

if left && command -v psql >/dev/null 2>&1; then
  SQL="
select 'RLS disabled: '||c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace
 where n.nspname='public' and c.relkind='r' and not c.relrowsecurity
union all
select 'RLS on but no policy (reads return zero rows): '||c.relname from pg_class c
 join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r'
 and c.relrowsecurity and not exists (select 1 from pg_policy p where p.polrelid=c.oid)
union all
select 'SECURITY DEFINER without pinned search_path: '||p.proname from pg_proc p
 join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prosecdef
 and (p.proconfig is null or not exists (select 1 from unnest(p.proconfig) cfg where cfg like 'search\_path=%'));"
  ROWS="$(cap 20 psql "$DB_URL" -At -c "$SQL")"
  if [ -n "$ROWS" ]; then
    echo "Schema state after applying this branch's migrations:"
    printf '%s\n' "$ROWS" | head -30 | sed 's/^/  | /'
    echo
    echo "These cover the whole public schema and the project may carry pre-existing ones — attribute a line to"
    echo "this PR only if it names an object the diff touches."
    echo
  fi
fi

exit 0
