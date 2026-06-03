import { sql } from 'drizzle-orm';
import { snakeCase, text, int, check, index, unique, uniqueIndex } from 'drizzle-orm/sqlite-core';
import { createInsertSchema, createSelectSchema } from 'drizzle-orm/zod';
import { contentTimestamps, databaseTimestamps, integrationTypeEnum } from './utils';
import { PredicateSlugSchema, recordTypeEnum, type PredicateSlug } from '@shared/types';

const sqliteTable = snakeCase.table;

export const records = sqliteTable(
  'records',
  {
    id: int().primaryKey({ autoIncrement: true }),
    slug: text().notNull(),
    type: text({ enum: recordTypeEnum }).notNull().default('artifact'),
    title: text(),
    url: text(),
    isCurated: int({ mode: 'boolean' }).notNull().default(false),
    summary: text(),
    content: text(),
    notes: text(),
    source: text({ enum: integrationTypeEnum }),
    ...databaseTimestamps,
    ...contentTimestamps,
  },
  (table) => [
    check('slug_not_empty', sql`${table.slug} != ''`),
    index('records_type_title_url_idx').on(table.type, table.title, table.url),
    uniqueIndex('records_slug_idx').on(table.slug),
    index('records_record_created_at_idx').on(table.recordCreatedAt),
    index('records_record_updated_at_idx').on(table.recordUpdatedAt),
    index('records_is_curated_idx').on(table.isCurated),
  ],
);

// export const RecordSelectSchema = createSelectSchema(records);
export type RecordSelect = typeof records.$inferSelect;
export const RecordInsertSchema = createInsertSchema(records);
export type RecordInsert = typeof records.$inferInsert;

export const links = sqliteTable(
  'links',
  {
    id: int().primaryKey({ autoIncrement: true }),
    sourceId: int()
      .references(() => records.id, {
        onDelete: 'cascade',
        onUpdate: 'cascade',
      })
      .notNull(),
    targetId: int()
      .references(() => records.id, {
        onDelete: 'cascade',
        onUpdate: 'cascade',
      })
      .notNull(),
    /** Predicate slug identifying the relationship type (e.g., 'contained_by', 'created_by') */
    predicate: text().notNull().$type<PredicateSlug>(),
    notes: text(),
    ...databaseTimestamps,
  },
  (table) => [
    index('links_source_predicate_idx').on(table.sourceId, table.predicate),
    index('links_target_predicate_idx').on(table.targetId, table.predicate),
    index('links_source_idx').on(table.sourceId),
    index('links_target_idx').on(table.targetId),
    index('links_predicate_idx').on(table.predicate),
    unique('links_source_target_predicate_unique').on(
      table.sourceId,
      table.targetId,
      table.predicate,
    ),
  ],
);

export const LinkSelectSchema = createSelectSchema(links);
export type LinkSelect = typeof links.$inferSelect;

export const LinkInsertSchema = createInsertSchema(links, {
  predicate: PredicateSlugSchema,
});
export type LinkInsert = typeof links.$inferInsert;
