---
name: conform-validation
description: When building forms, is able to use the below documentation to build streamlined form validation using all available features found in Conform + Zod 4. Is able to search the web for any syntax or patterns not included.
---

# Conform Form Validation

Conform is a type-safe form validation library for Next.js that handles FormData parsing with automatic type coercion using Zod schemas.

## Installation

```bash
pnpm add @conform-to/react @conform-to/zod
```

## Zod 4 Import Pattern

**Important**: When using Zod v4, you must use the `/v4` subpath for proper type alignment:

```typescript
import { parseWithZod } from "@conform-to/zod/v4";
```

Using the default import (`@conform-to/zod`) with Zod 4 may cause type errors. The `/v4` subpath ensures Conform's types match Zod 4's internal metadata structure.

## Why Conform?

Eliminates manual FormData extraction and type casting. Instead of:

```typescript
// Manual approach - redundant!
const formValues = {
  is_new_client: formData.get("is_new_client") as "true" | "false",
  behaviour_change: formData.get("behaviour_change") === "true",
  ethnicity_id: formData.get("ethnicity_id")
    ? Number(formData.get("ethnicity_id"))
    : undefined,
  // ... 20+ more fields
};
const validationResult = careHomeObservationFormSchema.safeParse(formValues);
```

You get automatic type coercion from FormData to typed objects using your existing Zod schema.

## Core Concepts

### Automatic Type Coercion

Conform introspects your Zod schema and automatically coerces FormData strings to the correct types:

| FormData Value       | Zod Type       | Coerced To             |
| -------------------- | -------------- | ---------------------- |
| `"true"` / `"false"` | `z.boolean()`  | `true` / `false`       |
| `"123"`              | `z.number()`   | `123`                  |
| `"2024-01-15"`       | `z.date()`     | `Date` object          |
| Empty string         | optional field | `undefined` (stripped) |

### Server Action Pattern

```typescript
"use server";
import { parseWithZod } from "@conform-to/zod/v4";
import { careHomeObservationFormSchema } from "@/zod/forms/observation";

export async function createCareHomeObservation(
  prevState: unknown,
  formData: FormData,
) {
  const submission = parseWithZod(formData, {
    schema: careHomeObservationFormSchema,
  });

  if (submission.status !== "success") {
    return submission.reply();
  }

  const data = submission.value; // Fully typed, coerced values
  // ... database operations
}
```

**Key points:**

- Server actions receive `prevState` as first argument when used with `useActionState`
- `parseWithZod` returns `{ status: 'success' | 'failure', value, error }`
- `submission.reply()` formats errors for client-side display
- No manual type casting needed

### Client Component Pattern (React 19)

```typescript
'use client';
import { useForm, getFormProps, getInputProps } from '@conform-to/react';
import { parseWithZod } from '@conform-to/zod/v4';
import { useActionState } from 'react';
import { createCareHomeObservation } from '@/actions/observations';
import { careHomeObservationFormSchema } from '@/zod/forms/observation';

export function ObservationForm() {
  const [lastResult, action] = useActionState(createCareHomeObservation, undefined);

  const [form, fields] = useForm({
    lastResult,
    onValidate: ({ formData }) => parseWithZod(formData, { schema: careHomeObservationFormSchema }),
    shouldValidate: 'onBlur',
    shouldRevalidate: 'onInput',
  });

  return (
    <form {...getFormProps(form)} action={action}>
      <input
        {...getInputProps(fields.pseudonym, { type: 'text' })}
        key={fields.pseudonym.key}
      />
      {fields.pseudonym.errors && (
        <span>{fields.pseudonym.errors}</span>
      )}
      <button type="submit">Submit</button>
    </form>
  );
}
```

**Key points:**

- `lastResult` carries server validation errors back to the form
- `fields.name.errors` contains error messages for each field
- `fields.name.key` is required for React's key prop on re-render
- `getFormProps`, `getInputProps` provide proper form attributes

## API Reference

### parseWithZod

```typescript
import { parseWithZod } from '@conform-to/zod/v4';

const submission = parseWithZod(formData, {
  schema: z.object({ ... }),           // Required: Zod schema
  async: false,                         // Optional: Use safeParseAsync
  errorMap: z.errorMap,                 // Optional: Custom error messages
  formatError: (error) => ({ ... }),    // Optional: Custom error structure
  disableAutoCoercion: false,           // Optional: Disable type coercion
});
```

### useForm Configuration Options

```typescript
useForm({
  lastResult, // Server action result for error display
  onValidate, // Client validation function
  shouldValidate: "onSubmit", // When to validate: 'onSubmit' | 'onBlur' | 'onInput'
  shouldRevalidate: "onInput", // When to revalidate
  defaultValue: {}, // Initial form values
});
```

### Helper Functions

| Function                         | Purpose                                  |
| -------------------------------- | ---------------------------------------- |
| `getFormProps(form)`             | Props for `<form>` element               |
| `getInputProps(field, { type })` | Props for `<input>` elements             |
| `getSelectProps(field)`          | Props for `<select>` elements            |
| `getTextareaProps(field)`        | Props for `<textarea>` elements          |
| `getFieldsetProps(fields)`       | Props for fieldset grouping              |
| `getCollectionProps(fields)`     | Props for array fields (checkbox groups) |

## Form Field Patterns

### Text Input

```typescript
<input
  {...getInputProps(fields.pseudonym, { type: 'text' })}
  key={fields.pseudonym.key}
/>
```

### Select Dropdown

```typescript
<select {...getSelectProps(fields.ethnicity_id)}>
  <option value="">Select...</option>
  {ethnicities.map(e => (
    <option key={e.id} value={e.id}>{e.name}</option>
  ))}
</select>
```

### Checkbox (Boolean)

```typescript
<input
  {...getInputProps(fields.behaviour_change, { type: 'checkbox' })}
  key={fields.behaviour_change.key}
  value="true"
/>
```

**Important**: Conform checkboxes use `value="true"` - the schema handles boolean coercion.

### Radio Group

```typescript
{['red', 'amber', 'green'].map((level) => (
  <label key={level}>
    <input
      {...getInputProps(fields.staff_urgency, { type: 'radio' })}
      key={fields.staff_urgency.key}
      value={level}
    />
    {level}
  </label>
))}
```

## Error Display

```typescript
{fields.fieldName.errors && (
  <ul>
    {fields.fieldName.errors.map((error) => (
      <li key={error}>{error}</li>
    ))}
  </ul>
)}
```

## Conditional Validation

```typescript
const schema = z
  .object({
    is_new_client: z.enum(["true", "false"]),
    pseudonym: z.string().optional(),
    existing_client_id: z.string().optional(),
  })
  .superRefine((data, ctx) => {
    if (data.is_new_client === "true" && !data.pseudonym) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: "Pseudonym required for new clients",
        path: ["pseudonym"],
      });
    }
  });
```

## Server Action Return Types

### Validation Failure

```typescript
return submission.reply();
```

Returns structured errors mapped to field names.

### Success with State Update

```typescript
return submission.reply({ resetForm: true });
```

### Success with Redirect

```typescript
// Conform won't see the redirect
redirect("/staff");
```

## Reference

- [Conform Documentation](https://conform.guide/)
- [Next.js Forms Guide](https://nextjs.org/docs/app/guides/forms)
