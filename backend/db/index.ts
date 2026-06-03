import { drizzle } from 'drizzle-orm/better-sqlite3';
import Database from 'better-sqlite3';
import * as sqliteVec from 'sqlite-vec';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { relations } from '../db/schema/relations';
import {
  EMBEDDING_DIMENSIONS,
  VEC_META_TABLE,
  VEC_TABLE,
} from '../integrations/embeddings/constants';

// Anchor the SQLite path to the repo root, not the process CWD. The dev server
// happens to start from the repo root, but the `ench` CLI can be invoked from
// anywhere — a relative path would create an empty DB in whatever directory
// the user ran from. Override with DATABASE_PATH if you need to point at a
// different file (tests, scratch copies, etc.).
const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const databasePath = process.env.DATABASE_PATH ?? resolve(repoRoot, 'enchiridion.db');

const sqlite = new Database(databasePath);
sqlite.pragma('journal_mode = WAL');

// Load the sqlite-vec extension so the vec0 virtual table is available. These
// vector tables are managed here (not by Drizzle/drizzle-kit) because drizzle
// connections don't load the extension — see `tablesFilter` in drizzle.config.ts.
sqliteVec.load(sqlite);

// If the vec table was created with a different dimensionality (i.e. the
// embedding model was changed), drop and recreate it so the new vectors fit.
// Also wipe the meta table so its content-hash rows don't refer to vectors
// that no longer exist. Hashes are namespaced by model name anyway, so the
// next backfill would re-embed everything regardless.
const existingVec = sqlite
  .prepare(`SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?`)
  .get(VEC_TABLE) as { sql: string } | undefined;
if (existingVec && !existingVec.sql.includes(`FLOAT[${EMBEDDING_DIMENSIONS}]`)) {
  sqlite.exec(`DROP TABLE ${VEC_TABLE}`);
  sqlite.exec(`DROP TABLE IF EXISTS ${VEC_META_TABLE}`);
  // eslint-disable-next-line no-console
  console.log(
    `[embeddings] dimension changed → dropped ${VEC_TABLE}; run \`pnpm embed\` to backfill.`,
  );
}

sqlite.exec(
  `CREATE VIRTUAL TABLE IF NOT EXISTS ${VEC_TABLE} USING vec0(
    record_id INTEGER PRIMARY KEY,
    embedding FLOAT[${EMBEDDING_DIMENSIONS}] distance_metric=cosine
  )`,
);

sqlite.exec(
  `CREATE TABLE IF NOT EXISTS ${VEC_META_TABLE} (
    record_id INTEGER PRIMARY KEY,
    content_hash TEXT NOT NULL
  )`,
);

export const db = drizzle({ client: sqlite, relations });

export type Db = typeof db;

/** Absolute path of the SQLite file this process is connected to. */
export const DATABASE_PATH = databasePath;
