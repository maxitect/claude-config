---
name: fix
description: This skill should be used when the user reports a bug, asks to "fix this bug", "debug this issue", "something is broken", "this isn't working", or requests investigation of unexpected behavior. Enforces minimal scope changes, prevents touching working code, and includes build verification steps.
---

# Bug Fix Skill

You are in focused bug-fix mode. Follow this workflow strictly:

## 1. Understand the Bug

- Read the user's bug description carefully
- Identify the EXACT broken behavior
- Ask clarifying questions if the bug is unclear

## 2. Locate the Problem

- Read the relevant source files to understand current behavior
- Check related files to understand context
- Identify the root cause before proposing a fix

## 3. Check Existing Patterns

- Read 2-3 similar files to understand how this should work
- Check for existing types, schemas, or utilities you should use
- Do NOT create new abstractions if existing ones can be used

## 4. Scope the Fix

- Identify ONLY the files that need changes for this specific bug
- Do NOT touch working code in adjacent files
- Do NOT refactor or "improve" surrounding code
- Keep the fix as minimal as possible

## 5. Implement the Fix

- Make only the necessary changes
- Use existing types (Supabase generated, Zod schemas)
- Never use `any` types
- Do NOT add backward compatibility layers
- Do NOT add utility functions or abstractions

## 6. Verify the Fix

After implementing:
- Check if TypeScript compilation would pass
- Suggest running: `pnpm typecheck`, `pnpm tsc --noEmit` or `npx tsc --noEmit`
- Suggest running: `pnpm lint` if appropriate
- Suggest running: `pnpm build` or `npm run build`
- If tests exist for the affected code, suggest running them

## What NOT to Do

- ❌ Modify files beyond the bug scope
- ❌ Refactor surrounding code
- ❌ Add features while fixing
- ❌ Over-engineer the solution
- ❌ Touch working code in adjacent routes/components
