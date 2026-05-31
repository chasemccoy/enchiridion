import { index, int, snakeCase, text, unique, type AnySQLiteColumn } from 'drizzle-orm/sqlite-core';
import { contentTimestamps, databaseTimestamps, integrationRuns } from './utils';
import { records } from './records';
import { z } from 'zod/v4';

const sqliteTable = snakeCase.table;

export const readwiseLocationEnum = ['new', 'later', 'shortlist', 'archive', 'feed'] as const;

export const ReadwiseLocation = z.enum(readwiseLocationEnum);
export type ReadwiseLocation = z.infer<typeof ReadwiseLocation>;

export const readwiseCategoryEnum = [
  'article',
  'email',
  'rss',
  'highlight',
  'note',
  'pdf',
  'epub',
  'tweet',
  'video',
  'book',
] as const;

export const ReadwiseCategory = z.enum(readwiseCategoryEnum);
export type ReadwiseCategory = z.infer<typeof ReadwiseCategory>;

export const readwiseDocuments = sqliteTable(
  'readwise_documents',
  {
    id: text().primaryKey(),
    url: text().notNull(),
    sourceUrl: text(),
    title: text(),
    author: text(),
    authorId: int().references(() => readwiseAuthors.id, {
      onDelete: 'set null',
      onUpdate: 'cascade',
    }),
    source: text(),
    content: text(),
    htmlContent: text(),
    category: text({ enum: readwiseCategoryEnum }),
    location: text({ enum: readwiseLocationEnum }),
    tags: text({ mode: 'json' }).$type<string[]>(),
    siteName: text(),
    wordCount: int(),
    notes: text(),
    summary: text(),
    imageUrl: text(),
    parentId: text().references((): AnySQLiteColumn => readwiseDocuments.id, {
      onDelete: 'cascade',
      onUpdate: 'cascade',
    }),
    readingProgress: int(),
    publishedDate: text(),
    firstOpenedAt: text(),
    lastOpenedAt: text(),
    savedAt: text().notNull(),
    lastMovedAt: text().notNull(),
    integrationRunId: int()
      .references(() => integrationRuns.id)
      .notNull(),
    recordId: int().references(() => records.id, {
      onDelete: 'set null',
      onUpdate: 'cascade',
    }),
    deletedAt: text(),
    ...contentTimestamps,
    ...databaseTimestamps,
  },
  (table) => [
    index('readwise_documents_parent_id_idx').on(table.parentId),
    index('readwise_documents_record_id_idx').on(table.recordId),
    index('readwise_documents_author_id_idx').on(table.authorId),
    index('readwise_documents_deleted_at_idx').on(table.deletedAt),
  ],
);

export type ReadwiseDocumentSelect = typeof readwiseDocuments.$inferSelect;
export type ReadwiseDocumentInsert = typeof readwiseDocuments.$inferInsert;

export const readwiseAuthors = sqliteTable(
  'readwise_authors',
  {
    id: int().primaryKey({ autoIncrement: true }),
    name: text().notNull(),
    origin: text(),
    recordId: int().references(() => records.id, {
      onDelete: 'set null',
      onUpdate: 'cascade',
    }),
    deletedAt: text(),
    ...databaseTimestamps,
  },
  (table) => [
    index('readwise_authors_name_idx').on(table.name),
    index('readwise_authors_origin_idx').on(table.origin),
    unique().on(table.name, table.origin),
    index('readwise_authors_deleted_at_idx').on(table.deletedAt),
  ],
);

export type ReadwiseAuthorSelect = typeof readwiseAuthors.$inferSelect;
export type ReadwiseAuthorInsert = typeof readwiseAuthors.$inferInsert;

export const readwiseTags = sqliteTable(
  'readwise_tags',
  {
    id: int().primaryKey({ autoIncrement: true }),
    tag: text().unique().notNull(),
    recordId: int().references(() => records.id, {
      onDelete: 'set null',
      onUpdate: 'cascade',
    }),
    deletedAt: text(),
    ...databaseTimestamps,
  },
  (table) => [index('readwise_tags_deleted_at_idx').on(table.deletedAt)],
);

export type ReadwiseTagSelect = typeof readwiseTags.$inferSelect;
export type ReadwiseTagInsert = typeof readwiseTags.$inferInsert;

export const readwiseDocumentTags = sqliteTable(
  'readwise_document_tags',
  {
    id: int().primaryKey({ autoIncrement: true }),
    documentId: text()
      .notNull()
      .references(() => readwiseDocuments.id, {
        onDelete: 'cascade',
        onUpdate: 'cascade',
      })
      .notNull(),
    tagId: int()
      .notNull()
      .references(() => readwiseTags.id, {
        onDelete: 'cascade',
        onUpdate: 'cascade',
      }),
    deletedAt: text(),
    ...databaseTimestamps,
  },
  (table) => [
    index('readwise_document_tags_document_id_idx').on(table.documentId),
    index('readwise_document_tags_tag_id_idx').on(table.tagId),
    unique().on(table.documentId, table.tagId),
  ],
);

export type ReadwiseDocumentTagSelect = typeof readwiseDocumentTags.$inferSelect;
export type ReadwiseDocumentTagInsert = typeof readwiseDocumentTags.$inferInsert;
