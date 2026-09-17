Tickets live in Linear.

**Find the issue id**

Ids are `<TEAM>-<number>` (`ENG-812`). Linear's own branch names embed them —
`username/eng-812-retry-webhooks` — and the PR body usually carries the magic word link.

```bash
git branch --show-current
gh pr view --json title,body 2>/dev/null
```

No id in either → note the absence and work from the PR description.

**Read it**

- Linear MCP if connected: fetch the issue by id — title, description, state, estimate, labels, sub-issues.
- Otherwise `linear` CLI or the GraphQL API with `LINEAR_API_KEY`:

  ```bash
  curl -s -X POST https://api.linear.app/graphql \
    -H "Authorization: $LINEAR_API_KEY" -H 'Content-Type: application/json' \
    -d '{"query":"{ issue(id:\"ENG-812\"){ title description state{name} comments{nodes{body}} } }"}'
  ```

- Read comments and sub-issues; a parent issue's criteria are often split across its children.

No access → say so rather than reviewing against a guessed scope.
