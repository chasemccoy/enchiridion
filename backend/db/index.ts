import { drizzle } from 'drizzle-orm/better-sqlite3';
import Database from 'better-sqlite3';
import * as schema from '../db/schema';
import { relations } from '../db/schema/relations';

const sqlite = new Database('enchiridion.db');
sqlite.pragma('journal_mode = WAL');

// Verify FTS5 extension is available (should be default in SQLite 3.9+)
try {
  const fts5Check = sqlite
    .prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name='records_fts'")
    .get();
  if (!fts5Check) {
    // FTS5 table doesn't exist yet - this is expected on first run before migration
    // eslint-disable-next-line no-console
    console.warn('FTS5 table (records_fts) not found. Run migration to create it.');
  }
} catch {
  // Ignore errors - table might not exist yet
}

export const db = drizzle({ client: sqlite, schema, relations, casing: 'snake_case' });

// Export raw SQLite client for FTS5 and other raw SQL queries
export const sqliteClient = sqlite;

export type Db = typeof db;
