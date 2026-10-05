---
description: Find bug tickets assigned to me in a tracker (GitHub / Jira / Monday), fan out one worktree + Sonnet agent per ticket to fix them, open a draft PR each, and comment on the ticket only where the fix deviated from the spec
argument-hint: "<tracker: gh|jira|monday> [status] (default status: open / \"Ready for Dev\")"
allowed-tools: Bash(git*), Bash(gh*), Bash(cat*), Bash(ls*), Bash(mkdir*), Bash(curl*), Bash(file*), Bash(ffmpeg*), Bash(ffprobe*), Bash(whisper*), Bash(python3*), Read, Write, Agent, AskUserQuestion, SendMessage, ToolSearch, mcp__claude_ai_Atlassian__*, mcp__claude_ai_monday_com__*, mcp__claude_ai_Google_Drive__*, mcp__playwright__*
---

# Bugfixes — batch fix of my assigned bug tickets

Pull every bug ticket assigned to me with status `$2` from tracker `$1`. Worktree + agent per ticket.
Ends with one draft PR per ticket for me to review on GitHub.

**Models.** I run this on Opus — you are the orchestrator. Every fix agent is Sonnet:
`Agent({subagent_type: "general-purpose", model: "sonnet"})`. Never omit `model`, it inherits Opus and
burns the budget. Orchestrator work stays here: tracker queries, media extraction, clarification
judgement, tracker comments. Sonnet does the code.

Three things make or break this:

1. **Ambiguous ticket never guessed at.** Agent stops, asks this thread, waits. I answer, agent
   resumes. Never silent assumption, never skipped ticket.
2. **Tracker comments for deviations only.** Clean fix gets no comment. No PR links ever — I review
   in GitHub.
3. **Spec lives in screenshots and video, not text.** Body of `ER:` / `AR:` + 3 images is fully
   specified — spec inside images. §3.1 extracts it. Never call a ticket underspecified before its
   images, frames and transcript all read.

---

## 0. Preflight

`$1` required: `gh` | `jira` | `monday`. Else stop, state three options.

`$2` = status filter. Absent → `open` (gh), `"Ready for Dev"` (jira/monday).

Match **case-insensitively against statuses tracker actually has**, then query with tracker's own
spelling — `"ready for Dev"` must resolve to `Ready for Dev`, not return zero rows. No match → stop,
list real statuses. Never fuzzy-match beyond case: `"ready"` is not `"Ready for QA"`, that my typo to
fix. Echo resolved status before agents spin up.

```bash
git branch --show-current
gh repo view --json nameWithOwner -q .nameWithOwner
git rev-parse --show-toplevel
git fetch origin
git status -sb
git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@'
gh pr list --state merged --limit 20 --json baseRefName -q '[.[].baseRefName] | group_by(.) | map({base: .[0], n: length})'
```

Store `REPO`, `ROOT`, `BASE`. Worktrees branch off `origin/$BASE`.

**`origin/HEAD` not authoritative for `BASE`.** Repos leave it on `main` while every feature branch
targets `develop`. Take `BASE` from where recent PRs merged; use `origin/HEAD` only if that empty.
Disagreement → PR evidence wins, report both so I can override. Wrong here = N branches off wrong
commit, N PRs against wrong base.

Read `~/.claude/commands/pr-prep.md` now — title + body rules for this command's PRs, not restated
below. Missing → stop.

Load tracker tools, most deferred:

- `jira` → `ToolSearch("+Atlassian jira issue search comment")`. Only `authenticate` /
  `complete_authentication` back → connector not authed, stop, tell me to auth.
- `monday` → `ToolSearch("select:mcp__claude_ai_monday_com__get_user_context,mcp__claude_ai_monday_com__search,mcp__claude_ai_monday_com__get_board_items_page,mcp__claude_ai_monday_com__get_board_info,mcp__claude_ai_monday_com__get_assets,mcp__claude_ai_monday_com__get_updates,mcp__claude_ai_monday_com__all_api_read,mcp__claude_ai_monday_com__create_update,mcp__claude_ai_monday_com__get_monday_dev_sprints_boards")`
- `gh` → nothing, CLI covers it.

Media tooling, once:

