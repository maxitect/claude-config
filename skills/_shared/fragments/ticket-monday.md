Tickets live in Monday, reached through the Monday MCP. The branch or PR carries the id.

**Find the ticket id**

Branch shape is `<commit-type>/<ticket-id>-<description>` — e.g. `fix/bozn-192-carousel-image-blink` → `bozn-192`.
A bare `feat/tozn-051` with no description is valid too. The prefix carries the type (e.g. `tozn-` feature,
`bozn-` bug) and is part of the id. Check the repo's own workflow doc for the exact prefixes.

PR titles and bodies also carry `Closes TOZN-<n>` — a second lookup path when the branch has no id.

```bash
git branch --show-current
gh pr view --json title,body 2>/dev/null
```

Neither carries an id → note the absence and work from the PR description.

**Read it** — search the full id (e.g. `tozn-332`), don't guess a board:

- `mcp__claude_ai_monday_com__search` — locate the item by id.
- `mcp__claude_ai_monday_com__get_board_items_page` / `..._get_board_info` — status, column values, acceptance criteria.
- `mcp__claude_ai_monday_com__get_updates` — the discussion thread, where criteria get clarified or dropped.
- `mcp__claude_ai_monday_com__read_docs` — when the description references a Monday doc.

**Google Docs fallback.** Sometimes the description is only a Google Docs link; that doc holds the real scope.

- `mcp__claude_ai_Google_Drive__search_files` (by doc title) or read directly by file id.
- `mcp__claude_ai_Google_Drive__read_file_content` — pull the body.

If the MCP can't be reached, say so in the review — an unread ticket is not a met acceptance criterion.
