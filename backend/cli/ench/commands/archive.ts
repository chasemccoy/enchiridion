/**
 * Local web archive command for the `ench` CLI.
 *
 * Archives (or re-archives) a record's URL into a self-contained offline folder
 * — the same action as the record detail page's "Archive this page" button, and
 * a handy backfill path for records created by a sync.
 */

import { db } from '@db/index';
import { getRecord } from '@db/queries/records';
import { archiveRecord, pastVersionStamp } from '@integrations/archive';
import { z } from 'zod/v4';
import { BaseOptionsSchema, parseId, parseOptions } from '../lib/args';
import { createError } from '../lib/errors';
import { success } from '../lib/output';
import type { CommandHandler } from '../lib/types';

function isProbablyUrl(value: string): boolean {
  return /^https?:\/\//i.test(value);
}

/**
 * Usage: ench archive <record-id-or-url> [--at=<date|stamp|latest|wayback-url>]
 *
 * A URL is resolved to the record that owns it (every archive belongs to a
 * record), so a URL with no matching record is an error. `--at` archives a past
 * version from the Wayback Machine into the same folder's timeline.
 */
const ArchiveOptionsSchema = BaseOptionsSchema.extend({ at: z.string().optional() });

export const create: CommandHandler = async (args, options) => {
  const { at: requested } = parseOptions(ArchiveOptionsSchema, options);
  const target = args[0];
  if (!target) {
    throw createError('VALIDATION_ERROR', 'Usage: ench archive <record-id-or-url>');
  }

  let record;
  if (isProbablyUrl(target)) {
    record = await db.query.records.findFirst({ where: { url: target } });
    if (!record) {
      throw createError(
        'NOT_FOUND',
        `No record found with URL ${target}. Archive a record by id instead.`,
      );
    }
  } else {
    const id = parseId([target]);
    record = await getRecord(id);
    if (!record) throw createError('NOT_FOUND', `Record ${id} not found`);
  }

  if (!record.url) {
    throw createError('VALIDATION_ERROR', `Record ${record.id} has no URL to archive`);
  }

  let at: string | undefined;
  if (requested?.trim()) {
    try {
      at = pastVersionStamp(requested, record.url);
    } catch (error) {
      throw createError('VALIDATION_ERROR', (error as Error).message);
    }
  }

  const archive = await archiveRecord(record, { at });
  return success({
    recordId: record.id,
    url: archive.url,
    status: archive.status,
    path: archive.path,
    title: archive.title,
    error: archive.error,
  });
};
