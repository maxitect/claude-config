### Supabase

Most common bug source in a Supabase codebase: the wrong client for the context. Check every `createClient` call.

- [ ] Is the **correct client** used — server (cookie-bound, RLS as the user), browser, admin/service-role
      (bypasses RLS: server-only, never reachable from a route a user can hit unauthenticated), public/anon?
      CLAUDE.md usually holds the selection table; check the call against it rather than re-deriving it.
- [ ] Is `await createClient()` used in server contexts? A missing `await` is a silent bug.
- [ ] Is the browser client instantiated at module level or in a closure that persists across users?
      It must be fresh per render.
- [ ] Is every Supabase response destructured and `error` checked before `data` is used?
- [ ] Do mutations use `TablesInsert<"table">` / `TablesUpdate<"table">` — not hand-rolled shapes?
- [ ] Is auth done through the project's auth helper, and is `getUser()` (server-validated) used rather
      than `getSession()` (unvalidated local JWT)?
- [ ] Is an ownership filter (`.eq("user_id", user.id)`) present on user-scoped mutations — belt and
      suspenders over RLS?
- [ ] Is `SUPABASE_SERVICE_ROLE_KEY` server-side only — never `NEXT_PUBLIC_`, never passed to a client component?
- [ ] Are reusable queries extracted to a shared queries module rather than inlined in components?

**When the diff touches `supabase/migrations/`, the schema dump, or generated DB types**

- [ ] Are generated types regenerated and committed with the migration? (`supabase gen types` / the repo's `db:gen` script)
- [ ] Do new tables and columns have RLS policies covering them? A table with RLS enabled and no policy
      is a silent 0-rows bug; a table without RLS is a hole.
- [ ] Is deterministic side-effect logic (audit timestamps, cascading writes, denormalised counters,
      invariant enforcement) a trigger rather than app code that callers can skip?
- [ ] Do new trigger functions follow the convention — `SECURITY DEFINER`, pinned `search_path`, revoked
      grants — and not trip advisor lints 0011 / 0028 / 0029?
- [ ] Do seed / preview fixtures that write to the changed table get updated in the same PR?

**Probes**

```bash
supabase status --output json | head -1        # is the local stack up?
psql "$(supabase status --output json | jq -er '.DB_URL')"
# then, to reproduce an RLS result as a real user:
#   set local role authenticated;
#   set local request.jwt.claims = '{"sub":"<uuid>"}';
#   <the exact query the code runs>
supabase db lint --linked --schema public --level warning   # plpgsql linter, no Docker needed
```

- `get_advisors` (Supabase MCP, both `security` and `performance`) after any schema change. Reason from the
  advisor output, never from reading the SQL. MCP unreachable → say so: an unrun advisor is not a clean advisor.
- Advisors and the linter report the **whole** schema and most projects carry pre-existing findings — attribute
  one to this PR only if it names an object the diff touches.
- Both read the *linked* project (usually staging), not this branch's preview branch, so a clean result proves
  less than it looks. Don't settle behaviour a migration in this branch introduces against staging — it
  doesn't have it yet.
