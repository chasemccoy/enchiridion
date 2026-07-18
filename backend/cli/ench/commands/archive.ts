/**
 * Local web archive command for the `ench` CLI.
 *
 * Archives (or re-archives) a record's URL into a self-contained offline folder
 * — the same action as the record detail page's "Archive this page" button, and
 * a handy backfill path for records created by a sync.
 */

import { db } from '@db/index';
import { getRecord } from '@db/queries/records';
import { archiveRecord } from '@integrations/archive';
import { BaseOptionsSchema, parseId, parseOptions } from '../lib/args';
import { createError } from '../lib/errors';
import { success } from '../lib/output';
import type { CommandHandler } from '../lib/types';

function isProbablyUrl(value: string): boolean {
  return /^https?:\/\//i.test(value);
}

/**
 * Usage: ench archive <record-id-or-url>
 *
 * A URL is resolved to the record that owns it (every archive belongs to a
 * record), so a URL with no matching record is an error.
 */
export const create: CommandHandler = async (args, options) => {
  parseOptions(BaseOptionsSchema, options);
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

  const archive = await archiveRecord(record);
  return success({
    recordId: record.id,
    url: archive.url,
    status: archive.status,
    path: archive.path,
    title: archive.title,
    error: archive.error,
  });
};
