/**
 * Inbox commands for the `ench` CLI.
 *
 * The "inbox" surfaces Readwise documents that haven't been promoted to a
 * record yet — i.e. rows in `readwise_documents` where `record_id IS NULL`.
 * (The frontend InboxView uses a different signal — uncurated records — so
 * these results won't match it 1:1; see open question in the report.)
 */

import { and, asc, desc, eq, isNull, sql } from 'drizzle-orm';
import { z } from 'zod/v4';
import { readwiseDocuments } from '@db/schema';
import { upsertRecord } from '@db/queries/records';
import { slugify } from '@shared/lib/formatting';
import { BaseOptionsSchema, LimitSchema, parseOptions } from '../lib/args';
import { db } from '../lib/db';
import { createError } from '../lib/errors';
import { success } from '../lib/output';
import type { CommandHandler } from '../lib/types';

const InboxListOptionsSchema = z.looseObject({
  ...BaseOptionsSchema.shape,
  limit: LimitSchema.optional(),
});

const InboxPromoteOptionsSchema = z.looseObject({
  ...BaseOptionsSchema.shape,
  curated: z.boolean().optional(),
});

/** Common condition: Readwise doc that hasn't been promoted to a record yet. */
const unpromoted = and(isNull(readwiseDocuments.recordId), isNull(readwiseDocuments.deletedAt));

/**
 * List unprocessed Readwise documents.
 * Usage: ench inbox list [--limit=N]
 */
export const list: CommandHandler = async (_args, options) => {
  const parsed = parseOptions(InboxListOptionsSchema, options);
  const limit = parsed.limit ?? 25;
  const rows = await db
    .select({
      id: readwiseDocuments.id,
      title: readwiseDocuments.title,
      url: readwiseDocuments.url,
      author: readwiseDocuments.author,
      category: readwiseDocuments.category,
      location: readwiseDocuments.location,
      savedAt: readwiseDocuments.savedAt,
      summary: readwiseDocuments.summary,
    })
    .from(readwiseDocuments)
    .where(unpromoted)
    .orderBy(desc(readwiseDocuments.savedAt))
    .limit(limit);
  return success(rows, { count: rows.length, limit });
};

/**
 * Return the next unprocessed Readwise document.
 *
 * No in-progress marking — the schema doesn't have a column for that and
 * adding one is out of scope for this CLI. Use `ench inbox promote <id>` to
 * convert it to a record, or `ench inbox dismiss <id>` to skip it.
 *
 * Usage: ench inbox next
 */
export const next: CommandHandler = async (_args, options) => {
  parseOptions(BaseOptionsSchema, options);
  const [row] = await db
    .select()
    .from(readwiseDocuments)
    .where(unpromoted)
    .orderBy(asc(readwiseDocuments.savedAt))
    .limit(1);
  if (!row) return success(null);
  return success(row);
};

/**
 * Promote a Readwise document to a record.
 * Usage: ench inbox promote <document-id> [--curated]
 */
export const promote: CommandHandler = async (args, options) => {
  const parsed = parseOptions(InboxPromoteOptionsSchema, options);
  const docId = args[0];
  if (!docId) {
    throw createError('VALIDATION_ERROR', 'Usage: ench inbox promote <document-id>');
  }
  const [doc] = await db
    .select()
    .from(readwiseDocuments)
    .where(eq(readwiseDocuments.id, docId))
    .limit(1);
  if (!doc) throw createError('NOT_FOUND', `Readwise document ${docId} not found`);
  if (doc.recordId) {
    throw createError('CONFLICT', `Document ${docId} already linked to record ${doc.recordId}`);
  }

  const dryRun = options['dry-run'] === true || options.n === true;
  const slug = slugify(doc.title || doc.url || docId);
  if (dryRun) {
    return success({
      wouldCreate: {
        slug,
        title: doc.title,
        url: doc.url,
        source: 'readwise' as const,
      },
    });
  }

  const record = await upsertRecord({
    slug,
    title: doc.title ?? null,
    url: doc.url,
    type: 'artifact',
    source: 'readwise',
    content: doc.content ?? null,
    summary: doc.summary ?? null,
    notes: doc.notes ?? null,
    contentCreatedAt: doc.publishedDate ?? null,
    isCurated: parsed.curated ?? false,
  });
  await db
    .update(readwiseDocuments)
    .set({ recordId: record.id, recordUpdatedAt: sql`(CURRENT_TIMESTAMP)` })
    .where(eq(readwiseDocuments.id, docId));
  return success({ document: docId, record });
};

/**
 * Mark a Readwise document as dismissed (without creating a record).
 * Implemented via the deletedAt soft-delete column.
 * Usage: ench inbox dismiss <document-id>
 */
export const dismiss: CommandHandler = async (args, options) => {
  parseOptions(BaseOptionsSchema, options);
  const docId = args[0];
  if (!docId) {
    throw createError('VALIDATION_ERROR', 'Usage: ench inbox dismiss <document-id>');
  }
  const dryRun = options['dry-run'] === true || options.n === true;
  if (dryRun) {
    return success({ wouldDismiss: docId });
  }
  const [updated] = await db
    .update(readwiseDocuments)
    .set({ deletedAt: sql`(CURRENT_TIMESTAMP)` })
    .where(and(eq(readwiseDocuments.id, docId), isNull(readwiseDocuments.recordId)))
    .returning({ id: readwiseDocuments.id });
  if (!updated) {
    throw createError(
      'NOT_FOUND',
      `Unprocessed Readwise document ${docId} not found (or already promoted)`,
    );
  }
  return success({ dismissed: docId });
};
