---
name: zod4
description: Zod 4 syntax reference and migration guide. Use when writing Zod schemas to ensure correct Zod 4 patterns are used instead of deprecated Zod 3 syntax.
---

# Zod 4 Syntax Reference

This skill documents Zod 4 breaking changes and new patterns. Always use these patterns when writing Zod schemas in this codebase.

## String Format Validators (BREAKING)

Format methods moved from `z.string()` chain to top-level `z` namespace:

| Zod 3 (Deprecated)       | Zod 4 (Correct)             |
| ------------------------ | --------------------------- |
| `z.string().email()`     | `z.email()`                 |
| `z.string().uuid()`      | `z.uuid()`                  |
| `z.string().url()`       | `z.url()`                   |
| `z.string().ipv4()`      | `z.ipv4()`                  |
| `z.string().ipv6()`      | `z.ipv6()`                  |
| `z.string().cidr()`      | `z.cidrv4()` / `z.cidrv6()` |
| `z.string().emoji()`     | `z.emoji()`                 |
| `z.string().base64()`    | `z.base64()`                |
| `z.string().base64url()` | `z.base64url()`             |
| `z.string().nanoid()`    | `z.nanoid()`                |
| `z.string().cuid()`      | `z.cuid()`                  |
| `z.string().cuid2()`     | `z.cuid2()`                 |
| `z.string().ulid()`      | `z.ulid()`                  |

```typescript
// Zod 3 - DEPRECATED
const schema = z.object({
  email: z.string().email(),
  id: z.string().uuid(),
  website: z.string().url(),
});

// Zod 4 - CORRECT
const schema = z.object({
  email: z.email(),
  id: z.uuid(),
  website: z.url(),
});
```

### UUID Strictness

`z.uuid()` is now RFC 9562/4122 compliant (stricter). Use `z.guid()` for permissive GUID matching.

## Error Customization (BREAKING)

### Unified `error` Parameter

The `message`, `required_error`, and `invalid_type_error` parameters are replaced with a unified `error` parameter:

```typescript
// Zod 3 - DEPRECATED
z.string({ required_error: "Required", invalid_type_error: "Must be string" });
z.string().min(5, { message: "Too short" });

// Zod 4 - CORRECT
z.string({ error: "Must be a string" });
z.string().min(5, { error: "Too short" });

// For distinguishing missing vs wrong type:
z.string({
  error: (issue) => (issue.input === undefined ? "Required" : "Must be string"),
});
```

### Error Maps

```typescript
// Zod 3 - DEPRECATED
z.string({ errorMap: (issue, ctx) => ({ message: "Custom error" }) });

// Zod 4 - CORRECT (return string directly, not { message })
z.string({ error: (issue) => "Custom error" });
```

## Object Methods (BREAKING)

Chainable object modifiers replaced with dedicated constructors:

| Zod 3 (Deprecated)           | Zod 4 (Correct)                 |
| ---------------------------- | ------------------------------- |
| `z.object({}).strict()`      | `z.strictObject({})`            |
| `z.object({}).passthrough()` | `z.looseObject({})`             |
| `z.object({}).strip()`       | `z.object({})` (default)        |
| `z.object({}).nonstrict()`   | Removed                         |
| `schema1.merge(schema2)`     | `schema1.extend(schema2.shape)` |
| `z.object({}).deepPartial()` | Removed                         |

```typescript
// Zod 3 - DEPRECATED
const strictSchema = z.object({ name: z.string() }).strict();
const looseSchema = z.object({ name: z.string() }).passthrough();

// Zod 4 - CORRECT
const strictSchema = z.strictObject({ name: z.string() });
const looseSchema = z.looseObject({ name: z.string() });
```

## z.record() (BREAKING)

Single-argument usage removed. Must specify both key and value schemas:

```typescript
// Zod 3 - DEPRECATED
z.record(z.string()); // Record<string, string>

// Zod 4 - CORRECT
z.record(z.string(), z.string()); // Record<string, string>
```

### Enum Keys Now Required

When using enum keys, all keys are required (exhaustive). Use `z.partialRecord()` for optional keys:

```typescript
const Status = z.enum(["active", "inactive"]);

// All keys required
z.record(Status, z.number()); // { active: number, inactive: number }

// Keys optional
z.partialRecord(Status, z.number()); // { active?: number, inactive?: number }
```

## z.number() Changes

