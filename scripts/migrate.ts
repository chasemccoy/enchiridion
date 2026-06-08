#!/usr/bin/env tsx
/**
 * Apply pending Drizzle migrations.
 *
 * Runs through the *app's* database connection (backend/db/index.ts), which
 * loads the sqlite-vec extension. This is why we use the drizzle-orm migrator
 * here instead of `drizzle-kit migrate`/`push`: drizzle-kit opens its own
 * connection without the extension and dies on the `vec_records` virtual table
 * ("no such module: vec0"). The drizzle-orm migrator only executes the
 * generated SQL files and stamps `__drizzle_migrations` — it never introspects
 * the live schema, so the vec tables are irrelevant to it.
 *
 *   pnpm db:migrate                 apply pending migrations
 *   pnpm db:migrate --mark-applied  stamp every migration file as applied
 *                                   WITHOUT running it (adopt an existing DB
 *                                   into a re-baselined migration history)
 */
import 'dotenv/config';
import { migrate } from 'drizzle-orm/better-sqlite3/migrator';
import { readMigrationFiles } from 'drizzle-orm/migrator';
import { sql } from 'drizzle-orm';
import { db } from '@db/index';

/* eslint-disable no-console */

const MIGRATIONS_FOLDER = './backend/db/migrations';

function markAllApplied() {
  const migrations = readMigrationFiles({ migrationsFolder: MIGRATIONS_FOLDER });
  if (migrations.length === 0) {
    console.error('No migrations found to mark as applied. Run `pnpm db:generate` first.');
    process.exit(1);
  }

  // Drizzle v1 tracks applied migrations BY NAME (drizzle-orm/migrator.utils
  // getMigrationsToRun), so the stamp must populate `name` — and match v1's
  // `__drizzle_migrations` schema (id, hash, created_at, name, applied_at).
  // Recreate the table so this works whether it's absent, on the old v0 shape,
  // or already upgraded.
  const appliedAt = new Date().toISOString();
  db.run(sql`DROP TABLE IF EXISTS __drizzle_migrations`);
  db.run(
    sql`CREATE TABLE __drizzle_migrations (
      id INTEGER PRIMARY KEY,
      hash text NOT NULL,
      created_at numeric,
      name text,
      applied_at TEXT
    )`,
  );
  for (const m of migrations) {
    db.run(
      sql`INSERT INTO __drizzle_migrations (hash, created_at, name, applied_at)
          VALUES (${m.hash}, ${m.folderMillis}, ${m.name}, ${appliedAt})`,
    );
  }

  console.log(`✓ Marked ${migrations.length} migration(s) as applied without executing any SQL.`);
}

function applyPending() {
  migrate(db, { migrationsFolder: MIGRATIONS_FOLDER });
  console.log('✓ Migrations up to date.');
}

if (process.argv.includes('--mark-applied')) {
  markAllApplied();
} else {
  applyPending();
}
