#!/usr/bin/env zsh
set -euo pipefail

# Read JSON input from stdin
input=$(cat)
file_path=$(echo "$input" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null)

# Only run typecheck for TypeScript files
if [[ "$file_path" =~ \.(ts|tsx)$ ]]; then
  if [[ -f package.json ]]; then
    if command -v pnpm &> /dev/null; then
      if grep -q '"typecheck"' package.json; then
        pnpm typecheck 2>&1 | head -20
      elif command -v tsc &> /dev/null; then
        npx tsc --noEmit 2>&1 | head -20
      fi
    fi
  fi
fi

echo '{"continue": true}'
exit 0
