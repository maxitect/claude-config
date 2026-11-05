# Worked examples

Four tickets and one plan row from a finished run, anonymised. Match their density and tone: every sentence carries a number, a name or a `file:line`, and nothing restates what the reader can see in the diff. Names, tables and figures below are placeholders; yours come from the repo.

## Security bug (outside the budget, filed first)

```markdown
# PROJ-CE9-BUG-01 Saved lists readable and editable by any signed-in user

> [!CAUTION]
> **Security.** Outside the CE9 budget lines. Pick up before any other CE9 work.

The baseline schema gives `lists` and `list_items` four `TO authenticated USING (true)` policies (`supabase/migrations/20260409140438_remote_schema.sql:2189-2233`) alongside the owner-check policies. Permissive policies are OR'd, so the owner checks do nothing: any signed-in user can read, rename, empty or delete anyone else's lists through the client with the publishable key.

`list_items` also carries two copies of every owner policy.

## Deliverables

- Migration dropping the four `Allow … for authenticated` policies on both tables
- Migration dropping the duplicate owner policies on `list_items`, leaving one per command
- Remaining owner policies scoped `TO authenticated` and using `(select auth.uid())` so they stop tripping lint 0003
- Covering index on `lists.user_id`
- `docs/schema.sql` regenerated (`pnpm db:schema`)

## Open questions

- Was list sharing ever intended? Nothing in the UI shares lists, so the `USING (true)` policies look like dashboard leftovers. If sharing is wanted later it needs its own policy, not these

## Files (indicative)

- `supabase/migrations/<timestamp>_fix_list_rls.sql` (new)
- `docs/schema.sql`

## Acceptance criteria

- Run against live `pg_policies` first: the dropped policies exist in production, or the ticket is closed as already fixed
- User A cannot select, insert into, update or delete user B's list or its items (checked with two real sessions against local Supabase)
- User A can still do all four on their own lists, and every `/lists` page works unchanged
- `get_advisors` shows no multiple-permissive-policy or auth-initplan warnings for either table

+0.25 day.

### Notes for dev

Check prod before writing the migration: the remote schema was pulled from the dashboard, so prod is the source of truth. Use `drop policy if exists` so the migration is safe either way.
```

What to copy: the first sentence names the exact policies with `file:line`; the mechanism is explained in one sentence ("permissive policies are OR'd"); the first criterion checks production; the criteria come in a pair (cannot / can still); the notes give the safe-migration trick.

## Parent ticket

```markdown
# PROJ-CE9-T02 Search efficiency and concurrent capacity

Parent for spreadsheet line **T02** in the CE9 tasklist (20261001). Plan: `docs/plans/ce9/README.md`.

<The goal in the client's words, then the incidents it must fix, with dates.>

- **Budget:** 3 days
- **Window:** 1 – 30 Oct 2026
- **Key deliverable:** Deployed to production.

Work is in the sub-issues. Their estimates add up to the budget.
```

The label on a parent is its budget (`3`); the label on a child is its estimate (`0.5`). Both also carry the contract label (`ce9`).

## Test ticket that turns incidents into scenarios

```markdown
# PROJ-CE9-T02-01 Load test that reproduces the slowdowns

Two real incidents give us the scenarios this phase has to pass. Without a repeatable load test we cannot show that T02-02 to T02-04 fixed them.

- **1 Jul 2026:** a workshop put about 40 users on the app at the same time and it became unusable. The database was idle during it (CPU 3%, 9 of 60 connections, no errors), so it was not the bottleneck
- **1 Oct 2026:** timeouts during a load spike. Field data showed LCP P50 2.9s, P90 4.7s, with 20% of page loads rated poor, concentrated on four pages

## Deliverables

- A k6 script in the repo with three scenarios:
  1. **Workshop:** 40 virtual users each opening a page, applying two filters, paging and opening a detail page, with realistic think time
  2. **Typing:** 40 virtual users typing into search one keystroke at a time (`AutoComplete.tsx`, `debounceMs={100}`)
  3. **Ramp:** step from 10 to 150 users to find where p95 passes 2s or errors start
- A baseline results table (p50/p95/p99, error rate, requests per second, CPU) per scenario in `docs/perf/baseline.md`

## Acceptance criteria

- The workshop scenario reproduces the slowdown on the current single-worker backend, proving the test is realistic
- Anyone can run the scenarios with one documented command
- Baseline numbers are recorded before any fix merges

+0.5 day.
```

What to copy: incidents become scenarios with dates and measured figures; the acceptance criteria prove the test itself works, and the baseline is ordered before the fixes it will judge.

## Spike

A spike's deliverable is a decision with evidence, not code to keep.

- Deliverables name the artefacts that make the decision checkable: a test set written before running anything (size, how it is split into tuning and held-back sets, where it is committed), the metrics per option, timings on the real target machine, and a short write-up at a named path, reviewed before the next ticket starts
- A `## Not in scope` section lists what was decided elsewhere, so the spike does not reopen it
- Acceptance criteria name the decision and the evidence it needs, and add "any change this causes to <later tickets> is made in those issues"
- Follow-on tickets say "assumes the spike picks X; adjust after"
- An estimate that grew carries a reason: `+0.5 day. The 10 extra queries over the original 20 are the held-back set.`
- A spike with a long protocol gets its own file `docs/plans/<code>/tNN/<ticket>.md`, linked from the first lines of the ticket as `Plan: <path>`

## Holding ticket for client-driven or time-boxed budget

```markdown
# PROJ-CE9-T11-01 Ongoing maintenance and ad-hoc enhancements (Oct 2026 – Mar 2027)

Holding ticket for the 6 days of maintenance support in CE9, running 1 Oct 2026 to 31 Mar 2027 with an office-hours SLA. Small fixes, dependency updates, incident response and minor enhancements are logged here or raised as sub-issues against it, so the budget can be reported on.

## Deliverables

- The SLA written down and agreed (response times in office hours, what counts as urgent, how to raise an issue)
- Dependabot and security alert triage at least monthly
- Each piece of work over 1 hour gets a sub-issue; smaller items are logged in a comment with date and time spent
- Monthly running total posted on this ticket

## Open questions

- SLA terms: proposed response within 1 working day for urgent issues and 3 working days otherwise, office hours Mon–Fri 09:00–17:30 UK. Agree with client

## Acceptance criteria

- SLA agreed and recorded on this ticket
- Time logged against this ticket does not pass 6 days without the client agreeing more

6 days (budget).
```

When the client's needs are unknown (an integration partner's API requests, say), the ticket holds the budget and the questions: each request becomes its own sub-issue with its own estimate once agreed. Its questions cover what they are building, which entities and fields, request volume and pattern, pagination, whether changes need announcing, and who the technical contact is. A hard date goes in a `> [!IMPORTANT]` callout at the top (`**Code freeze 20 Nov 2026.** Any API change must be deployed before then.`).

## Plan doc budget row

| Code | Work packet | Days | Window | Tickets |
| --- | --- | --- | --- | --- |
| T04 (#384) | Auto-deployment | 2 (+0.5 over) | 1–30 Oct 2026 | T04-01 versioned images (1), T04-02 deploy and rollback (0.5), T04-03 zero-downtime reindex (0.5), T04-04 image hardening (0.5, over budget) |

Below the table, one sentence on whether the window fits: "The 1–30 Oct window for T02, T04 and T05 leaves 10 days from today (20 Oct) for 6 days of work."

Open questions in the plan are numbered, each naming the ticket it blocks. When the client answers, strike the question through and add the answer and date: `~~third-party API, spare RAM~~ answered: self-hosted model; the server has the RAM (2 Nov 2026)`.
