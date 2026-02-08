---
name: refactor
description: This skill should be used when the user asks to "refactor this code", "clean up this component", "reorganize these files", "consolidate duplicated code", "extract shared logic", or requests code restructuring. Forces a PLAN → APPROVE → EXECUTE workflow with phased changes and build verification between phases.
disable-model-invocation: true
---

# Refactoring Skill

You are in refactoring mode. This is a two-phase process: PLAN then EXECUTE.

## PHASE 1: PLAN (Do this first, always)

### 1. Understand Current State

- Read the target files thoroughly
- Read 2-3 similar files to understand existing patterns
- Identify the current architecture and conventions
- Note any generated files or auto-generated code

### 2. Understand Project Patterns

Check for:

- How types are defined (Supabase generated? Zod schemas? Manual?)
- How components are structured
- How validation is handled
- What naming conventions are used
- What base hooks or utilities exist

### 3. Create a Phased Plan

Write a brief plan (max 5 bullet points per phase):

- Break the refactor into phases
- Each phase must be independently buildable
- List specific files to create/modify per phase
- Identify any decisions that need user input
- Flag potential risks or breaking changes

### 4. Present Plan for Approval

- Show the plan to the user
- **WAIT for approval before coding**
- Write the plan to a markdown file in ai-docs project folder
- Do NOT start implementation until approved

## PHASE 2: EXECUTE (Only after approval)

### 1. Execute Phase by Phase

For each phase:

- Make only the changes listed in that phase
- Do NOT add extra features or improvements
- Do NOT add backward compatibility unless planned
- Use existing patterns and types
- Never use `any` types

### 2. Verify After Each Phase

After each phase:

- Suggest running: `pnpm lint` or `npm run lint`
- Suggest running: `pnpm typecheck`, `tsc --noEmit` or `npx tsc --noEmit`
- Suggest running: `pnpm build` or `npm run build`
- If any of these fail, fix before moving to next phase
- Do NOT skip ahead if the current phase doesn't build

### 3. Stay on Track

- If you encounter something that doesn't match the plan, STOP and ask
- Do NOT make unplanned changes
- Do NOT expand scope without approval

## Constraints

- ❌ Do NOT over-engineer
- ❌ Do NOT add backward compatibility layers unless explicitly planned
- ❌ Do NOT create new abstractions for one-time operations
- ❌ Do NOT modify files outside the refactoring scope
- ❌ Do NOT add features during refactoring
- ✅ DO keep changes minimal and focused
- ✅ DO follow existing project patterns
- ✅ DO leave the build passing after each phase