```bash
which curl ffmpeg ffprobe whisper
ASSETS="$(mktemp -d -t bugfix-assets)" && echo "$ASSETS"
```

`ASSETS` holds run media. Agents read from it — must outlive fan-out, never delete while agent
working. `ffmpeg`/`ffprobe` missing → no video frames, say so up front (`brew install ffmpeg`).
`whisper` missing → no transcript (`brew install openai-whisper`). Neither fatal.

Google Docs read via Google Drive connector, no separate Docs server. Load lazily, only when ticket
links a doc:
`ToolSearch("select:mcp__claude_ai_Google_Drive__read_file_content,mcp__claude_ai_Google_Drive__get_file_metadata,mcp__claude_ai_Google_Drive__search_files")`.

Uncommitted changes in `ROOT` → warn. Don't follow into worktrees, but mean I have work in flight.

---

## 1. Resolve who I am

Assignee mismatch = commonest way this silently returns nothing. I appear as **Maxime Downe**,
**Max Downe**, **Max**, **maxitect**.

- **gh** — `@me`.
- **jira** — `assignee = currentUser()`.
- **monday** — no `currentUser()`. Two traps:

  **Trap 1: `get_board_items_page` returns person columns as display names, not ids.** Get real ids
  via `all_api_read`:

  ```graphql
  query ($ids: [ID!]) {
    items (ids: $ids) {
      id name
      column_values (types: [people]) {
        id
        ... on PeopleValue { text persons_and_teams { id kind } }
      }
    }
  }
  ```

  Match `persons_and_teams[].id` against my id from `get_user_context`.

  **Trap 2: boards have several person columns, one is the assignee.** On Ozeaon Bugs Queue,
  `people1` = **reporter** (QA who filed it), `multiple_person_mky2f1n9` = assignee. Matching my id
  across all person columns drags in tickets I only reported. Read `get_board_info`, pick assignee
  column by title (Developer / Assignee / Owner — not Reporter / Created by / QA), state which id you
  used. Several plausible → ask me.

  Multi-assignee normal: my id + someone else's still mine. Note co-assignee in working set.

---

## 2. Fetch tickets

**gh**

```bash
gh issue list --repo $REPO --assignee @me --state "${2:-open}" --label bug --limit 100 \
  --json number,title,url,body,labels,state,milestone
```

No `bug` label in repo → drop `--label bug`, use all open assigned, say so. `$2` not
`open`/`closed`/`all` is a label or project status, not a state — try
`--search "assignee:@me state:open label:\"$2\""` before reporting zero.

**jira** — JQL via Atlassian search:

```
assignee = currentUser() AND issuetype = Bug AND status = "$2" ORDER BY priority DESC, created ASC
```

Zero results on a status the board doesn't use looks identical to no work. Read project statuses,
name them before reporting nothing.

**monday** — candidate boards via `get_monday_dev_sprints_boards` or `search`, then
`get_board_items_page` filtered on status `$2` + assignee column from §1. Column titles vary per
board — `get_board_info` for real ids, never assume `status` / `person`.

Capture per ticket: **ticket id** (`BUG-412`, `#88`, Monday item id), title, url, full body, status,
every link in body.

Monday bodies arrive as `item_description.blocks[]`, each `content` a JSON string. Two block types
carry everything, both need parsing not skimming:

- `"normal text"` / `"numbered list"` → `content.deltaFormat[]`, array of `{insert}` runs. Concatenate
  `insert` for prose. Runs with `attributes.link` are the links — **video urls live there, invisible
  to a plain text read**. An `insert` of `{"mention": {...}}` is an @-mention, usually an unanswered
  question at a person: keep it, often marks the thing never decided.
- `"image"` → `content.assetId`. **Only usable handle on the image.** The `url` beside it is
  `ozeaon.monday.com/protected_static/...`, auth-walled, 403s for you and every agent. Never pass a
  `protected_static` url anywhere. Collect `assetId`s → §3.1.

`includeItemDescription: true` or none of this arrives. Comments carry evidence too: `get_updates`
with `objectType: "Item"`, `includeAssets: true`, `includeReplies: true` — a later "still broken, see
attached" reopens tickets whose description reads solved.

---

## 3. Resolve real ticket content

Body often a pointer, not the spec. Chase before any agent starts.

