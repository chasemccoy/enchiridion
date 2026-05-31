import { sql } from 'drizzle-orm';
import {
  snakeCase,
  text,
  int,
  type AnySQLiteColumn,
  check,
  index,
  unique,
  uniqueIndex,
} from 'drizzle-orm/sqlite-core';
import { createInsertSchema, createSelectSchema } from 'drizzle-orm/zod';
import { contentTimestamps, databaseTimestamps, integrationTypeEnum } from './utils';
import { recordTypeEnum } from '@shared/types';

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
    predicateId: int()
      .references(() => predicates.id, {
        onDelete: 'cascade',
        onUpdate: 'cascade',
      })
      .notNull(),
    notes: text(),
    ...databaseTimestamps,
  },
  (table) => [
    index('links_source_predicate_idx').on(table.sourceId, table.predicateId),
    index('links_target_predicate_idx').on(table.targetId, table.predicateId),
    index('links_source_idx').on(table.sourceId),
    index('links_target_idx').on(table.targetId),
    index('links_predicate_idx').on(table.predicateId),
    unique('links_source_target_predicate_unique').on(
      table.sourceId,
      table.targetId,
      table.predicateId,
    ),
  ],
);

export const LinkSelectSchema = createSelectSchema(links);
export type LinkSelect = typeof links.$inferSelect;

export const LinkInsertSchema = createInsertSchema(links);
export type LinkInsert = typeof links.$inferInsert;

const predicateTypeEnum: [string, ...string[]] = [
  'creation', // authorship, ownership …
  'containment', // has_part, sequence …
  'description', // about, tag …
  'association', // related_to, similar_to …
  'reference', // cites, responds_to …
  'identity', // instance_of, same_as …
] as const;

export const predicates = sqliteTable(
  'predicates',
  {
    id: int().primaryKey({ autoIncrement: true }),
    slug: text().notNull(),
    name: text().notNull(),
    type: text({ enum: predicateTypeEnum }).notNull(),
    role: text(),
    inverseSlug: text().references((): AnySQLiteColumn => predicates.slug, {
      onDelete: 'set null',
      onUpdate: 'cascade',
    }),
    canonical: int({ mode: 'boolean' }).notNull().default(true),
    ...databaseTimestamps,
  },
  (table) => [
    index('predicates_id_type_idx').on(table.id, table.type),
    uniqueIndex('predicates_slug_idx').on(table.slug),
    index('predicates_type_idx').on(table.type),
    index('predicates_role_idx').on(table.role),
    index('predicates_canonical_idx').on(table.canonical),
    index('predicates_inverse_slug_idx').on(table.inverseSlug),
    index('predicates_type_canonical_idx').on(table.type, table.canonical),
  ],
);

// export const PredicateSelectSchema = createSelectSchema(predicates);
export type PredicateSelect = typeof predicates.$inferSelect;
// export const PredicateInsertSchema = createInsertSchema(predicates);
export type PredicateInsert = typeof predicates.$inferInsert;
