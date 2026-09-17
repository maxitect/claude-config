Tickets live in Jira, reached through the Atlassian MCP.

**Find the issue key**

Keys are `<PROJECT>-<number>` (`PLAT-1423`). Branches usually embed one — `feature/PLAT-1423-retry-webhooks` —
and PR titles or bodies carry it in the subject or a `PLAT-1423` reference.

```bash
git branch --show-current
gh pr view --json title,body 2>/dev/null
```

No key in either → note the absence and work from the PR description.

**Read it**

- `mcp__claude_ai_Atlassian_Rovo__*` — search for the key, then fetch the issue: summary, description, status,
  issue type, fix version, and the acceptance-criteria field (teams often use a custom field or a checklist in
  the description rather than a standard one).
- Read the comment thread; scope changes land there more often than in the description.
- Follow linked issues (`blocks`, `relates to`) and any Confluence page the description points at — that page is
  frequently where the real spec lives.

If the MCP isn't connected, say so in the review rather than reviewing against a guessed scope.
