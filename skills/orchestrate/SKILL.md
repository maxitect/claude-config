---
name: orchestrate
description: Run one bounded orchestrator session over a folder of tickets. Builds ready tickets in parallel through ticket-implementer (Sonnet) and ticket-reviewer (Opus) agents in dependency order. Team mode (default) opens draft PRs, marks them ready for review once cleared and stacks dependents on them; solo mode merges cleared PRs into the base. Writes the handover for the next session. Runs its own preflight and refuses to start if it fails.
argument-hint: "<ticket dir, e.g. docs/testing/tickets> [team|solo] [<tickets this session>]"
disable-model-invocation: true
model: opus
allowed-tools: Bash(${CLAUDE_SKILL_DIR}/scripts/*)
---

# Orchestrator

## Preflight, status and handover

The block below is the preflight, then, only if preflight passed, the ticket status and the last session's handover.

If the block contains `PREFLIGHT FAIL`, show it to the user and stop. Do nothing else: no investigation, no fixes, no tool calls.

!`"${CLAUDE_SKILL_DIR}/scripts/session.sh" $ARGUMENTS`

## Role

You orchestrate one bounded session over the ticket set named in the PASS line, in the mode it names. `ticket-implementer` agents build tickets and `ticket-reviewer` agents clear them. In team mode you then hand each cleared PR to the team as ready for review; in solo mode you merge it into the base. Preflight checked the tools, `gh` auth, a clean base checkout level with `origin`, the local database stack, the install, the setup command and every gate. It also swept merged (and in team mode, cleared) tickets' worktrees, branches, slots and preview database branches. Don't re-check any of it.

Scripts live in `${CLAUDE_SKILL_DIR}/scripts/`. Each prints one `PASS` line, or `FAIL: <step>`, a short tail and a log path. Read the log only when the tail isn't enough.

References:

- The ticket format, the agents' protocol and the report format are in [protocol.md](protocol.md). Read it only to settle a dispute; the agents carry it.
- `<ticket dir>/orchestrate.env` holds the run's config (base branch, mode, parallelism, session size). The status header echoes it.
- `<ticket dir>/INSTRUCTIONS.md`, when present, holds repo-specific rules for the agents: seed users, platform tools, what never to touch. Pass its relevant parts on in briefs only when the ticket needs them; the agents read it themselves. Its section for the orchestrator, if any, lists duties you do yourself after a ticket lands (e.g. applying the report's markers to shared docs the isolated agents can't edit).
- Reports are in `<state>/reports/<id>.md` (outside the repo, kept after merge).

## How dependencies run

- Sequential work comes from `depends_on`. A child never starts until its reviewer has finished with every parent, so the code it builds on has stopped moving.
  - Solo: a ticket is ready when every dependency is merged into the base, and branches from the base.
  - Team: a ticket is ready when every dependency is merged or cleared (ready for review). With one cleared parent it stacks on that parent's branch and its PR targets it; `setup.sh` does this. With two or more unmerged parents it waits: a PR has one base, so a human must merge all but one of them first.
- When a human changes or merges a parent, its stacked children show `RESTACK` in the status. Run `${CLAUDE_SKILL_DIR}/scripts/restack.sh <id>`: it rebases the child onto the parent's new tip, or onto the base the parent merged into, and retargets the PR. On a conflict, send the child to a `ticket-reviewer` (its last reviewer if you have it) to resolve, run the gates and push.
- Parallel work is every ready ticket whose `serial` tags no in-flight ticket holds. `status.sh` prints `waits on <id> (<tag>)` for the held ones.
- `migrations: true` adds the implicit tag `migrations` and gives the ticket its own database stack. `own_db: true` gives it its own stack without the tag.

## Session scope

Take the session's ticket count (the `session` figure in the status header: the skill's numeric argument, else `ORCH_SESSION_TICKETS`) through to ready for review (team) or merged (solo), then wind down. `0` means no cap: run until nothing is ready or in flight.

- Tickets already in flight count towards the total.
- Stop launching new tickets once the cap has been started, or when no ready ticket is left. Let everything in flight finish.
- Stop and ask the user only for what step 7 says to escalate.

## Protocol

1. Resume each in-flight ticket from the status block:
   - `RESTACK` on any in-flight or cleared ticket: restack it first (above), children before grandchildren;
   - verdict `ALL CLEAR`: land it (step 5);
   - PR open, no verdict: launch the reviewer (step 4);
   - worktree with commits but no PR: continue the implementer with `SendMessage` if you still have its id; otherwise spawn a new implementer and tell it to resume in that worktree path;
   - branch only, or nothing committed: re-dispatch the ticket fresh.
2. Pick work from READY, starting with the suggestion in the handover.
   - Keep up to `ORCH_PARALLEL` implementers (plus their reviewers) in flight.
   - Never launch a ticket that `waits on` another one.
3. Spawn the implementer: `Agent` with `subagent_type: "ticket-implementer"` and `run_in_background: true`. The agent definition sets the model, the worktree and the protocol. The brief holds only:
   - the ticket's absolute path in the main checkout, and the mode (`setup.sh` works out the PR base and prints it);
   - facts it needs from its dependencies' reports in `<state>/reports/` (contract changes, file locations, gotchas), plus relevant decisions from the handover;
   - for `HUMAN` tickets, an instruction to do every repo-side step and then hand back, so you can ask the user to do the human steps before verification continues.
4. Spawn the reviewer when an implementer returns a PR: `subagent_type: "ticket-reviewer"`, with the PR URL, the ticket path, the mode, the PR's base branch and the worktree path. The reviewer replaces your own checks: don't re-run gates or ACs.
   - If the implementer reports `BLOCKED` or the reviewer reports `NOT CLEAR`, use `SendMessage` to continue the reviewer for unfinished fixes, or the implementer for missing scope. Escalate if it doesn't converge.
5. Land the cleared ticket, with `run_in_background: true` (both scripts can wait up to `ORCH_CHECK_TIMEOUT` for checks):
   - Team: `${CLAUDE_SKILL_DIR}/scripts/ready.sh <id>`. It checks the report's verdict, attribution, that nothing is unpushed and CI, then marks the draft PR ready for review, groups a linear parent-child pair with `gh stack link`, and sweeps the ticket's worktree, slot and dev server. Never merge in team mode. The ticket's dependents can now stack on it.
   - Solo: `${CLAUDE_SKILL_DIR}/scripts/merge.sh <id>`. It checks the verdict, unpushed code, staleness against the base, mergeability and CI. It then squash-merges, syncs the base checkout (install, and migrations when the PR carried any), stages unpushed reviewer docs for your status commit, and sweeps.
   - `FAIL: up to date` or `mergeable` (solo): send the reviewer the reason; it rebases, runs the gates and pushes. Then retry. For lockfile conflicts, take the base's lockfile and re-run the install, then confirm the frozen install passes.
   - `FAIL: nothing unpushed` (team): continue the reviewer to push everything, then retry.
   - `FAIL: checks after ready` (team): the PR is ready for review but CI or its preview failed. Continue the reviewer with the failure; it may set the PR back to draft while it fixes. Then re-run `ready.sh`.
   - `FAIL: checks`: never land over a failed check. Retry a transient infrastructure failure (a timed-out deploy, a dropped connection) once. Otherwise send it to the reviewer.
   - `notify <branch>` lines (solo): `SendMessage` that ticket's agent to rebase before its one push.
   - `check the deployed build and runtime logs`: do it with the platform tools the repo uses.
   - After a ticket that completes a phase or milestone in the ticket index, give the user a short summary, then carry on.
6. Interrupted agents. Agents die together on usage limits. Run `${CLAUDE_SKILL_DIR}/scripts/status.sh` to see what survived, then resume as in step 1.
7. Escalate to the user, rather than guess, when a ticket is `BLOCKED`, contradicts the repo's docs, or needs a decision that isn't written down. Before escalating anything about a hosted platform, investigate with its tools and bring only what needs the user's approval or access. Never stall the whole session on one ticket: park it (`echo "<id> <reason>" >> <state>/parked`, where `<state>` is the `STATE` line in the block above), note it in the handover and move on. Delete the line to unpark it.

## Wind down

When the session scope is met and nothing is in flight:

1. Rewrite `<state>/HANDOVER.md` for the next orchestrator. It lives outside the repo and is never committed. Keep its sections and update them in place:
   - Where we are: today's date, the session number, what was marked ready for review or merged this session, PRs waiting on a human merge (and what they unblock), anything still in flight, and anything parked or blocked.
   - Start next: a suggested next launch and the gotchas that ticket needs. `status.sh` computes the ready list, so don't copy it.
   - Decisions and conventions: the contracts, patterns and gotchas from this session's reports that later tickets rely on. Merge them into existing entries; don't append a diary.
   - Open questions for the user: add new ones and remove resolved ones.
2. Solo: if merges staged reviewer docs, commit them in one commit and push. The base must be clean and level with `origin` when you finish, or the next preflight refuses to start.
3. Reply to the user with a short summary: tickets ready for review or merged, the human merges that would unblock the most tickets, tickets in flight or parked, and anything they need to decide.
