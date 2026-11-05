---
description: Batch-review every PR merged into the current branch since a given date - one agent per PR, findings verified against the code as it stands now, aggregated into a single markdown remediation plan for an implementation agent
argument-hint: "<since-date YYYY-MM-DD> (inclusive)"
allowed-tools: Bash(gh*), Bash(git*), Bash(cat*), Bash(grep*), Bash(ls*), Read, Write, Agent
---

# PR Audit — Batch Review of Recently Merged Work

Run from `main` / `develop` (the base branch), **not** a feature branch. Reviews every PR **merged
into this branch** since `$1` (inclusive), fans out one review agent per PR, then aggregates
everything into one deduplicated, severity-ranked markdown file that a follow-up implementation
agent can execute against.

Uses `/pr-review`'s checklist as-is - each agent reads `~/.claude/commands/pr-review.md` and walks
§2, §4, §5 and §6 against its PR. That file stays the single source of truth for what a review
covers; nothing is duplicated here. This command differs from it in four ways that matter:

1. **Diffs come from GitHub** (`gh pr diff`), not from `git diff` against a base - each PR's diff is
   isolated even though they're all already merged.
2. **Merged only.** Open, closed-unmerged, and draft PRs are out of scope. Nothing is reviewed that
   isn't already in this branch.
3. **Findings are verified against HEAD, not against the diff.** All this code is already merged, so
   the working tree is the ground truth. A problem introduced by PR #12 and fixed by PR #19 is
   **not a finding**. This is the single most important rule of this command.
4. **The PR's discussion is read first, not last.** These PRs were reviewed and argued over before
   merging. Trade-offs already explained in the description, review threads, or commit messages
   kill uncertain findings outright - raising a settled point makes the whole audit look careless.

Output is a plan to fix, not a report to read. The exit path is a branch + PR that closes out
everything found.

---

## 0. Preflight

`$1` is required and must be `YYYY-MM-DD`. Missing or malformed → stop, state the expected format.

```bash
git branch --show-current
git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@'
gh repo view --json nameWithOwner -q .nameWithOwner
git fetch origin
git status -sb
```

```bash
ls ~/.claude/commands/pr-review.md
```

Store `BRANCH`, `REPO`. Resolve the absolute path to `pr-review.md` - the review agents read it for
the checklist, so confirm it exists here rather than letting N agents discover it's missing. Not
found → stop and say so.

Hard checks - each one wrong makes the audit wrong:

- **On a base branch.** `BRANCH` is the origin default, or one of `main`/`master`/`develop`. If on a
  feature branch → stop, say so, suggest checking out the base branch first.
- **Up to date with origin.** `git status -sb` shows behind → stop, offer to pull. Auditing a stale
  branch means verifying findings against code that isn't current.
- **Clean tree.** Uncommitted changes → warn, they'll pollute verification. Not fatal.

---

## 1. Collect the merged PRs

```bash
gh pr list --repo $REPO --state merged --base $BRANCH --limit 200 \
  --search "merged:>=$1" \
  --json number,title,url,author,mergedAt,mergeCommit,headRefName,body,additions,deletions,changedFiles \
  --jq 'sort_by(.mergedAt)'
```

Window is **merge date**, not creation date - the question is what landed in this branch since `$1`,
regardless of when the PR was opened. Say so in the output header so the scope is unambiguous.

Confirm each PR is genuinely in this branch (a PR can be merged into a different base, or the merge
commit can have been reverted since):

```bash
git merge-base --is-ancestor <mergeCommit.oid> HEAD && echo IN_BRANCH || echo NOT_IN_BRANCH
git log --oneline --grep="Revert" --since="$1"   # spot reverts of PRs in the list
```

Drop `NOT_IN_BRANCH` PRs. Note any reverted ones and exclude them - reviewing reverted code wastes
an agent.

Report the working set before spending tokens on it:

```
Auditing N PRs merged into <branch> since <date>:
#12 title (+120/-30, 8 files, @author)
...
Total ~X files changed across all PRs.
```

Zero PRs → say so and stop. Every PR in the window gets an agent - never sample, never skip the
small ones, never trim the list to keep the run cheap. If the count is large enough that the run
will be slow, say so and let the user decide whether to narrow the date; that's their call, not
yours.

