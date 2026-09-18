---
description: Post code-review findings onto the open PR as a PENDING review - inline comments and suggestions in my own commenting voice - and write the summary to pr-<number>-review.md in the repo root
argument-hint: "[extra instructions for this run] (optional)"
allowed-tools: Bash(gh*), Bash(git*), Bash(python3*), Bash(cat*), Read, Write, Grep, Glob
---

# Post PR Comments

Takes severity-graded findings from a preceding review (already in context) and posts them onto the open PR as a single **PENDING** review - inline comments and `suggestion` blocks. I read it in GitHub and submit it myself. This command does not review code - if no findings exist in the conversation, then lets discuss first.

`$ARGUMENTS`, when given, is extra steering for this run: what to focus on, findings to drop, a tone nudge. It wins over the defaults below wherever they conflict, except for two things it can never override - the review stays `PENDING`, and nothing posts before I approve the preview.

## 1. Preconditions

Target the current branch's PR. Confirm it exists and get the diff:

```bash
gh pr view --json number,title,headRefOid,state,url -q '{n:.number,sha:.headRefOid,state:.state,url:.url}'
gh repo view --json nameWithOwner -q .nameWithOwner
gh pr diff <number> --patch > /tmp/pr-<number>.diff
```

Line comments can only anchor to diff lines (added → `RIGHT`, removed → `LEFT`); whole-file findings anchor to the **file itself** (§3.4). Findings on files the PR doesn't touch go in the summary body as `path:line` prose (_"realise this isn't edited in this PR but…"_). No PR on this branch → stop and say so.

## 2. The voice

**Short, direct, no hedging.** One sentence, two max: `[thing] [problem] [reason/fix].`

> ❌ "I think it might be a good idea to consider deriving this type from our generated Supabase types rather than redefining it here, as that would help avoid the double maintenance burden…"
> ✅ "derive from supabase types - saves the double maintenance"

- Cut filler (_just / really / basically / it might be worth considering_) and hedge-padding (_not blocking_, _just flagging_, _happy to leave it_). If a suggestion needs a cushion to survive, drop it entirely.
- One reason, not three. Name the principle: DRY, single source of truth, stale info, race, security, YAGNI, REST convention.
- Direct ≠ bossy: state the finding and the fix - we verified it, so say so plainly. Reserve questions only for a genuine open call, not as default phrasing for a suggestion we've checked (_"unless I'm missing something?"_), never a wall of them.
- **British English** (organise, colour, -ise). Casual, contractions, lowercase starts fine. Warm, but write clean - no fabricated typos. Light emoji only where playful, never in a bug report.
- Point at existing code with exact paths (_"this already exists in `utils/formatters.ts`"_). Prefer canonical sources: supabase/zod types over retyping, constants/config over hardcoded values, design tokens over raw tailwind, db triggers over repeated app logic.
- Acknowledge scope on pre-existing code (_"realise this is not edited in this PR but…"_).

### Punctuation, how to sound more human

- **No em dashes.** A paired-em-dash aside becomes parentheses: ✅ _"fetch (which resolves on HTTP errors) never sees the 401"_. A lone one becomes a semicolon, colon or full stop. A spaced hyphen is the fallback if nothing else fits, not the habit.
- **No "not X but Y"** - also _"isn't just X, it's Y"_, _"less about X, more about Y"_. State the point: ❌ _"this isn't a types problem - it's a data-modelling one"_ ✅ _"the column is nullable, so the non-optional type is lying"_.
- **No parade of examples.** Three same-shaped sentences each covering one facet, then a synthesis line, is a list in prose costume. Keep the one that matters.
- **Lead with the specific.** Never open the summary with framing (_"this PR makes several changes to the invite flow…"_). Open on the verdict, the file or the finding.
- **Vary the punctuation.** Semicolons, colons, parentheses, a question. Not five flat declaratives in a row.

### Dots + severity framing

Every comment's prose starts with its dot (for suggestion-block comments, on the rationale line):

- 🟢 **Suggestion → finding + recommended fix, stated plainly.** _"belongs in the types folder"_, _"derive from supabase types - saves the double maintenance"_. Low severity comes from the dot and brevity.
- 🟡 **Warning → issue + the one reason, tight.** _"better as a db trigger - app-side fails → phantom pending invites, and it's repeated in join-requests."_
- 🔴 **Critical → mechanism → consequence, one line.** _"fetch resolves on HTTP errors - no `r.ok` guard, so the 401 gets parsed as JSON."_ Fix as a suggestion block, not prose.
- 🟣 **Accolade → at most one or two, zero is fine.** Only non-obvious good calls: a clean abstraction, the right canonical source, a subtle race avoided, a great guard against a non-trivial edge case. Anchor to the line that _does_ the thing - never a docstring/comment describing it. Whole-mechanism/file praise → file-level comment (§4). One line with the why; don't re-explain the mechanism back to its author. Never praise the routine.

