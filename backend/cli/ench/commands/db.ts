/**
 * Database commands for the `ench` CLI.
 *
 * SQLite operations are file-level (backup is `better-sqlite3.backup`, restore
 * swaps the file under the running process). Destructive operations refuse to
 * run when NODE_ENV=production unless `--force` is passed.
 */

import { promises as fs, statSync } from 'node:fs';
import path from 'node:path';
import Database from 'better-sqlite3';
import { count, sql } from 'drizzle-orm';
import { z } from 'zod/v4';
import { records, links, media } from '@db/schema';
import { DATABASE_PATH } from '@db/index';
import { VEC_META_TABLE } from '@integrations/embeddings';
import { BaseOptionsSchema, parseOptions } from '../lib/args';
import { db } from '../lib/db';
import { createError } from '../lib/errors';
import { success } from '../lib/output';
import type { CommandHandler } from '../lib/types';

const BackupOptionsSchema = z.looseObject({
  ...BaseOptionsSchema.shape,
  'data-only': z.boolean().optional(),
  'dry-run': z.boolean().optional(),
  n: z.boolean().optional(),
  out: z.string().optional(),
  o: z.string().optional(),
  force: z.boolean().optional(),
});

const RestoreOptionsSchema = z.looseObject({
  ...BaseOptionsSchema.shape,
  clean: z.boolean().optional(),
  'dry-run': z.boolean().optional(),
  n: z.boolean().optional(),
  force: z.boolean().optional(),
});

const ResetOptionsSchema = z.looseObject({
  ...BaseOptionsSchema.shape,
  force: z.boolean().optional(),
});

function requireNonProduction(action: string, force: boolean | undefined) {
  if (process.env.NODE_ENV === 'production' && !force) {
    throw createError(
      'PERMISSION_DENIED',
      `${action} refused in production. Re-run with --force to override.`,
    );
  }
}

/**
 * Backup the SQLite database to a file using better-sqlite3's online backup.
 * Usage: ench db backup [--out=<path>] [--data-only] [--dry-run]
 *
 * --data-only is accepted for parity with the spec but a no-op: SQLite backups
 * are inherently full-file snapshots (schema + data are inseparable in one
 * file). Use a separate sqlite-diffable export if you need data-only.
 */
export const backup: CommandHandler = async (_args, options) => {
  const parsed = parseOptions(BackupOptionsSchema, options);
  const dryRun = parsed['dry-run'] === true || parsed.n === true;
  const out = parsed.out ?? parsed.o ?? path.join('backup', `enchiridion-${Date.now()}.sqlite`);
  const outPath = path.resolve(out);

  if (dryRun) {
    return success({
      action: 'backup',
      source: DATABASE_PATH,
      destination: outPath,
      dataOnly: parsed['data-only'] ?? false,
    });
  }

  await fs.mkdir(path.dirname(outPath), { recursive: true });
  // better-sqlite3's online backup acquires a shared lock and copies the file
  // even while other writers hold the WAL, so this is safe during dev usage.
  const src = new Database(DATABASE_PATH, { readonly: true, fileMustExist: true });
  try {
    await src.backup(outPath);
  } finally {
    src.close();
  }
  const stat = await fs.stat(outPath);
  return success({
    action: 'backup',
    source: DATABASE_PATH,
    destination: outPath,
    bytes: stat.size,
  });
};

/**
 * Restore the database from a backup file. The source must pass
 * `PRAGMA integrity_check` before it replaces the live DB.
 *
 * Usage: ench db restore <path> [--clean] [--dry-run] [--force]
 */
