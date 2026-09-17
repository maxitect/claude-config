Tickets are GitHub issues, and none was fetched: the PR closes no issue and the branch carries no issue number.

Before falling back, check whether the link is there but unparsed — `gh` only parses closing keywords
(`closes`, `fixes`, `resolves`) followed by `#N` or a full issue URL. A bare `#N` or a "see issue 412" in the
body is a link a human would follow:

```bash
gh pr view --json body --jq '.body' | grep -oE '#[0-9]+|issues/[0-9]+'
gh issue view <number> --json title,body,labels,state,comments
```

Still nothing → work from the PR description, and say plainly in the report that no linked issue defined the
acceptance criteria. Don't reverse-engineer criteria from the diff; that grades the code against itself.