- **Google Doc links** (`docs.google.com/document/...`) — real writeup there, ticket a stub. Read via
  Drive tools, treat doc as authoritative bug report. Permission denied → note it, carry on with
  body, tell me which doc to share.
- **Linked/parent tickets** — bug usually purports to a feature/spec ticket. Fetch it (`gh issue
  view`, Jira issue links / parent / epic, Monday connected-boards column), capture acceptance
  criteria verbatim. That is what "correct" is measured against, and what makes a deviation
  reportable in §8.
- **Figma node link** (`?node-id=`) — note node id in brief, let the agent fetch via Figma MCP. Design
  context is large, belongs in agent's context not yours.
- **Which repo the ticket is for.** Jira/Monday not repo-scoped; boards hold tickets for other
  services. Judge from ticket text — named files, paths, modules, linked PR/branch. Nothing points at
  `REPO` and nothing points elsewhere → in-scope, note assumption. Clearly another repo → skipped,
  listed in §4, no worktree, no comment.

Per ticket → **ticket brief**: bug report, spec criteria, §3.1 media manifest, every place any two
disagree. Disagreements go in the brief; agent must not discover them alone.

---

## 3.1 Pull media down — images, frames, audio

Spec lives in attachments. `ER:` + `AR:` + three screenshots is not an underspecified ticket, it is a
ticket whose spec is in PNG form. Do this for every ticket before fan-out. Never report a ticket as
image-only-therefore-unworkable.

**Orchestrator's job, not the agents'.** Monday asset urls signed, expire in **1 hour** — agent
resolving later gets a dead link. CLI work costs no context. You fetch bytes to disk, agents read
files. You do **not** read the images — that burns the main thread, and understanding the ticket is
the agent's job.

```bash
mkdir -p "$ASSETS/<ticket-id>"
```

### Images

`assetId`s from description blocks + `get_updates` assets → one batched `get_assets` call. Each result
carries `public_url`: pre-signed S3 on `prod-*-files-monday-com.s3.*.amazonaws.com`, no auth, **1h
valid**. That is the answer to "images are auth-walled" — they are not, by this route.

```bash
curl -sL -o "$ASSETS/<ticket-id>/<assetId>.png" "<public_url>"
file "$ASSETS/<ticket-id>/<assetId>.png"   # PNG, not an HTML error page
```

HTML or 0 bytes → url expired or asset gone. Re-call `get_assets`, urls minted fresh each call.

Keep `original_geometry` + `uploaded_by.name`: 2560x1153 from the QA who filed it is ER/AR evidence,
200x200 from anyone else is probably an avatar.

**Spec screenshots are a lead, not a dead end.** Ozeaon QA screenshots the Google Doc spec and
highlights the line in green. When an image turns out to be a doc screenshot, search Drive for that
doc by visible title and read the real thing — full spec beats a crop. Note doc title in brief either
way.

### Video

Url sits in a `deltaFormat` run's `attributes.link`, so it only exists if you parsed blocks properly.
Ozeaon QA uses `awesomescreenshot.com/video/<id>?key=<key>`, public, no login.

`curl` on the share page returns a ~5KB SPA shell with no media url — do not conclude unreachable.
**No browser needed**, there is a public JSON API:

```bash
curl -s "https://www.awesomescreenshot.com/api/v1/video/load_video?id=<id>&key=<key>" -o "$ASSETS/<ticket-id>/video.json"
python3 -c "
import json,sys
v=json.load(open('$ASSETS/<ticket-id>/video.json'))['data']['video']
print(v['durationSecond'], v['title'])
print(v.get('fileMP4WithAnnURI') or v['fileMP4URI'])"
```

`fileMP4WithAnnURI` preferred — QA's on-screen annotations baked in; falls back to `fileMP4URI` (same
object when nothing was annotated). Signed, 24h. Then pure CLI:

