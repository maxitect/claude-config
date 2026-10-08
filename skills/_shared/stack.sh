# Repo, stack and ticket detection shared by the PR skills. Source it, then call the
# pieces the skill needs — each prints one section of the injected context.
#
# Recognised argument tokens (each axis autodetects independently when none is given):
#   stack:  typescript|ts python|py pnpm npm yarn bun poetry|poe uv
#           supabase postgres|pg mongo|mongodb
#   ticket: monday github|gh|issues jira|atlassian linear none|noticket
#   target: local | <pr number>

SHARED_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRAG="$SHARED_DIR/fragments"
STACK=""
TICKET=""
TARGET=""
STACK_MODE=""
TICKET_MODE=""
BASE_BRANCH=""
BASE_REF=""
HEAD_BRANCH="${PR_HEAD_BRANCH:-$(git branch --show-current 2>/dev/null)}"
HEAD_REF="${PR_HEAD_BRANCH:+HEAD}"   # what the diff is taken against; a caller targeting another PR overrides it
HEAD_REF="${HEAD_REF:-$HEAD_BRANCH}"  # PR_HEAD_BRANCH: a detached checkout of that PR's head (pr-sweep worktrees)
CHANGED_FILE="$(mktemp -t prskill)"
trap 'rm -f "$CHANGED_FILE"' EXIT

MANIFESTS="$(cat package.json pyproject.toml go.mod Cargo.toml requirements.txt 2>/dev/null)"
COMPOSE="$(cat docker-compose.yml docker-compose.yaml compose.yml compose.yaml 2>/dev/null)"
REPO_NAME="$(git remote get-url origin 2>/dev/null | sed -E 's#.*/##; s#\.git$##' | tr '[:upper:]' '[:lower:]')"
CONVENTIONS="$(find . -maxdepth 3 -name CLAUDE.md -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null | sort)"

add_stack() {
  case " $STACK " in *" $1 "*) return 0 ;; esac
  [ -f "$FRAG/$1.md" ] && STACK="$STACK $1"
}

add_ticket() {
  [ -n "$TICKET" ] && return 0
  [ -f "$FRAG/$1.md" ] && TICKET="$1"
}

parse_args() {
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
}

detect_stack() {
  if [ -n "$STACK" ]; then STACK_MODE="from arguments"; return 0; fi
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
  return 0
}

detect_ticket() {
  if [ -n "$TICKET" ]; then TICKET_MODE="from arguments"; return 0; fi
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
  return 0
}

print_repo_facts() {
  echo "### Repo facts (detected)"
  echo
  if [ -n "$CONVENTIONS" ]; then
    echo "Convention files — read these first; they outrank anything in this skill:"
    printf '%s\n' "$CONVENTIONS" | sed 's/^/  /'
  else
    echo "No CLAUDE.md found. Derive conventions from the surrounding code."
  fi
  echo

  HITS="$(printf '%s' "$MANIFESTS" | grep -oiE '"(next|react|vue|svelte|@angular/core|express|fastify|hono|nestjs|@nestjs/core)"|(django|fastapi|flask|litestar|sqlalchemy|pydantic|celery)' | tr -d '"' | tr '[:upper:]' '[:lower:]' | sort -u | tr '\n' ' ')"
  [ -n "$HITS" ] && echo "Framework/library signals: $HITS" && echo

  TESTS="$(printf '%s' "$MANIFESTS" | grep -oiE 'vitest|jest|playwright|cypress|testing-library|pytest|unittest|nose2' | tr '[:upper:]' '[:lower:]' | sort -u | tr '\n' ' ')"
  [ -n "$TESTS" ] && echo "Test tooling: $TESTS" && echo

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
  return 0
}

# resolve_base_ref [preferred-base-branch] — sets BASE_BRANCH and BASE_REF.
resolve_base_ref() {
  BASE_BRANCH="${1:-}"
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
  return 0
}

# align_head_ref <pr-head-branch> — points the diff at the PR's head when it isn't the checked-out
# branch, and says so, because every file read afterwards is of the working tree, not of the PR.
align_head_ref() {
  local pr_head="${1:-}"
  [ -n "$pr_head" ] && [ "$pr_head" != "$HEAD_BRANCH" ] || return 0

  echo "### You are not on this PR's branch"
  echo
  echo "PR head: \`$pr_head\`  ·  checked out: \`${HEAD_BRANCH:-unknown}\`"
  if git rev-parse --verify -q "refs/remotes/origin/$pr_head" >/dev/null 2>&1; then
    HEAD_REF="origin/$pr_head"
    echo "The diff below is taken against \`origin/$pr_head\`, so it is the PR's. Every file you read or edit"
    echo "is still the working tree's — a different branch. Check the PR branch out before changing anything:"
  else
    echo "\`origin/$pr_head\` is not fetched, so the diff below is the checked-out branch's, not the PR's."
    echo "Fetch and check the PR branch out before trusting any of it:"
  fi
  echo
  echo "  gh pr checkout $pr_head"
  echo
  return 0
}

