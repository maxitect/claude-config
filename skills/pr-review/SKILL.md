---
name: pr-review
description: Perform thorough, structured code review on a PR. Detects stack/conventions from the codebase, checks linked issues for acceptance criteria, then reviews the diff with severity-graded findings.
compatibility:
  tools:
    - bash
    - read
    - edit
---

# Code Review Skill

Structured code review. Adapts to whatever stack is in the repo. Reviews only changes in the PR diff — never touches unrelated code.

---

## 0. Identify the PR

```bash
git branch --show-current
gh pr view --json number,title,url,body,baseRefName,headRefName,state
```

If no PR found, tell user and stop.

Store: `PR_NUMBER`, `BASE_BRANCH`, `HEAD_BRANCH`.

---

## 1. Detect Stack & Conventions

Before reviewing, read the codebase to understand what patterns to enforce.

```bash
# Check for CLAUDE.md (project conventions)
cat CLAUDE.md 2>/dev/null || cat .claude/CLAUDE.md 2>/dev/null

# Detect package manager
ls package-lock.json yarn.lock pnpm-lock.yaml bun.lockb 2>/dev/null | head -1

# Detect framework / language
cat package.json 2>/dev/null | head -60
ls tsconfig.json pyproject.toml go.mod Cargo.toml mix.exs 2>/dev/null

# Detect test framework
grep -r "jest\|vitest\|pytest\|rspec\|go test" package.json pyproject.toml go.mod 2>/dev/null | head -5
```

From this, derive:

- Language + runtime
- Framework (Next.js, Express, Django, Rails, Go stdlib, etc.)
- Package manager
- TypeScript strictness (if applicable)
- Test framework
- Any project-specific conventions from CLAUDE.md

---

## 2. Check Linked Issues

```bash
# Get PR body to find closing keywords
gh pr view $PR_NUMBER --json body --jq '.body'
```

Scan body for closing keywords: `closes`, `fixes`, `resolves` (case-insensitive), followed by `#N` or a full GitHub issue URL.

For each linked issue:

```bash
gh issue view $ISSUE_NUMBER --json title,body,labels,milestone
```

Extract:

- **Goal / problem statement**
- **Acceptance criteria** (look for checklist items, "should", "must", "expected behaviour" sections)
- **Out of scope** notes

Build an **Issue Checklist** — a list of requirements the PR must satisfy. You will verify these during review.

---

## 3. Get the Diff

```bash
# Full diff against base branch
git diff origin/$BASE_BRANCH...HEAD

# Files changed (for orientation)
git diff --name-status origin/$BASE_BRANCH...HEAD
```

Classify changed files by type (page, route handler, component, hook, model, migration, test, config, etc.).

For large PRs (>20 files), group by feature area and review group by group.

---

## 4. Review Each File

Read every changed file **twice** — once for intent, once for issues.

```bash
cat src/<path/to/file>
```

Never skim. Never review only the diff lines — understand surrounding context.

### Severity Classification

- 🔴 **Critical** — bug, security hole, broken auth, data loss, crash, build failure
- 🟡 **Warning** — anti-pattern, likely future bug, performance problem, missing error handling
- 🟢 **Suggestion** — readability, naming, style, conventions

---

## 5. Review Checklist

Apply these checks universally. Skip sections not applicable to the stack.

### Issue / Acceptance Criteria Coverage

- [ ] For each item in the Issue Checklist (§2): is it implemented?
  - ✅ Implemented correctly
  - ⚠️ Partially implemented / unclear
  - ❌ Not implemented / missing

Flag any acceptance criteria not met as 🔴 Critical.

### Logic & Correctness

- [ ] Does the changed code do what it claims to do?
- [ ] Are edge cases handled (empty input, null/undefined, zero, large input)?
- [ ] Are off-by-one errors possible in loops or array indexing?
- [ ] Are async operations awaited where they must be?
- [ ] Are promises left floating (fire-and-forget where result matters)?
- [ ] Are race conditions possible in concurrent operations?

### Security

- [ ] Is user input validated and sanitised before use?
- [ ] Are SQL queries parameterised (no string interpolation into queries)?
- [ ] Is authentication checked before accessing protected resources?
- [ ] Is authorisation checked (user owns the resource, not just logged in)?
- [ ] Are secrets / API keys absent from source code and client-facing bundles?
- [ ] Is `dangerouslySetInnerHTML` / `eval` / `exec` used? If so, is input sanitised?
- [ ] Are file uploads validated for type and size before processing?