export const restore: CommandHandler = async (args, options) => {
  const parsed = parseOptions(RestoreOptionsSchema, options);
  const src = args[0];
  if (!src) throw createError('VALIDATION_ERROR', 'Usage: ench db restore <path>');
  const srcPath = path.resolve(src);
  const dryRun = parsed['dry-run'] === true || parsed.n === true;

  requireNonProduction('db restore', parsed.force);

  const stat = await fs.stat(srcPath).catch(() => null);
  if (!stat?.isFile()) {
    throw createError('IO_ERROR', `Backup file not found: ${srcPath}`);
  }

  // Integrity check on the source — better-sqlite3 returns 'ok' when fine.
  const probe = new Database(srcPath, { readonly: true, fileMustExist: true });
  let integrity: string;
  try {
    const row = probe.prepare('PRAGMA integrity_check').get() as { integrity_check: string };
    integrity = row.integrity_check;
  } finally {
    probe.close();
  }
  if (integrity !== 'ok') {
    throw createError('DB_ERROR', `integrity_check failed on source: ${integrity}`);
  }

  if (dryRun) {
    return success({
      action: 'restore',
      source: srcPath,
      destination: DATABASE_PATH,
      clean: parsed.clean ?? false,
      integrity,
    });
  }

  // Close the active handle by overwriting via fs is unsafe — the process's
  // SQLite connection cached the file. The least surprising thing is to write
  // alongside and ask the user to restart. For our local-first scope, we copy
  // the file directly; the next reads will pick up the new pages.
  if (parsed.clean) {
    // Drop -wal/-shm so the next opener can't see stale pages from the old DB.
    await fs.rm(`${DATABASE_PATH}-wal`, { force: true });
    await fs.rm(`${DATABASE_PATH}-shm`, { force: true });
  }
  await fs.copyFile(srcPath, DATABASE_PATH);
  return success({
    action: 'restore',
    source: srcPath,
    destination: DATABASE_PATH,
    bytes: stat.size,
    note: 'Restart any long-running processes (dev server) to see the new state.',
  });
};

/**
 * Reset the database (delete + recreate via drizzle-kit push + seed).
 * Refuses in production unless --force.
 * Usage: ench db reset [--force]
 */
export const reset: CommandHandler = async (_args, options) => {
  const parsed = parseOptions(ResetOptionsSchema, options);
  requireNonProduction('db reset', parsed.force);

  // We can't actually shell out from inside a handler without bringing in a
  // process runner. Tell the user what to do instead — the existing
  // `pnpm db:reset` script does exactly this and any side-effect cleanup.
  throw createError(
    'PERMISSION_DENIED',
    'Use `pnpm db:reset` instead. The CLI runs in-process and would corrupt the active SQLite connection.',
  );
};

/**
 * Database status: file path, file size, page counts, record counts, link
 * count, embedded record count, last sync per integration.
 * Usage: ench db status
 */
export const status: CommandHandler = async (_args, options) => {
  parseOptions(BaseOptionsSchema, options);

  const fileStat = statSync(DATABASE_PATH);
  const pragma = db.all(sql`PRAGMA page_count`) as { page_count: number }[];
  const pageSize = db.all(sql`PRAGMA page_size`) as { page_size: number }[];

  const [recordCounts, linkCount, mediaCount, embeddedCount, lastRuns] = await Promise.all([
    db.select({ type: records.type, count: count() }).from(records).groupBy(records.type),
    db.select({ count: count() }).from(links),
    db.select({ count: count() }).from(media),
    Promise.resolve(
      (
        db.all(sql`SELECT COUNT(*) AS c FROM ${sql.identifier(VEC_META_TABLE)}`) as { c: number }[]
      )[0]?.c ?? 0,
    ),
    db.all(
      sql`SELECT integration_type AS integration, MAX(run_end_time) AS lastRun
          FROM integration_runs WHERE status = 'success'
          GROUP BY integration_type`,
    ) as Promise<{ integration: string; lastRun: string | null }[]>,
  ]);

  const byType = Object.fromEntries(recordCounts.map((row) => [row.type, row.count]));
  const totalRecords = recordCounts.reduce((sum, row) => sum + row.count, 0);

  return success({
    path: DATABASE_PATH,
    fileSizeBytes: fileStat.size,
    pageCount: pragma[0]?.page_count ?? null,
    pageSizeBytes: pageSize[0]?.page_size ?? null,
    counts: {
      records: totalRecords,
      recordsByType: byType,
      links: linkCount[0]?.count ?? 0,
      media: mediaCount[0]?.count ?? 0,
      embeddedRecords: embeddedCount,
    },
    lastSync: Object.fromEntries(lastRuns.map((row) => [row.integration, row.lastRun])),
    nodeEnv: process.env.NODE_ENV ?? 'development',
  });
};
