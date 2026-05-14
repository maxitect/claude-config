---
name: address-pr-comments
description: Methodically work through PR review comments one-by-one. Fetches comments via gh CLI, explains each reviewer comment, assesses its validity, proposes a solution, waits for user approval, implements, then moves to the next comment.
---

# Address PR Comments Skill

You are in PR review triage mode. Work through reviewer comments methodically — one at a time — until all are resolved.

## 1. Find the PR

Run these commands to identify the PR for the current branch:

```bash
# Get current branch
git branch --show-current

# Find associated PR
gh pr view --json number,title,url,state,reviewDecision,reviews
```

If no PR found, tell user and stop.

## 2. Fetch All Review Comments

```bash
# Get all review comments (inline code comments)
gh pr view <PR_NUMBER> --json reviews,comments

# Get inline review thread comments
gh api repos/{owner}/{repo}/pulls/<PR_NUMBER>/comments --jq '[.[] | {id: .id, path: .path, line: .line, body: .body, user: .user.login, created_at: .created_at}]'

# Get PR-level review comments (not inline)
gh api repos/{owner}/{repo}/pulls/<PR_NUMBER>/reviews --jq '[.[] | select(.state == "CHANGES_REQUESTED" or .body != "") | {id: .id, state: .state, body: .body, user: .user.login, submitted_at: .submitted_at}]'
```

Deduplicate. Build ordered list of all unresolved comments. Number them.

## 3. For Each Comment — Follow This Loop

Work through comments in order. Do NOT batch or skip.

### Step A: Present the Comment

Show:

- **Comment #N of Total**
- Reviewer name
- File + line (if inline)
- Exact quoted comment text

### Step B: Explain What the Reviewer Means

Translate reviewer intent into plain language. If the comment is terse or uses jargon, unpack it. Reference the actual code at that file/line so the explanation is grounded.

### Step C: Assess the Comment

Judge the reviewer's point:

- **Valid** — correct, important, should address
- **Valid but minor** — correct but low stakes (style, nitpick)
- **Debatable** — reasonable people disagree; explain both sides
- **Incorrect** — reviewer is mistaken; explain why

Give your honest assessment. Don't rubber-stamp every comment.

### Step D: Propose a Solution

Propose the specific change to address the comment:

- Show the current code (quoted from file)
- Show the proposed change
- Explain why this addresses the reviewer's concern

If the comment is debatable or incorrect, propose how to respond to the reviewer instead of (or alongside) a code change.

### Step E: Wait for User Response

Stop. Wait for user to:

- Approve the proposal → implement it
- Modify the proposal → adjust and confirm before implementing
- Reject / skip → note why and move on
- Push back on your assessment → discuss, then proceed

Do NOT implement until user confirms.

### Step F: Implement

Once approved:

- Make the exact change discussed — no scope creep
- Do NOT refactor surrounding code
- Do NOT "improve" adjacent things
- Confirm implementation done, show diff summary

Then immediately move to next comment.

## 4. Tracking Progress

Keep a running count visible: **"Comment N of Total — X resolved, Y skipped, Z pending"**

After all comments addressed, summarise:

- Resolved (with what was changed)
- Skipped (with reason)
- Any comments that require a reply to reviewer rather than code change

## 5. Repo Context for gh CLI

To get owner/repo for API calls:

```bash
gh repo view --json owner,name --jq '"\(.owner.login)/\(.name)"'
```

## Rules

- ❌ Never batch multiple comments into one implementation
- ❌ Never implement without user confirmation
- ❌ Never touch code outside the specific change discussed
- ❌ Never skip a comment without noting it
- ✅ Read the actual file at the referenced line before explaining
- ✅ Give honest assessment — push back on weak reviewer comments
- ✅ Keep proposals minimal and scoped
