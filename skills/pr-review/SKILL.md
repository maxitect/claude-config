---
name: pr-review
description: Thorough, structured code review of the current branch's PR (or of the branch diff when no PR exists). Derives PR, base branch, stack and conventions from the repo, resolves the ticket for acceptance criteria, and probes every finding before reporting it.
argument-hint: "[tracker: monday|github|jira|linear|none]"
allowed-tools: Bash(${CLAUDE_SKILL_DIR}/render.sh *), Bash(gh*), Bash(git*), Bash(cat*), Bash(grep*), Bash(ls*), Bash(find*), Bash(curl*), Bash(jq*), Bash(pnpm*), Bash(npm*), Bash(npx*), Bash(yarn*), Bash(bun*), Bash(bunx*), Bash(python*), Bash(pytest*), Bash(mypy*), Bash(ruff*), Bash(poetry*), Bash(uv*), Bash(go*), Bash(cargo*), Bash(docker*), Bash(psql*), Bash(mongosh*), Bash(supabase*), Read, Grep, Glob, mcp__claude_ai_monday_com, mcp__claude_ai_Atlassian_Rovo, mcp__claude_ai_Google_Drive, mcp__playwright, mcp__supabase__get_advisors, mcp__supabase__execute_sql
---

# Code Review

Review only what the diff changes — never touch unrelated code. Every finding is probed before it ships (§7);
an unprobed finding is a hypothesis and goes out labelled as one.

---

## 1. Context

Gathered already — the PR or its absence, the diff scope, conventions, tracker, and the checklists for this
stack. Take it as given; re-running detection wastes a turn and can contradict it.

!`${CLAUDE_SKILL_DIR}/render.sh $ARGUMENTS`

Working rules from that block:

- **Read every convention file listed.** They outrank this skill wherever they disagree.
- **Use the exact script/task names printed.** A probe invented from habit (`pnpm typecheck` where the repo
  says `check`) fails for the wrong reason and proves nothing.
- The stack fragments extend the §5 checklist and the §7 probe table. They are checklist, not background reading.
  Anything not rendered isn't this repo's stack — don't review against it.
- The ticket section is §2's input: either the ticket itself, or the path to it. Follow what it rendered
  rather than assuming GitHub issues.
- The PR description, where one was rendered, is the author's stated intent. Where it conflicts with the ticket
  (§2), the ticket defines the requirements and the description explains the deviation.
- If a specific PR was asked for and did not resolve, stop and say so. The current branch is not a substitute
  for the diff you were asked about.
- State in the report header (§8) which of the two the block rendered: a PR, or a branch with none. A review of
  a branch with no PR must never read as though a PR was reviewed — there was no description to check the work
  against and no reviewer thread to defer to.
- If the rendered stack is plainly wrong for this repo, say so before reviewing.

---

## 2. Resolve the Ticket

Do this **before** reading the diff. Reviewing without the intent means grading the code against your own guess
at the requirements.

§1 either rendered the ticket itself — GitHub issues are fetched with the PR — or the lookup path for the
tracker this repo uses. A rendered ticket is already read; don't fetch it again. A lookup path means the ticket
lives somewhere `gh` can't reach: follow it now, before the diff. If §1 rendered neither, say so in the output
and work from the PR description alone.

With no PR, the body lookup path doesn't apply but the branch-name one still does — most trackers put the id
there. Only when the branch carries no id is there nothing to resolve.

From the ticket (and any doc it links) extract:

- **Goal / problem statement** — what this PR is meant to solve.
- **Acceptance criteria** — checklist items, "should", "must", "expected behaviour". These are what "done" means.
- **Out of scope** notes — explicit non-goals.

Build the **Issue Checklist**: the requirements the diff must satisfy. Cross-check it in §5 and report it in §8.

Anything in the diff that no criterion covers is scope creep — flag it, but check the PR description first, which
often justifies it.

If the ticket couldn't be read (no id, tracker unreachable, no access), say which and mark the Issue Coverage
table unverified rather than inferring criteria from the code. Code cannot evidence its own requirements.

