#!/usr/bin/env zsh

# Read JSON input from stdin
file_path=$(grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')

# Only run linter for TypeScript/JavaScript files
if [[ -n "$file_path" && "$file_path" =~ \.(ts|tsx|js|jsx)$ ]]; then
  if [[ -f package.json ]]; then
    if command -v pnpm &> /dev/null; then
      if grep -q '"lint"' package.json; then
        results=$(pnpm lint 2>&1 | head -20) || true
      elif command -v eslint &> /dev/null; then
        results=$(npx eslint "$file_path" 2>&1 | head -20) || true
      fi
    fi
  fi
fi

# Output to stderr and exit 2 for agent visibility
if [[ -n "$results" ]]; then
  echo "🔍 Lint results:" >&2
  echo "$results" >&2
  echo "" >&2
  exit 2  # Exit 2 + stderr = agent sees this
fi

# Exit 0 for success (no errors to show)
exit 0
