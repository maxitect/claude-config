#!/usr/bin/env bash
# Stop hook for ticket-implementer: blocks finishing until the report is written, the gates passed on the
# current code, and the PR is open against its base (a draft in team mode), pushed and free of AI attribution. A BLOCKED
# report, a second stop, or a branch that is not a ticket branch passes straight through.

INPUT="$(cat)"
CWD="$(jq -r '.cwd // empty' <<< "$INPUT")"
[ -n "$CWD" ] && cd "$CWD" 2>/dev/null
[ "$(jq -r '.stop_hook_active // false' <<< "$INPUT")" = "true" ] && exit 0
# As SubagentStop, cwd is the parent session's (the main checkout); the agent's own worktree is named after it.
AGENT="$(jq -r '.agent_id // empty' <<< "$INPUT")"
if [ -n "$AGENT" ]; then
  MAIN="$(dirname "$(cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd)")"
  [ -d "$MAIN/.claude/worktrees/agent-$AGENT" ] && cd "$MAIN/.claude/worktrees/agent-$AGENT"
fi

. "$(dirname "$0")/lib.sh"
ID="$(id_from_branch "$(git branch --show-current 2>/dev/null)")"
[ -n "$ID" ] && [ -n "$ORCH_TICKETS" ] || exit 0
load_config

block() { echo "Not finished: $1" >&2; exit 2; }

REPORT="$(report_path "$ID")"
[ -f "$REPORT" ] || block "write $REPORT (protocol §4). It lives outside the repo; never commit it."
grep -qE '^Status:[[:space:]]*BLOCKED' "$REPORT" && exit 0
[ -z "$(git status --porcelain --untracked-files=no)" ] || block "commit your changes."

RECORDED="$(cat "$STATE/$ID/gates.ok" 2>/dev/null)"
{ [ -n "$RECORDED" ] && code_unchanged_since "$RECORDED" "$TOP"; } \
  || block "code changed since the last green gates run. Run ~/.claude/skills/orchestrate/scripts/gates.sh again."

BRANCH="$(git branch --show-current)"
PR_BASE="$(env_get "$ID" PR_BASE)"; PR_BASE="${PR_BASE:-$ORCH_BASE}"
DRAFT=""; [ "$ORCH_MODE" = team ] && DRAFT=" draft"
PR="$(gh pr list --head "$BRANCH" --state open --json number,baseRefName,isDraft,body -q '.[0]')"
[ -n "$PR" ] || block "open the PR with /pr-prep $PR_BASE$DRAFT."
[ "$(jq -r .baseRefName <<< "$PR")" = "$PR_BASE" ] || block "the PR targets $(jq -r .baseRefName <<< "$PR"), not $PR_BASE: gh pr edit --base $PR_BASE."
[ "$ORCH_MODE" = team ] && [ "$(jq -r .isDraft <<< "$PR")" != true ] && block "team mode opens draft PRs: gh pr ready --undo."
attribution_in "$(jq -r .body <<< "$PR")" && block "remove the AI attribution from the PR description (gh pr edit --body-file)."
[ -z "$(git log '@{u}..HEAD' --oneline -- . ':(exclude)docs' ':(exclude)*.md' 2>/dev/null)" ] || block "code commits are not pushed."
exit 0