---

## 3. Get the Diff

§1 rendered the base ref, the diffstat and the changed-file list. Read the diff itself, using the exact range
§1 printed:

```bash
git diff <base-ref>...<head-ref>   # the exact range §1 printed
```

Classify the changed files by type (page, route handler, component, hook, model, migration, test, config, …).

Large PR (>20 files) → group by feature area and review group by group, so no group gets skimmed at the end.

If the rendered file list looks stale or empty, fetch the base ref and re-derive before reviewing — a diff
against a stale base invents findings that were fixed upstream.

---

## 4. Review Each File

Read every changed file **twice** — once for intent, once for issues.

```bash
cat src/<path/to/file>
```

Never skim. Never review diff lines alone — understand surrounding context.

### Severity Classification

- 🔴 **Critical** — bug, security hole, broken auth, data loss, crash, build failure
- 🟡 **Warning** — anti-pattern, likely future bug, performance problem, missing error handling
- 🟢 **Suggestion** — readability, naming, style, conventions

---

## 5. Review Checklist

Apply universally. Skip sections not applicable to stack.

### Issue / Acceptance Criteria Coverage

- [ ] Each Issue Checklist item (§2): implemented?
  - ✅ Implemented correctly
  - ⚠️ Partially implemented / unclear
  - ❌ Not implemented / missing

Unmet acceptance criteria → 🔴 Critical.

### Logic & Correctness

- [ ] Changed code does what it claims?
- [ ] Edge cases handled (empty input, null/undefined, zero, large input)?
- [ ] Off-by-one errors possible in loops/array indexing?
- [ ] Async operations awaited where must be?
- [ ] Promises left floating (fire-and-forget where result matters)?
- [ ] Race conditions possible in concurrent operations?

### Security

- [ ] User input validated/sanitised before use?
- [ ] SQL queries parameterised (no string interpolation)?
- [ ] Auth checked before accessing protected resources?
- [ ] Authorisation checked (user owns resource, not just logged in)?
- [ ] Secrets / API keys absent from source, client bundles?
- [ ] `dangerouslySetInnerHTML` / `eval` / `exec` used? Input sanitised?
- [ ] File uploads validated for type/size before processing?

### Error Handling

- [ ] Async ops wrapped in try/catch (or equivalent)?
- [ ] Errors surfaced to user appropriately — not swallowed silently?
- [ ] Error messages safe to show users (no stack traces, no internal paths)?
- [ ] Expected error cases (404, validation fail) distinguished from unexpected (500)?

### Types & Contracts (TypeScript / typed languages)

- [ ] `any` / `unknown` / type assertions (`as X`) used? Each needs justification.
- [ ] Function signatures typed — params and return values?
- [ ] Nullability assumptions safe (no unchecked `!` non-null assertions)?
- [ ] Types derive from authoritative sources (DB schema, API response, Zod schema) — not hand-rolled shapes that drift?

### State & Data Flow

- [ ] Server-fetched data duplicated into local state unnecessarily?
- [ ] Global state used only for genuinely global concerns?
- [ ] Derived values computed — not stored/synced manually?
- [ ] Mutations invalidate/refresh dependent queries or UI state?

### Performance

- [ ] N+1 queries possible (query inside loop)?
- [ ] Large collections paginated — not fetched entirely?
- [ ] Expensive computations memoised where appropriate?
- [ ] Large dependencies/libraries lazy-loaded where possible?
- [ ] Images/assets optimised (correct format, explicit dimensions)?

### Code Quality

- [ ] Code self-documenting? Names explain intent?
- [ ] Magic strings/numbers that should be named constants?
- [ ] `console.log`/debug statements present that shouldn't reach production?
- [ ] Dead imports, unused vars, commented-out code present?
- [ ] Duplicated logic that should be extracted?
- [ ] Functions/methods too long (>50 lines smell, >100 flag)?
- [ ] Business logic mixed into UI components/view templates?

