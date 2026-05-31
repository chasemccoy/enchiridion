import { sql } from 'drizzle-orm';
import { snakeCase, text, int } from 'drizzle-orm/sqlite-core';
import { createInsertSchema, createSelectSchema } from 'drizzle-orm/zod';
import { z } from 'zod/v4';

const sqliteTable = snakeCase.table;

const recordCreatedAt = text('created_at')
  .notNull()
  .default(sql`(CURRENT_TIMESTAMP)`);

const recordUpdatedAt = text('updated_at')
  .notNull()
  .default(sql`(CURRENT_TIMESTAMP)`);

export const databaseTimestamps = {
  recordCreatedAt,
  recordUpdatedAt,
};

export const databaseTimestampsNonUpdatable = {
  recordCreatedAt,
};

const contentCreatedAt = text();
const contentUpdatedAt = text();

export const contentTimestamps = {
  contentCreatedAt,
  contentUpdatedAt,
};

export const integrationStatusEnum = ['success', 'fail', 'in_progress'] as const;
export const IntegrationStatus = z.enum(integrationStatusEnum);
export type IntegrationStatus = z.infer<typeof IntegrationStatus>;

export const integrationTypeEnum = ['manual', 'readwise', 'twitter'] as const;
export const IntegrationTypeSchema = z.enum(integrationTypeEnum);
export type IntegrationType = z.infer<typeof IntegrationTypeSchema>;

export const runTypeEnum = ['seed', 'sync'] as const;
export const RunType = z.enum(runTypeEnum);
export type RunType = z.infer<typeof RunType>;

export const integrationRuns = sqliteTable('integration_runs', {
  id: int().primaryKey({ autoIncrement: true }),
  integrationType: text({ enum: integrationTypeEnum }).notNull(),
  runType: text({ enum: runTypeEnum }).notNull().default('sync'),
  status: text({ enum: integrationStatusEnum }).notNull().default('in_progress'),
  message: text(),
  runStartTime: text().notNull(),
  runEndTime: text(),
  entriesCreated: int().default(0),
  ...databaseTimestampsNonUpdatable,
});

export const IntegrationRunSelectSchema = createSelectSchema(integrationRuns);
export type IntegrationRunSelect = typeof integrationRuns.$inferSelect;
export const IntegrationRunInsertSchema = createInsertSchema(integrationRuns);
export type IntegrationRunInsert = typeof integrationRuns.$inferInsert;
