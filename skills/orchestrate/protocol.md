# Ticket protocol

The shared reference for the `/orchestrate` build, in any repo. The roles are defined elsewhere:

- Orchestrator: the `/orchestrate` skill (`SKILL.md`, next to this file).
- Implementer: `~/.claude/agents/ticket-implementer.md` (Sonnet, in its own worktree).
- Reviewer: `~/.claude/agents/ticket-reviewer.md` (Opus, in the implementer's worktree).

What to build and how the code should look is defined by the ticket, the repo's `CLAUDE.md` and `.claude/rules/` (which load automatically), the docs the ticket cites, and `<ticket dir>/INSTRUCTIONS.md` when present. That file holds repo-specific rules: seed users, platform tools and what never to touch. It outranks this file wherever they disagree. Don't restate any of these documents in reports or code comments. Follow them.

`$S` below means `~/.claude/skills/orchestrate/scripts`.

## 1. Scripts

Each prints one `PASS` line, or `FAIL: <step>`, the last lines of output and the path of the full log. Read the log only when the tail isn't enough.

| Script | Who runs it | What it does |
|---|---|---|
| `$S/preflight.sh <dir> [team\|solo] [<n>]` | orchestrator (the skill runs it) | Checks tools, auth and the base checkout, starts the local database stack, sweeps, installs and runs the gates. Records `<dir>`, the mode and the session's ticket cap as the active run |
| `$S/setup.sh <id>` | implementer, in its worktree | Names the branch `<type>/<id>-<slug>` and starts it from its PR base (the run's base, or in team mode the cleared parent it stacks on), copies the local env files (remapping `:3000` to the ticket's port), starts the ticket's own Supabase stack when it has `migrations: true` or `own_db: true`, installs and runs the repo's setup command. Prints the PR base, the `/pr-prep` command, the port, `DB_URL` and artefacts dir. Idempotent |
| `$S/gates.sh` | implementer, reviewer | Runs the repo's gates (build, typecheck, lint, test, or `ORCH_GATES`), one worktree at a time machine-wide, and records the tree they passed on |
| `$S/stop-check.sh` | the implementer's Stop hook | Blocks finishing until the report is committed, the gates passed on the current code, and the PR is open against its base (a draft in team mode), pushed and free of AI attribution |
| `$S/status.sh` | orchestrator | In-flight and cleared tickets (PR, report, verdict, worktree, restack needed), ready tickets with where they branch from and any hold, parked tickets, and counts |
| `$S/ready.sh <id>` | orchestrator, team mode | Verdict, attribution, unpushed and CI checks, then marks the draft PR ready for review and sweeps its worktree |
| `$S/merge.sh <id>` | orchestrator, solo mode | Verdict, staleness, mergeability and CI checks, then squash-merges into the base, syncs it and sweeps |
| `$S/restack.sh <id>` | orchestrator | Rebases a stacked ticket onto its parent's new tip, or onto the parent's base once the parent merged, and retargets the PR |
| `$S/sweep.sh` | preflight, ready, merge | Removes merged tickets' worktrees, branches, slots, dev servers and Neon preview branches; in team mode frees cleared tickets' worktrees too |

State lives outside the repo in `~/orchestrate/<owner>__<repo>/`: the per-ticket `env` (port, `DB_URL`, `PR_BASE`, `PARENT_TIP`), logs, `gates.ok` and `artefacts/`, plus `reports/`, `HANDOVER.md` and `parked`.

A worktree-isolated implementer can read anything, but it can write in the repository only inside its own worktree. Write files outside the repo (reports, artefacts) with Write or a simple Bash command. Never edit the main checkout: if a ticket asks for a change to a file there (e.g. a shared planning doc), record it in the report for the orchestrator to apply.

### Modes

- team (default): PRs open as drafts. Once the reviewer clears one, the orchestrator marks it ready for review and never merges. A ticket whose dependencies are all merged or cleared starts, stacking on its one cleared parent if it has one.
- solo: the orchestrator squash-merges cleared PRs into the base, and dependents start from the base.

## 2. Verification

### 2.1 Gates

`$S/gates.sh` must pass before AC verification and before every push. A failing test is a failed AC.

### 2.2 Methods

Each AC names one or more methods, and each method sets the tools you must use. Mocks are not a substitute.

| Method | How to verify | Evidence to capture |
|---|---|---|
| `db` | Query the database `setup.sh` printed: `psql "$DB_URL" -c "…"`. Use a transaction for negative tests and for any write on a shared stack (`BEGIN; … ; ROLLBACK;`) | The exact SQL and its output, including the error messages of expected failures |
| `api` | Run the dev server on your port (§3) and call it with `curl -i` | The command, the status line and the relevant headers and body |
| `browser` | Prefer an isolated headless `@playwright/test` script against your dev server. With the Playwright MCP: `browser_navigate`, `browser_snapshot` before interacting, then `browser_click`/`browser_type`, and `browser_console_messages` to check for errors. Take a screenshot for anything visual | The snapshot excerpt or screenshot path, and any console errors (there must be none unless the AC allows them) |
| `next` | Next devtools MCP: `nextjs_index` and `nextjs_call` for routes, build errors and runtime errors | The tool output excerpt |
| `unit` | The repo's unit test runner. The named test file must exist and pass | The test names and the pass output |
| `e2e` | The repo's E2E runner (e.g. `pnpm test:e2e`) against your dev server or the PR's preview | The spec names and the pass output, plus the trace path for any failure |
| `cli` | Run the named script or command | The command, its output and its exit code |
| `deploy` | The repo's platform tools (see `INSTRUCTIONS.md`) against the PR's preview, or production after merge | The command or tool call and its output, including the deployment URL |
| `code` | A static check of the source with `grep` or by reading files, for structural rules | The command and its output |

General rules:

- Post-ready ACs (`Verify (deploy, post-ready)`) need CI or a deployment that only runs once a PR leaves draft. In team mode, report them as `DEFERRED (post-ready)` with the exact check that will prove them. `ready.sh` waits for those checks after marking the PR ready, and a failure goes back to the reviewer. In solo mode, and for PRs that are never drafts, verify them as normal `deploy` ACs.
- Negative ACs ("X must fail") need proof that the failure happens and that the valid path still succeeds.
- Server logs: before reporting, check your dev server's output for errors and warnings.

## 3. Local environment

Every ticket gets its own worktree, port and artefacts dir, so implementers can run in parallel.

| Item | Value |
|---|---|
| Dev server port | `5000 + <numeric id>`, e.g. T07 uses 5007. Run the dev server on it in the background, and stop it when you're done |
| Database | `migrations: true` and `own_db: true` tickets get their own Supabase stack (a slot), which they may reset; everyone else shares the base stack. `setup.sh` prints which, and the `DB_URL` |
| Env files | Copied from the main checkout by `setup.sh`, with `:3000` remapped to your port |
| Verification artefacts | `~/orchestrate/<owner>__<repo>/<id>/artefacts/`: screenshots, cookies, logs. Never write them inside the repo |

Rules:

- Never print env files or secrets, and never modify the main checkout's env files.
- On the shared stack, write only inside a rolled-back transaction or to rows you created, and never reset the database. Other agents use it at the same time.
- Never stop or recreate shared containers. Never `supabase stop`, `supabase db reset` or `docker compose down` outside your own slot.
- Kill only your own dev server, by port: `lsof -tiTCP:<port> -sTCP:LISTEN | xargs kill`. Never `pkill -f`.
- Parallel agents hijack the shared Playwright MCP tab, so prefer an isolated headless `@playwright/test` script.
- A remote database MCP (Supabase, Neon) points at a hosted project, not your stack. Use `psql "$DB_URL"` for local SQL. Hosted writes need the user's approval: implementers ask the orchestrator, and the orchestrator asks the user.

## 4. Report format

`~/orchestrate/<owner>__<repo>/reports/<id>.md`, the path `setup.sh` prints. It lives outside the repo because a worktree-isolated agent can't write anywhere in the repository except its own worktree, and because the report is evidence for the orchestrator, not part of the change. The scripts read the verdict from this file.

```markdown
# <id> report: <title>

Status: DONE | BLOCKED
Branch: <type>/<id>-<slug>
Verify cycles: <n>

## Summary table

| AC | Result | Method | Evidence |
|---|---|---|---|
| AC1 | PASS | db | see AC1 below |
| AC2 | FAIL→PASS (cycle 2) | browser | <artefacts>/ac2.png |

## Gates

<gate> ✔ · <gate> ✔ (N passed) · …

## Evidence

### AC1
<command>
<trimmed output>

## Deviations and follow-ups

- Anything out of scope you noticed, any ambiguity in the ticket or docs, and any doc you edited.

## Review

Verdict: ALL CLEAR | NOT CLEAR
PR: #<n>
Rounds: <n>

| Finding | Severity | Resolution |
|---|---|---|
| <short title> | critical/warning/suggestion | fixed in <sha> / open: <reason> |

Re-verified: AC<n> (<method>) PASS, … · gates ✔
```

- Evidence must be real output, trimmed to the decisive lines. Never paraphrase it.
- For a `BLOCKED` ticket, say what was tried, the root-cause hypothesis and what is needed to unblock it.

## 5. Ticket format

One file per ticket, `<id>-<slug>.md`, where the id is letters then digits (`T07`). Frontmatter:

| Key | Meaning |
|---|---|
| `id`, `title` | Must match the file name |
| `type` | Conventional-commit type for the branch prefix: the branch is `<type>/<id>-<slug>` in lower case (e.g. `test/t12-vitest-infra`). Defaults to `ORCH_BRANCH_TYPE`, else `feat` |
| `depends_on` | `[T01, T03]`: tickets that must be merged (solo), or merged or cleared (team), before this one starts |
| `serial` | `[fixture, ci]`: tags that no two in-flight tickets may share. Use one for any file several tickets edit (a seed file, a CI workflow, a shared config) |
| `migrations` | `true` when the ticket changes migrations: it gets its own database stack and the implicit `migrations` serial tag |
| `own_db` | `true` when the ticket needs its own database stack without serialising, e.g. it edits seed data it must reset to verify |
| `requires_human` | `true` when a step needs the user (credentials, a dashboard, a decision) |
| `skills` | Skills the implementer must invoke before coding |

The body has Context, Scope (In and Out), Notes and Acceptance criteria. ACs are numbered `AC1…ACn`, and each has a `Verify (<method>)` line that says exactly what to run and what result to expect. See `_TEMPLATE.md`.

The ticket dir lives in the main checkout and may be untracked there (e.g. listed in `.git/info/exclude`), so ticket branches never carry it. Agents reach it by absolute path. It also holds `orchestrate.env` (run config; see the skill's README), an optional `INSTRUCTIONS.md`, an optional `README.md` index, and `reports/`.
