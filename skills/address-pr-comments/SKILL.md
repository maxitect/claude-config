---
name: address-pr-comments
description: Work through a PR's unresolved review comments one at a time. Detects the repo's stack, fetches the unresolved threads, reproduces each reviewer's claim before touching anything, fixes only what the probe confirmed, proves the fix with the same probe, presents it, then commits that one thread before moving on.
argument-hint: "[tracker: monday|github|jira|linear|none] [pr number]"
allowed-tools: Bash(${CLAUDE_SKILL_DIR}/render.sh *), Bash(gh*), Bash(git*), Bash(cat*), Bash(grep*), Bash(ls*), Bash(find*), Bash(curl*), Bash(jq*), Bash(pnpm*), Bash(npm*), Bash(npx*), Bash(yarn*), Bash(bun*), Bash(bunx*), Bash(python*), Bash(pytest*), Bash(mypy*), Bash(ruff*), Bash(poetry*), Bash(uv*), Bash(go*), Bash(cargo*), Bash(docker*), Bash(psql*), Bash(mongosh*), Bash(supabase*), Read, Edit, Grep, Glob, Skill, mcp__claude_ai_monday_com, mcp__claude_ai_Atlassian_Rovo, mcp__claude_ai_Google_Drive, mcp__playwright, mcp__supabase__get_advisors, mcp__supabase__execute_sql
---

# Address PR Comments

Work the unresolved threads one at a time. A reviewer's claim is a hypothesis until a command says
otherwise — reproduce it before you touch anything, and prove the fix with the same command afterwards.

Per thread, in this order and no other:

**verify the claim → fix it → verify the fix → present it → wait → commit it → next thread.**

A claim the probe refuted, or one no probe can settle, never reaches the fix step: it stops at the assessment
and waits for the user (§3D).

---

## 1. Context

Gathered already — the PR, the diff scope, conventions, the ticket, the stack's probe commands, and the
unresolved review threads in order. Take it as given; re-fetching wastes a turn and can contradict it.

!`${CLAUDE_SKILL_DIR}/render.sh $ARGUMENTS`

Working rules from that block:

- **Read every convention file listed.** They outrank this skill wherever they disagree.
- **Use the exact script/task names printed.** A probe invented from habit (`pnpm typecheck` where the repo
  says `check`) fails for the wrong reason and proves nothing.
- The stack fragments carry this repo's probe commands. They are what §3C and §3G run — not background reading.
  Anything not rendered isn't this repo's stack.
- The thread list is the agenda and its order is the order. Resolved threads were dropped: they are work
  already done, and reopening them is not the ask.
- A thread marked **OUTDATED** was written against a line that has since moved. Re-read the file before
  believing the quoted hunk — the comment may already be dead.
- No PR resolved → say so and stop. This skill needs reviewer comments; a self-review is `/pr-review`.
- Zero unresolved threads → say so and stop. Don't mine the resolved ones for work.
- If the rendered stack is plainly wrong for this repo, say so before starting.

---

## 2. Before the First Comment

Two things, once, up front:

1. **Acceptance criteria.** §1 rendered the ticket or the lookup path for it. A rendered ticket is already
   read; a lookup path means following it now. The criteria are the scope boundary — a reviewer asking for
   something no criterion covers is asking for scope creep, which is a legitimate thing to say back to them.
2. **Is the stack runnable?** Check once, not per comment; every probe below depends on the answer.

```bash
curl -sf -o /dev/null http://localhost:3000 && echo up || echo down   # port from package.json/Procfile/compose
docker compose ps 2>/dev/null | head -5
```

Cheap to start → start it. Nothing runnable (no deps, no DB, no creds) → say so once, and every claim below
is assessed statically and labelled UNVERIFIED.

If the working tree is dirty, don't check it, don't report it, don't offer to stash it. It just means `git add -A` and `git commit -a` are not an option: §3G stages by path, so whatever was already uncommitted stays that way.

Then state the agenda: **N unresolved threads, in this order**.

---

