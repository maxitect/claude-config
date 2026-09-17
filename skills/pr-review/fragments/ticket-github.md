Tickets are GitHub issues linked from the PR body.

**Find the ticket**

```bash
gh pr view $PR_NUMBER --json body --jq '.body'
```

Scan the body for closing keywords — `closes`, `fixes`, `resolves` (case-insensitive) — followed by `#N` or a
full issue URL. `gh` also parses them for you:

```bash
gh pr view $PR_NUMBER --json closingIssuesReferences --jq '.closingIssuesReferences[]'
```

A branch named `<type>/<number>-<description>` (`fix/482-carousel-blink`) is a second lookup path when the body
has no closing keyword.

**Read it**

```bash
gh issue view $ISSUE_NUMBER --json title,body,labels,milestone,comments
```

Read the comments too — acceptance criteria get amended there more often than in the body.

If the PR links no issue and the branch carries no number, note the absence and work from the PR description.