```bash
curl -sL -o "$ASSETS/<ticket-id>/video.mp4" "<mp4 uri>"
ffprobe -v error -show_entries stream=codec_type,codec_name,width,height,duration \
  -of csv=p=0 "$ASSETS/<ticket-id>/video.mp4"

mkdir -p "$ASSETS/<ticket-id>/frames"
ffmpeg -v error -i "$ASSETS/<ticket-id>/video.mp4" -vf "fps=1/4,scale=1280:-1" \
  "$ASSETS/<ticket-id>/frames/f%02d.png" -y

ffmpeg -hide_banner -nostats -i "$ASSETS/<ticket-id>/video.mp4" -af volumedetect -f null /dev/null 2>&1 \
  | grep -E "mean_volume|max_volume"
whisper "$ASSETS/<ticket-id>/video.mp4" --model base --language en \
  --output_format txt --output_dir "$ASSETS/<ticket-id>" --fp16 False
```

`fps=1/4` suits a 30-60s repro; tighten for short clips, loosen for long — scale to `durationSecond`,
never emit 200 frames from a 10-minute video. `mean_volume` under ~-50 dB = silent screen recording,
skip whisper, note "no narration"; louder gets transcribed, since narration routinely states the ER
the body omits. First whisper run downloads its model (~140MB, once).

**Frames are where root cause hides.** These are recorded with devtools open — a frame shows the
failing request, console error, response body, real constraint name. One Ozeaon frame read
`duplicate key value violates unique constraint "projects_slug_key"` on a ticket whose text only said
"error popup wrong": bug is slug collision, not name collision. Nothing in the text would tell you.

Other hosts (Loom, Drive video, raw mp4): try the host's own share/API url with curl first. Only if
that fails, `mcp__playwright__browser_navigate` + `browser_evaluate` reading
`document.querySelector('video').src`. Browser is last resort — it is a shared singleton (see §6).

Anything unretrievable is stated in the brief as unavailable, with reason. Agent must never guess
whether it has the whole spec.

### Manifest

Per ticket, into the brief — paths, not bytes:

```
images:     <dir>/248704521.png (2560x1153, Elina Bchk)  ← ER, highlighted spec line
            <dir>/248704036.png (2110x920, Elina Bchk)   ← AR
video:      <dir>/video.mp4 (39s, 1152x720)
frames:     <dir>/frames/f01.png … f10.png (one per 4s)
transcript: <dir>/video.txt
unavailable: figma node 6850-33004 (agent to fetch)
```

---

## 4. Report working set, then stop

```
Tracker: <$1>   Status: <resolved status>
Assignee: <identity> (matched on <column id / @me / currentUser()>)
Repo: <REPO>   Base: <BASE> (<N of last 20 PRs merged here; origin/HEAD says X>)
Assets: <ASSETS>

N tickets:
BUG-412  Session token expiry off-by-one   spec: PROJ-88  media: 2 img, video 39s + transcript
#88      Upload retries loop forever       spec: none     media: none
BUG-175  Latest projects: funding pill     spec: doc "1. Home page_UI_Logged-In User"
                                                          media: 3 img (one a spec screenshot)

Skipped, wrong repo:
BUG-503  Nightly export cron times out     points at: ops-jobs
```

Drop skipped block when empty. Zero in scope → say which query ran, which status it resolved to,
which statuses exist. Don't guess another filter.

Media column reports what was **retrieved**, not what was linked; failures named with reason. No
"images only, not workable" verdict available to you — §3.1 already made them readable files.

Every in-scope ticket gets a worktree and an agent. Never sample. Count high enough to be expensive →
say so, let me narrow the status.

Explicit go-ahead before creating worktrees. Up to here only reads (`git fetch` aside); after, writes
branches, commits, PRs.

---

## 5. One worktree per ticket

Branch `fix/<ticket-id-lowercased>-<2-3 word desc>`, kebab-case, from ticket title —
`fix/bug-412-token-expiry`, `fix/88-upload-retry-loop`. Two or three words, no more.

```bash
git worktree add "$(dirname "$ROOT")/$(basename "$ROOT")-<ticket-id>" \
  -b fix/<ticket-id>-<desc> origin/$BASE
```

Branch exists (local or remote) → don't clobber. No commits on it → reuse in fresh worktree.
Otherwise report ticket as already in progress, skip.

Install deps per worktree (`node_modules` not shared) — check lock file, matching install. Note the
cost in §4 if the repo is big.

Assign each worktree a dev-server port, `3001`, `3002`, … by index, pass it to that agent. Agents
verifying UI fixes run the app concurrently and will collide on `3000` with each other and my
checkout.

