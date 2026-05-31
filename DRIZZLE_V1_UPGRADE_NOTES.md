# Drizzle v1 upgrade — completed

This branch upgrades from `drizzle-orm@1.0.0-beta.1-03a5cdc` /
`drizzle-kit@1.0.0-beta.1` / `drizzle-zod@0.8.3` to the current 1.0 release
candidate. Runtime is verified end-to-end: typecheck clean, Readwise sync
exits 0, all API routes (`search`, `record/slug/...`, `record/.../related`,
`tree/...`, `record/.../similar`) return 200.

## Dependency changes
- `drizzle-orm`: `1.0.0-beta.1-03a5cdc` → `1.0.0-rc.4-5d5b77c`
- `drizzle-kit`: `1.0.0-beta.1-03a5cdc` → `1.0.0-rc.4-5d5b77c`
- `drizzle-zod`: removed (folded into `drizzle-orm/zod` in v1)
- `better-sqlite3`: `^12.6.2` → `^12.10.0`

## Code migration

### Casing API moved (the main change)
In rc.1 the instance-level `casing: 'snake_case'` option on `drizzle()` was
removed. Casing now lives at table-definition time via the `snakeCase` helper
exposed from `drizzle-orm/sqlite-core`. The wrapper has the exact same
`SQLiteTableFn` signature as `sqliteTable`, so each schema file aliases it:

```ts
import { snakeCase, text, int /* ... */ } from 'drizzle-orm/sqlite-core';
// other imports
const sqliteTable = snakeCase.table;
```

Applied across all four schema files: `records.ts`, `readwise.ts`, `media.ts`,
`utils.ts`. None of the `sqliteTable(...)` call sites changed — only the
import.

### Other touched files
- `backend/db/index.ts`: dropped `casing: 'snake_case'` (now ignored) and the
  unused `schema` arg (RQBv2 takes `relations` only).
- `drizzle.config.ts`: dropped top-level `casing: 'snake_case'` (no longer in
  the kit config type), and pointed `schema` at the barrel file
  (`./backend/db/schema/index.ts`) instead of the dir — kit rc.4 reads every
  `.ts` in the dir, which loads both the barrel re-exports and the originals
  and registers every table twice.
- `backend/db/schema/records.ts` + `utils.ts`: `drizzle-zod` import →
  `drizzle-orm/zod`.

## Known cosmetic drift (DO NOT auto-apply — see below)

`pnpm drizzle-kit push --force` (or a generated migration) against the live DB
wants to **recreate every table** to:
- give existing unique constraints **explicit names** (e.g. anonymous unique →
  `links_source_target_predicate_unique`), and
- rewrite one check expression (`"records"."slug" != ''` → `"slug" != ''`).

These differences are between *what the new schema generator emits* and
*what's currently in the DB*. They are cosmetic — the runtime is fully working
without applying them.

### ⚠️ Why this can't be applied with the standard SQLite recreate dance

I tried `pnpm db:generate && pnpm db:migrate` once. It generated the obvious
DDL:

```sql
PRAGMA foreign_keys=OFF;
CREATE TABLE __new_records ( ... );
INSERT INTO __new_records SELECT ... FROM records;
DROP TABLE records;
ALTER TABLE __new_records RENAME TO records;
PRAGMA foreign_keys=ON;
```

This **destroyed dependent rows**: 1066 `links` → 0, 449 `readwise_document_tags`
→ 0, 17 `media` → 0.

Root cause: drizzle's migrator wraps the entire script in `BEGIN/COMMIT`
(`sqlite-core/dialect.js:579-585`). Per SQLite spec, `PRAGMA foreign_keys`
inside an active transaction is **silently a no-op**. So FKs stayed ON, and
when `DROP TABLE records` ran, the FK CASCADE on `links.source_id`,
`links.target_id`, `media.record_id`, etc. wiped every dependent row before
`__new_records` was renamed back in. (`records` itself was preserved because
its data was already copied to `__new_records`.)

Restored from VACUUM-INTO backup `/tmp/enchiridion.preCosmetic-*.db`; all
data is intact. The damaged DB is preserved at
`/tmp/enchiridion.damaged-*.db` for forensic comparison if needed.

### If you want to retry this cleanup later
You can't use the in-process migrator for this. Options:

1. **Run the recreate DDL outside drizzle's transaction.** Use `sqlite3` CLI
   or a one-off Node script that explicitly: `pragma foreign_keys=OFF;` then
   each `CREATE __new_x / INSERT / DROP / RENAME` block — NOT wrapped in
   `BEGIN`. SQLite docs are explicit that the recreate dance must run with FK
   disabled OUTSIDE a transaction.
2. **Live with the cosmetic drift.** The runtime is correct and the
   constraints (anonymous unique, old check expression form) still enforce
   what they should.

Option 2 is what's in effect now. Option 1 is straightforward but should not
be attempted casually — make a backup first.

## Pre-existing schema/DB drift (NOT introduced by this upgrade)

`records.slug` and `predicates.slug` are declared in the schema as
`text().unique().notNull()` but the live DB only has non-unique
`records_slug_idx` / `predicates_slug_idx` indexes — no uniqueness enforced.
This is unchanged by the v1 upgrade; it was already drifted on beta.1. Worth
a follow-up to either remove `.unique()` from the schema (if intentional) or
add the missing unique index (if a real bug).

## Migrations folder
Not touched in this upgrade. The existing single migration
(`0000_uneven_dexter_bennett.sql`) is preserved in the old beta.1 format.
`drizzle-kit up` would convert it to the v1 dir-based format, but I rolled
that back as part of the cosmetic-migration recovery — the converted layout
isn't required for the upgrade to work, and keeping the old format avoids
diverging from production state until a deliberate cutover.
