import { snakeCase, text, int, index } from 'drizzle-orm/sqlite-core';
import { databaseTimestamps } from './utils';
import { records } from './records';

const sqliteTable = snakeCase.table;

const mediaTypeEnum: [string, ...string[]] = [
  'application', // application or binary data
  'audio', // audio files
  'font', // font/typeface files
  'image', // images (jpg, png, etc)
  'message', // message data
  'model', // 3D models
  'multipart', // multipart files
  'text', // plain text, markdown, etc.
  'video', // video files
];

export const media = sqliteTable(
  'media',
  {
    id: int().primaryKey({ autoIncrement: true }),
    recordId: int().references(() => records.id, {
      onDelete: 'cascade',
      onUpdate: 'cascade',
    }),
    url: text().notNull(),
    altText: text(),
    type: text({ enum: mediaTypeEnum }).default('application'),
    contentTypeString: text().notNull().default('application/octet-stream'),
    fileSize: int(),
    width: int(),
    height: int(),
    ...databaseTimestamps,
  },
  (table) => [index('media_record_id_idx').on(table.recordId)],
);

export type MediaSelect = typeof media.$inferSelect;
export type MediaInsert = typeof media.$inferInsert;