# print_diff_scope [with-commits] — needs resolve_base_ref first. Writes the changed-file
# list to $CHANGED_FILE for maybe_db_check.
print_diff_scope() {
  local with_commits="${1:-}"
  [ -n "$BASE_REF" ] && [ -n "$HEAD_REF" ] || return 0

  echo "### Diff scope"
  echo
  echo "Base: $BASE_REF  ·  Head: $HEAD_REF"
  echo "This is the branch under discussion: git diff $BASE_REF...$HEAD_REF"
  case "$BASE_REF" in
    origin/*) echo "(origin refs are not fetched by this renderer — if the list below looks stale, git fetch origin $BASE_BRANCH first)" ;;
    *)        echo "(no remote-tracking ref for $BASE_BRANCH — this compares against the local branch, which may lag the remote)" ;;
  esac
  echo
  STAT="$(git diff --shortstat "$BASE_REF...$HEAD_REF" 2>/dev/null)"
  [ -n "$STAT" ] && echo "$STAT" && echo

  if [ "$with_commits" = "with-commits" ]; then
    LOG="$(git log --oneline "$BASE_REF..$HEAD_REF" 2>/dev/null | head -30)"
    if [ -n "$LOG" ]; then
      echo "Commits on this branch (no PR description to read — this is the stated intent):"
      printf '%s\n' "$LOG" | sed 's/^/  /'
      echo
    fi
  fi

  FILES="$(git diff --name-status "$BASE_REF...$HEAD_REF" 2>/dev/null)"
  printf '%s\n' "$FILES" > "$CHANGED_FILE"
  COUNT="$(printf '%s\n' "$FILES" | grep -c . )"
  if [ -n "$FILES" ]; then
    echo "Changed files ($COUNT):"
    printf '%s\n' "$FILES" | head -150 | sed 's/^/  /'
    [ "$COUNT" -gt 150 ] && echo "  ... $((COUNT - 150)) more"
    echo
  fi
  return 0
}

# print_ticket_block [pr-json] — GitHub issues are fetched and injected; the other trackers
# live behind MCPs bash can't call, so their fragment renders the lookup path instead.
print_ticket_block() {
  local pr_json="${1:-}"
  if [ "$TICKET" = "skip" ]; then
    echo "### Ticket source: none requested"
    echo
    echo "No tracker lookup. Take intent and acceptance criteria from the PR description alone."
    echo
    return 0
  fi

  if [ "$TICKET" = "ticket-github" ]; then
    ISSUE_NUMS=""
    [ -n "$pr_json" ] && ISSUE_NUMS="$(printf '%s' "$pr_json" | gh_jq '.closingIssuesReferences[] | "\(.repository.owner.login)/\(.repository.name)#\(.number)"')"
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
      return 0
    fi

    echo "### Ticket source ($TICKET_MODE): github"
    echo
    cat "$FRAG/ticket-github.md"
    echo
    return 0
  fi

  if [ -n "$TICKET" ]; then
    echo "### Ticket source ($TICKET_MODE): ${TICKET#ticket-}"
    echo
    cat "$FRAG/$TICKET.md"
    echo
    return 0
  fi

  echo "### Ticket source: unknown"
  echo
  echo "No tracker detected. Ask which one the team uses (monday / github / jira / linear), or re-run with that"
  echo "token. Until then take intent and acceptance criteria from the PR description or branch commits alone."
  echo
  return 0
}

print_stack_fragments() {
  ORDER="lang-typescript lang-python pm-pnpm pm-npm pm-yarn pm-bun pm-poetry pm-uv db-supabase db-postgres db-mongo"
  PICKED=""
  for f in $ORDER; do
    case " $STACK " in *" $f "*) PICKED="$PICKED $f" ;; esac
  done

  if [ -z "$PICKED" ]; then
    echo "### Stack fragments: none matched ($STACK_MODE)"
    echo
    echo "Work with the universal checklist only, and derive stack conventions from the files above."
    print_repo_fragment
    return 1
  fi

  echo "### Stack fragments ($STACK_MODE):$PICKED"
  echo
  for f in $PICKED; do
    cat "$FRAG/$f.md"
    echo
  done
  print_repo_fragment
  return 0
}

# fragments/repo-<origin repo name>.md: rules for one repo, rendered after the stack fragments.
print_repo_fragment() {
  [ -n "$REPO_NAME" ] && [ -f "$FRAG/repo-$REPO_NAME.md" ] || return 0
  cat "$FRAG/repo-$REPO_NAME.md"
  echo
}

maybe_db_check() {
  case " $STACK " in
    *" db-supabase "*) "$SHARED_DIR/db-check.sh" "$CHANGED_FILE" ;;
  esac
  return 0
}
