/**
 * Per-file test bootstrap. Runs before each test file (in its own forked
 * process — see vitest.config.ts), pointing the app's module-level singletons
 * at a scratch environment BEFORE anything imports them:
 *
 * - DATABASE_PATH → a fresh temp SQLite file, migrated from scratch, so tests
 *   never touch enchiridion.db (this is the override backend/db/index.ts
 *   exists for)
 * - ARCHIVE_DIR / ARCHIVE_BACKEND → temp folder, static-fetch captures only
 * - ANTHROPIC_API_KEY / OPENAI_API_KEY cleared → amber uses its heuristic
 *   plan and the embeddings layer no-ops; WAYBACK_AUTO_ARCHIVE=0 keeps new
 *   records from firing background requests at web.archive.org
 * - ENCHIRIDION_DEVICES → a path that doesn't exist, so the Tailscale auth
 *   scheme is off and the API open (a developer's ~/.enchiridion/devices or
 *   .env can't leak in); ENCHIRIDION_TAILSCALE → a binary that doesn't exist,
 *   so no test can run the real tailscale CLI even with the scheme on;
 *   ENCHIRIDION_API_HOST cleared, so the API's name is the default
 */
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';

const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'ench-test-'));
process.env.DATABASE_PATH = path.join(scratch, 'test.db');
process.env.ARCHIVE_DIR = path.join(scratch, 'archives');
process.env.ARCHIVE_BACKEND = 'fetch';
process.env.ANTHROPIC_API_KEY = '';
process.env.OPENAI_API_KEY = '';
process.env.WAYBACK_AUTO_ARCHIVE = '0';
process.env.ENCHIRIDION_DEVICES = path.join(scratch, 'devices');
process.env.ENCHIRIDION_TAILSCALE = path.join(scratch, 'no-tailscale');
delete process.env.ENCHIRIDION_API_HOST;

// Imported dynamically so the env above is set before the db module reads it.
const { db } = await import('@db/index');
const { migrate } = await import('drizzle-orm/better-sqlite3/migrator');

migrate(db, {
  migrationsFolder: path.resolve(import.meta.dirname, '../backend/db/migrations'),
});
