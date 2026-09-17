### MongoDB

- [ ] Does user input reach a query operator position? `{$where: ...}`, `$expr`, or a raw body spread into a
      filter lets a caller inject operators — validate and whitelist fields before querying.
- [ ] Is document shape validated at the application boundary (schema / Pydantic / Zod)? Mongo will happily
      store a shape nothing else can read.
- [ ] Do queried and sorted fields have indexes? Is a new index added for a new access pattern?
- [ ] Are `find()` calls bounded — `limit` + projection — not fetching whole collections into memory?
- [ ] In aggregation pipelines, does `$match` (and `$limit`) come before `$lookup` / `$unwind`, not after?
- [ ] Is a multi-document write assumed atomic? It isn't without a session transaction — and transactions
      need a replica set.
- [ ] Are string ids cast to `ObjectId` before querying? A string `_id` filter silently matches nothing.
- [ ] Are updates using operators (`$set`, `$inc`) rather than passing a whole document that drops fields?
- [ ] Is `upsert: true` used where it can create partial documents that fail later validation?

**Probes**

```bash
mongosh "$MONGO_URL" --quiet --eval 'db.<coll>.getIndexes()'
mongosh "$MONGO_URL" --quiet --eval 'db.<coll>.find(<filter>).explain("executionStats").executionStats'
# ^ COLLSCAN + high totalDocsExamined is the evidence for a missing-index finding
mongosh "$MONGO_URL" --quiet --eval 'db.<coll>.insertOne(<doc that should be rejected>)'
```
