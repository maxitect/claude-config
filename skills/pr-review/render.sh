#!/usr/bin/env bash
# Renders only the repo context relevant to this review, so unrelated stack and
# ticket-tracker guidance never enters the prompt.
#
# Usage: render.sh [any args] — recognised tokens are picked out, everything else ignored.
#   stack:  typescript|ts python|py pnpm npm yarn bun poetry|poe uv
#           supabase postgres|pg mongo|mongodb
#   ticket: monday github|gh|issues jira|atlassian linear none|noticket
# Each axis autodetects independently when no token for it was given.

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRAG="$DIR/fragments"
STACK=""
TICKET=""
TARGET=""
CHANGED_FILE="$(mktemp -t prreview)"
trap 'rm -f "$CHANGED_FILE"' EXIT

# gh can stall on a bad network or an auth prompt; a stalled injection kills the whole
# skill invocation, so every gh call is capped.
. "$DIR/_cap.sh"
gh_t() { cap 25 gh "$@" 2>/dev/null; }

# Extract a field from gh JSON: jq when present, else the ghjson.py fallback beside this script.
gh_jq() {
  if command -v jq >/dev/null 2>&1; then
    jq -r "$1" 2>/dev/null
  else
    python3 "$DIR/ghjson.py" "$1" 2>/dev/null
  fi
}

add_stack() {
  case " $STACK " in *" $1 "*) return 0 ;; esac
  [ -f "$FRAG/$1.md" ] && STACK="$STACK $1"
}
add_ticket() {
  [ -n "$TICKET" ] && return 0
  [ -f "$FRAG/$1.md" ] && TICKET="$1"
}

for raw in "$@"; do
  case "$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')" in
    ts|typescript|tsx)        add_stack lang-typescript ;;
    py|python)                add_stack lang-python ;;
    pnpm)                     add_stack pm-pnpm ;;
    npm)                      add_stack pm-npm ;;
    yarn)                     add_stack pm-yarn ;;
    bun)                      add_stack pm-bun ;;
    poetry|poe)               add_stack pm-poetry ;;
    uv)                       add_stack pm-uv ;;
    supabase)                 add_stack db-supabase ;;
    pg|postgres|postgresql)   add_stack db-postgres ;;
    mongo|mongodb)            add_stack db-mongo ;;
    monday)                   add_ticket ticket-monday ;;
    gh|github|issues)         add_ticket ticket-github ;;
    jira|atlassian)           add_ticket ticket-jira ;;
    linear)                   add_ticket ticket-linear ;;
    none|noticket|no-ticket)  TICKET="skip" ;;
    local)                    TARGET="local" ;;
    [0-9]*)                   case "$raw" in *[!0-9]*) ;; *) TARGET="$raw" ;; esac ;;
  esac
done

MANIFESTS="$(cat package.json pyproject.toml go.mod Cargo.toml requirements.txt 2>/dev/null)"
COMPOSE="$(cat docker-compose.yml docker-compose.yaml compose.yml compose.yaml 2>/dev/null)"
CONVENTIONS="$(find . -maxdepth 3 -name CLAUDE.md -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null | sort)"

if [ -z "$STACK" ]; then
  STACK_MODE="autodetected"
  [ -f pnpm-lock.yaml ]                            && add_stack pm-pnpm
  [ -f yarn.lock ]                                 && add_stack pm-yarn
  { [ -f bun.lockb ] || [ -f bun.lock ]; }         && add_stack pm-bun
  [ -f package-lock.json ]                         && add_stack pm-npm
  { [ -f tsconfig.json ] || [ -f package.json ]; } && add_stack lang-typescript

  if [ -f pyproject.toml ]; then
    add_stack lang-python
    grep -q '\[tool\.poetry' pyproject.toml && add_stack pm-poetry
    { [ -f uv.lock ] || grep -q '\[tool\.uv' pyproject.toml; } && add_stack pm-uv
  fi

  { [ -f supabase/config.toml ] || printf '%s' "$MANIFESTS" | grep -qi 'supabase'; } && add_stack db-supabase
  { printf '%s' "$MANIFESTS" | grep -qiE '"(pg|postgres|postgres\.js|drizzle-orm)"|prisma|psycopg|asyncpg|sqlalchemy|alembic' \
    || printf '%s' "$COMPOSE" | grep -qi 'postgres'; } && add_stack db-postgres
  { printf '%s' "$MANIFESTS" | grep -qiE 'mongoose|mongodb|pymongo|motor|beanie' \
    || printf '%s' "$COMPOSE" | grep -qi 'mongo'; } && add_stack db-mongo
