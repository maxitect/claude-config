# \_shared — machinery behind the PR skills

Not a skill. `pr-review/render.sh` and `address-pr-comments/render.sh` both source this; nothing here is loaded
into an agent's context except the fragments the renderers print.

| File             | Role                                                                                         |
| ---------------- | -------------------------------------------------------------------------------------------- |
| `stack.sh`       | Argument parsing, stack/ticket autodetection, and one function per rendered section.         |
| `gh.sh`          | `gh_t` (capped gh), `gh_json` (capped gh that rejects non-JSON), `gh_jq`, `gh_repo_slug`.    |
| `_cap.sh`        | `cap <seconds> <cmd>` — hard timeout that kills the whole process group.                     |
| `ghjson.py`      | Fallback for the small jq filter set `stack.sh` uses, on machines without jq.                |
| `db-check.sh`    | Deterministic database checks; runs only when Supabase migrations changed.                   |
| `fragments/*.md` | Per-stack and per-tracker checklists and probe commands; only the matching ones are printed. |

## stack.sh API

Source `gh.sh` first — `print_ticket_block` uses `gh_t`/`gh_jq`.

```bash
parse_args "$@"            # sets STACK, TICKET, TARGET from recognised tokens
detect_stack               # autodetects unless parse_args set one; sets STACK_MODE
detect_ticket              # same, for the tracker; sets TICKET_MODE
print_repo_facts           # conventions, framework signals, real script/task names, tsconfig strictness
resolve_base_ref [branch]  # sets BASE_BRANCH and BASE_REF; pass the PR's base when there is one
print_diff_scope [with-commits]   # base/head, diffstat, changed files -> $CHANGED_FILE
print_ticket_block [pr-json]      # GitHub issues fetched and injected; other trackers render a lookup path
print_stack_fragments      # returns 1 when nothing matched, so callers can bail
maybe_db_check             # runs db-check.sh when the stack is Supabase
```

Globals a caller can read after those: `STACK`, `TICKET`, `TARGET`, `HEAD_BRANCH`, `BASE_BRANCH`, `BASE_REF`,
`CHANGED_FILE` (temp file, removed by the `trap` in `stack.sh`).

Every external call is wrapped in `cap`, because a stalled injection kills the whole skill invocation at 120s.

## Why gh_json exists

`cap` folds stderr into stdout, so `gh pr view` on a branch with no PR returns its error text as a successful
payload. `gh_json` accepts output only when it starts with `{` or `[`; without it, both renderers announce an
empty pull request instead of taking the no-PR path.

## Arguments (all optional, order-free)

| Token                                                        | Effect                                                     |
| ------------------------------------------------------------ | ---------------------------------------------------------- |
| `monday` `github`\|`gh` `jira`\|`atlassian` `linear`         | Force the ticket tracker                                   |
| `none`                                                       | Skip ticket lookup entirely                                |
| `<number>`                                                   | Target that PR instead of the current branch's             |
| `local`                                                      | Skip PR lookup on a branch that has one (`pr-review` only) |
| `ts` `python` `pnpm` `npm` `yarn` `bun` `poetry`\|`poe` `uv` | Pin language / package manager                             |
| `supabase` `postgres`\|`pg` `mongo`                          | Pin the data layer                                         |

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

Drop `fragments/<axis>-<name>.md` in, add its token to the `case` in `parse_args`, add an autodetect line to
`detect_stack`, and add the name to `ORDER` in `print_stack_fragments` so it renders in position. Axes are
`lang-`, `pm-`, `db-`, `ticket-`. Both skills pick it up at once.

Ticket fragments differ: `ticket-github.md` is the _fallback_ text for when no issue could be fetched, not the
normal path. A new tracker whose API bash can reach should follow the GitHub shape (fetch and inject); one
behind an MCP should follow the Monday/Jira/Linear shape (render the lookup path).

## Database block

Fires only when the stack is Supabase **and** the diff touches `supabase/migrations/`. In order: locate
`docs/**/schema.sql` and `docs/**/DATABASE.md`; check the local stack is up (down → says so, findings ship
UNVERIFIED); `supabase migration up`; regenerate types; `supabase db lint --local` on `public` plus every
schema the changed migrations create objects in; `supabase db advisors --local --type all --level warn`; RLS
and `SECURITY DEFINER` psql queries. Failures and non-empty lint output are printed; a closing "Lints that ran"
line lists every lint that completed, so a clean result is citable and a missing one is visible.

The regeneration step is the interesting one: if `db:gen` changes tracked files, the PR's generated types are
stale against its own migrations, and that file list is the evidence. It then restores those files — only ones
that were clean beforehand, so uncommitted work is never discarded, and untracked build output is ignored.

Time budget is 100s of the 120s cap, checked between steps.

## Known gaps

- The `command -v jq` branch in `gh_jq` is untested: macOS ships jq at `/usr/bin/jq`, so the fallback can't be
  reached without a test seam. `ghjson.py`'s output is verified against `jq -r` on real PR JSON.
- `db-check.sh` lint and advisor steps were run against a live local stack (amagi PR #200); the advisor WARN
  print path is untested because that run had no WARN-level findings. `supabase migration up` output shape is
  still assumed.
