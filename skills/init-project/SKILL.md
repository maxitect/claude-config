---
name: init-project
description: Explore codebase and update project-context.md with detected frameworks, patterns, git context, and current focus.
---

# Project Context Updater

When invoked:

1. Read `.claude/project-context.md` to understand current state
2. Explore the project:
   - Detect frontend framework (package.json dependencies)
   - Detect backend setup
   - Detect database (dependencies, connection patterns)
   - Detect validation approach (Zod, Conform, Yup, etc.)
   - Detect authentication method
   - Check for Supabase usage (generated types, client)
   - Check shadcn/ui usage
   - Identify key patterns (file organisation, naming, etc.)
3. Git context:
   - Recent commit themes (last 20 commits)
   - Open branches and their purposes
   - Use gh CLI for open PRs if available
4. Update `.claude/project-context.md`:
   - Fill in detected tech stack
   - Update conventions based on observed patterns
   - Update current sprint focus based on recent activity
   - Add any discovered gotchas or known issues

Preserve manual sections, only update where you have confidence. Mark uncertain findings with `[detected]` or `[inferred]`.