---

## 2. Detect stack & conventions (once, shared)

Do this **before** fanning out. Every agent gets the result, so none of them re-derive it.

```bash
cat CLAUDE.md 2>/dev/null || cat .claude/CLAUDE.md 2>/dev/null
ls package-lock.json yarn.lock pnpm-lock.yaml bun.lockb 2>/dev/null | head -1
cat package.json 2>/dev/null | head -60
ls tsconfig.json pyproject.toml go.mod Cargo.toml mix.exs 2>/dev/null
```

Condense to a short **stack brief**: language + runtime, framework, package manager, TS strictness,
test framework, and the project-specific rules from CLAUDE.md worth enforcing. A dozen lines, no
more - it's pasted into every agent prompt.

---

## 3. Fan out — one agent per PR

One `Agent` call per PR (`subagent_type: general-purpose`). Launch in batches of ~5 concurrent calls;
independent calls go in a single message. Never review a PR yourself in the main thread - the point
is keeping the diffs out of this context so aggregation stays sharp.

**Head branches are usually deleted after merge. That's fine and changes nothing.** `gh pr diff` and
`gh pr view` read `refs/pull/<N>/head` through the API, which GitHub keeps permanently - deletion of
the head branch doesn't affect them. But `refs/pull/*` is NOT fetched by a normal clone, so local
git commands cannot reach PR head commits. Consequence, and it's in the agent prompt below: diffs
come from `gh` only, and local `Read`/`git` is used only against the working tree (the base branch,
which already contains all this code). Never `git checkout` or `git show` a PR head.

The agent starts cold, so the prompt carries what it can't derive: the stack brief, the audit's
merged-code rules, and the return contract. The review standard itself is NOT copied in - the agent
reads `~/.claude/commands/pr-review.md` directly, so there's one checklist, not a copy that drifts.
Fill `<>`, keep the rest verbatim.

````
Review PR #<N> ("<title>") in <REPO>. It is ALREADY MERGED into <BRANCH>, which is the branch
checked out in your working directory - so every line this PR added is already in the working tree.

Fetch the PR from the API (its head branch is probably deleted; this works regardless):
  gh pr diff <N> --repo <REPO>
  gh pr view <N> --repo <REPO> --json body,files,commits,author,mergedAt

Do NOT try to `git checkout`, `git show`, or `git log` the PR's head branch or head SHA - those
refs are not in the local clone and the commands will fail. Diff comes from `gh`. Current code
comes from Read against the working tree.

## Read the discussion BEFORE reviewing a single line

This is not optional and it is not last. Reviewers on this PR already argued about this code, and
the author already explained things. Walk in knowing what was settled.

  # PR description - the author's own account of intent, approach, trade-offs, known gaps
  gh pr view <N> --repo <REPO> --json body,title

  # Conversation-tab comments
  gh pr view <N> --repo <REPO> --json comments \
    --jq '.comments[] | {author: .author.login, body}'

  # Review summary bodies (approvals, change requests, and their reasoning)
  gh api repos/<REPO>/pulls/<N>/reviews --paginate \
    --jq '.[] | select(.body != "") | {author: .user.login, state, body}'

  # Inline review threads - the richest source; where a specific line was justified
  gh api repos/<REPO>/pulls/<N>/comments --paginate \
    --jq '.[] | {path, line: (.line // .original_line), author: .user.login, body}'

  # Commit messages often carry the "why" the description omits
  gh pr view <N> --repo <REPO> --json commits --jq '.commits[].messageHeadline'

From all of that, build a short list of ALREADY-SETTLED POINTS before you review: decisions made
deliberately, trade-offs accepted with a stated reason, alternatives considered and rejected,
scope explicitly deferred (with or without a ticket), and anything a reviewer already raised that
the author answered.

How settled points change your verdict:

- Finding you're UNSURE about, and the discussion explains it → drop it. This is the main purpose
  of reading the discussion. Re-litigating a settled trade-off wastes the reader's time and makes
  the whole audit look careless.
