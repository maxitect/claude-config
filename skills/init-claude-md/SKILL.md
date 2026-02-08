---
name: init-claude-md
description: Explore codebase and update CLAUDE.md with detected frameworks, patterns, and conventions.
---

# CLAUDE.md Initialiser

When invoked:

1. Read `./CLAUDE.md` to understand current state (or create from template if missing)
2. Explore the project:
   - Detect framework (Next.js, React, Vue, etc.) and version from package.json
   - Detect database setup (Supabase, PostgreSQL, MongoDB, Drizzle, Prisma, etc.)
   - Detect validation approach (Zod, Conform, Yup, etc.)
   - Detect styling approach (TailwindCSS, shadcn/ui, DaisyUI, CSS Modules, etc.)
   - Detect authentication method
   - Check for code generation patterns
   - Identify key conventions from existing code (imports, naming, file structure)
3. Update `./CLAUDE.md`:
   - Fill in detected tech stack and versions
   - Update framework-specific patterns based on what's detected
   - Add observed conventions (import ordering, naming patterns, etc.)
   - Update project structure section based on actual directories
   - Add any discovered gotchas or common pitfalls

Preserve manual sections (project overview, known issues). Only update where you have direct evidence. Mark uncertain findings with `[detected]` or `[inferred]`.
