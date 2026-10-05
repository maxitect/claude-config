---
description: After a submitted PR review, pull maxitect's ACTUAL review comments from GitHub (not the draft from this context), the dev's replies, and the updated code - then report per-comment whether each item was implemented as suggested, implemented differently, declined with a reason, or ignored
argument-hint: "[pr-number] (default: PR on current branch)"
allowed-tools: Bash(gh*), Bash(git*), Bash(python3*), Bash(cat*), Read, Grep, Glob
---

# Review Follow-up — Did the Dev Address My Comments?

Runs AFTER the full cycle: review done (`/oz-review`, `pr-review`, `/code-review`) → pending review posted (`/pr-comment`) → **maxitect edited that pending review in GitHub** (reworded comments, deleted some, added his own new ones) → submitted it → dev responded and pushed changes → branch pulled locally.

**Critical rule: the review that matters is the one ON GITHUB, not the one drafted earlier in this conversation.** maxitect will have changed it. Ignore any findings/comments from earlier in this context window - fetch everything fresh from the GitHub API and treat that as the single source of truth. Never assume a comment from the draft survived, and never miss one he added himself.

If `$1` is provided, target that PR number; otherwise use the PR on the current branch.

---

## 0. Identify PR, reviewer, and state

```bash
gh pr view ${1:-} --json number,title,url,state,headRefName,headRefOid,baseRefName \
  -q '{n:.number,title:.title,sha:.headRefOid,head:.headRefName,base:.baseRefName,state:.state,url:.url}'
gh repo view --json nameWithOwner -q .nameWithOwner
gh api user -q .login   # maxitect's GitHub login - filter comments by this author
```

Confirm the local branch matches and is up to date - the whole point is assessing the code the dev pushed since the review:

```bash
git branch --show-current      # should be the PR head branch
git fetch origin
git status -sb                 # warn if behind origin - offer to pull before assessing
git rev-parse HEAD             # should equal headRefOid; if not, local is stale - stop and say so
```

If local HEAD ≠ PR head SHA, stop and tell the user to pull first. Assessing stale code produces wrong verdicts.

---

## 1. Fetch the ACTUAL review from GitHub

Three sources, all needed:

### 1a. Submitted reviews (the summary bodies)

```bash
gh api repos/<nameWithOwner>/pulls/<n>/reviews --paginate \
  -q '[.[] | select(.user.login=="<login>") | {id, state, commit_id, submitted_at, body}]'
```

Keep every review by maxitect (there may be more than one round). Note each review's `commit_id` - that's the SHA the review was made against; everything after it is the dev's response.

### 1b. Review threads — inline comments + replies + resolution state

GraphQL is the right tool here: it gives threads with `isResolved`, `isOutdated`, and the full reply chain in one call.

```bash
gh api graphql -f query='
query($owner:String!, $repo:String!, $pr:Int!, $cursor:String) {
  repository(owner:$owner, name:$repo) {
    pullRequest(number:$pr) {
      reviewThreads(first:50, after:$cursor) {
        pageInfo { hasNextPage endCursor }
        nodes {
          isResolved isOutdated path line originalLine
          comments(first:30) {
            nodes { author { login } body createdAt }
          }
        }
      }
    }
  }
}' -F owner=<owner> -F repo=<repo> -F pr=<n> --paginate
```

For each thread, extract:

- **The comment** — first comment in the thread authored by maxitect (usually the root). Threads rooted by someone else where maxitect never commented are out of scope - skip them.
- **Replies** — every subsequent comment, who said what, in order. The dev's replies are the claimed response.
- **`path` + `line`** (fall back to `originalLine` when the thread is outdated) — where to look in the updated code.
- **`isResolved` / `isOutdated`** — signals, not verdicts. Resolved ≠ fixed (devs resolve threads they've decided to skip); outdated means the anchored lines changed, which _suggests_ the code moved but doesn't prove the suggestion was taken.

### 1c. Issue-level conversation comments

maxitect and the dev may also have talked in the PR conversation tab:

```bash
gh api repos/<nameWithOwner>/issues/<n>/comments --paginate \
  -q '[.[] | {author:.user.login, created:.created_at, body}]'
```

Pull any comment by maxitect that raises a point (from the review summary body's non-inlined findings, e.g. `path:line` prose items), and any dev reply addressing one. Summary-body findings that never got an inline thread still count as items to assess.

### Build the item list

Merge 1a–1c into a flat list of **review items**, one per distinct point maxitect raised:

- inline thread comments (1b)
- non-inlined `path:line` findings from the review body (1a)
- conversation-tab points (1c)

Deduplicate where the same point appears in body + thread. Each item carries: what was asked, where (`path:line` if any), the dev's reply (if any), thread resolution state.

---

## 2. Establish what changed since the review

```bash
# Commits the dev pushed after the review
git log --oneline <review_commit_id>..HEAD

# The response diff - what actually changed in reaction to the review
git diff <review_commit_id>..HEAD

# Files touched since the review (quick map of where responses landed)
git diff --name-status <review_commit_id>..HEAD
```

Use the **earliest** of maxitect's review `commit_id`s as the baseline if there were multiple rounds. If `git log` shows nothing after the review commit, every code-change verdict is automatically "not addressed" - only comment-replies can count.

---

## 3. Assess each item against the updated code

For every review item, in order:

1. **Read the current code** at the item's `path` (Read tool, around the relevant lines - the line number may have shifted; find the code the comment was about, don't trust the stale line number). For outdated threads, diff-hunt: `git log -L` or search the response diff for the relevant symbol.
2. **Compare against what was asked.** Was the exact suggestion applied (suggestion block committed verbatim or near-verbatim)? A different fix for the same problem? Nothing?
3. **Read the dev's reply** (if any) and check it against reality:
   - Reply says "done" → verify the code actually does it. "Done" with no matching change is a flag.
   - Reply pushes back with a reason → judge the reason on its merits. Is it technically sound? Does it hold up against the code? Say so either way - maxitect wants an assessment, not a transcription.
   - Reply defers ("will do in a follow-up", "separate ticket") → note it as deferred, and whether a ticket/issue reference was given.
4. **Assign a verdict:**

   | Verdict                         | Meaning                                                                                 |
   | ------------------------------- | --------------------------------------------------------------------------------------- |
   | ✅ **Implemented as suggested** | Change matches the suggestion                                                           |
   | 🔀 **Implemented differently**  | Problem solved another way - state whether the alternative is as good, better, or worse |
   | 💬 **Declined with reason**     | Dev pushed back - state the reason and whether it holds up                              |
   | ⏳ **Deferred**                 | Acknowledged, promised later - note ticket ref or lack of one                           |
   | ❌ **Not addressed**            | No reply, no code change                                                                |
   | ⚠️ **Claimed but not done**     | Reply says fixed/done but the code doesn't show it                                      |
   | 🤔 **Partially addressed**      | Some of the point handled, rest ignored - say which part                                |

5. **Spot regressions and side effects.** While reading the response diff, flag anything the fixes broke or any new issue the response commits introduced - briefly, this isn't a full re-review. Every such finding is a **follow-up point** and feeds the verdict in §4. Offer a full re-review at the end if the response diff is large.

Verify with real evidence: quote the current code or the response-diff hunk that justifies each verdict. Never mark ✅ from the dev's reply alone.

---

## 4. Report

**First line, before anything else: the verdict.** `APPROVE` or `DO NOT APPROVE`, bold, on its own - maxitect reads that line and knows what to do. Everything below it is backup, not the headline.

- `DO NOT APPROVE` - any ⚠️ Claimed-but-not-done, any ❌ Not-addressed on a point that matters, any 💬 decline whose reason doesn't hold, or any follow-up point found while reading the response diff (§3.5) - a regression or a new issue the dev's own fix introduced. Name the blocking items right there on the verdict line, not two sections down.
- `APPROVE` - none of the above: every open item is ✅/🔀, every 💬/⏳ holds up on its own merits, and the response diff introduced nothing new.

No hedging on the verdict itself (_"probably fine"_, _"mostly looks good"_) - it's binary, say which one.

Then the scoreboard, then per-item detail. Order items: ⚠️ and ❌ first (needs maxitect's attention), then 💬 (needs his judgement), then 🤔/⏳/🔀, then ✅ last. New issues from §3.5 go last, after the scoreboard items, under their own heading.

````
## Review Follow-up: [PR title] (#N)

**DO NOT APPROVE** - blocked on #2 (null guard claimed done, code unchanged), #3 (declined reason doesn't hold), and a new null deref introduced in the response commit at `src/upload.ts:58`

**X of Y items addressed** — A implemented as suggested, B differently, C declined, D deferred, E outstanding

| # | Comment (short) | Where | Dev response | Verdict |
|---|---|---|---|---|
| 1 | derive from supabase types | `src/types/foo.ts:10` | "done" | ✅ |
| 2 | null guard before deref | `src/upload.ts:42` | "done" | ⚠️ claimed, code unchanged |
| 3 | move to db trigger | `api/invites/route.ts` | declined - "trigger can't access auth context" | 💬 reason doesn't hold - `auth.uid()` available in triggers |
| ... |

### Needs your attention

**2. null guard before deref** (`src/upload.ts:42`) — ⚠️
Dev replied "done" but the current code still derefs `file.name` before the guard:
```ts
<current code snippet>
```

**3. move to db trigger** — 💬
Dev's reason: "trigger can't access auth context". Doesn't hold - `auth.uid()` works in SECURITY DEFINER triggers and it's how `handle_new_user` already does it. Your call whether to press.

### Resolved fine

**1. derive from supabase types** — ✅ now `Pick<Tables<"organisations">, ...>` (commit abc123)
...one line each...

### New issues in the response commits

**`src/upload.ts:58`** — new null deref introduced fixing #2: `file.size` read before the same guard that was supposed to cover it. Blocks approval on its own.
...only if any were spotted; otherwise omit the section...
````

Rules:

- Every verdict backed by evidence - a code snippet, a diff hunk, or a commit ref. No verdicts from replies alone.
- For 💬 declined items, always give a view on whether the reason stands - that's the judgement maxitect is asking this command for.
- Keep ✅ items to one line each; spend the words on ⚠️/❌/💬.
- Thread `isResolved` state is worth a mention when it disagrees with the verdict (e.g. resolved but not addressed).
- **No preamble, no recap, no hedging in the prose.** Each `###` item states cause and fix, plain - not _"upon reviewing this, it appears that..."_, not a re-summary of the table row that precedes it. Matter-of-fact even on ⚠️/❌ - no _"unfortunately"_, no softening a claimed-but-not-done into sounding like a near-miss.
- Don't bury a blocking item in prose to be polite. If it blocks approval, say so in the same sentence as the finding, not as an inference the reader has to draw three lines later.

---

## 5. After the report

1. Offer to draft replies (via `/pr-comment` conventions) for the items needing a response - as replies on the existing threads, pending his approval before posting.
2. Offer a full re-review of the response diff if it's substantial or introduced new issues.
3. Do NOT post anything, resolve threads, or approve - reporting only. Follow-up actions are maxitect's call.
