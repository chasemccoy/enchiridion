import { sql } from 'drizzle-orm';
import { snakeCase, text, int, uniqueIndex } from 'drizzle-orm/sqlite-core';
import { databaseTimestamps } from './utils';
import { records } from './records';

const sqliteTable = snakeCase.table;

export const archiveStatusEnum = ['pending', 'ok', 'failed'] as const;

/**
 * A local, self-contained web archive of a record's URL (the "Archive this page"
 * action). One current archive per record — re-archiving upserts the row.
 *
 * `status`/`error` describe the LATEST run ('pending' → 'ok' | 'failed'), while
 * `path`/`title`/`archivedAt` always describe the last SUCCESSFUL capture, so a
 * failed re-archive never orphans a working copy. The 'pending' status doubles
 * as the cross-process claim on the row (see `claimArchive`).
 */
export const archives = sqliteTable(
  'archives',
  {
    id: int().primaryKey({ autoIncrement: true }),
    recordId: int()
      .references(() => records.id, {
        onDelete: 'cascade',
        onUpdate: 'cascade',
      })
      .notNull(),
    url: text().notNull(),
    /**
     * Folder of the last successful capture, relative to ARCHIVE_DIR (null when
     * no run has succeeded yet).
     */
    path: text(),
    status: text({ enum: archiveStatusEnum }).notNull(),
    title: text(),
    /** Failure message when status is 'failed'. */
    error: text(),
    /** When the last successful capture was taken. */
    archivedAt: text()
      .notNull()
      .default(sql`(CURRENT_TIMESTAMP)`),
    ...databaseTimestamps,
  },
  (table) => [uniqueIndex('archives_record_id_idx').on(table.recordId)],
);

export type ArchiveSelect = typeof archives.$inferSelect;
export type ArchiveInsert = typeof archives.$inferInsert;
