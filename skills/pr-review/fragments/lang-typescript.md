### TypeScript

- [ ] Are `any` types present? Flag every one — there is almost always a better option.
- [ ] Do types derive from an authoritative source rather than hand-rolled shapes that drift?
      Generated DB types (`Tables<"table">`) → projections (`Pick<>`) → joins (`&`) → mutation types
      (`TablesInsert<>` / `TablesUpdate<>`); or `z.infer<typeof schema>` where Zod owns the shape.
- [ ] Are type assertions (`as X`) used where a guard or a correct signature would do?
- [ ] Are non-null assertions (`!`) used where `?.` or an explicit null check would be safer?
- [ ] Are `unknown` catch-clause values narrowed before use?
- [ ] Are domain types defined in a shared `types/` location — not inside component files?
- [ ] Are function params and return values typed at module boundaries?
- [ ] If the repo uses Zod: do schemas live in one place, are Zod 4 APIs used (not deprecated Zod 3
      methods), and are all external inputs (request bodies, Server Action args) parsed before use?

**Probes**

| Claim                  | Probe                                                           |
| ---------------------- | ----------------------------------------------------------------- |
| Type or inference error | `<pm> exec tsc --noEmit` (or the repo's `check` / `typecheck` script) |
| "X doesn't exist" / wrong import path | grep the definition or the barrel export before claiming it |
| Lint or convention     | `<pm> exec eslint <file>` — run the rule, don't assert it fires   |
