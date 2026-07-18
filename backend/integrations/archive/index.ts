/**
 * Local web archiving for records — the "Archive this page" action.
 *
 * This is the ONLY module in Enchiridion that imports the upstream archiver
 * package (`amber`). Everything else (the API route, the CLI command) depends on
 * `archiveRecord` / `archiveRoot` here, so if that project is renamed the change
 * is confined to this file plus `package.json`.
 *
 * Row semantics: `status`/`error` describe the latest run ('pending' → 'ok' |
 * 'failed'), while `path`/`title`/`archivedAt` always describe the last
 * successful capture — a failed re-archive records the error without wiping the
 * working copy. The 'pending' row is also the concurrency guard: it lives in
 * the DB, so it holds across the API server and the `ench` CLI (separate
 * processes an in-memory lock can't see).
 */

import * as os from 'node:os';
import * as path from 'node:path';
import { archiveUrl } from 'amber';
import { eq, sql } from 'drizzle-orm';
import { db } from '@db/index';
import { archives, type ArchiveSelect, type RecordSelect } from '@db/schema';

/** Root directory archive folders are written to (and served from). */
export function archiveRoot(): string {
  const configured = process.env.ARCHIVE_DIR?.trim();
  return configured || path.join(os.homedir(), 'Documents', 'Archives');
}

/**
 * Capture backend. Defaults to a full headless-Chromium render: this is a
 * deliberate "save a faithful copy" action, so fidelity beats speed. The render
 * runs the page's JS and scrolls to trigger lazy-loaded images — `auto` (static
 * fetch, escalate only if the page looks empty) silently under-captures
 * JS-rendered or lazy-loading pages. Override with ARCHIVE_BACKEND if needed.
 */
function archiveBackend(): 'fetch' | 'playwright' | 'auto' {
  const v = process.env.ARCHIVE_BACKEND?.trim();
  if (v === 'fetch' || v === 'auto') return v;
  return 'playwright';
}

/**
 * A 'pending' claim older than this is treated as abandoned (the archiving
 * process died before writing an outcome) and may be reclaimed. The longest
 * legitimate run is bounded by the 4-minute page-load timeout plus asset
 * downloads and the cleanup-plan call.
 */
const PENDING_STALE_MS = 10 * 60 * 1000;

/**
 * Atomically claim a record's archive row by marking it 'pending'. Returns the
 * claimed row, or null when another run (from this process, the CLI, or the
 * server) already holds a fresh claim — SQLite serializes the conditional
 * upsert, so exactly one claimant wins.
 */
export async function claimArchive(record: RecordSelect): Promise<ArchiveSelect | null> {
  if (!record.url) {
    throw new Error(`Record ${record.id} has no URL to archive`);
  }

  const [claimed] = await db
    .insert(archives)
    .values({ recordId: record.id, url: record.url, status: 'pending', error: null })
    .onConflictDoUpdate({
      target: archives.recordId,
      set: {
        url: record.url,
        status: 'pending',
        error: null,
        recordUpdatedAt: sql`(CURRENT_TIMESTAMP)`,
      },
      // Only take the row when no fresh claim is on it; stale claims are
      // reclaimable so a crashed run doesn't wedge the record forever.
      setWhere: sql`NOT (${archives.status} = 'pending' AND unixepoch(${archives.recordUpdatedAt}) > unixepoch('now') - ${PENDING_STALE_MS / 1000})`,
    })
    .returning();

  return claimed ?? null;
}

/** Write a run's outcome onto the record's (claimed) archive row. */
async function finishArchive(
  recordId: RecordSelect['id'],
  outcome:
    | { status: 'ok'; path: string; title: string | null }
    | { status: 'failed'; error: string },
): Promise<ArchiveSelect> {
  const [saved] = await db
    .update(archives)
    .set(
      outcome.status === 'ok'
        ? {
            status: 'ok',
            path: outcome.path,
            title: outcome.title,
            error: null,
            archivedAt: sql`(CURRENT_TIMESTAMP)`,
            recordUpdatedAt: sql`(CURRENT_TIMESTAMP)`,
          }
        : {
            // Leave path/title/archivedAt alone: they point at the last
            // successful capture, which a failed re-run must not orphan.
            status: 'failed',
            error: outcome.error,
            recordUpdatedAt: sql`(CURRENT_TIMESTAMP)`,
          },
    )
    .where(eq(archives.recordId, recordId))
    .returning();

  if (!saved) {
    throw new Error(`Archive row missing for record ${recordId}`);
  }
  return saved;
}

/**
 * Run the capture for an already-claimed record and persist the outcome.
 * Best-effort: a failed run is recorded on the row rather than thrown, so the
 * failure is visible in the UI.
 */
export async function runArchive(record: RecordSelect): Promise<ArchiveSelect> {
  if (!record.url) {
    throw new Error(`Record ${record.id} has no URL to archive`);
  }

  const root = archiveRoot();
  try {
    const res = await archiveUrl(record.url, {
      // Each record archives into its own subfolder: amber's folder slug is
      // host+pathname only, so records whose URLs differ only by query string
      // (e.g. youtube.com/watch?v=…) would otherwise collide in one folder.
      outRoot: path.join(root, String(record.id)),
      useLLM: true,
      model: 'claude-sonnet-4-6',
      backend: archiveBackend(),
      // Generous page-load timeout — archiving is a deliberate, user-initiated
      // action and some pages legitimately take a while.
      timeoutMs: 4 * 60 * 1000,
      insecureTLS: process.env.ARCHIVE_INSECURE_TLS === '1',
      verbose: false,
    });

    return await finishArchive(record.id, {
      status: 'ok',
      path: path.relative(root, res.outDir),
      title: res.plan.title || null,
    });
  } catch (err) {
    return await finishArchive(record.id, {
      status: 'failed',
      error: String((err as Error)?.message ?? err),
    });
  }
}

/**
 * Claim + run in one awaited call — the synchronous path used by the CLI (and
 * anything happy to wait out the capture). Throws when another run already
 * holds the claim.
 */
export async function archiveRecord(record: RecordSelect): Promise<ArchiveSelect> {
  const claimed = await claimArchive(record);
  if (!claimed) {
    throw new Error(`Record ${record.id} is already being archived`);
  }
  return runArchive(record);
}
