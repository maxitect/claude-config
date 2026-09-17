# pr-review — maintenance notes

Not loaded into the review context; this is for you, not the agent.

## Usage

```
/pr-review                # PR for the current branch, or the branch diff if none is open
/pr-review monday         # same, forcing the ticket tracker
/pr-review 178            # a specific PR
/pr-review local          # branch diff, ignoring the PR
```

## Files

| File        | Role                                                                                   |
| ----------- | ---------------------------------------------------------------------------------------- |
| `SKILL.md`  | The review itself: checklist, verification discipline, output format. All instruction.   |
| `render.sh` | Gathers everything before the prompt reaches the agent (§1 of SKILL.md).                 |

Detection, fragments, the gh helpers and the database checks are shared with `address-pr-comments` — see
`../_shared/README.md` for the `stack.sh` API, the argument tokens, autodetection, and how to add a stack.

## What render.sh feeds the agent

- **Repo facts, diff scope, ticket, stack fragments, database block** — the shared blocks (`../_shared/stack.sh`).
- **The PR** — resolved from the current branch, or a number passed in. Header, description verbatim, closing
  issue references, existing review comments. No PR → branch-diff mode, with the branch's commits standing in
  for the description.

## Known gaps

- Existing review comments come from `gh pr view --comments`, capped at 120 lines and with no resolved/unresolved
  distinction — a reviewer's settled thread reads like a live one. `address-pr-comments` uses GraphQL for this;
  this skill only needs the gist.
