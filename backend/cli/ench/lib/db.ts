/**
 * Re-exports the project's better-sqlite3-backed Drizzle handle.
 *
 * The handle is initialised at import time (see backend/db/index.ts), so any
 * file that pulls this module in incurs the WAL/PRAGMA setup + sqlite-vec
 * extension load. Command modules import this through `./db` so we have a
 * single chokepoint if we ever need to swap in a different connection (a
 * read-only opener, an in-memory test DB, etc.).
 */

export { db, type Db } from '@db/index';
