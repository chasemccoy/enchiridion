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

import { existsSync, readdirSync, readFileSync } from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { archiveUrl, slugifyUrl } from 'amber';
import { eq, sql } from 'drizzle-orm';
import { db } from '@db/index';
import { archives, type ArchiveSelect, type RecordSelect } from '@db/schema';
import type { ArchiveVersion } from '@shared/types/archive';

export type { ArchiveVersion } from '@shared/types/archive';

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
 * Where a record's archive goes, relative to the archive root.
 *
 * Records share the flat `<root>/<slug>/` layout amber's own CLI and library use,
 * so a page archived either way lands in one folder with one version history
 * and shows up in the library index. Amber's slug drops the query string, so
 * two records whose URLs differ only there would share a slug; that case has
 * never occurred in practice, and when it does the later record is given its
 * own `<id>/` subfolder rather than being filed as a version of the other page.
 * Records with the same URL deliberately share the folder.
 */
export async function archivePrefix(record: RecordSelect): Promise<string> {
  if (!record.url) throw new Error(`Record ${record.id} has no URL to archive`);
  const slug = slugifyUrl(record.url);
  const takenByOtherUrl = await db.query.archives.findFirst({
    where: { path: slug, url: { ne: record.url } },
    columns: { id: true },
  });
  return takenByOtherUrl ? String(record.id) : '';
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

/**
 * Write a run's outcome onto the record's (claimed) archive row. `filed` is a past version (a Wayback capture older
 * than the current copy) filed into `versions/`: the run succeeded, but the current copy, and so the row's
 * path/title/archivedAt, stay as they were.
 */
async function finishArchive(
  recordId: RecordSelect['id'],
  outcome:
    | { status: 'ok'; path: string; title: string | null }
    | { status: 'filed' }
    | { status: 'failed'; error: string },
): Promise<ArchiveSelect> {
  const [saved] = await db
    .update(archives)
    .set(
      outcome.status === 'filed'
        ? { status: 'ok', error: null, recordUpdatedAt: sql`(CURRENT_TIMESTAMP)` }
        : outcome.status === 'ok'
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
 * A past version to archive, as asked for: a date ("2000", "2000-03", "2000-03-09"), a Wayback timestamp
 * ("20000309212237"), "latest" (a dead site's last capture), or a web.archive.org link to a capture of this record's
 * own page. Returns the timestamp amber takes as `at`; throws a message for the person when it can't be read, or
 * when the link is a capture of some other page.
 */
export function pastVersionStamp(input: string, recordUrl: string): string {
  const value = input.trim();
  const link = /^https?:\/\/(?:www\.)?web\.archive\.org\/web\/(\d{4,14})[a-z_]*\/(.+)$/i.exec(
    value,
  );
  if (link) {
    let original = link[2]!.replace(/^(https?:)\/(?!\/)/i, '$1//');
    if (!/^https?:\/\//i.test(original)) original = `http://${original}`;
    if (slugifyUrl(original) !== slugifyUrl(recordUrl)) {
      throw new Error(`That Wayback link is a capture of ${original}, not this record's page`);
    }
    return link[1]!;
  }
  if (/^(latest|\d{4,14})$/i.test(value)) return value.toLowerCase();
  const date = /^(\d{4})(?:-(\d{2})(?:-(\d{2}))?)?$/.exec(value);
  if (date) return date.slice(1).filter(Boolean).join('');
  throw new Error(
    `Can't read "${input}" as a date: use 2000, 2000-03, 2000-03-09, or a web.archive.org link`,
  );
}

/**
 * The captures in an archive folder, newest first: the top copy, then `versions/<stamp>/`, each read from the
 * manifest amber writes beside it. The folders are the history, so nothing about versions is stored in the
 * database. A folder without a readable manifest is skipped.
 */
export function listArchiveVersions(archivePath: string | null): ArchiveVersion[] {
  if (!archivePath) return [];
  const root = archiveRoot();
  const folder = path.resolve(root, archivePath);
  if (!folder.startsWith(path.resolve(root) + path.sep)) return [];

  const read = (dir: string, current: boolean): ArchiveVersion | null => {
    try {
      const manifest = JSON.parse(readFileSync(path.join(dir, 'manifest.json'), 'utf8')) as {
        snapshotAt?: string;
        capturedAt?: string;
        wayback?: unknown;
        title?: string;
      };
      return {
        path: path.relative(root, dir),
        date: manifest.snapshotAt ?? manifest.capturedAt ?? null,
        wayback: Boolean(manifest.wayback),
        title: manifest.title ?? null,
        current,
      };
    } catch {
      return null;
    }
  };

  const versionsDir = path.join(folder, 'versions');
  const past = existsSync(versionsDir)
    ? readdirSync(versionsDir, { withFileTypes: true })
        .filter((entry) => entry.isDirectory())
        .map((entry) => read(path.join(versionsDir, entry.name), false))
    : [];
  return [read(folder, true), ...past]
    .filter((version): version is ArchiveVersion => version !== null)
    .sort((a, b) => (a.current ? -1 : b.current ? 1 : (b.date ?? '').localeCompare(a.date ?? '')));
}

/** Test seam: an alternate Wayback host, with no politeness delay (ARCHIVE_WAYBACK_BASE). */
function waybackOptions(): { base: string; requestDelayMs: number } | undefined {
  const base = process.env.ARCHIVE_WAYBACK_BASE?.trim();
  return base ? { base, requestDelayMs: 0 } : undefined;
}

/**
 * Run the capture for an already-claimed record and persist the outcome.
 * Best-effort: a failed run is recorded on the row rather than thrown, so the
 * failure is visible in the UI. `at` archives a past version from the Wayback
 * Machine (`pastVersionStamp`): amber files it into the same folder's timeline
 * by its snapshot date, as a past version when the folder already has a newer
 * copy.
 */
export async function runArchive(
  record: RecordSelect,
  options: { at?: string } = {},
): Promise<ArchiveSelect> {
  if (!record.url) {
    throw new Error(`Record ${record.id} has no URL to archive`);
  }

  const root = archiveRoot();
  try {
    const res = await archiveUrl(record.url, {
      outRoot: path.join(root, await archivePrefix(record)),
      useLLM: true,
      model: 'claude-sonnet-4-6',
      backend: archiveBackend(),
      // Generous page-load timeout — archiving is a deliberate, user-initiated
      // action and some pages legitimately take a while.
      timeoutMs: 4 * 60 * 1000,
      insecureTLS: process.env.ARCHIVE_INSECURE_TLS === '1',
      verbose: false,
      ...(options.at ? { at: options.at, wayback: waybackOptions() } : {}),
    });

    if (res.filedAs) return await finishArchive(record.id, { status: 'filed' });
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
export async function archiveRecord(
  record: RecordSelect,
  options: { at?: string } = {},
): Promise<ArchiveSelect> {
  const claimed = await claimArchive(record);
  if (!claimed) {
    throw new Error(`Record ${record.id} is already being archived`);
  }
  return runArchive(record, options);
}
