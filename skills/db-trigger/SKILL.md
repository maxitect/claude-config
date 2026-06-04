---
name: db-trigger
description: Write PostgreSQL trigger functions and migrations for this Supabase project. Enforces all security and performance rules derived from the project's migration history to avoid Supabase advisor warnings (lints 0011, 0028, 0029).
---

# Secure Database Trigger Skill

Use this skill when writing any PostgreSQL trigger function or migration that includes one. All rules below are derived from this project's own migration history — violating them will produce Supabase advisor warnings that require follow-up migrations to fix.

---

## 1. Decide where the function lives

| Function type                             | Schema    | Why                                                  |
| ----------------------------------------- | --------- | ---------------------------------------------------- |
| Called only from a trigger                | `public`  | Fine; just revoke after creating                     |
| Called only from RLS policies             | `private` | PostgREST doesn't expose `private`; no REVOKE needed |
| Called via `supabase.rpc()` from app code | `public`  | Must stay exposed; grant to `authenticated` only     |

**The `private` schema already exists in this project.** For RLS helpers, the migration pattern is:

```sql
GRANT USAGE ON SCHEMA private TO anon, authenticated;

CREATE OR REPLACE FUNCTION private.my_helper(...)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
AS $$ ... $$;

GRANT EXECUTE ON FUNCTION private.my_helper(...) TO anon, authenticated;
```

---

## 2. Function definition template

```sql
CREATE OR REPLACE FUNCTION public.trg_<descriptive_name>()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
BEGIN
  -- use fully-qualified public.table_name references throughout
  RETURN NEW;  -- or RETURN NULL for AFTER triggers
END;
$$;
```

### Required on every function

- `SECURITY DEFINER` — trigger runs as function owner, not caller; required for cross-table writes and `auth.uid()` access
- `SET search_path TO ''` — prevents search_path injection (lint 0011); all table refs must be fully qualified (`public.table_name`)
- **Exception:** simple triggers that ONLY mutate `NEW` (no table access, e.g. `update_updated_at`, `handle_published_at`) do NOT need `SECURITY DEFINER`

### Naming

- Prefix both the function and the trigger with `trg_`
- Function name describes the event: `trg_member_added`, `trg_post_reactions_stats`, `trg_protect_org_slug`

---

## 3. Return values

| Trigger timing              | Return value  |
| --------------------------- | ------------- |
| `BEFORE` (mutating `NEW`)   | `RETURN NEW`  |
| `AFTER` (side-effects only) | `RETURN NULL` |

---

## 4. Trigger timing rule

| Use case                                                           | Timing                             |
| ------------------------------------------------------------------ | ---------------------------------- |
| Set timestamps or override field values on the row being written   | `BEFORE UPDATE` or `BEFORE INSERT` |
| Cascade inserts, update stats, stamp audit columns on OTHER tables | `AFTER INSERT` or `AFTER UPDATE`   |

Guard status transitions to avoid re-firing on unrelated column updates:

```sql
IF OLD.status IS DISTINCT FROM NEW.status THEN
  -- only fires when status actually changes
END IF;
```

---

## 5. Revoke access — CRITICAL for new functions in `public`

Supabase's initialization applies `ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon, authenticated`. This means **every new function created in `public` gets two grants automatically**:

- An explicit grant to `anon` and `authenticated` (from default privileges)
- A grant to `PUBLIC`

**Both must be revoked.** Each alone is insufficient:

- `REVOKE FROM PUBLIC` alone leaves the explicit anon/authenticated grants → still flagged
- `REVOKE FROM anon, authenticated` alone leaves the PUBLIC grant → still flagged (it's a no-op when PUBLIC holds the grant)

```sql
-- Always both, always in this order, in the same migration as CREATE
REVOKE EXECUTE ON FUNCTION public.trg_<name>() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.trg_<name>() FROM anon, authenticated;
```

Apply this pattern to **every** new `public` trigger function. Existing functions that were created before the default privilege setup only need `REVOKE FROM PUBLIC`.

---

## 6. Action functions (callable via RPC)

Functions intentionally called via `supabase.rpc()` stay in `public` but should only be callable by authenticated users:

```sql
REVOKE EXECUTE ON FUNCTION public.my_action(uuid, uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.my_action(uuid, uuid) FROM anon;
GRANT  EXECUTE ON FUNCTION public.my_action(uuid, uuid) TO authenticated;
```

---

## 7. RLS policies (when writing alongside triggers)

- Use `(SELECT auth.uid())` not bare `auth.uid()` — prevents per-row evaluation (lint 0015)
- Split `FOR ALL` into explicit `FOR SELECT`, `FOR INSERT`, `FOR UPDATE`, `FOR DELETE`
- Scope write policies: `TO authenticated`
- `FOR INSERT` uses `WITH CHECK`, not `USING`
- `FOR UPDATE` uses both `USING` and `WITH CHECK`

```sql
-- ✅ Correct
CREATE POLICY "Owner can update" ON public.posts FOR UPDATE TO authenticated
  USING  ((SELECT auth.uid()) = user_id)
  WITH CHECK ((SELECT auth.uid()) = user_id);

-- ❌ Wrong — bare auth.uid() evaluated per row
CREATE POLICY "Owner can update" ON public.posts FOR UPDATE TO authenticated
  USING (auth.uid() = user_id);
```

---

## 8. Full migration example

```sql
-- Stamp audit columns when a member is added to an organization.

CREATE OR REPLACE FUNCTION public.trg_member_added()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
BEGIN
  UPDATE public.organization_invites
  SET status = 'accepted', accepted_at = now()
  WHERE organization_id = NEW.organization_id
    AND invitee_user_id  = NEW.user_id
    AND status = 'pending';

  UPDATE public.organization_join_requests
  SET status = 'approved', approved_at = now(), reviewer_id = auth.uid()
  WHERE organization_id = NEW.organization_id
    AND user_id = NEW.user_id
    AND status = 'pending';

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_member_added
  AFTER INSERT ON public.organization_members
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_member_added();

REVOKE EXECUTE ON FUNCTION public.trg_member_added() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.trg_member_added() FROM anon, authenticated;
```

---

## 9. After writing — verify

```sql
-- Should return false for both
SELECT has_function_privilege('anon',          'public.trg_<name>()', 'execute');
SELECT has_function_privilege('authenticated', 'public.trg_<name>()', 'execute');
```

Do not run any supabase commands to reset or migrate, advise the user to do so and to check local advisor or run the SQL above in Supabase Studio.
