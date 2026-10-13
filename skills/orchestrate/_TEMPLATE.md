---
id: T00
title: Short imperative title
type: feat
depends_on: []
serial: []
migrations: false
own_db: false
requires_human: false
skills: []
---

# T00: Short imperative title

## Context

One or two sentences on why this ticket exists and where it sits in the plan. Link the docs it builds on; don't copy them.

## Scope

In

- Concrete deliverables: files, routes, tables, components, tests.

Out

- Things a reader might expect here that belong to another ticket (name the ticket).

## Notes

Only what isn't already in the repo's docs, `CLAUDE.md` or the rules: gotchas, decisions taken for this ticket, and docs to read.

## Acceptance criteria

- [ ] AC1: An observable outcome, stated as a fact.
  - _Verify (db):_ `psql "$DB_URL" -c "…"` returns …
- [ ] AC2: …
  - _Verify (browser):_ Navigate to `/…`, do …, and expect ….
- [ ] ACn: The gates pass.
  - _Verify (cli):_ `~/.claude/skills/orchestrate/scripts/gates.sh` prints `GATES PASS`.
