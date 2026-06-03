/**
 * Media commands for the `ench` CLI.
 */

import { promises as fs } from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { and, asc, desc, eq } from 'drizzle-orm';
import { z } from 'zod/v4';
import { getMedia, insertMedia, updateMedia } from '@db/queries/media';
import { getRecord } from '@db/queries/records';
import { media } from '@db/schema';
import { IdSchema, LimitSchema, OffsetSchema } from '@shared/types/api';
import { UPLOADS_DIR } from '@shared/lib';
import { BaseOptionsSchema, parseId, parseIds, parseJsonInput, parseOptions } from '../lib/args';
import { db } from '../lib/db';
import { createError } from '../lib/errors';
import { success } from '../lib/output';
import type { CommandHandler } from '../lib/types';

const MediaTypeSchema = z.enum([
  'application',
  'audio',
  'font',
  'image',
  'message',
  'model',
  'multipart',
  'text',
  'video',
]);

const MediaListOptionsSchema = z.looseObject({
  ...BaseOptionsSchema.shape,
  limit: LimitSchema.optional(),
  offset: OffsetSchema.optional(),
  record: z.coerce.number().int().positive().optional(),
  type: MediaTypeSchema.optional(),
  order: z.enum(['recordCreatedAt', 'recordUpdatedAt', 'id']).optional(),
  direction: z.enum(['asc', 'desc']).optional(),
});

const MediaGetOptionsSchema = z.looseObject({
  ...BaseOptionsSchema.shape,
  'with-record': z.boolean().optional(),
});

const MediaCreateOptionsSchema = z.looseObject({
  ...BaseOptionsSchema.shape,
  record: IdSchema,
  file: z.string().optional(),
  url: z.string().optional(),
  alt: z.string().optional(),
  type: z.string().optional(),
});

const MediaUpdateSchema = z.object({
  altText: z.string().nullable().optional(),
  url: z.string().optional(),
  type: MediaTypeSchema.optional(),
});

const MIME_TO_TYPE: Record<string, string> = {
  'image/jpeg': 'image',
  'image/png': 'image',
  'image/gif': 'image',
  'image/webp': 'image',
  'video/mp4': 'video',
  'video/quicktime': 'video',
  'video/x-msvideo': 'video',
  'application/pdf': 'application',
};

const MIME_TO_EXT: Record<string, string> = {
  'image/jpeg': '.jpg',
  'image/png': '.png',
  'image/gif': '.gif',
  'image/webp': '.webp',
  'video/mp4': '.mp4',
  'video/quicktime': '.mov',
  'video/x-msvideo': '.avi',
  'application/pdf': '.pdf',
};

function guessMimeFromExt(filePath: string): string | undefined {
  const ext = path.extname(filePath).toLowerCase();
  const entry = Object.entries(MIME_TO_EXT).find(([, value]) => value === ext);
  return entry?.[0];
}

/**
 * Get media item(s).
 * Usage: ench media get <id...> [--with-record]
 */
export const get: CommandHandler = async (args, options) => {
  const parsed = parseOptions(MediaGetOptionsSchema, options);
  const ids = parseIds(args);
  if (ids.length === 0) {
    throw createError('VALIDATION_ERROR', 'At least one ID is required');
  }
  const results = await Promise.all(
    ids.map(async (id) => {
      const item = await getMedia(id);
      if (!item) return { id, error: 'NOT_FOUND' as const };
      if (!parsed['with-record'] || !item.recordId) return item;
      const record = await getRecord(item.recordId);
      return { ...item, record };
    }),
  );
  if (ids.length === 1) {
    const result = results[0]!;
    if ('error' in result) throw createError('NOT_FOUND', `Media ${ids[0]} not found`);
    return success(result);
  }
  return success(results, { count: results.length });
};

/**
 * List media.
 * Usage: ench media list [--record=<id>] [--type=...] [--limit=N] [--offset=N]
 */