### Summary body

A few sentences: overall take + headline points + non-inlineable findings as `path:line` prose.

- **Never report process.** No _"lint/tests/build pass"_, no _"checked against the acceptance criteria"_ - CI shows the checks; a missed AC is a finding.
- **No "Claude checked / Claude said" formulas.** Own the points. A self-aware Claude joke very rarely, as a joke - never boilerplate.
- Praise one line max (_"nice, looks solid"_).
- Body suggestions follow the same rules: terse, `path:line`, one reason, no justifying padding.
- Frontend PR with no images in the description (`gh pr view <n> --json body -q .body`, look for `![` / `<img`) → add _"also this PR should have screenshots"_. Skip for backend-only PRs.

## 3. Shape each comment

1. **In diff + contiguous known fix** → inline with `suggestion` block, dot + one-line rationale under:

   ````
   ```suggestion
         onClick={closeMenu}
   ```
   🟢 closeMenu is already a stable useCallback, wrapping it in another arrow is needless allocation
   ````

   Delete dead code with an empty block + _"🟢 dead code"_.

2. **In diff + conceptual/non-contiguous fix** → inline prose (optionally an illustrative ` ```ts ` block), warning me off blind-committing if the diff is messy.
3. **Not in a file the PR touches** → summary body as `path:line` prose.
4. **About the whole file** - dead file, byte-for-byte duplicate, file in the wrong place, whole-mechanism praise → **file-level comment** (§4), never pinned to line 1 or an arbitrary line. Test per comment: would it read the same anchored to any other line of the file? Then it's file-level. Line-anchor only what's genuinely about that line.
5. **🟣 praise** per §2.

Merge near-duplicates; one comment per distinct issue - thorough, not piling on.

**Investigate before commenting.** If a draft comment would send the dev off researching (_"does X exist? could we use it?"_), check it yourself first - read the files and docs. Then propose the concrete fix, or **withdraw the comment** if the dev was right. Never post speculation you could have verified.

## 4. Build + post

One JSON payload: `body` (summary) + `comments` (`path`, `line`, `side`; add `start_line` + `start_side` for multi-line spans). Write to a temp file; validate with `python3 -m json.tool`. **Never send `event`** - omitting it creates the review in `PENDING` state; never `COMMENT`/`APPROVE`/`REQUEST_CHANGES`. `commit_id` must be the head SHA from §1 or comments anchor to a stale commit.

```json
{
  "commit_id": "<headRefOid>",
  "body": "<summary per §2>",
  "comments": [
    {
      "path": "src/types/organizations.ts",
      "line": 10,
      "side": "RIGHT",
      "body": "🟢 most of these can be inherited from the supabase types - saves the double maintenance burden"
    }
  ]
}
```

Before previewing, re-read every comment body and the summary against the bans above: em dashes, _not X but Y_, generic openers, filler. Fix them in the payload, not after posting.

One pending review per user per PR - a second one 422s. Check first:

```bash
gh api repos/<nameWithOwner>/pulls/<number>/reviews -q '.[] | select(.state=="PENDING") | .id'
```

Hit → tell me, and either add to it (`POST .../reviews/<id>/comments`) or delete it (`DELETE .../reviews/<id>`) on my call. Never delete a pending review unprompted.

Preview first - body + every comment with its `path:line` - and get explicit approval before posting. Then:

```bash
gh api repos/<nameWithOwner>/pulls/<number>/reviews --method POST \
  --input /tmp/pr-review-payload.json -q '{id:.id,node_id:.node_id,state:.state}'
```

Confirm the response shows `"state":"PENDING"`.

**File-level comments** (§3.4): the REST review payload only takes line anchors (`subject_type` isn't accepted there, and no `gh pr` subcommand does it) - attach them to the pending review afterwards via GraphQL; they land as part of the same review. Include them in the preview like any other comment, marked _(file-level)_:

```bash
gh api graphql -f query='
mutation($reviewId: ID!, $path: String!, $body: String!) {
  addPullRequestReviewThread(input: {
    pullRequestReviewId: $reviewId, path: $path, subjectType: FILE, body: $body
  }) { thread { id } }
}' -f reviewId=<node_id from POST response> -f path=<path> -f body=<comment>
```

Failures: 422 _"line must be part of the diff"_ → re-anchor to the nearest changed line or demote to the body; 422 on a suggestion → convert to a plain ` ```ts ` block in prose. If the head SHA moved since §1 (dev pushed mid-review), re-fetch it, re-check every anchor against the new diff, and re-preview before re-posting.

## 5. Wrap up

Write the full review **verbatim**, as markdown to `$(git rev-parse --show-toplevel)/pr-<number>-review.md`, led by _"Pending review posted - submit at <files-tab URL>"_. Report what went up: N inline comments (M with suggestions), anything demoted to the body, and the pick-up URL `https://github.com/<nameWithOwner>/pull/<number>/files`. Never submit, approve or request changes.
