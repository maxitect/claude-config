### pnpm

Never `npm` or `yarn` in this repo — the lockfile is `pnpm-lock.yaml` and mixing managers corrupts it.

- [ ] Is `pnpm-lock.yaml` committed alongside any `package.json` dependency change?
- [ ] Are new shadcn/ui components added via `pnpm dlx shadcn@latest add <component>` — not hand-written?
- [ ] In a workspace, do cross-package deps use `workspace:*` rather than a version range?

**Probes** — check `package.json` scripts first; these are the common names:

```bash
pnpm check 2>&1 | head -40      # or: pnpm exec tsc --noEmit
pnpm lint 2>&1 | head -40
pnpm test 2>&1 | tail -20
pnpm build 2>&1 | tail -20
pnpm exec eslint <file>          # single-file lint probe
```
