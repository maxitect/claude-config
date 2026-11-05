---
name: plan-tickets
description: Turn a contract phase (extension, change request, new award) into investigated, estimated tickets for the current repo, as GitHub issues, markdown files in the repo, or Jira issues. Reads the scoping spreadsheet plus any supporting material the user points to (fee proposal, SoW, functional design, Drive folders, client emails), always searches Gmail for client context, investigates the codebase per work item, asks only what the sources cannot answer, then creates parent tickets with children and one overview plan doc.
argument-hint: "<contract code, e.g. CE3 or CE4> [--to github|repo|jira[:<project key>]] [links, file paths or hints on where to look]"
disable-model-invocation: true
---

# Plan tickets for a contract phase

Arguments: `$ARGUMENTS`. The first token is the contract code (`CE3`, `CE4`…). `--to` picks the destination. Everything else is links, local paths or hints ("emails with the client contact since September", "fee proposal in the client folder"). If no code is given, ask for it before anything else.

## Destination

Without `--to`, infer it and say which in one line: `docs/tickets/` with a `_TEMPLATE.md` means `repo`; earlier issues titled `<PROJECT>-<CODE>-…` mean `github`; a Jira key in the hints or earlier tickets means `jira`. If none of those hold, ask. Never write the same tickets to two destinations: one single source of truth.

| Destination | Body format | Consumed by |
| --- | --- | --- |
| `github` | [ticket-template.md](ticket-template.md) | the repo's ticket skill (for example `/ticket`) |
| `repo` | the repo's `docs/tickets/_TEMPLATE.md` and `INSTRUCTIONS.md`, frontmatter included; [ticket-template.md](ticket-template.md) only where they are silent | `/orchestrate` and its implementer agents |
| `jira` | [ticket-template.md](ticket-template.md) converted to Jira's format (`getContentFormatGuide`) | Jira board |

Whatever the destination, read the skill or agent that will consume the tickets and keep every field and section it parses.

When in doubt about shape or tone, open two or three recent tickets in the repo and match them.

## 1. Gather sources

Read everything before planning. Note each fact's source so conflicts can be resolved by precedence.

**Precedence:** the scoping/estimates spreadsheet is ground truth for line codes, budgets (days) and dates. Signed SoW or fee proposal next, then the functional design, then emails. Never invent a deadline or budget; if a ticket needs a date the sources don't give, leave it out.

- **Local files:** read the paths given and any spreadsheet/PDF/docx in the repo root that looks like scoping material (`xlsx`, `pdf` and `docx` skills). For a workbook, find the sheet the user means; if several look current, ask which.
- **Google Drive / Docs / Sheets:** read every link given. For a hint without a link, `search_files` on the project and client names, then confirm the hit with the user only if more than one plausible file comes back. Read Sheets with `get_values`, Docs with `read_doc`.
- **Gmail, always, even if the user gave no hint.** Search threads with the client contacts and project name over the period since the last contract started (`search_threads`, then `get_thread` on the relevant ones). Look for: scope added or dropped after the spreadsheet, priorities, deadlines, data the client promised to send, approvals still pending, technical constraints (hosting, data egress, design standards), and anything said in confidence. Pasted chat logs or call notes from the user count as the same kind of source.
- **Repo context:** `CLAUDE.md`, `docs/` (plans, ADRs, database rules, runbooks), the previous contract's plan doc, and open issues (`gh issue list --state all`) so nothing is duplicated and carried-over work is visible.

Read-only throughout: never send, draft or label email, and never edit a Drive file in this skill.

## 2. Investigate each work item

For every spreadsheet line, find out what the code does today before deciding what to build. Fan out one read-only `Explore` agent per group of related lines (2–4 lines each), in parallel, each told to return file:line evidence of current state, gaps, blockers and bugs found on the way. Read their findings; spot-check anything a ticket will rest on.

Things to look for:

- **Security holes found while investigating** (RLS too open, leaked keys, open proxies) become separate `BUG` tickets outside the budget lines, flagged top priority, with a `> [!CAUTION]` callout. Don't hide them in a maintenance budget.
- **Existing bugs next to the work** go in that ticket's deliverables as "Existing bug fixed while here" if they are small; otherwise their own `BUG` ticket.
- **Data the client must supply** (category mappings, hierarchies, approvals) gets a `## Blocked on` section naming who supplies it and the exact format to ask for (for example "a CSV of record IDs plus the required flags").
- **Production may differ from the repo** (schema pulled from a dashboard, hand-deployed servers). Say so in the ticket and make "check production first" the first acceptance criterion.
- **Reusable work in sibling projects.** Ask the user which other repos solved similar problems and point the ticket at the exact files.

