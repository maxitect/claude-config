# pr-review — maintenance notes

Not loaded into the review context; this is for you, not the agent.

## Usage

```
/pr-review                # PR for the current branch, or the branch diff if none is open
/pr-review monday         # same, forcing the ticket tracker
```

## Files

| File             | Role                                                                                   |
| ---------------- | -------------------------------------------------------------------------------------- |
| `SKILL.md`       | The review itself: checklist, verification discipline, output format. All instruction. |
| `render.sh`      | Gathers everything before the prompt reaches the agent (§1 of SKILL.md).               |
| `fragments/*.md` | Per-stack and per-tracker text; only the matching ones are rendered.                   |
| `db-check.sh`    | Deterministic database checks; runs only when Supabase migrations changed.             |
| `_cap.sh`        | `cap <seconds> <cmd>` — hard timeout that kills the whole process group.               |
| `ghjson.py`      | Fallback for the jq filters `render.sh` uses, on machines without jq.                  |

## What render.sh feeds the agent

- **Repo facts** — CLAUDE.md paths, framework/test signals, `package.json` scripts or `[tool.poe.tasks]`
  verbatim (so probes use real task names), tsconfig strict flags.
- **The PR** — resolved from the current branch, or a number passed in. Header, description verbatim, closing
  issue references, existing review comments. No PR → branch-diff mode with the branch's commits instead.
- **Diff scope** — base ref (remote-tracking, else local), diffstat, changed-file list.
- **The ticket** — GitHub issues are _fetched and injected_ (body + last 5 comments, repo-qualified so a
  cross-repo link isn't read from the wrong repo). Monday, Jira and Linear render a lookup path instead,
  because those live behind MCPs bash can't call.
- **Stack fragments** — checklist items extending §5, probe commands extending §7.
- **Database block** — see below.

Every external call is wrapped in `cap`, because a stalled injection kills the whole skill invocation at 120s.

## Database block

Fires only when the stack is Supabase **and** the diff touches `supabase/migrations/`. In order: locate
`docs/**/schema.sql` and `docs/**/DATABASE.md`; check the local stack is up (down → says so, findings ship
UNVERIFIED); `supabase migration up`; regenerate types; `supabase db lint`; RLS and `SECURITY DEFINER` psql
queries. Failures and non-empty lint output are printed; clean results print nothing.

The regeneration step is the interesting one: if `db:gen` changes tracked files, the PR's generated types are
stale against its own migrations, and that file list is the evidence. It then restores those files — only ones
that were clean beforehand, so uncommitted work is never discarded, and untracked build output is ignored.

Time budget is 100s of the 120s cap, checked between steps.

## Arguments (all optional, order-free)

| Token                                                        | Effect                                                                       |
| ------------------------------------------------------------ | ---------------------------------------------------------------------------- |
| `monday` `github`\|`gh` `jira`\|`atlassian` `linear`         | Force the ticket tracker                                                     |
| `none`                                                       | Skip ticket lookup entirely                                                  |
| `<number>`                                                   | Review that PR instead of the current branch's (stops if it doesn't resolve) |
| `local`                                                      | Skip PR lookup on a branch that has one                                      |
| `ts` `python` `pnpm` `npm` `yarn` `bun` `poetry`\|`poe` `uv` | Pin language / package manager                                               |
| `supabase` `postgres`\|`pg` `mongo`                          | Pin the data layer                                                           |

Unrecognised tokens are ignored.

## Autodetection

- **Stack** — lockfiles, `tsconfig.json`, `pyproject.toml` (`[tool.poetry]`, `[tool.uv]`), dependency names in
  the manifests, `supabase/config.toml`, and database images in compose files.
- **Tracker** — CLAUDE.md files, `README`, `CONTRIBUTING`, `docs/*.md` and `.github/` filenames, checked in the
  order monday → jira → linear → github. GitHub is last because nearly every repo has a github remote, so it
  only wins when no other tracker leaves a trace.
- **Issue number**, when GitHub and the PR closes nothing — a leading number in the branch name, anchored to
  start-or-`/` so `feat/tozn-441-x` yields nothing and `fix/456-x` yields 456.

Both axes detect independently: pinning the tracker doesn't disable stack autodetection.

## Adding a stack

Drop `fragments/<axis>-<name>.md` in, add its token to the `case` in `render.sh`, add an autodetect line, and
add the name to `ORDER` so it renders in position. Axes are `lang-`, `pm-`, `db-`, `ticket-`.

Ticket fragments differ: `ticket-github.md` is the _fallback_ text for when no issue could be fetched, not the
normal path. A new tracker whose API bash can reach should follow the GitHub shape (fetch and inject); one
behind an MCP should follow the Monday/Jira/Linear shape (render the lookup path).

## Known gaps

- The `command -v jq` branch is untested: macOS ships jq at `/usr/bin/jq`, so the fallback can't be reached
  without a test seam. `ghjson.py`'s output is verified against `jq -r` on real PR JSON.
- `db-check.sh` has not run against a live Docker stack — the shapes of real `supabase migration up` and
  `supabase db lint` output are assumed. The logic is verified with stubbed CLIs.
