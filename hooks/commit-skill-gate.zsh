#!/usr/bin/env zsh

# PreToolUse gate: block bare `git commit` so commits go through the /commit skill.
# Escape hatch while executing that skill: prefix with COMMIT_VIA_SKILL=1.
cmd=$(jq -r '.tool_input.command // empty')

[[ -z "$cmd" ]] && exit 0
[[ "$cmd" == *"COMMIT_VIA_SKILL=1"* ]] && exit 0

if [[ "$cmd" =~ '(^|[;&|[:space:]])git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+commit([[:space:]]|$)' ]]; then
  echo "⛔ git commit blocked: use the /commit skill for all commits (granular conventional commits)." >&2
  echo "If you are already executing /commit, re-run with the skill prefix: COMMIT_VIA_SKILL=1 git commit ..." >&2
  exit 2
fi

exit 0