### Conventions (from CLAUDE.md and detected stack)

Apply the convention files and every stack-fragment checklist item rendered in §1.
Violations → 🟡 Warning unless the fragment grades them higher.

---

## 6. Anti-Pattern Radar

Vibe-coding / over-engineering signs, regardless of stack:

| Pattern                          | What to look for                                      |
| -------------------------------- | ----------------------------------------------------- |
| Unnecessary fallbacks            | Default values masking real errors                    |
| Over-complicated data processing | Multi-step transforms that could be single expression |
| Non-SOLID code                   | God functions, mixed concerns, feature envy           |
| Defensive over-engineering       | Try/catch around code that can't throw                |
| Stale TODO/FIXME                 | Comments referencing issues that should be resolved   |
| Premature abstraction            | Generic helper written for one use case               |
| Shadowed variables               | `const x` in inner scope hiding outer `x`             |

---

## 7. Verify Every Finding — and the Change Itself

A finding you have not reproduced is a hypothesis. A review pass produces genuine catches and confident
fabrications in the same breath, and on the page they read identically — the only thing separating them is a
command with output. Run one for every finding the stack can settle.

**Reading code is not a probe.** Rereading the diff, tracing a call path by eye or reasoning about what a regex
"would" match is how the hypothesis was formed — it cannot also confirm it. A probe executes something and
returns output that could have said "no": a command, a test, a function call, a query, a request, a browser
action. The one exception is an existence claim ("X is never called", "the docstring still names Y"), where a
grep *is* the execution — quote the grep and its output.

### Check the environment first — always

