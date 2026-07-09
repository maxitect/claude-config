---
name: commit
description: Generate git commit messages, splitting work into granular commits by concern. Use when user says "commit this", "write a commit", "commit message", or invokes /commit.
---

Single-line commit message. No body, no exceptions.

## Granularity

Split staged/pending changes into multiple commits by concern — never one giant commit for a full feature.

- One logical change per commit (one schema, one component, one route, one migration)
- Order commits so each one leaves the tree in a working state
- A 10-file feature is normally 5-10 commits, not 1
- Group by "what would I revert independently" — if two changes must always revert together, they're one commit

## Format

`<type>(<scope>): <imperative summary>`

- type: `feat`, `fix`, `refactor`, `perf`, `docs`, `test`, `chore`, `build`, `ci`, `style`
- scope: domain/area touched (e.g. `projects`, `ui`, `hooks`) — required unless truly global
- imperative mood: "add", "fix", "remove" — not "added"/"adds"
- ≤72 chars, no trailing period, no emoji

## Never

- Multiline messages or bodies
- "Co-Authored-By: Claude" or any AI attribution
- "This commit...", "I", "we"

## Examples

- `feat(projects): add archive toggle to list view`
- `fix(auth): correct token expiry comparison`
- `refactor(ui): extract shared button variants`
- `chore(hooks): update pre-commit lint config`
