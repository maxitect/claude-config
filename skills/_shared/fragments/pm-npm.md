### npm

- [ ] Is `package-lock.json` committed alongside any `package.json` dependency change?
- [ ] Are dependencies in the right block — build-time tooling in `devDependencies`, runtime in `dependencies`?

**Probes** — check `package.json` scripts first; these are the common names:

```bash
npm run typecheck 2>&1 | head -40   # or: npx tsc --noEmit
npm run lint 2>&1 | head -40
npm test 2>&1 | tail -20
npm run build 2>&1 | tail -20
npx eslint <file>                    # single-file lint probe
```