---

## 6. Fan out — one Sonnet agent per ticket

`Agent({subagent_type: "general-purpose", model: "sonnet"})`, one per ticket, batches of ~4. Never fix
a ticket in this thread — this thread stays free for clarification.

Agent starts cold. Prompt carries brief, paths, return contract. Fill `<>`, keep rest verbatim.

````
Fix ticket <ticket-id> ("<title>") in <REPO>.

Working directory: the worktree at <absolute worktree path>, branch `fix/<ticket-id>-<desc>`, off
origin/<BASE>. Work ONLY there. Do not touch the main checkout at <ROOT>, do not switch branches.

## Ticket brief

Bug report (source: <ticket body | Google Doc "<title>">):
<full bug report text>

Spec / parent <spec-id> acceptance criteria, verbatim:
<criteria, or "none linked">

Where bug report and spec disagree:
<disagreements, or "none found">

Ticket url: <url>   Spec url: <url or none>   Dev server port: <assigned port>

## Media — READ BEFORE THE TEXT, THE SPEC IS IN HERE

Already downloaded. Local files, nothing to fetch, nothing expires:

<manifest from §3.1, or "none attached">

Read every one with Read before forming a view. All of them, not a sample. `ER:` = expected result,
`AR:` = actual result, and on this board the line after each is usually a screenshot, not a sentence.
Body text is the caption; images are the specification.

- **Annotations are the spec.** Green or red box marks the exact element in question. Read inside the
  box, and the surrounding UI for where it sits.
- **A screenshot of a document is a spec extract.** QA screenshots the Google Doc spec, highlights
  the line. Treat the highlighted line as an acceptance criterion, quote it in the PR body, name the
  doc in `notes` so it can be read in full.
- **Frames carry the root cause.** Recorded with devtools open. Read every frame: one shows the
  failing request, console error, response body, real constraint name. Text says "error popup wrong";
  frame says `duplicate key value violates unique constraint "projects_slug_key"`. Fix what the frame
  shows, not what the caption guessed.
- **Transcript states the ER out loud.** QA narrates — "easiest solution would be just to change the
  text of the popup" is a decision, in the transcript, absent from the body. Weight it as ticket
  content. Auto-transcribed, so proper nouns and product names come through garbled: read through the
  noise, never treat a mangled word as a requirement.
- **Transcript vs frames.** Narration says one thing, screen shows another → real conflict, goes in
  deviations or a clarification question.

Unretrievable media is named in the manifest with its reason. Everything else is on disk, so "image
only, cannot tell what is wanted" is not an available conclusion.

## Before code

Read CLAUDE.md + 2-3 files adjacent to the fix, match what is there. Follow
~/.claude/skills/fix/SKILL.md if present — minimal scope, never modify working code, verify build.

Reproduce the bug, or prove it from the code, before changing anything. A fix for a bug you haven't
located is a guess.

## If ambiguous, STOP — do not guess

Ambiguous = expected behaviour unstated and more than one reading defensible; bug report and spec
conflict with no obvious winner; fix needs a product decision (which behaviour is right, what to do
with existing bad data, whether to change a public contract); or you cannot find the code described.

**Only after the media.** A thin body is not ambiguity. Ambiguity is images + frames + transcript
together still leaving expected behaviour undetermined. Asking what the screenshots already answer is
the likeliest way this goes wrong. In the question, state what you read and what it left open.

An @-mention with an unanswered question next to it ("do we forbid the same names or allow them?") is
real ambiguity even when all else is clear — nobody answered it.

Then return `needs_clarification` and stop. Do not commit, do not open a PR, do not pick the likelier
reading and note it. You will be messaged the answer and resume, so leave the worktree working and
record `progress_so_far`.

A judgement call you can make from code + conventions is NOT ambiguity — make it, record it as a
deviation if it departs from either document.

## Implement

1. Smallest change that fixes the reported bug. No refactors, no drive-by improvements, no
   backward-compat shims.
2. Test that fails before, passes after, if the project has tests.
3. Project's own checks — type check, lint, tests (real script names from package.json). Fix what you
   broke. Pre-existing unrelated failures: leave, report in `notes`.