Do this before reviewing any file, whether or not you expect findings. Use the stack fragment's probe from §1
(`supabase status`, the repo's serve port, its compose file) — the generic forms below are a fallback only:

```bash
# Is a dev server / app already running? (port from package.json, Procfile, compose file)
curl -sf -o /dev/null http://localhost:3000 && echo up || echo down

# Is a local DB / service stack up?
docker compose ps 2>/dev/null | head -5
```

Record what is up; it goes in the report header (§8).

- App down but startable cheaply → start it; a probe beats an argument.
- Nothing runnable (no deps installed, no DB, no creds) → review statically, findings ship labelled UNVERIFIED.
- Don't settle branch behaviour against a shared staging/production environment — it doesn't have this branch yet.

### Exercise the change

Run the changed code path against the live stack at least once, **regardless of findings**. A clean review
with nothing executed is an unreviewed PR.

- Pure function or filter → run it over real rows pulled from the local DB, on the base ref *and* the head ref
  (`git archive <base> <dir> | tar -x -C <scratch>` gives you the base without touching the checkout), and diff
  the outputs.
- Route → `curl` it on the running server. UI → walk it in Playwright. Migration → apply it locally.
- If the local data cannot contain the case under test (an empty or synthetic seed with none of the shapes the
  change targets), the run could never have returned "no" — it is not evidence. Say so, and name the data
  that would settle it.

### Check the author's verification

When the PR description has a verification section:

- Spot-check the "Checked" items — re-run at least the one that matters most and compare against the stated result.
- For every "Not checked" item, either probe it or carry it into the report as UNVERIFIED with what it is
  waiting on. Unchecked claims in the description are where untested risk sits.

### Prove the finding

Pick the cheapest probe that is actually a probe (above) and is capable of returning "no". §1 carries this
repo's real script names and stack-specific probe commands — prefer those over the generic forms below.
Anything §1 already ran is CONFIRMED evidence; quote it rather than re-running it:

| Claim                                   | Probe                                                                                                                                                          |
| --------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Type or inference error                 | project typecheck — `tsc --noEmit`, `mypy`, `go build ./...`, `cargo check`                                                                                    |
| Lint or convention violation            | run the linter on that file (`eslint <file>`, `ruff check <file>`) — run the rule, don't assert it fires                                                       |
| "X doesn't exist" / "wrong import path" | grep the definition or barrel export before claiming it                                                                                                        |
| Logic bug in a pure function            | execute it — existing test, `node -e`, `python -c`, REPL — with the input that should break it                                                                 |
| Broken or missing test coverage         | run the suite (or the single test) and quote the decisive line                                                                                                 |
| API route / handler behaviour           | `curl -i` the running server with a real session; assert status code and body shape                                                                            |
| DB query, migration, constraint, policy | apply locally, then write the row that should trip it and show what actually happened                                                                          |
| Rendering, hydration, client state      | Playwright MCP — walk the real flow, `browser_snapshot`, read `browser_console_messages`. A console error is evidence; "this looks like it would break" is not |
| Build or bundle claim                   | run the build; quote the failing line                                                                                                                          |

Label every finding before writing anything up:

- **CONFIRMED** — probe output in hand.
- **REFUTED** — the probe disagreed with you. Delete it. Don't demote it to a 🟢, don't reword it as a question.
- **UNVERIFIED** — no probe can settle it (design opinion, readability, scope creep vs the issue) or the stack
  wasn't runnable. Ships, but labelled, with the reason. "I read the code" is never the reason: if a command
  could settle it, run the command.

A pass that probed its findings and refuted none of them almost certainly didn't probe them.

### Prove the fix

Same discipline on the remedy:

1. Capture the failing probe output **first**. Red before green, or you can't tell a fix from a coincidence.
2. Apply the fix, re-run that exact probe, capture the passing output.
3. Regression sweep: typecheck, lint, test suite; re-run probes for every other finding touching the same file;
   for UI, re-walk the other flows using the changed component.
4. If step 2 or 3 fails, the fix is wrong. Iterate from 1 with a different fix.

---

## 8. Output Format

Prioritise by severity, not file order.

```
## Code Review: [PR title] (#N) — or [branch name] (no PR) when §1 rendered none

Environment: [what was up] · exercised: [the change runs against it, base vs head] · not used: [what, and why]

### Issue Coverage
> Linked issues: #X — [title]
> No PR: "No PR — intent taken from the ticket and branch commits."

| Criterion | Status |
|---|---|
| [AC item 1] | ✅ / ⚠️ / ❌ |
| [AC item 2] | ✅ / ⚠️ / ❌ |

### Summary
One paragraph: overall quality, biggest concerns, what's done well.
Verification: N findings probed, M confirmed, K refuted and dropped, J unverified.
Author's claims: [checked items re-run and their result] · [not-checked items probed, or carried as unverified].

### 🔴 Critical Issues
1. **[Short title]** (`src/path/to/file.ts`, line N)
   Problem. Why it matters. Concrete fix.
   Evidence: `<command run>` → `<decisive line of output>`  — or `UNVERIFIED — <reason>`

// Before
...
// After
...

### 🟡 Warnings
...same format...

### 🟢 Suggestions
...same format...

### ✅ What's working well
Callouts of good patterns to reinforce.
```

Rules:

- Lead with most severe issue, not first file
- Every 🔴 and 🟡 carries an `Evidence:` line — the command run and the decisive line of its output, or
  `UNVERIFIED — <reason>` (§7). Never no line at all
- The `Environment:` line is mandatory. "Not checked" is not an allowed value — §7's first step always runs
- Say how many findings were refuted by probing; it tells the author how much to trust the rest
- Every finding gets concrete fix — not just description
- Large fixes → offer: _"Want me to apply this?"_
- Cap ~10 items per category for large PRs
- 🔴 mapping to unmet acceptance criterion → say so explicitly

---

## 9. After the Review

1. **Issue coverage verdict**: all criteria met / partially met / missing items
2. **Verification verdict**: how many findings were probed, and what the unverified ones are waiting on
3. **Offer to apply fixes** for 🔴 and 🟡 items: _"Want me to apply any of these?"_
4. **Offer deeper dive** if category had 3+ issues in same area
5. **Check related files** if tight coupling spotted

Apply fixes one at a time, each following "Prove the fix" (§7): red probe, fix, green probe, regression sweep.
Confirm each before moving to the next.