- Finding you're unsure about, and the discussion is silent → report it, normal severity.
- Finding is a REAL defect - a bug, security hole, data loss, unmet acceptance criterion - and the
  discussion explains why they did it that way → still report it. An explanation is not a fix.
  Do NOT report that it was discussed. Just make sure your `fix` answers the reasoning they gave
  instead of proposing the thing they already rejected.
- A reviewer raised it, the author promised a follow-up, and the code still doesn't do it → it's a
  finding like any other. Report the defect, not the broken promise.

Deferred-by-choice work with a ticket tracking it is not a finding.

The discussion is INPUT. It decides what you report. It never appears in what you report - no
"this was discussed", no "@x decided", no "settled in review". The reader wants the fix, not the
minutes of the meeting.

Stack brief (do not re-derive it, it's already been established):
<stack brief from §2>

## THE RULE THAT OVERRIDES EVERYTHING

A finding only counts if the problem is STILL PRESENT in the code as it stands right now. All of
this is merged; later PRs may have fixed it, refactored the file, or deleted it. For every
candidate finding, Read the current file and confirm the problematic code is still there and still
reachable. Diff-only findings are worthless here - drop them silently, do not report them as
"possibly fixed" or "was an issue at merge time".

Second rule: check context before judging. Read the code surrounding the change, not just diff
lines, and hold every candidate against the settled points above. A pattern that looks wrong in
isolation is often the established convention or an explained decision. If you're overriding
either, say which one and why.

Do not fix anything. Do not edit files. Read only.

## The review method - read it, don't improvise it

Your FIRST action, before the diff, before anything:

  Read ~/.claude/commands/pr-review.md

That file is the review standard and the single source of truth for it. Apply, in full:

- §2 Check Linked Issues - build the Issue Checklist from any issue the PR closes
- §4 Severity Classification - 🔴 critical / 🟡 warning / 🟢 suggestion, exactly as defined there
- §5 Review Checklist - every applicable section, every box: acceptance criteria coverage, logic &
  correctness, security, error handling, types & contracts, state & data flow, performance, code
  quality, conventions
- §6 Anti-Pattern Radar - the full table

Do not work from memory of what a code review usually covers. Read the file and walk its boxes.

If that Read fails, STOP and return {"pr": <N>, "error": "could not read pr-review.md at <path>"}.
Do not fall back to reviewing from memory - a half-standard review silently poisons the audit.

Two adaptations for this command, which reviews already-merged code:

- §2's issue checklist is verified against the code as it stands NOW, not against the diff. Unmet
  criterion is still critical. No linked issue - skip §2, that absence is not a finding.
- §7's output format does not apply. Return the JSON below instead.

## Return format

Return ONLY this JSON object. No prose before or after.

{
  "pr": <N>,
  "findings": [
    {
      "severity": "critical" | "warning" | "suggestion",
      "title": "short imperative title - the change to make, not the problem's name",
      "file": "src/path/to/file.ts",
      "line": <current line number in the working tree, NOT the diff line>,
      "problem": "what is wrong and why it matters - 1-2 sentences, no history",
      "fix": "concrete change to make - specific enough to implement without re-reviewing",
      "snippet": "the current offending code, a few lines",
      "verified": "how you confirmed it is still present in the working tree",
      "unmet_criterion": "omit unless this is an acceptance criterion from a linked issue that the
                          code does not satisfy - then state the criterion verbatim"
    }
  ]
}

`findings` is [] when nothing survived verification - a valid and useful result. Report every
finding that survived, ranked; there is no limit and no quota. Do not drop a real one to keep the
list short, and do not manufacture one to look thorough. Scale effort to the size of the PR.

Every field describes the code as it is now and the change to make. Nothing describes your process,
the review history, or what you decided not to report. `verified` is for the aggregator to
sanity-check you; it does not reach the reader.
````

Agent returns nothing usable / errors → note it in the output as an unreviewed PR. Don't silently
drop it.

---

## 4. Aggregate

You are not a compiler for the agents' output. You are the editor deciding what makes the list.
Findings arrive as candidates; they earn a place or they're gone. Plain work, done in this thread:

1. **Cross-examine every candidate.** You have what no agent had: all the findings at once, and the
   whole codebase. For each one - is it real, is it still real given the other PRs, does the fix
   still make sense when you can see the neighbouring changes? Anything that doesn't survive, drop
   without comment. This applies hardest to suggestions and nits: a naming quibble from one agent
   goes in ONLY if it's genuinely worth an implementer's time in the context of everything else.
   Most won't be. Cutting is the job.
2. **Dedupe.** Same problem found by two agents → one item. Near-duplicates that differ only in
   wording → one item, best fix wins.
3. **Cluster.** Findings sharing a root cause across files (same missing guard in five handlers,
   same hand-rolled type in three components) → one item listing every location. One fix, one entry.
4. **Verify every critical yourself.** Read the file before a 🔴 goes in. Agents over-report; a
   wrong critical costs more than a missed nit. Downgrade or drop what doesn't hold up.
5. **Add what no single agent could see.** The cross-PR defects - the real reason this exists over
   running `/pr-review` N times. They go in the list as ordinary items, not a special section:
   - Two PRs adding the same helper/type/util in different places
   - A PR consuming an interface another PR changed underneath it
   - Migrations landing out of order, or a migration whose backfill a later PR broke
   - Auth/validation applied in one new route but not its sibling from another PR
   - Dead code: something one PR added and another orphaned
6. **Unmet acceptance criteria are items like any other**, ranked critical, with the criterion
   quoted in the problem statement so the implementer can't reinterpret it.
7. **Rank by what to fix first**: severity, then blast radius. No cap. Every item that survived
   cross-examination goes in the file, however many that is. The only reason anything is ever
   dropped is that it failed step 1 (not real, no longer real, or not worth doing) or step 2
   (duplicate) - never because the list got long.

What does NOT survive aggregation, ever: which PR a finding came from, what the review discussion
said, what was decided deliberately, what you dropped and why, which PRs were clean, what the code
does well. The reader is an implementation agent with a branch to open. None of that changes a
single edit it will make.

---

## 5. Write the remediation plan

Write to `pr-audit-<$1>-to-<today>.md` in the repo root. It is a work order for an implementation
agent, not a report on the audit. Every line either tells the implementer what to change or gets
cut.

The whole file is the list. No preamble, no findings tables, no summary of overall health, no
sections about what was settled, deferred, or done well.

````markdown
# Fixes: <REPO> — merged work since <$1>

Verified against `<branch>` at `<HEAD sha>`. <N> items, most severe first.

## 1. 🔴 <title - the change to make>

- **Where:** `src/path/file.ts:42` (every location, if clustered)
- **Problem:** what is wrong now, and what breaks because of it. Two sentences.
- **Fix:** the change to make.

```ts
// current
...
// after
...
```

- **Verify:** `pnpm test src/foo.test.ts` / `tsc --noEmit` / the manual step that proves it

## 2. 🟡 <title>

...same shape...
````

Rules:

- Every item: concrete fix + verification step. An item the implementer must re-investigate has
  failed.
- Write for someone who has never seen these PRs, has no access to them, and doesn't care that they
  exist. Quote the code, not the diff. Never write "#12", "as PR #40 introduced", "the author
  decided", "raised in review" - if the reader can't act on it, it isn't in the file.
- 🔴/🟡/🟢 sets order and nothing else. There are no severity sections and no per-severity quotas -
  a 🟢 that made the list earns its place by being worth doing, and gets the same shape as a 🔴.
- Clustered items list every location.
- Unmet acceptance criteria quote the criterion inside **Problem**.
- If nothing survived: say the audit found nothing worth fixing, in one line. Don't pad it.

---

## 6. After the plan

1. Report to the user in chat - not in the file: how many PRs were audited, how many items made the
   list, counts by severity, path to the file. Chat is where the scope and coverage story belongs;
   the file stays a work order. Keep it to a few lines.
2. Offer the implementation route: branch off `BRANCH`, hand the file to an implementation agent
   (or work through it directly), fix top-down, then `/pr-prep` to open the PR.
3. Do not start fixing without an explicit go-ahead, and do not commit to `BRANCH` - the whole point
   is a fix PR.
4. After fixes land: type check, lint, tests. A remediation PR that breaks the build is worse than
   the issues it fixes.