4. Commit, conventional, ticket id in subject: `fix(auth): correct token expiry check (BUG-412)`.
   Split by concern only if the work genuinely has more than one.
5. `git push -u origin fix/<ticket-id>-<desc>`.

## Verify a UI fix against the screenshots

ER is a screenshot — a pill that should appear, a menu item that should move — so a passing type check
proves nothing. Compare rendered output to the ER image.

Use the project's OWN browser tooling inside your worktree: its Playwright/Cypress runner, or dev
server + headless script. Real scripts from package.json. Dev server on <assigned port>, never 3000.
Shut it down before returning.

Do NOT use `mcp__playwright__*`. That browser is one shared instance across every agent in this run;
concurrent navigation corrupts everyone's session. Orchestrator only.

No project e2e runner, and `npx playwright`/`puppeteer` won't install (this repo's `devEngines` Node
pin blocks npm) — that is NOT "cannot render". Drive an isolated headless Chrome over CDP. No
dependency to install, Chrome is already on the machine, and each agent gets its own browser so
nothing collides:

```bash
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
PROFILE="$(mktemp -d)"                  # own profile — never the user's real one
CDP=922<agent index>                    # own port, like the dev port
"$CHROME" --headless=new --disable-gpu --remote-debugging-port=$CDP \
  --user-data-dir="$PROFILE" --window-size=1280,900 about:blank &   # [mob] → 390,844
```

Then drive it from python3 over the websocket: `GET http://127.0.0.1:$CDP/json` for the target's
`webSocketDebuggerUrl`, then `Page.navigate`, and `Runtime.evaluate` for the actual assertion. Kill
the Chrome PID and the dev server before returning.

`Runtime.evaluate` is where the verdict comes from — assert the DOM, don't eyeball a screenshot:

- clickable region → `document.elementFromPoint(x, y).closest('a')?.href` at the element's own
  on-screen position. Check the sibling links too: a stretched overlay that fixes the card can
  swallow a nested author or tag link, and that regression is invisible in a screenshot.
- overflow / side-swipe → `document.documentElement.scrollWidth > clientWidth`, then walk elements
  for the one whose `getBoundingClientRect().right` exceeds the viewport. Names the culprit element,
  which "it looks cut off" never does.
- ordering → map the menu's items to `textContent`, compare the array to the spec order.
- scroll-into-view → `getBoundingClientRect()` before and after the click.

Anything needing a session: seed an auth cookie via `Network.setCookie` before `Page.navigate`, or
say plainly in `checks` that the flow needs a login you could not produce.

Compare deliberately, element by element, in the region the annotation marks. Different → not fixed,
keep going. Cannot render (no e2e setup, needs auth or seed data you lack) → say so plainly in
`checks`, never imply visual confirmation you didn't get. `[mob]` in the title → mobile viewport.

## Draft PR

Read ~/.claude/commands/pr-prep.md, follow its title + body rules exactly. Draft, against <BASE>,
body from temp file:

  gh pr create --repo <REPO> --draft --base <BASE> --head fix/<ticket-id>-<desc> \
    --title "<title>" --body-file <tmp>

Sections, this order — pr-prep's shape plus three:

  ## What        one line
  ## Bug         factual: symptom, root cause you found, ticket id. What the ticket says, what the
                 code did. No narrative.
  ## Spec        acceptance criteria this fix is measured against, quoted. From whichever exists:
                 spec/parent ticket, a criterion highlighted in a screenshotted spec doc (name the
                 doc), or an ER stated in the narration (quote it). Omit only if none exists.
  ## Changes     bullets of what shipped
  ## Deviations  omit if none. Per deviation: what the ticket or spec asked, what you did instead,
                 why, what it costs. Include every case where bug report and spec disagreed and you
                 chose — say which you followed and why. Clarification from the orchestrator → state
                 the decision as the decision, don't narrate the exchange.
  ## Closes      ticket id
  ## Notes       only if a real caveat remains — deferred work, pre-existing failures, follow-ups

Factual throughout. No "should", no confidence claims, no describing your process.

## Return format

ONLY one JSON object, no prose around it.