## 3. Ask, once, in batches

Ask only what the sources and code can't answer, with `AskUserQuestion`, up to four questions per call, recommended option first. Put the evidence in the question so it stands alone. Typical questions:

- Lines with 0 days or marked optional: skip, defer or ticket?
- Non-dev lines: make handover real tickets, maintenance one holding ticket for logging time, and skip optional extension months.
- How things work today when the repo can't tell (deploy method, hosting, who approves).
- Where a technical choice is still open: **don't prescribe it**. If the user's answer is "not sure yet" or the right choice needs measurement (models, chunk sizes, libraries), make a spike ticket that compares options against real data, and write the follow-on tickets as "assumes the spike picks X; adjust after".

Questions only the client can answer go in the plan doc's open questions, not to the user.

## 4. Shape the tickets

**IDs and titles:** `<PROJECT>-<CODE>-<Txx-yy> <Title>`, keeping the spreadsheet line code (`PROJ-CODE-T02-01 Load test that reproduces the slowdowns`). Parent per spreadsheet line: `<PROJECT>-<CODE>-<Txx> <Line title>`. Bugs: `<PROJECT>-<CODE>-BUG-yy`. Titles say the outcome in plain words, not the mechanism. Ask the user for the project prefix if the repo has no earlier tickets that show it.

**Estimates:** in days, in 0.25 steps. Children of a line add up to that line's budget. Work you think is needed but isn't budgeted goes in as its own ticket marked "over budget" in the plan table, never squeezed into another estimate. Nice-to-haves go in titled "(stretch)" or "(stretch, deprioritised)".

**Body:** in the destination's format (see Destination). Acceptance criteria are checkable outcomes, each provable by a test or a stated manual check, and realistic at the data scale the client will have, not today's. For `repo`, give each criterion its verify method as the template asks, and number files `Tnnn-<slug>.md` after the highest existing id.

**Parents:** short: which spreadsheet line, the goal in client words, budget, window, key deliverable, and "Work is in the sub-issues".

**Order:** work out dependencies across all tickets; they drive the `## Depends on` sections and the plan doc's suggested order.

## 5. Review with the user, then create

Draft every body in the scratchpad. Show the user a table: ID, title, estimate, depends on, and anything over budget, blocked or a spike. Wait for approval; remote tickets are outward-facing.

**`repo`:** move the approved files into `docs/tickets/`, update its README index if it has one, and commit them with the plan doc.

**`jira`:** load the Atlassian tools, check the project's issue types and fields (`getJiraProjectIssueTypesMetadata`), and map parent to Epic and child to Story/Task, or to whatever the project already uses. Put the estimate in the field the project uses for it (ask if unclear), link dependencies with `createIssueLink` ("blocks"), and rewrite ID references to Jira keys.

**`github`:**

1. Create missing labels: the contract code (lower case, e.g. `ce3`) and one label per estimate value used (`0.25`, `0.5`… with description "Estimated to take N days"). Reuse existing ones.
2. Create bugs, then each parent followed by its children, with `gh issue create --body-file`, labels `<code>,<estimate>` (plus `bug` for bugs). Record each ID → number.
3. Link children as sub-issues: `gh api -X POST repos/<owner>/<repo>/issues/<parent>/sub_issues -F sub_issue_id=<child database id>`.
4. Rewrite every `<PROJECT>-<CODE>-…` reference in the bodies to `ID (#n)` and `gh issue edit` the ones that changed.
5. Add each issue to the GitHub project board if the repo uses one (ask which; use `gh project item-add <number> --owner <org>`).

## 6. Plan doc

Write `docs/plans/<code lower>/README.md` (or the repo's existing plan file, such as `docs/PLAN.md`, for `repo`), overview only, never ticket detail:

- Source: file name and sheet, total days, what's excluded
- Budget table: code (#parent), work packet, days (with "+N over"), window, child tickets with estimates
- Lines not ticketed and why
- Suggested order as a small text graph
- What the scoping found, one short section per line, with the evidence that shaped the tickets
- Open questions for the client, numbered, each tagged with the ticket it blocks

Commit it with the `commit` skill on a `docs/` branch. Don't commit the source spreadsheets or client documents.

## Report

Reply with the issue range, the parent numbers, totals against budget (and anything over), the tickets blocked on the client, and the client questions, so the user can send them on.
