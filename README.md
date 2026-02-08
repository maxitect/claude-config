# Claude Code Configuration

Quick reference for my Claude Code setup.

---

## Global Guidelines

**File:** `~/.claude/CLAUDE.md`

Core development principles applied to all projects. No over-engineering, respect scope, follow patterns.

---

## Skills

**Location:** `~/.claude/skills/`

User-invocable workflows.

### `/fix`

Bug fixing workflow. Enforces minimal scope, checks patterns, includes validation.

**When:** Reporting bugs
**Why:** Prevents scope creep during fixes

### `/refactor`

Refactoring workflow with PLAN → APPROVE → EXECUTE phases.

**When:** Code cleanup or restructuring
**Why:** Ensures plan approval before changes

### `/explore-patterns`

Discovers existing codebase patterns before implementation.

**When:** Before building features or understanding code
**Why:** Prevents wrong approach by understanding conventions first

### `/init-project`

Explore codebase and update `.claude/project-context.md`.

**When:** After `init-context` alias
**Why:** Auto-populates project context with detected patterns

### `/init-claude-md`

Explore codebase and update `./CLAUDE.md`.

**When:** After `init-claude` alias
**Why:** Auto-populates CLAUDE.md with detected frameworks and patterns

### `/zod4`

Zod 4 syntax reference and migration guide.

**When:** Writing Zod schemas
**Why:** Ensures correct Zod 4 patterns instead of deprecated Zod 3 syntax

### `/conform-validation`

Conform + Zod 4 form validation documentation.

**When:** Building forms with validation
**Why:** Streamlined type-safe form handling with automatic coercion

---

## Agents

**Location:** `~/.claude/agents/`

Specialised sub-agents with isolated contexts. Auto-invoke based on task.

### `pattern-validator`

Validates changes follow existing patterns. Fast (haiku), read-only, project memory.

**When:** Before implementation
**Why:** Prevents pattern violations

### `build-validator`

Runs type checking, linting, builds. Reports errors only, doesn't fix.

**When:** After code changes
**Why:** Catches errors immediately

### `scope-reviewer`

Reviews planned changes for scope creep.

**When:** Before starting work
**Why:** Prevents excessive changes

### `simplicity-enforcer`

Identifies over-engineering and unnecessary complexity.

**When:** After writing code
**Why:** Keeps solutions minimal

### `debugger`

Root cause analysis. Proposes minimal fixes, doesn't touch working code.

**When:** Debugging issues
**Why:** Fixes root cause, not symptoms

---

## Output Style

**File:** `~/.claude/output-styles/direct.md`

Communication preferences: British English, no softening criticism, concise responses, code-only for short questions, trade-offs included.

**Activation:** `/output-style direct`

---

## Hooks

**Location:** `~/.claude/hooks/` + `~/.claude/settings.json`

### `session-start.zsh`

Loads project context at session start. Shows git status, recent commits, diff vs main, open PRs, project context.

**When:** SessionStart (startup/resume/compact)
**Why:** Immediate project context without manual lookup

### `typecheck-after-edit.zsh`

Auto-runs type checking after Edit/Write operations on TypeScript files.

**When:** PostToolUse (Edit/Write)
**Why:** Immediate error feedback for TypeScript

### `lint-after-edit.zsh`

Auto-runs linter after Edit/Write operations on TypeScript files.

**When:** PostToolUse (Edit/Write)
**Why:** Immediate lint feedback for TypeScript

---

## Aliases

**Location:** `~/.zshrc`

### Project Setup

```bash
init-context    # Copy .claude/project-context.md template
init-claude     # Copy CLAUDE.md template to root
```

### Model Switching

```bash
cc-glm          # Switch to GLM models
cc-claude       # Switch to Claude models
```

---

## Project Context

**Template:** `~/.claude/templates/project-context.md`

Per-project manual context (purpose, tech stack, conventions, architecture, current focus).

**Setup:** `init-context` → `/init-project`

**Template:** `~/.claude/templates/CLAUDE.md`

Project-level CLAUDE.md for team conventions.

**Setup:** `init-claude` → `/init-claude-md`

---

## MCP Servers

**github** - Repository search, PRs, issues (backup to gh CLI)

**fs** - Access files outside current project

**fetch** - Access online documentation and web resources

**daisyui** - DaisyUI component library documentation

**tailwindcss-mcp-server** - Tailwind CSS utilities and docs

**shadcn** - shadcn/ui component system

**supabase** - Supabase backend and database operations

**next-devtools** - Next.js development tools

**playwright** - Browser automation and testing

---

## Quick Start

**New project:**
```bash
init-context      # Create .claude/project-context.md
/init-project      # Populate with detected patterns
init-claude       # Create CLAUDE.md
/init-claude-md    # Populate with detected frameworks
```

**Activate output style:** `/output-style direct`

**Skills:** `/fix`, `/refactor`, `/explore-patterns`, `/init-project`, `/init-claude-md`, `/zod4`, `/conform-validation`

**Agents:** Auto-invoke or request manually

---

## File Structure

```
~/.claude/
├── CLAUDE.md
├── README.md
├── settings.json
├── templates/          # Project setup files
├── output-styles/      # Communication preferences
├── skills/             # User-invocable workflows
├── agents/             # Specialised sub-agents
└── hooks/              # Event-triggered scripts
```

---

## Troubleshooting

**Hooks not running:** Check scripts executable (`chmod +x ~/.claude/hooks/*.zsh`)

**Agents not invoking:** Verify files exist, try manual invocation

**MCP not available:** Restart session, check auth (`/mcp`)

**Type errors unrelated to changes:** Hooks show first 20 lines, focus on files you modified
