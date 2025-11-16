import { db, sqliteClient } from '@db/index';
import type { RecordSelect } from '@db/schema';

/**
 * Rebuild the entire FTS5 index
 * Useful after migrations, data corruption, or when triggers fail
 */
export async function rebuildFTS5Index(): Promise<number> {
  // Delete all existing FTS5 data
  sqliteClient.prepare('DELETE FROM records_fts').run();

  // Re-populate from records table
  const result = sqliteClient
    .prepare(
      `
      INSERT INTO records_fts(id, title, summary, content, notes)
      SELECT id, title, summary, content, notes
      FROM records
    `,
    )
    .run();

  return result.changes || 0;
}

/**
 * Sync a single record to the FTS5 table
 * Useful for manual synchronization or fixing individual records
 */
export async function syncFTS5ForRecord(recordId: RecordSelect['id']): Promise<boolean> {
  // Get the record
  const record = await db.query.records.findFirst({
    where: { id: recordId },
    columns: {
      id: true,
      title: true,
      summary: true,
      content: true,
      notes: true,
    },
  });

  if (!record) {
    return false;
  }

  // Check if record exists in FTS5
  const existing = sqliteClient
    .prepare('SELECT id FROM records_fts WHERE id = ? LIMIT 1')
    .get(recordId) as { id: number } | undefined;

  if (existing) {
    // Update existing
    sqliteClient
      .prepare(
        `
        UPDATE records_fts
        SET title = ?, 
            summary = ?, 
            content = ?, 
            notes = ?
        WHERE id = ?
      `,
      )
      .run(record.title, record.summary, record.content, record.notes, recordId);
  } else {
    // Insert new
    sqliteClient
      .prepare(
        `
        INSERT INTO records_fts(id, title, summary, content, notes)
        VALUES (?, ?, ?, ?, ?)
      `,
      )
      .run(record.id, record.title, record.summary, record.content, record.notes);
  }

  return true;
}

/**
 * Verify FTS5 table integrity by checking record counts
 * Returns true if counts match, false otherwise
 */
export async function verifyFTS5Integrity(): Promise<{
  isValid: boolean;
  recordsCount: number;
  fts5Count: number;
}> {
  const recordsCountResult = sqliteClient
    .prepare('SELECT COUNT(*) as count FROM records')
    .get() as { count: number };
  const fts5CountResult = sqliteClient
    .prepare('SELECT COUNT(*) as count FROM records_fts')
    .get() as { count: number };

  const recordsCount = recordsCountResult?.count || 0;
  const fts5Count = fts5CountResult?.count || 0;

  return {
    isValid: recordsCount === fts5Count,
    recordsCount,
    fts5Count,
  };
}