- Infinite values (`POSITIVE_INFINITY`, `NEGATIVE_INFINITY`) now rejected
- `.safe()` behaves like `.int()` (no longer accepts floats)
- `.int()` validates only safe integers (`Number.MIN_SAFE_INTEGER` to `Number.MAX_SAFE_INTEGER`)

## z.array() Changes

`.nonempty()` now behaves like `.min(1)` and returns `string[]` not `[string, ...string[]]`.

For tuple type with at least one element:

```typescript
// Zod 3 - returned [string, ...string[]]
z.array(z.string()).nonempty();

// Zod 4 - for non-empty tuple type
z.tuple([z.string()], z.string()); // [string, ...string[]]
```

## Default Values (BREAKING)

`.default()` now short-circuits parsing. Default must match OUTPUT type, not input:

```typescript
// Zod 3 behavior - default applied before parsing
z.string()
  .transform((s) => s.length)
  .default("hello"); // Worked

// Zod 4 - default must match output type
z.string()
  .transform((s) => s.length)
  .default(5); // Must be number

// Use .prefault() for old behavior (apply before parsing)
z.string()
  .transform((s) => s.length)
  .prefault("hello");
```

### Defaults in Optional Object Fields

Defaults now applied automatically in optional fields:

```typescript
const schema = z.object({
  name: z.string().default("anonymous").optional(),
});

schema.parse({}); // { name: "anonymous" } - not { name: undefined }
```

## z.nativeEnum() Deprecated

`z.enum()` now handles native enums directly:

```typescript
enum Status {
  Active = "active",
  Inactive = "inactive",
}

// Zod 3 - DEPRECATED
z.nativeEnum(Status);

// Zod 4 - CORRECT
z.enum(Status);
```

Also removed: `.Enum` and `.Values` properties. Use `.enum` only.

## z.promise() Deprecated

Await promises before parsing instead:

```typescript
// Zod 3 - DEPRECATED
z.promise(z.string());

// Zod 4 - CORRECT
const result = await promise;
z.string().parse(result);
```

## z.function() Restructured

No longer a Zod schema. Uses `input`/`output` properties:

```typescript
// Zod 3 - DEPRECATED
const fn = z.function().args(z.string()).returns(z.number());

// Zod 4 - CORRECT
const fn = z.function({
  input: z.tuple([z.string()]),
  output: z.number(),
});

// Implementation
const myFn = fn.implement((arg) => arg.length);

// Async implementation
const myAsyncFn = fn.implementAsync(async (arg) => arg.length);
```

## z.refine() Changes

- Type predicates no longer narrow types
- `ctx.path` removed for performance
- Function as second argument dropped

```typescript
// Zod 3 - type narrowing worked
z.string().refine((s): s is "hello" => s === "hello");

// Zod 4 - no type narrowing, use transform instead
z.string().transform((s) => {
  if (s !== "hello") throw new Error("Must be hello");
  return s as "hello";
});
```

## ZodError Changes

- No longer extends native `Error` class
- `instanceof Error` checks will fail
- Deprecated: `.format()`, `.flatten()`, `.formErrors`, `.addIssue()`, `.addIssues()`
- Use `z.treeifyError()` for error formatting

```typescript
// Zod 4 error handling
try {
  schema.parse(data);
} catch (e) {
  if (e instanceof z.ZodError) {
    const formatted = z.treeifyError(e);
    console.log(formatted);
  }
}
```

## Removed APIs

| Removed                      | Replacement                     |
| ---------------------------- | ------------------------------- |
| `z.ostring()`, `z.onumber()` | `z.string().optional()`         |
| `z.literal(Symbol())`        | Not supported                   |
| `ZodType.create()`           | Direct instantiation            |
| `z.ZodBranded`               | Use branded types differently   |
| `z.preprocess()`             | Use `.transform()` or `.pipe()` |

## Internal Changes

- `._def` moved to `._zod.def`
- Generics simplified: `ZodType<Output, Input>` (removed `Def` parameter)
- New `z.core` namespace for shared utilities

## ISO DateTime

For datetime strings, use:

```typescript
z.iso.datetime(); // ISO 8601 datetime string
z.iso.date(); // ISO 8601 date string
z.iso.time(); // ISO 8601 time string
```

## Reference

- [Zod Documentation](https://zod.dev)
- [Zod 4 Changelog](https://zod.dev/v4/changelog)
- [Migration Codemod](https://github.com/nicoespeon/zod-v3-to-v4)