{
  "ticket": "<ticket-id>",
  "status": "needs_clarification",
  "questions": [
    {
      "question": "the decision needed, answerable in a sentence",
      "options": ["defensible reading A", "defensible reading B"],
      "why": "what is underspecified or contradictory",
      "media_checked": "which images, frames, transcript you read and what each left unresolved",
      "recommendation": "which option the code and conventions point to, and why"
    }
  ],
  "progress_so_far": "what you located, reproduced or ruled out before stopping"
}

`media_checked` mandatory — it is the gate. No question before every image, every frame and the
transcript is read. Say what they showed, not that you opened them.

{
  "ticket": "<ticket-id>",
  "status": "done",
  "branch": "fix/<ticket-id>-<desc>",
  "worktree": "<absolute path>",
  "pr_url": "<url>",
  "root_cause": "one or two sentences",
  "evidence": "what the media established — annotated ER, error in frame N, ER from transcript. Omit
               if no media. Where a root cause found in a devtools frame gets stated.",
  "fix": "what you changed, by file",
  "checks": "commands run + results, verbatim on failure. UI fix: whether you compared rendered
             output to the ER image and what came of it, or plainly that you could not render it",
  "deviations": [
    {
      "from": "bug ticket" | "spec ticket" | "both",
      "asked": "what the document asked, quoted where possible",
      "did": "what you implemented instead",
      "why": "the reason",
      "cost": "what this leaves unresolved, or 'none'"
    }
  ],
  "notes": "pre-existing failures, follow-ups, or ''"
}

{ "ticket": "<ticket-id>", "status": "blocked", "reason": "...", "progress_so_far": "..." }

`deviations` is `[]` when the fix matches both documents — common and best case. Don't invent one to
look thorough, don't hide one to look clean. A deviation omitted here is one I find in review.
````

---

## 7. Clarification loop

`needs_clarification` back → put to me with `AskUserQuestion`. One question per item, agent's options
as options, its recommendation first labelled `(Recommended)`, its `why` in the descriptions. Don't
answer for me, don't downgrade a question to a guess so the run can finish.

Judge `media_checked` first. Question the screenshots already answer → don't forward it, send the
agent back to the media with `SendMessage`.

I answer → resume that agent via `SendMessage` to its id, context intact:

```
Clarification: <question>
Answer: <my answer, verbatim>
Continue from where you stopped. Record as a deviation ONLY if it departs from the bug ticket or the
spec ticket; filling a gap both left is not a deviation.
```

Other tickets keep running while one waits. No answer this session → ticket ends unfinished, worktree
left, listed in §9 as awaiting me. Never auto-resolve.

---

## 8. Tracker comments — deviations only

Each `done` ticket with non-empty `deviations` gets one comment. Nothing else does.

Never post: PR link, branch name, "implemented in <PR>", status update, summary of a clean fix. A
ticket implemented as written stays untouched — I review code in GitHub.

Body, plain, no preamble:

```
Implemented with deviations from the ticket:

- <asked> → <did>. <why>. <cost, if any>
```

Two deviations, two bullets. Name the document departed from (bug ticket / spec ticket / both) when
not obvious from wording.

- **gh** — `gh issue comment <n> --repo $REPO --body-file <tmp>`
- **jira** — Atlassian add-comment tool
- **monday** — `create_update` on the item

Confirm each posted. Failed post reported, not silently retried.

---

## 9. Report

In chat, not a file:

```
N tickets: X done, Y awaiting my answer, Z blocked

BUG-412  fix/bug-412-token-expiry   <pr url>   2 deviations, commented
#88      fix/88-upload-retry-loop   <pr url>   clean
BUG-509  awaiting answer: which behaviour when session already expired?
BUG-517  blocked: <reason>
```

- Worktree paths for anything unfinished, so I can pick it up by hand.
- Nothing merged, no PR leaves draft. Every PR mine to review.
- Cleanup after merge is `git worktree remove <path>` — offer, don't run. Never remove a worktree with
  uncommitted or unpushed work.
- Any failed check, quoted. A draft PR that doesn't build is worse than an unfixed ticket.
- Any UI fix not visually verified, named as such. "Types pass" is not "looks right".
- `ASSETS` path, and leave it alone — I may want the frames and transcripts, and a resumed agent needs
  them. Signed urls long dead by then; local copies are all there is.
