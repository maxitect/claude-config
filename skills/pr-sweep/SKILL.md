---
name: pr-sweep
description: Review every open PR in the current repo. Scripts build an isolated worktree per PR (its own Supabase stack for migration PRs, max 3), headless Opus reviewers probe and report, Sonnet writes the comments, and each lands as a PENDING review. Reviewer sessions stay resumable for questions.
argument-hint: "[mine] [<pr number>...]"
disable-model-invocation: true
model: sonnet
allowed-tools: Bash(${CLAUDE_SKILL_DIR}/scripts/*), Read
---

# PR sweep (orchestrator)

You coordinate. Scripts do the deterministic work and headless reviewer sessions do the reviewing. You never review code, edit files, post to GitHub or answer questions about a PR's code yourself.

Every script prints one `<STAGE> PASS` line or `<STAGE> FAIL: <reason>` with a short tail and a log path. Read the log only when the tail isn't enough. Scripts live in `${CLAUDE_SKILL_DIR}/scripts/`.

## 1. Preflight

Run `preflight.sh` with a 10-minute Bash timeout (it may start the base Supabase stack). On `PREFLIGHT FAIL`, show it to the user and stop: no investigation, no fixes. Relay any `note:` lines.

## 2. Discover

Run `discover.sh $ARGUMENTS`. `mine` limits it to PRs assigned to me; PR numbers queue exactly those. Show the `queue` and `skip` lines as they are. Queue empty: run `status.sh`, show it and stop.

## 3. Run the queue

For each queued PR, run `run.sh <n>` with `run_in_background: true`. It does prepare, review, validate, comment and post, and frees the PR's stack when done.

- Keep at most **4** PRs in flight, and at most **3** of them `MIG`. `run.sh` waits for a free Supabase slot, but a waiting run still holds one of the 4 places.
- Launch `MIG` PRs first: they take longest.
- Wait for completion notifications. Never poll, and never read a run's files while it's going.

When one finishes, read its last line:

- `RUN PASS`: note the review URL and the resume command.
- `RUN FAIL ... at <stage>`: if the tail shows a transient cause (network, a GitHub 5xx, a timeout), re-run `run.sh <n>` once; it resumes from that stage. Otherwise park the PR. `POST FAIL ... pending review` means the user already holds a pending review on that PR: park it and say so.

## 4. Report

When nothing is in flight, run `status.sh` and reply with one line per PR: number, title, finding counts from its `REVIEW PASS` line, the review URL, then the parked PRs with their reason. Then add:

> Pending reviews are on GitHub; nothing was submitted. Ask me about any PR (e.g. "#123 why is the RLS finding critical?"), or open its reviewer directly with the resume command.

## 5. Questions while the user reviews

Stay available. The reviewer sessions hold the context, so route every question to them:

- A question about PR #n: run `ask.sh <n> "<question, verbatim>"` (10-minute timeout) and relay the answer unchanged. Follow-ups go the same way.
- The user wants to talk to the reviewer directly: run `open.sh <n>` and give them its command to run in another terminal. While they have it open, don't `ask.sh` that PR.
- Done with a migration PR: `teardown.sh <n>` frees its Supabase slot. Worktrees of merged or closed PRs are removed by the next preflight.
- A request to re-review after new commits: run `discover.sh <n>`, then `run.sh <n>`. It archives the previous head's artefacts and starts a new reviewer session.