### Error Handling

- [ ] Are all async operations wrapped in try/catch (or equivalent)?
- [ ] Are errors surfaced to the user appropriately — not swallowed silently?
- [ ] Are error messages safe to show users (no stack traces, no internal paths)?
- [ ] Are expected error cases (404, validation fail) distinguished from unexpected ones (500)?

### Types & Contracts (TypeScript / typed languages)

- [ ] Are `any` / `unknown` / type assertions (`as X`) used? Each needs justification.
- [ ] Are function signatures typed — parameters and return values?
- [ ] Are nullability assumptions safe (no unchecked `!` non-null assertions)?
- [ ] Do types derive from authoritative sources (DB schema, API response, Zod schema) rather than hand-rolled shapes that can drift?

### State & Data Flow

- [ ] Is server-fetched data being duplicated into local state unnecessarily?
- [ ] Is global state used only for genuinely global concerns?
- [ ] Are derived values computed — not stored and kept in sync manually?
- [ ] Are mutations invalidating / refreshing dependent queries or UI state?

### Performance

- [ ] Are N+1 queries possible (query inside a loop)?
- [ ] Are large collections paginated — not fetched entirely?
- [ ] Are expensive computations memoised where appropriate?
- [ ] Are large dependencies / libraries lazy-loaded where possible?
- [ ] Are images / assets optimised (correct format, explicit dimensions)?

### Code Quality

- [ ] Is code self-documenting? Do names explain intent?
- [ ] Are there magic strings / numbers that should be named constants?
- [ ] Are `console.log` / debug statements present that shouldn't reach production?
- [ ] Are dead imports, unused variables, or commented-out code present?
- [ ] Is there duplicated logic that should be extracted?
- [ ] Are functions / methods too long (>50 lines is a smell, >100 is a flag)?
- [ ] Is business logic mixed into UI components or view templates?

### Conventions (from CLAUDE.md and detected stack)

Apply any project-specific rules detected in §1. Flag violations as 🟡 Warning.

---

## 6. Anti-Pattern Radar

Watch for signs of vibe coding / over-engineering regardless of stack:

| Pattern                          | What to look for                                        |
| -------------------------------- | ------------------------------------------------------- |
| Unnecessary fallbacks            | Default values that mask real errors                    |
| Over-complicated data processing | Multi-step transforms that could be a single expression |
| Non-SOLID code                   | God functions, mixed concerns, feature envy             |
| Defensive over-engineering       | Try/catch around code that can't throw                  |
| Stale TODO/FIXME                 | Comments referencing issues that should be resolved     |
| Premature abstraction            | Generic helper written for one use case                 |
| Shadowed variables               | `const x` in inner scope hiding outer `x`               |

---

## 7. Output Format

Prioritise by severity, not by file order.

```
## Code Review: [PR title] (#N)

### Issue Coverage
> Linked issues: #X — [title]

| Criterion | Status |
|---|---|
| [AC item 1] | ✅ / ⚠️ / ❌ |
| [AC item 2] | ✅ / ⚠️ / ❌ |

### Summary
One paragraph: overall quality, biggest concerns, what's done well.

### 🔴 Critical Issues
1. **[Short title]** (`src/path/to/file.ts`, line N)
   Problem. Why it matters. Concrete fix.
```

// Before
...
// After
...

```

### 🟡 Warnings
...same format...

### 🟢 Suggestions
...same format...

### ✅ What's working well
Callouts of good patterns to reinforce.
```

Rules:

- Lead with the most severe issue, not the first file
- Every finding gets a concrete fix — not just a description
- For large fixes, offer: _"Want me to apply this?"_
- Cap at ~10 items per category for large PRs
- If a 🔴 maps to an unmet acceptance criterion, say so explicitly

---

## 8. After the Review

1. **Issue coverage verdict**: all criteria met / partially met / missing items
2. **Offer to apply fixes** for 🔴 and 🟡 items: _"Want me to apply any of these?"_
3. **Offer a deeper dive** if a category had 3+ issues in same area
4. **Check related files** if tight coupling spotted
5. **Run type check** after any TypeScript changes: `pnpm tsc --noEmit` (or equivalent)
6. **Run lint** after changes: `pnpm lint` (or equivalent)

Apply fixes one at a time, confirm each before moving to the next.
