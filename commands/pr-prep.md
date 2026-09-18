---
description: Prepare a concise PR and open it on GitHub against a base branch
argument-hint: "[base-branch] (default: main)"
allowed-tools: Bash(git*), Bash(gh*)
---

Open a pull request for the current branch against base `${1:-main}`.

Context to gather first (run these, do not guess):

- `git branch --show-current`
- `git log --oneline ${1:-main}..HEAD`
- `git diff --stat ${1:-main}...HEAD`
- `gh pr list --head <current-branch> --json number,url` - if a PR already exists, update its body with `gh pr edit` instead of creating a duplicate.
- Push the branch if it has unpushed commits (`git status -sb`).

Write the PR body to a temp file, then create with
`gh pr create --base ${1:-main} --head <current-branch> --title "<title>" --body-file <tmp>`.

Title: conventional-commit style, include the ticket id if the branch name carries one (e.g. `tozn-332` → `(TOZN-332)`).

## Language

The single biggest lever on quality. Aim for concise, direct, communicative, and above all **functional** language.

- Functional means: describe impact, not mechanism. The reviewer has the diff open - they can already see every line changed. Don't narrate it back to them ("moved the check to line 40, added an early return"); say what it does now ("auth check runs before the DB write"). Say as much as possible in as few words as possible.
- Same register as the voice section in `pr-comment.md` - short, direct, no hedging, one reason not three, point at exact things rather than describing around them. A PR body sits a notch more formal than a review comment though: no emoji, full bullet clauses rather than clipped fragments, sparing contractions. Don't copy it verbatim, translate the same discipline up one register.
- Cut like caveman would, without writing like one: drop filler (just / really / basically), drop hedges, cut any word that doesn't earn its place. Full sentences and normal English, just none of them wasted.
- No bold, no emphasis markup, no frontloading labels (`- The thing: description of the thing`) - jump straight into the point.

## Structure

Plain `##` headings, plain bullets throughout, no prose paragraphs.

- `## What` - 1-2 lines, plain statement of what this PR does and why it exists. If it can't be said in 1-2 lines, the PR is carrying too many concerns - say so, and offer to split it into multiple PRs before writing anything further.
- `## Changes` - what changed and why, bullets only, no prose. Multiple distinct concerns in one PR → break into subheadings, one per concern, each with its own tight bullet list.
- `## Closes` - ticket id, derived from branch when present.
- `## Notes` - only for a real caveat: deferred work, dormant routes, follow-ups. Drop the heading entirely if there's nothing to say. Do not refer to any local failures that have nothing to do with remote repo setup.
- Describe the actual diff, not assumptions. Base every bullet on the commits and diffstat you read, not on what you expect the branch to contain.

Report the PR url when done.

## Never

- "🤖 Generated with Claude Code"
- "Co-Authored-By: Claude" or any AI attribution, including "Claude session:" links
