# Global Development Guidelines

## Core Principles

- Do NOT over-engineer (no backward compatibility layers, extra abstractions, or utility functions unless requested)
- Scope changes ONLY to required files - never modify working code
- Follow established patterns and conventions - read 2-3 similar files first
- Check for auto-generated files ('DO NOT EDIT', '@generated') before editing

## Workflows

Use structured skills for common tasks:

- `/explore-patterns` - Before significant work
- `/fix` - For bug fixes
- `/refactor` - For refactoring (manual invocation)

## Code Style

- DRY principles and avoiding unnecessary code duplication, but with AHA in mind
- Separation of concerns and component responsibility boundaries
- DOTADIW (Do One Thing And Do It Well) and single responsibility principle application
- UNIX philosophy and modular design patterns
- KISS principles and simplicity-first approaches
- React composition patterns and state management strategies
- TypeScript type system design and constraint modelling
- Modular code organisation and reusable component design
- Maintainability assessment and technical debt identification
- Code should be self-documenting with minimal (if any) comments
- Complex reusable methods can have concise docstrings (no example usage)
- Only comment when code cannot be made clearer

## TypeScript

Never use `any` types. Derive from:

- Supabase generated types
- Zod schemas (`z.infer<typeof schema>`)
- Existing type definitions
- Only resort to creating new custom types if none of the options above exist, ask me to confirm first

## Dependencies & Tools

**shadcn/ui:** Use `pnpm dlx shadcn@latest add <component>`

**Package manager:** Check lock files to determine which to use

## Available MCP Servers

The following Model Context Protocol servers are configured:

**github:** GitHub integration via MCP

- Provides tools for interacting with GitHub (issues, PRs, repositories, etc.)
- **Note:** Prefer using `gh` CLI (GitHub CLI) as the primary interface for GitHub operations
- MCP tools available as fallback for operations not easily done via CLI

**fs:** Filesystem operations via MCP

- Advanced file system tools (reading, writing, searching, directory operations)
- Use standard Read/Write/Edit tools when possible; MCP fs tools for specialized operations

**fetch:** Web content fetching

- Fetch and process content from URLs
- Useful for retrieving documentation, API responses, or web resources

**daisyui:** DaisyUI component library

- Access DaisyUI documentation and component examples
- Utility for building with DaisyUI components

**tailwindcss-mcp-server:** Tailwind CSS utilities

- Tailwind CSS class reference and documentation
- Color palettes, utility classes, and configuration

**shadcn:** shadcn/ui component system

- Component registry and examples
- Available as both MCP and CLI (`pnpm dlx shadcn@latest add <component>`)

**supabase:** Supabase operations and documentation

- Search Supabase documentation (GraphQL-based)
- Project management, logs, and security advisors
- Edge Functions and database operations

**next-devtools:** Next.js development tools

- Next.js documentation and utilities
- Development workflow helpers

**playwright:** Browser automation and testing

- Test features in real browsers instead of curl
- Detects runtime errors, hydration issues, client-side problems
- Navigate, click, type, fill forms, evaluate JavaScript
- Screenshots and console message capture

## Build & Validation

After changes, consider:

1. Type checking: `pnpm typecheck`, `tsc --noEmit` or `npx tsc --noEmit`
2. Linting: `pnpm lint` or `npm run lint`
3. Tests if relevant
4. Build: `pnpm build` or `npm run build`

Check `package.json` for specifics and additional scripts to run.
