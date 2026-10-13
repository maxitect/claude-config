# orchestrate

An agentic build over a folder of tickets, run from the repo it changes. One Opus orchestrator session (`/orchestrate <ticket dir> [team|solo]`) spawns a Sonnet `ticket-implementer` per ready ticket in its own worktree, then an Opus `ticket-reviewer` per PR. Generalised from the Ludwig build.

- team (default), for repos other people work in: draft PRs, marked ready for review once the reviewer clears them, never merged. Dependents stack on cleared parents.
- solo (the Ludwig flow): cleared PRs are squash-merged into the base, and dependents start from the base.

## Files

| File | Role |
|---|---|
| `SKILL.md` | The orchestrator's protocol. Its first block runs preflight, status and handover |
| `protocol.md` | What the agents share: scripts, verification methods, environment rules, report and ticket format |
| `_TEMPLATE.md` | Ticket template |
| `scripts/lib.sh` | Ticket parsing, stack detection (pnpm, yarn, bun, npm, poetry, uv; Supabase, compose, Neon), gates, slots, locks |
| `scripts/*.sh` | `preflight`, `setup`, `gates`, `stop-check`, `status`, `ready` (team), `merge` (solo), `restack`, `sweep`, `handover` |
| `~/.claude/agents/ticket-implementer.md`, `ticket-reviewer.md` | The agents. The implementer's Stop hook is `scripts/stop-check.sh` |

The scripts reuse `_shared/_cap.sh`, and `pr-sweep/scripts/patch_supabase.py` for per-ticket Supabase stacks. The reviewer runs `/pr-review`, so its stack detection applies there too. Scripts target the macOS system bash (3.2), so there are no associative arrays.

## Using it in a repo

1. Write tickets as `<dir>/<id>-<slug>.md` from `_TEMPLATE.md`. Set `depends_on`, and `serial` tags for files several tickets edit.
2. Add `<dir>/orchestrate.env` (below), and `<dir>/INSTRUCTIONS.md` for repo-specific agent rules (seed users, platform IDs, what never to touch).
3. Make sure `.claude/worktrees/` is git-ignored. The ticket dir can be committed or local-only (add it to `.git/info/exclude`); either way agents read it from the main checkout and never commit it.
4. Run `/model opus` (the skill's `model: opus` only holds for the turn that invokes it; later turns, such as agent hand-backs, use the session model). Check out the base branch in the main checkout, clean and pushed, and run `/orchestrate <dir>` (team) or `/orchestrate <dir> solo`. Add a number to cap the session, e.g. `/orchestrate <dir> 2` for a trial run on two tickets. Re-run it for each session; the handover carries context between sessions.

## orchestrate.env

Shell assignments, sourced by every script. All are optional.

| Var | Default | Meaning |
|---|---|---|
| `ORCH_BASE` | the repo's default branch | The branch unstacked ticket PRs target (and, in solo mode, merge into) |
| `ORCH_MODE` | `team` | `team` or `solo`. The skill argument overrides it for that session |
| `ORCH_PARALLEL` | 3 | Implementers in flight at once |
| `ORCH_BRANCH_TYPE` | `feat` | Branch prefix for tickets without a `type`: branches are `<type>/<id>-<slug>` |
| `ORCH_PR_LABELS` | none | Comma-separated labels `ready.sh`/`merge.sh` add before checks (e.g. a repo's ticket-check opt-out) |
| `ORCH_SESSION_TICKETS` | 6 | Tickets taken to ready for review (team) or merged (solo) per session. `0` means no cap. The skill's numeric argument overrides it |
| `ORCH_SLOTS` | 2 | Concurrent per-ticket Supabase stacks (`migrations: true` or `own_db: true` tickets) |
| `ORCH_GATES` | detected | `"name=cmd;name=cmd"`, replacing the detected build, typecheck, lint and test scripts |
| `ORCH_SETUP` | none | Command run after install in preflight and in every worktree (e.g. type generation) |
| `ORCH_PREFLIGHT_GATES` | 1 | `0` skips the gates in preflight |
| `ORCH_NEON_PROJECT` | none | Neon project id: preflight checks `neonctl`, and sweep deletes merged tickets' `preview/ticket/*` branches |
| `ORCH_MIGRATION_PATHS` | `supabase/migrations/ drizzle/ migrations/ alembic/ prisma/migrations/` | Paths that make a base change force a rebase, and that trigger `supabase migration up` after a merge |
| `ORCH_SEED_PATHS` | `supabase/seed supabase/seeds/` | Also trigger the post-merge migration sync |
| `ORCH_PROD_PATHS` | none | Paths whose merge adds a "check the deployed build" note |
| `ORCH_CHECK_TIMEOUT`, `ORCH_GATE_TIMEOUT` | 1200, 1200 | Seconds |

## Stacking (team mode)

A child starts only once its reviewer-cleared parent is ready for review. The parent's code has stopped moving by then, so the child never rebases mid-build on agent fixes. When a human later pushes review fixes to the parent, or merges it, `status.sh` flags the child `RESTACK`. `restack.sh` then rebases it onto the parent's new tip, or onto the parent's base after a squash merge, and retargets the PR. It finds the fork point from the `PARENT_TIP` that `setup.sh` recorded, so it is never confused by a squash merge.

A PR has one base, so a ticket with two or more cleared-but-unmerged parents waits until a human merges all but one of them. The orchestrator's wind-down summary names the merges that would unblock the most tickets.

When a parent has exactly one stacked child, `ready.sh` also groups the pair on GitHub with `gh stack link`, so reviewers get the stack view. A parent with several children stays a plain base-chained tree, since gh-stack stacks are linear. Humans can then use `gh stack sync` and `gh stack merge` on the grouped chains.

Solo mode never stacks: dependents wait for the merge and branch from the base.