else
  STACK_MODE="from arguments"
fi

if [ -z "$TICKET" ]; then
  TICKET_MODE="autodetected"
  DOCS="$(cat $CONVENTIONS 2>/dev/null
           cat README.md CONTRIBUTING.md 2>/dev/null
           cat docs/*.md 2>/dev/null
           ls .github/workflows .github 2>/dev/null)"
  if   printf '%s' "$DOCS" | grep -qiE 'monday\.com|monday (ticket|item|board|sync)|monday-'; then add_ticket ticket-monday
  elif printf '%s' "$DOCS" | grep -qiE 'atlassian\.net|jira'; then add_ticket ticket-jira
  elif printf '%s' "$DOCS" | grep -qiE 'linear\.app|linear (issue|ticket)'; then add_ticket ticket-linear
  elif git remote -v 2>/dev/null | grep -qi 'github\.com'; then add_ticket ticket-github
  fi
else
  TICKET_MODE="from arguments"
fi

echo "### Repo facts (detected)"
echo
if [ -n "$CONVENTIONS" ]; then
  echo "Convention files — read these before reviewing; they outrank anything in this skill:"
  printf '%s\n' "$CONVENTIONS" | sed 's/^/  /'
else
  echo "No CLAUDE.md found. Derive conventions from the surrounding code."
fi
echo

HITS="$(printf '%s' "$MANIFESTS" | grep -oiE '"(next|react|vue|svelte|@angular/core|express|fastify|hono|nestjs|@nestjs/core)"|(django|fastapi|flask|litestar|sqlalchemy|pydantic|celery)' | tr -d '"' | tr '[:upper:]' '[:lower:]' | sort -u | tr '\n' ' ')"
[ -n "$HITS" ] && echo "Framework/library signals: $HITS" && echo

TESTS="$(printf '%s' "$MANIFESTS" | grep -oiE 'vitest|jest|playwright|cypress|testing-library|pytest|unittest|nose2' | tr '[:upper:]' '[:lower:]' | sort -u | tr '\n' ' ')"
[ -n "$TESTS" ] && echo "Test tooling: $TESTS" && echo

HEAD_BRANCH="$(git branch --show-current 2>/dev/null)"
echo "Current branch: ${HEAD_BRANCH:-not a git repo}"
echo

if [ -f package.json ]; then
  echo "package.json scripts — use these exact names for probes, do not guess:"
  sed -n '/"scripts"[[:space:]]*:/,/^[[:space:]]*}/p' package.json | sed 's/^/  /'
  echo
fi

if [ -f pyproject.toml ] && grep -q '\[tool\.poe\.tasks\]' pyproject.toml; then
  echo "poe tasks — use these exact names for probes, do not guess:"
  sed -n '/\[tool\.poe\.tasks\]/,/^\[/p' pyproject.toml | grep -v '^\[tool\.poe' | sed 's/^/  /'
  echo
fi

if [ -f tsconfig.json ]; then
  STRICT="$(grep -oE '"(strict|strictNullChecks|noUncheckedIndexedAccess|noImplicitAny)"[[:space:]]*:[[:space:]]*(true|false)' tsconfig.json | tr '\n' ' ')"
  [ -n "$STRICT" ] && echo "tsconfig: $STRICT" && echo
fi

PR_FIELDS="number,title,url,state,isDraft,baseRefName,headRefName,labels,body,closingIssuesReferences"
PR_JSON=""
BASE_BRANCH=""

if [ "$TARGET" != "local" ] && command -v gh >/dev/null 2>&1; then
  PR_JSON="$(gh_t pr view $TARGET --json "$PR_FIELDS")"
fi

if [ -n "$PR_JSON" ]; then
  BASE_BRANCH="$(printf '%s' "$PR_JSON" | gh_jq '.baseRefName')"
  echo "### Pull request"
  echo
  echo "#$(printf '%s' "$PR_JSON" | gh_jq '.number') $(printf '%s' "$PR_JSON" | gh_jq '.title')"
  echo "$(printf '%s' "$PR_JSON" | gh_jq '.url')"
  echo "State: $(printf '%s' "$PR_JSON" | gh_jq '.state')$(printf '%s' "$PR_JSON" | gh_jq 'if .isDraft then " (draft)" else "" end')  ·  $(printf '%s' "$PR_JSON" | gh_jq '.headRefName') -> $(printf '%s' "$PR_JSON" | gh_jq '.baseRefName')"
  LABELS="$(printf '%s' "$PR_JSON" | gh_jq '[.labels[].name] | join(", ")')"
  [ -n "$LABELS" ] && echo "Labels: $LABELS"
  echo
  echo "Description (verbatim — this is the author's stated intent, do not re-fetch it):"
  echo
  printf '%s' "$PR_JSON" | gh_jq '.body' | sed 's/^/  | /' | head -200
  echo
  LINKED="$(printf '%s' "$PR_JSON" | gh_jq '.closingIssuesReferences[] | "#\(.number) \(.url)"' 2>/dev/null)"
  if [ -n "$LINKED" ]; then
    echo "Closing issue references (gh-parsed):"
    printf '%s\n' "$LINKED" | sed 's/^/  /'
    echo
  fi
  THREADS="$(gh_t pr view $TARGET --comments | head -120)"
  if [ -n "$THREADS" ]; then
    echo "Existing review comments (first 120 lines — reviewer concerns already raised):"
    printf '%s\n' "$THREADS" | sed 's/^/  | /'
    echo
  fi
elif [ "$TARGET" = "local" ]; then
  echo "### Branch-diff mode (requested)"
  echo
  echo "PR lookup skipped. There is no PR description and no review thread — intent comes from the ticket (§2)"
  echo "and the branch's commit messages. Label the report header branch-diff mode."
  echo
elif [ -n "$TARGET" ]; then
  echo "### PR #$TARGET did not resolve"
  echo
  echo "A specific PR was asked for and \`gh\` returned nothing: wrong number, wrong repo, or \`gh\` unavailable."
  echo "Stop and tell the user. Do not review the current branch instead — that is a different diff than the one"
  echo "they asked about."
  echo
  exit 0
else
  echo "### No PR for this branch — reviewing the branch diff instead"
  echo
  echo "No PR is open for \`$HEAD_BRANCH\` (or \`gh\` is unavailable). Continuing in branch-diff mode against the"
  echo "base below. There is no PR description and no review thread, so intent comes from the ticket (§2) and the"
  echo "branch's commit messages. Say so in the report header and in Issue Coverage — don't let it read as though"
  echo "a PR was reviewed."
  echo
fi

if [ -z "$BASE_BRANCH" ]; then
  BASE_BRANCH="$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')"
  [ -z "$BASE_BRANCH" ] && BASE_BRANCH="$(git branch -r 2>/dev/null | grep -oE 'origin/(main|master|develop)' | head -1 | sed 's@origin/@@')"
  if [ -z "$BASE_BRANCH" ]; then
    for b in main master develop; do
      git rev-parse --verify -q "refs/heads/$b" >/dev/null 2>&1 && BASE_BRANCH="$b" && break
    done
  fi
fi

# Prefer the remote-tracking ref; fall back to the local branch when there is no remote.
BASE_REF=""
if [ -n "$BASE_BRANCH" ]; then
  if git rev-parse --verify -q "refs/remotes/origin/$BASE_BRANCH" >/dev/null 2>&1; then
    BASE_REF="origin/$BASE_BRANCH"
  elif git rev-parse --verify -q "refs/heads/$BASE_BRANCH" >/dev/null 2>&1; then
    BASE_REF="$BASE_BRANCH"
  fi
fi

if [ -n "$BASE_REF" ] && [ -n "$HEAD_BRANCH" ]; then
  echo "### Diff scope"
  echo
  echo "Base: $BASE_REF  ·  Head: $HEAD_BRANCH"
  echo "Review only what this range contains: git diff $BASE_REF...HEAD"
  case "$BASE_REF" in
    origin/*) echo "(origin refs are not fetched by this renderer — if the list below looks stale, git fetch origin $BASE_BRANCH first)" ;;
    *)        echo "(no remote-tracking ref for $BASE_BRANCH — this compares against the local branch, which may lag the remote)" ;;
  esac
  echo
  STAT="$(git diff --shortstat "$BASE_REF...HEAD" 2>/dev/null)"
  [ -n "$STAT" ] && echo "$STAT" && echo
  if [ -z "$PR_JSON" ]; then
    LOG="$(git log --oneline "$BASE_REF..HEAD" 2>/dev/null | head -30)"
    if [ -n "$LOG" ]; then
      echo "Commits on this branch (no PR description to read — this is the stated intent):"
      printf '%s\n' "$LOG" | sed 's/^/  /'
      echo
    fi
  fi

  FILES="$(git diff --name-status "$BASE_REF...HEAD" 2>/dev/null)"
  printf '%s\n' "$FILES" > "$CHANGED_FILE"
  COUNT="$(printf '%s\n' "$FILES" | grep -c . )"
  if [ -n "$FILES" ]; then
    echo "Changed files ($COUNT):"
    printf '%s\n' "$FILES" | head -150 | sed 's/^/  /'
    [ "$COUNT" -gt 150 ] && echo "  ... $((COUNT - 150)) more"
    echo
  fi
fi

if [ "$TICKET" = "skip" ]; then
  echo "### Ticket source: none requested"
  echo
  echo "No tracker lookup. Take intent and acceptance criteria from the PR description alone, and say so in §2."
  echo
elif [ "$TICKET" = "ticket-github" ]; then
  ISSUE_NUMS=""
  [ -n "$PR_JSON" ] && ISSUE_NUMS="$(printf '%s' "$PR_JSON" | gh_jq '.closingIssuesReferences[] | "\(.repository.owner.login)/\(.repository.name)#\(.number)"')"
  if [ -z "$ISSUE_NUMS" ] && [ -n "$HEAD_BRANCH" ]; then
    ISSUE_NUMS="$(printf '%s' "$HEAD_BRANCH" | grep -oE '(^|/)[0-9]+(-|$)' | grep -oE '[0-9]+' | head -1)"
  fi

  if [ -n "$ISSUE_NUMS" ]; then
    echo "### Ticket: GitHub issue(s)"
    echo
    echo "Fetched below — the acceptance criteria are here, don't re-fetch them."
    echo
    for ref in $(printf '%s\n' "$ISSUE_NUMS" | head -3); do
      n="${ref##*#}"
      REPO="${ref%#*}"
      if [ "$REPO" = "$ref" ] || [ -z "$REPO" ]; then
        set -- "$n"
      else
        set -- "$n" -R "$REPO"
      fi
      ISSUE="$(gh_t issue view "$@" --json number,title,state,labels,body,comments --jq '
        "#\(.number) \(.title)  ·  \(.state)",
        (if (.labels|length) > 0 then "labels: " + ([.labels[].name] | join(", ")) else empty end),
        "",
        .body,
        (if (.comments|length) > 0 then "", "--- comments (\(.comments|length)) ---" else empty end),
        (.comments[-5:][] | "[\(.author.login)] \(.body)")
      ')"
      if [ -n "$ISSUE" ]; then
        printf '%s\n' "$ISSUE" | head -200 | sed 's/^/  | /'
      else
        echo "  | $ref — could not be read (no access, or the issue was deleted)."
      fi
      echo
    done
  else
    echo "### Ticket source ($TICKET_MODE): github"
    echo
    cat "$FRAG/ticket-github.md"
    echo
  fi
elif [ -n "$TICKET" ]; then
  echo "### Ticket source ($TICKET_MODE): ${TICKET#ticket-}"
  echo
  cat "$FRAG/$TICKET.md"
  echo
else
  echo "### Ticket source: unknown"
  echo
  echo "No tracker detected. Ask which one the team uses (monday / github / jira / linear), or re-run with that"
  echo "token. Until then take intent and acceptance criteria from the PR description or branch commits alone,"
  echo "and label §2 as such."
  echo
fi

ORDER="lang-typescript lang-python pm-pnpm pm-npm pm-yarn pm-bun pm-poetry pm-uv db-supabase db-postgres db-mongo"
PICKED=""
for f in $ORDER; do
  case " $STACK " in *" $f "*) PICKED="$PICKED $f" ;; esac
done

if [ -z "$PICKED" ]; then
  echo "### Stack fragments: none matched ($STACK_MODE)"
  echo
  echo "Review with the universal checklist only, and derive stack conventions from the files above."
  exit 0
fi

echo "### Stack fragments ($STACK_MODE):$PICKED"
echo
for f in $PICKED; do
  cat "$FRAG/$f.md"
  echo
done

case " $STACK " in
  *" db-supabase "*) "$DIR/db-check.sh" "$CHANGED_FILE" ;;
esac

exit 0
