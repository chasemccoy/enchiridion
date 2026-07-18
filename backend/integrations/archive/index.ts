/**
 * Local web archiving for records — the "Archive this page" action.
 *
 * This is the ONLY module in Enchiridion that imports the upstream archiver
 * package (`amber`). Everything else (the API route, the CLI command) depends on
 * `archiveRecord` / `archiveRoot` here, so if that project is renamed the change
 * is confined to this file plus `package.json`.
 */

import * as os from 'node:os';
import * as path from 'node:path';
import { archiveUrl } from 'amber';
import { sql } from 'drizzle-orm';
import { db } from '@db/index';
import { archives, type ArchiveInsert, type ArchiveSelect, type RecordSelect } from '@db/schema';

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

// Guard against a record being archived twice concurrently (e.g. a double
// request). The folder would just be overwritten, but two browser launches is
// wasteful — last writer would also race the DB row.
const inFlight = new Set<RecordSelect['id']>();

/** Insert or refresh the single archive row for a record. */
async function upsertArchive(row: ArchiveInsert): Promise<ArchiveSelect> {
  const [saved] = await db
    .insert(archives)
    .values(row)
    .onConflictDoUpdate({
      target: archives.recordId,
      set: {
        ...row,
        archivedAt: sql`(CURRENT_TIMESTAMP)`,
        recordUpdatedAt: sql`(CURRENT_TIMESTAMP)`,
      },
    })
    .returning();

  if (!saved) {
    throw new Error(`Archive upsert failed for record ${row.recordId}`);
  }
  return saved;
}

/**
 * Archive a record's URL into a self-contained local folder and record the
 * outcome. Best-effort: a failed run is persisted with `status: 'failed'` and an
 * error message rather than thrown, so the failure is visible in the UI.
 */
export async function archiveRecord(record: RecordSelect): Promise<ArchiveSelect> {
  if (!record.url) {
    throw new Error(`Record ${record.id} has no URL to archive`);
  }
  if (inFlight.has(record.id)) {
    throw new Error(`Record ${record.id} is already being archived`);
  }

  inFlight.add(record.id);
  const root = archiveRoot();
  try {
    const res = await archiveUrl(record.url, {
      outRoot: root,
      useLLM: true,
      model: 'claude-sonnet-4-6',
      backend: archiveBackend(),
      // Generous page-load timeout — archiving is a deliberate, user-initiated
      // action and some pages legitimately take a while.
      timeoutMs: 4 * 60 * 1000,
      insecureTLS: process.env.ARCHIVE_INSECURE_TLS === '1',
      verbose: false,
    });

    return await upsertArchive({
      recordId: record.id,
      url: record.url,
      status: 'ok',
      path: path.relative(root, res.outDir),
      title: res.plan.title || null,
      error: null,
    });
  } catch (err) {
    return await upsertArchive({
      recordId: record.id,
      url: record.url,
      status: 'failed',
      path: null,
      title: null,
      error: String((err as Error)?.message ?? err),
    });
  } finally {
    inFlight.delete(record.id);
  }
}
