#!/usr/bin/env zsh
set -euo pipefail

echo "📋 Auto-Generated Context"
echo "=========================="

# Package manager detection
if [[ -f package.json ]]; then
  pkg_manager="unknown"

  # Check packageManager field first
  if command -v jq &> /dev/null; then
    pkg_from_json=$(jq -r '.packageManager // empty' package.json 2>/dev/null)
    if [[ -n "$pkg_from_json" ]]; then
      pkg_manager=$(echo "$pkg_from_json" | cut -d@ -f1)
    fi
  fi

  # Fallback to lock files if not found in package.json
  if [[ "$pkg_manager" == "unknown" ]]; then
    [[ -f pnpm-lock.yaml ]] && pkg_manager="pnpm"
    [[ -f package-lock.json ]] && pkg_manager="npm"
    [[ -f yarn.lock ]] && pkg_manager="yarn"
    [[ -f bun.lockb ]] && pkg_manager="bun"
  fi

  echo "Package manager: $pkg_manager"
fi

# Git context
if git rev-parse --git-dir > /dev/null 2>&1; then
  echo ""
  echo "📍 Git Status"
  current_branch=$(git branch --show-current)
  echo "Current branch: $current_branch"

  # Check ahead/behind remote
  if git rev-parse --abbrev-ref --symbolic-full-name @{u} > /dev/null 2>&1; then
    ahead=$(git rev-list --count @{u}..HEAD)
    behind=$(git rev-list --count HEAD..@{u})
    [[ $ahead -gt 0 ]] && echo "  ↑ Ahead of remote: $ahead commits"
    [[ $behind -gt 0 ]] && echo "  ↓ Behind remote: $behind commits"
  fi

  # Uncommitted changes
  if ! git diff-index --quiet HEAD -- 2>/dev/null; then
    echo "  ⚠️  Uncommitted changes present"
  fi

  # Recent commits
  echo ""
  echo "Recent commits:"
  git log --oneline --decorate -5

  # Diff summary vs main
  main_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "main")
  if git rev-parse "$main_branch" > /dev/null 2>&1 && [[ "$current_branch" != "$main_branch" ]]; then
    echo ""
    echo "Changes vs $main_branch:"
    git diff --stat "$main_branch"...HEAD | tail -1
  fi

  # Open PRs (requires gh CLI)
  if command -v gh &> /dev/null; then
    pr_count=$(gh pr list --json number --jq length 2>/dev/null || echo "0")
    if [[ $pr_count -gt 0 ]]; then
      echo ""
      echo "🔀 Open PRs: $pr_count"
      gh pr list --limit 3 --json number,title,headRefName --template '{{range .}}  #{{.number}}: {{.title}} ({{.headRefName}}){{"\n"}}{{end}}'
    fi
  fi
fi

# Load manual project context
if [[ -f .claude/project-context.md ]]; then
  echo ""
  echo "================================"
  cat .claude/project-context.md
fi

exit 0
