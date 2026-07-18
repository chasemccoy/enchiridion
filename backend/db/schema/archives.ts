import { sql } from 'drizzle-orm';
import { snakeCase, text, int, uniqueIndex } from 'drizzle-orm/sqlite-core';
import { databaseTimestamps } from './utils';
import { records } from './records';

const sqliteTable = snakeCase.table;

export const archiveStatusEnum = ['ok', 'failed'] as const;

/**
 * A local, self-contained web archive of a record's URL (the "Archive this page"
 * action). One current archive per record — re-archiving upserts the row.
 * `path` is the archive folder relative to ARCHIVE_DIR; the files themselves live
 * on disk and are served as static assets.
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
    /** Archive folder relative to ARCHIVE_DIR (null when the run failed). */
    path: text(),
    status: text({ enum: archiveStatusEnum }).notNull(),
    title: text(),
    /** Failure message when status is 'failed'. */
    error: text(),
    archivedAt: text()
      .notNull()
      .default(sql`(CURRENT_TIMESTAMP)`),
    ...databaseTimestamps,
  },
  (table) => [uniqueIndex('archives_record_id_idx').on(table.recordId)],
);

export type ArchiveSelect = typeof archives.$inferSelect;
export type ArchiveInsert = typeof archives.$inferInsert;
