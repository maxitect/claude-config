# [Project Name]

## Project Overview

[Brief project description - 2-3 sentences explaining what this project does and its main purpose]

## Tech Stack

- **Languages:** TypeScript
- **Framework:** Next.js [version] with React [version]
- **Database:** [PostgreSQL/Supabase/other] with [ORM]
- **Styling:** [TailwindCSS/shadcn/ui/DaisyUI/other]
- **Validation:** [Zod/Yup/Conform/other]
- **Package Manager:** pnpm

## Core Principles

- **Do NOT over-engineer** - Start simple, add complexity only when needed
- **Scope boundaries** - Fix bugs in broken code only, don't touch working code
- **Follow existing patterns** - Read 2-3 similar files before creating new ones
- **Generated code** - Never edit generated files (schemas, types, client code)
- **No `any` types** - Always use proper TypeScript types

### Before Starting Work

1. Check for existing components/utilities that solve the problem
2. Read 2-3 similar files to understand patterns
3. Ask if unsure about approach or need to deviate from patterns

## Key Development Commands

```bash
# Development
pnpm dev                   # Start dev server

# Building and quality checks
pnpm build                 # Production build
pnpm lint                  # Run linter
pnpm typecheck             # TypeScript type checking
```

## Code Style & Conventions

### Import Order (strict)

```typescript
// 1. React and React-related
import React, { useState, useEffect } from "react";

// 2. Next.js imports
import Link from "next/link";
import { useRouter } from "next/navigation";

// 3. External libraries (alphabetical)
import { z } from "zod";

// 4. Internal components and utilities
import Button from "@/components/ui/Button";
import { db } from "@/db/connection";

// 5. Types (always last)
import type { User } from "@/types";
```

### Naming Conventions

- **Functions:** camelCase (`fetchUsers`, `handleSubmit`)
- **Components:** PascalCase function declarations (`function UserCard() {}`)
- **Files:** PascalCase for components (`UserCard.tsx`), kebab-case for utilities (`format-date.ts`)
- **Types:** PascalCase (`User`, `Booking`, `Property`)
- **Validation schemas:** PascalCase (`UserSchema`, `BookingSchema`, `PropertySchema`)
- **Database:** snake_case for tables and columns (`users`, `created_at`)

## Framework-Specific Patterns

**Examples for shadcn/ui:**

- Install via `pnpm dlx shadcn@latest add [component]`
- Don't manually write shadcn components

**Examples for Supabase:**

- Use generated types from `@/types/database`
- Don't define manual types that exist in generated code

**Examples for form validation:**

- Use Zod schemas with `z.infer<typeof schema>`
- Integrate validation framework properly

## Development Workflow

### Before Submitting Code

1. **Run validation:**

   ```bash
   pnpm lint
   pnpm typecheck
   pnpm build
   ```

2. **Self-review:**
   - [ ] Checked for existing similar components or functions before creating new ones
   - [ ] Imports properly ordered
   - [ ] No `any` types
   - [ ] Function declarations for components
   - [ ] No edits to generated files
   - [ ] Changes scoped to the task

### Git Workflow

- **Commit messages:** Conventional commits (`feat:`, `fix:`, `refactor:`, `docs:`, `chore:`)
- **Granular commits** - break up changes for traceability

## Project Structure

```
/
├── docs/                 # Project documentation
├── scripts/              # Project automation scripts (not required after build)
├── src/
│   ├── app/              # Next.js app directory
│   ├── components/       # React components
│   ├── lib/              # Fully re-usable library-level code
│   ├── utils/            # Utilities and helpers
│   ├── types/            # TypeScript types
│   └── zod/              # Validation schemas
├── public/               # Static assets
└── [other directories]
```

## Known Issues & Gotchas

[Document any project-specific issues, workarounds, or non-obvious behaviours]

---

## Notes

Keep this file concise. Add only what helps the team work effectively. Remove sections that don't apply.