export const list: CommandHandler = async (_args, options) => {
  const parsed = parseOptions(MediaListOptionsSchema, options);
  const limit = parsed.limit ?? 50;
  const offset = parsed.offset ?? 0;

  const conds = [];
  if (parsed.record !== undefined) conds.push(eq(media.recordId, parsed.record));
  if (parsed.type !== undefined) conds.push(eq(media.type, parsed.type));

  const orderField =
    parsed.order === 'id'
      ? media.id
      : parsed.order === 'recordUpdatedAt'
        ? media.recordUpdatedAt
        : media.recordCreatedAt;
  const orderFn = parsed.direction === 'asc' ? asc : desc;

  const rows = await db
    .select()
    .from(media)
    .where(conds.length ? and(...conds) : undefined)
    .orderBy(orderFn(orderField))
    .limit(limit)
    .offset(offset);

  return success(rows, { count: rows.length, limit, offset });
};

/**
 * Create a media row. Accepts either a remote URL (no file copy) or a local
 * file (copied into uploads/<bucket>/<uuid><ext>).
 *
 * Usage:
 *   ench media create --record=<id> --url=<url> [--alt=...]
 *   ench media create --record=<id> --file=<path> [--alt=...] [--type=<mime>]
 */
export const create: CommandHandler = async (args, options) => {
  if (args.length > 0) {
    throw createError('VALIDATION_ERROR', 'Unexpected positional args. Use --file or --url.');
  }
  const parsed = parseOptions(MediaCreateOptionsSchema, options);
  if (parsed.file && parsed.url) {
    throw createError('VALIDATION_ERROR', 'Use either --file or --url, not both.');
  }
  if (!parsed.file && !parsed.url) {
    throw createError('VALIDATION_ERROR', 'Missing --file or --url.');
  }

  const record = await getRecord(parsed.record);
  if (!record) throw createError('NOT_FOUND', `Record ${parsed.record} not found`);

  const dryRun = options['dry-run'] === true || options.n === true;

  if (parsed.url) {
    if (dryRun) {
      return success({ wouldInsert: { recordId: parsed.record, url: parsed.url } });
    }
    const inserted = await insertMedia({
      recordId: parsed.record,
      url: parsed.url,
      altText: parsed.alt ?? null,
      contentTypeString: parsed.type ?? 'application/octet-stream',
      type: parsed.type ? (MIME_TO_TYPE[parsed.type] ?? 'application') : 'application',
    });
    return success(inserted);
  }

  // File path branch.
  const sourcePath = path.resolve(parsed.file!);
  const stat = await fs.stat(sourcePath).catch(() => null);
  if (!stat?.isFile()) {
    throw createError('IO_ERROR', `File not found: ${sourcePath}`);
  }
  const mime = parsed.type ?? guessMimeFromExt(sourcePath) ?? 'application/octet-stream';
  const mediaType = MIME_TO_TYPE[mime] ?? 'application';
  const ext = MIME_TO_EXT[mime] ?? path.extname(sourcePath);
  const id = crypto.randomUUID();
  const subdir = mediaType === 'image' ? 'images' : mediaType === 'video' ? 'videos' : 'pdfs';
  const destDir = path.join(UPLOADS_DIR, subdir);
  const destPath = path.join(destDir, `${id}${ext}`);
  const url = `/uploads/${subdir}/${id}${ext}`;

  if (dryRun) {
    return success({
      wouldCopy: { source: sourcePath, dest: destPath, url },
    });
  }

  await fs.mkdir(destDir, { recursive: true });
  await fs.copyFile(sourcePath, destPath);

  const inserted = await insertMedia({
    recordId: parsed.record,
    url,
    altText: parsed.alt ?? null,
    type: mediaType,
    contentTypeString: mime,
    fileSize: stat.size,
  });
  return success(inserted);
};

/**
 * Update a media row's metadata.
 * Usage: ench media update <id> '<json>'
 */
export const update: CommandHandler = async (args, options) => {
  parseOptions(BaseOptionsSchema, options);
  const id = parseId(args);
  const existing = await getMedia(id);
  if (!existing) throw createError('NOT_FOUND', `Media ${id} not found`);
  const input = await parseJsonInput(MediaUpdateSchema, args.slice(1));
  const updated = await updateMedia(id, input);
  return success(updated);
};
