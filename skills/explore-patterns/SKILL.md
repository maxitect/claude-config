---
name: explore-patterns
description: This skill should be used when the user asks "how does this work", "what patterns are used here", "show me how this is done in the codebase", or before implementing features to understand existing conventions. Explores codebase patterns for types, components, validation, data fetching, and file organization without making any changes.
---

# Explore Patterns Skill

You are in pattern exploration mode. Your job is to understand how things are done in this codebase BEFORE making any changes.

## What to Explore

Based on the user's upcoming task, investigate:

### 1. Type Patterns

- Are types generated (Supabase, Prisma) or manual?
- How are types imported and used?
- Are Zod schemas used for validation?
- How are types derived (e.g., `z.infer<typeof schema>`)?
- Are there any `any` types in similar code? (Red flag if yes)

### 2. Component Patterns

- How are similar components structured?
- What naming conventions are used?
- Are there base components or shared wrappers?
- How are props typed?
- How is styling done (Tailwind, CSS modules, etc.)?

### 3. Form & Validation Patterns

If forms are involved:
- How is form state managed?
- Is Conform, React Hook Form, or another library used?
- How are validation schemas defined?
- How are errors displayed?
- Are there base form components or hooks?

### 4. Data Fetching Patterns

If data fetching is involved:
- How are API routes structured?
- How is data fetched (SWR, React Query, fetch)?
- How are loading states handled?
- How are errors handled?
- What types are used for responses?

### 5. File Organization

- Where do types live?
- Where do utilities live?
- Where do schemas live?
- Are there any generated files? (Check for comments like 'DO NOT EDIT')

### 6. Tooling & Dependencies

- Check `package.json` for installed libraries
- Note the package manager (`pnpm-lock.yaml`, `package-lock.json`, `yarn.lock`)
- Check for shadcn/ui usage
- Check for any special build scripts

## How to Explore

1. Use Grep to search for similar patterns
2. Use Glob to find relevant files
3. Read 2-4 representative files thoroughly
4. Look for both good patterns to follow AND anti-patterns to avoid

## Deliverable

After exploration, provide:

### Pattern Summary

A concise summary of key patterns:
- **Types:** How they're defined and used
- **Components:** Structure and conventions
- **Validation:** How it's done
- **File Organization:** Where things live
- **Dependencies:** Key libraries in use

### Recommendations

Based on the patterns found:
- ✅ What patterns to follow for the upcoming task
- ❌ What patterns to avoid
- 📋 Specific files or utilities to use as reference
- ⚠️ Any generated files to NOT edit

### Questions for User

If anything is unclear or if there are multiple valid approaches:
- Ask which pattern to follow
- Highlight trade-offs between approaches

## What NOT to Do

- ❌ Do NOT make any edits during exploration
- ❌ Do NOT propose implementation details yet
- ❌ Do NOT assume patterns without checking
- ✅ DO read actual code files
- ✅ DO present findings before implementation
- ✅ DO ask clarifying questions
