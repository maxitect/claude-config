### PostgreSQL

- [ ] Are queries parameterised? Any string-interpolated SQL is 🔴 regardless of where the value came from.
- [ ] Does the migration have a working down/rollback path, or is it explicitly one-way by design?
- [ ] Is the migration safe on a populated table — `ALTER TABLE ... ADD COLUMN NOT NULL` without a default,
      a type change rewriting a large table, an index built without `CONCURRENTLY`, a lock held across a
      long backfill?
- [ ] Do new foreign keys and frequently-filtered columns have indexes? Are redundant indexes added?
- [ ] Are multi-statement writes wrapped in a transaction so a partial failure can't leave torn state?
- [ ] Is there a query inside a loop (N+1) where a join or `WHERE id = ANY($1)` would do?
- [ ] Does the query select only needed columns — not `SELECT *` on a wide or large table?
- [ ] Are unbounded result sets returned to callers without a `LIMIT` / pagination?
- [ ] Are connections released back to the pool on every path, including error paths?
- [ ] Do enum / check-constraint changes match what the application code now writes?

**Probes**

```bash
psql "$DATABASE_URL" -c '\d+ <table>'                        # real shape after the migration
psql "$DATABASE_URL" -c 'explain analyze <the query>'        # index actually used? rows scanned?
psql "$DATABASE_URL" -c "<insert that should violate the new constraint>"   # show what actually happened
```

Apply the migration locally and write the row that should trip it. A constraint you reasoned about is a
hypothesis; a rejected insert is evidence.
