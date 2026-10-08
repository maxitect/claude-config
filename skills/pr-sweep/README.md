# pr-sweep: maintenance notes

Not loaded into any agent's context.

## Usage

```
/pr-sweep               # every open, non-draft PR not authored by me
/pr-sweep mine          # only PRs assigned to me
/pr-sweep 757 754       # exactly these PRs (draft/author/fork filters off)
```

Run it from the repo. The skill switches the session to Sonnet.

## Flow

```
preflight.sh            gh/docker/CLIs, base stack up (starts it), fetch, sweep merged/closed PRs
discover.sh [args]      filters -> queue.json, tags MIG (touches supabase/migrations, seed or config.toml)
run.sh <n>              per PR, in background, max 4 in flight / 3 MIG:
  prepare.sh <n>        worktree @ head, env files, own stack (MIG) or base, install, gates, context.md
  review.sh <n>         claude -p --agent pr-reviewer (Opus), --json-schema findings -> findings.json
  validate.py           schema, evidence, line ranges; resolves inline/file/body anchors
                        fail -> review.sh --fix (same session) once
  comment.sh <n>        claude -p --agent pr-commenter (Sonnet) -> comments.json; assemble.py -> payload.json
  post.py               REST pending review (no event) + GraphQL threads; rejected threads demoted to body
  teardown.sh <n>       stop own stack, release slot, keep worktree + sessions
open.sh <n> / ask.sh <n> "q"   bring the stack back, resume the reviewer (interactive / headless)
status.sh               furthest stage per PR, slots, resume commands
```

Everything lives in `~/pr-sweep/<owner>__<repo>/` (`PR_SWEEP_HOME` overrides). Not a dot-folder on purpose: tsc's include globs skip files under a dot-directory, so typecheck fails in worktrees there. Nothing is written inside the repo,
so the repo's tsc/eslint never see the worktrees.

## Knobs (env)

| Var | Default | |
|---|---|---|
| `PR_SWEEP_SLOTS` | 3 | concurrent PR Supabase stacks |
| `PR_SWEEP_SUPABASE_EXCLUDE` | `studio,imgproxy,vector,logflare,supavisor` | containers not started per PR stack |
| `PR_SWEEP_REVIEW_TIMEOUT` | 3600 | seconds per reviewer run |
| `PR_SWEEP_GATE_TIMEOUT` | 900 | seconds per gate |

## Supabase isolation

`patch_supabase.py` rewrites the worktree's `config.toml` (uncommitted): `project_id` gets `-pr<n>`, and every
`*port` key moves to `55000 + 100*slot + old%100` (54321 -> 55121 in slot 1). `:<old port>` elsewhere in the file and
in copied `.env*` files follows, as does `:3000` -> the PR's dev port (`4000 + n%1000`). `supabase status` from the
worktree then resolves the PR's stack, so `_shared/db-check.sh` works unchanged. Non-migration PRs keep the committed
config and resolve to the base stack; reviewers are told to wrap writes in `BEGIN ... ROLLBACK`.

Slots are `mkdir` locks in `slots/<k>`; gates hold `locks/gates` so only one PR builds at a time.

## Sessions

Reviewers run with `--session-id`, cwd the worktree. Resume needs the same cwd, which is why `teardown.sh` keeps the
worktree by default. `sessions.log` keeps every session per head. A head that moves gets a new session; the old
head's artefacts go to `history/<sha7>/`.

## Changes outside this folder

- `~/.claude/agents/pr-reviewer.md`, `pr-commenter.md`.
- `_shared/stack.sh`: honours `PR_HEAD_BRANCH`, diffing `HEAD` of a detached checkout as that PR's branch.
- The commenter reads `~/.claude/commands/pr-comment.md` §2–§3 for voice, so that file stays the one source.

## Known gaps

- Only Supabase gets per-PR databases. Drizzle/Prisma/compose repos share the base stack even for migration PRs.
- The reviewer's GitHub write ban is a tool deny-list (`git push`, `gh pr review|comment|edit|merge`, no `gh api`).
  It runs PR code (install scripts, tests) with your credentials: fork PRs are skipped by default for that reason.
- `auth.site_url` and `.env` values are remapped by port number; a hardcoded non-3000 app port isn't.
- Don't `ask.sh` a PR while its session is open interactively; both write to the same transcript.