## 3. For Each Thread — Follow This Loop

One thread at a time, in order. Never batch — and never start thread N+1 with thread N uncommitted.

### A. Present the comment

- **Thread N of Total**
- Reviewer, file and line
- Exact quoted comment text (all of it — a thread's later replies often move the goalposts)

### B. Ground it in the code

Read the file at that line — the current file, not the diff hunk from §1.

```bash
git diff <base-ref>...<head-ref> -- <path>   # the exact range §1 printed: what this PR did there
cat <path>                              # what is there now
```

Then say in plain language what the reviewer is claiming. Terse comment or jargon → unpack it. Name the claim
in a form a command could disagree with ("this throws on an empty array", "this type doesn't compile",
"this query is N+1"), because that is what §3C runs.

### C. Verify the claim — before touching anything

**This is the step that must not be skipped.** Editing for a claim you haven't reproduced means changing
working code on a stranger's say-so, and a reviewer who is wrong is wrong confidently. It is also what earns
the right to skip the approval gate on the fix: what goes in without asking is only ever what a command
already confirmed.

Pick the cheapest probe that can return "no". §1's fragments carry this repo's real commands — prefer those
over the generic forms:

| Reviewer claims                         | Probe                                                                                                    |
| --------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| Type error, bad inference               | the repo's typecheck script — `tsc --noEmit`, `mypy`, `go build ./...`, `cargo check`                    |
| Lint / convention violation             | run the linter on that file (`eslint <file>`, `ruff check <file>`) — run the rule, don't assert it fires |
| "X doesn't exist" / wrong import        | grep the definition or the barrel export                                                                 |
| Logic bug, unhandled edge case          | execute it — existing test, `node -e`, `python -c` — with the input that should break it                 |
| Missing or broken test coverage         | run the suite or the single test; quote the decisive line                                                |
| Route / handler behaviour               | `curl -i` the running server with a real session; assert status and body shape                           |
| DB query, migration, constraint, policy | apply locally, then write the row that should trip it and show what happened                             |
| Rendering, hydration, client state      | Playwright MCP — walk the flow, `browser_snapshot`, read `browser_console_messages`                      |
| Performance / N+1                       | count the queries or time it; a number, not an intuition                                                 |
| Security hole                           | reproduce the unauthorised call and show the response                                                    |

Anything §1 already ran (the database block, for instance) is evidence in hand — quote it, don't re-run it.

Label the claim:

- **CONFIRMED** — probe output in hand. Quote the decisive line.
- **REFUTED** — the probe disagrees with the reviewer. Say so plainly with the output; the deliverable here is
  a reply, not a code change.
- **UNVERIFIED** — no probe can settle it (readability, naming, design preference, scope) or the stack isn't
  runnable. Say which of the two.

Style and taste comments are legitimately UNVERIFIED — don't manufacture a probe for a naming suggestion. But
every claim about behaviour gets one.

### D. Assess, then branch

With the probe output in front of you:

- **Valid** — CONFIRMED, and inside the acceptance criteria (§2). Go straight to E and fix it.
- **Valid but minor** — CONFIRMED, low stakes (a real but trivial correctness nit). Also E.
- **Refuted** — the probe disagrees with the reviewer.
- **Unverifiable** — style, naming, design preference, or the stack isn't runnable.
- **Debatable, or outside the acceptance criteria** — reasonable people disagree, or the reviewer is asking
  for work no criterion covers.

The last three **stop here**. Present the evidence, say which of the three it is, and draft the reply to the
reviewer in ordinary prose with the decisive line in it. Then wait: the user decides whether to change the code
anyway, send the reply, or skip. Nothing is edited and nothing is committed on a claim that didn't survive a
probe — that is the whole point of running one.

A confirmed claim needs no permission to fix. An unconfirmed one needs a decision.

### E. Fix it, and prove the fix

1. **Red first** — the failing probe output from §3C, captured before the edit. Without it you cannot tell a
   fix from a coincidence. Already in hand from C; quote it, don't re-run it.
2. Make the smallest change that addresses the comment. No refactoring, no improving the neighbours, nothing
   the reviewer didn't ask for.
3. **Green** — re-run that exact probe, quote the passing output.
4. **Regression sweep** — typecheck, lint, tests as the repo names them; re-run the probes of every earlier
   thread touching this file; for UI, re-walk the other flows using the changed component.
5. Step 3 or 4 fails → the fix is wrong. Back to 2 with a different one. Three failed attempts → stop, say
   what you tried and what the probe keeps saying, and hand it back.

### F. Present it

Only now, with the fix green:

- **The comment** — one line, what the reviewer wanted
- **The claim** — CONFIRMED, with the red line from C
- **The change** — diff summary, and the code before/after where it isn't obvious
- **The proof** — the green line from E, plus what the sweep ran and said
- **Scope** — anything this touched beyond the comment, and why

Then stop and wait. The user approves, asks for a different fix, or reverts it.

### G. Commit — on their go-ahead

One thread, one commit. Invoke the **`commit` skill** rather than writing the message yourself; it owns the
format, the granularity rules, and the no-attribution rule. A fix that genuinely spans two concerns is the one
case where that skill splits it into two — but never the reverse: one commit never spans two threads.

```bash
git add <only the files this thread touched>
```

Stage by path, every time, and stage nothing else. The tree can carry unrelated uncommitted work as a matter of
course — it is not yours, not this commit's business, and not worth mentioning. Never `git add -A`, never
`git add .`, never `git commit -a`.

The commit lands before the next thread is presented. A branch where thread 3 is half-committed into thread 4's
work is one the reviewer cannot re-review.

### H. Reply on the PR — only when asked

Posting to the PR is outward-facing and goes out under the user's name. Offer, don't act:

> _"Want me to post the reply on thread N, or resolve it?"_

On a yes:

```bash
gh api graphql -f query='mutation($t:ID!,$b:String!){addPullRequestReviewThreadReply(input:{pullRequestReviewThreadId:$t,body:$b}){comment{url}}}' -F t=<thread-id> -F b='<reply>'
gh api graphql -f query='mutation($t:ID!){resolveReviewThread(input:{threadId:$t}){thread{isResolved}}}' -F t=<thread-id>
```

The thread ids are the `id=` values in §1. Resolve only what was actually addressed.

Then, and only then, thread N+1.

---

## 4. Tracking Progress

Keep the count visible: **"Thread N of Total — X committed, Y refuted, Z skipped, W pending"**

At the end:

- **Committed** — thread, what changed, the green probe, and the commit subject
- **Refuted** — the reviewer's claim, the probe that disagreed, what the user decided
- **Skipped** — and why
- **Unverified** — what is waiting on a runnable stack or a human judgement
- **Scope** — anything a reviewer asked for that no acceptance criterion covers

Then two things:

```bash
git log --oneline <base-ref>..HEAD | head -20   # one commit per addressed thread, nothing stray
```

and run the full check suite once more (typecheck, lint, test, build as the repo names them) and quote the
result. Several small green probes don't add up to a green branch.

---

## Rules

- ❌ Never edit for a claim the probe hasn't confirmed — refuted and unverifiable claims stop at §3D
- ❌ Never present a fix that isn't green, or commit one the user hasn't seen
- ❌ Never batch threads — one thread, one fix, one commit
- ❌ Never start the next thread with the last one uncommitted
- ❌ Never stage files the thread didn't touch — stage by path; `git add -A`/`.`/`commit -a` are always wrong
- ❌ Never report on, or offer to tidy, uncommitted work that was already there
- ❌ Never hand-write the commit message — the `commit` skill owns that
- ❌ Never post to the PR without being asked
- ❌ Never skip a thread silently
- ✅ Read the current file before explaining a comment — especially an OUTDATED one
- ✅ Quote probe output; a claim without a command is a hypothesis
- ✅ Push back with evidence when the reviewer is wrong
- ✅ Red before green, then sweep for regressions
