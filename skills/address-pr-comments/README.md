# address-pr-comments — maintenance notes

Not loaded into the skill context; this is for you, not the agent.

## Usage

```
/address-pr-comments            # unresolved threads on the current branch's PR
/address-pr-comments 178        # a specific PR
/address-pr-comments monday     # force the ticket tracker
```

## Files

| File        | Role                                                                              |
| ----------- | --------------------------------------------------------------------------------- |
| `SKILL.md`  | The loop: verify claim, fix, verify fix, present, wait, commit, next. Instruction. |
| `render.sh` | Gathers the context before the prompt reaches the agent (§1 of SKILL.md).         |

Detection, fragments and the gh helpers are shared with `pr-review` — see `../_shared/README.md`.
The per-thread commit hands off to the `commit` skill, which owns message format and granularity.

## Where the approval gate sits

There is exactly one, and it is **after** the fix is green (§3F), not before it is written. The trade is
deliberate: §3C must reproduce the reviewer's claim before anything is edited, so the only changes that go in
unasked are ones a command already confirmed. A claim that is refuted, unverifiable, debatable, or outside the
ticket's acceptance criteria never reaches the fix step at all — it stops at §3D with the evidence and a draft
reply, and waits.

Then the commit, one per thread, on the user's go-ahead, before the next thread is presented. The point is a
branch the reviewer can re-review thread by thread instead of one lump labelled "address review comments".

## What render.sh feeds the agent

- **Repo facts, diff scope, ticket, stack fragments** — the shared blocks (`../_shared/stack.sh`), identical to
  what `pr-review` renders. The fragments' probe tables are what §3C and §3E of SKILL.md actually run.
- **The PR** — header and description. No PR → the renderer prints a stop block and exits: this skill has no
  work without reviewer comments, and the agent is told not to substitute a self-review.
- **Unresolved review threads** — via GraphQL, numbered, each with its path, line, thread id, the diff hunk the
  comment was left on (last 14 lines) and every comment in the thread including replies.
- **Review-level comments** — review bodies not attached to a line, which is where the headline concern usually
  lives.
- **Database block** — when the stack is Supabase and migrations changed, same as `pr-review`.

## Why GraphQL for the threads

`repos/{owner}/{repo}/pulls/{n}/comments` (REST) has no `isResolved` and no `isOutdated`. Without those, a
resolved thread — work already done, often by an earlier run of this skill — reads exactly like a live one, and
the agent re-litigates it. GraphQL's `reviewThreads` carries both, plus the thread id the reply and resolve
mutations need.

Filtering goes through `gh api --jq`, which is gh's own built-in jq, so the thread rendering works on machines
with no system jq — unlike the `ghjson.py` fallback, which only covers the handful of simple filters
`../_shared/stack.sh` uses.

The two GraphQL calls (counts + review bodies, then the threads) run the same query twice rather than filtering
one cached payload locally, which is the price of not depending on system jq. Both are capped at 25s.

## Known gaps

- `reviewThreads(first:100)` and `comments(first:25)` are unpaginated. A PR with more than 100 threads, or a
  thread with more than 25 replies, silently truncates.
- Nothing dedupes a thread against the PR-level review body it belongs to, so a reviewer's summary comment can
  appear twice — once as prose, once as the thread that elaborates it.
- The skill offers to post replies and resolve threads, but never verifies afterwards that the resolve landed.
- Nothing stops a user approving a commit and then asking for a different fix on the same thread; that lands as
  a second commit on the same thread rather than an amend.
- The skill assumes this user's tree always carries unrelated uncommitted work, so it never checks or reports
  on it and stages strictly by path. There is no guard against a thread's fix touching a file that already had
  uncommitted changes — that commit would carry both.
