### Bun

- [ ] Is `bun.lock` / `bun.lockb` committed alongside any `package.json` dependency change?
- [ ] Does new code use Bun-only APIs (`Bun.file`, `Bun.serve`) in a path that must also run under Node
      (edge runtime, CI step, published package)?

**Probes**

```bash
bun run typecheck 2>&1 | head -40   # or: bunx tsc --noEmit
bun run lint 2>&1 | head -40
bun test 2>&1 | tail -20
bun run build 2>&1 | tail -20
```
