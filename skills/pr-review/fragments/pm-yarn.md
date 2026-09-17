### Yarn

- [ ] Is `yarn.lock` committed alongside any `package.json` dependency change?
- [ ] Under Yarn Berry (PnP), does new code assume a `node_modules` layout that doesn't exist?

**Probes** — check `package.json` scripts first:

```bash
yarn typecheck 2>&1 | head -40   # or: yarn tsc --noEmit
yarn lint 2>&1 | head -40
yarn test 2>&1 | tail -20
yarn build 2>&1 | tail -20
```
