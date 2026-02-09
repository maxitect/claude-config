#!/usr/bin/env zsh

# Read JSON input from stdin
file_path=$(grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')

# Only run typecheck for TypeScript files
if [[ -n "$file_path" && "$file_path" =~ \.(ts|tsx)$ ]]; then
  results=$(npx tsc --noEmit 2>&1)
fi

# Output to stderr and exit 2 for agent visibility
if [[ -n "$results" ]]; then
  echo "🔍 Typecheck results:" >&2
  echo "$results" >&2
  echo "" >&2
  exit 2
fi

exit 0
