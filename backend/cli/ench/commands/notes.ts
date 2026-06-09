/**
 * Notes commands for the `ench` CLI.
 *
 * Notes are records with `type: 'note'`, so these are thin sugar over the
 * existing `records` handlers: `list` is filtered to notes (pinned first),
 * `create` forces the note type and fills a slug, and `pin`/`unpin` toggle the
 * `isPinned` flag. `get`/`update`/`delete` delegate verbatim to records.
 */

import { z } from 'zod/v4';
import { getRecord, listRecords, upsertRecord } from '@db/queries/records';
import { RecordInsertSchema } from '@db/schema';
import { generateSlug } from '@shared/lib/formatting';
import {
  BaseOptionsSchema,
  LimitSchema,
  OffsetSchema,
  parseId,
  parseJsonInput,
  parseOptions,
} from '../lib/args';
import { createError } from '../lib/errors';
import { success } from '../lib/output';
import type { CommandHandler } from '../lib/types';
import { get, update, del } from './records';

// Identical behavior to records for these — a note is just a record.
export { get, update, del };
export { del as delete };

const NotesListOptionsSchema = z.looseObject({
  ...BaseOptionsSchema.shape,
  limit: LimitSchema.optional(),
  offset: OffsetSchema.optional(),
  pinned: z.boolean().optional(),
  full: z.boolean().optional(),
});

/**
 * List notes, pinned first then newest.
 * Usage: ench notes list [--pinned] [--limit=N] [--full]
 */
export const list: CommandHandler = async (_args, options) => {
  const parsed = parseOptions(NotesListOptionsSchema, options);

  const rows = await listRecords({
    filters: { type: 'note', isPinned: parsed.pinned },
    orderBy: [
      { field: 'isPinned', direction: 'desc' },
      { field: 'recordCreatedAt', direction: 'desc' },
    ],
    limit: parsed.limit ?? 100,
    offset: parsed.offset ?? 0,
  });

  if (parsed.full) {
    return success(rows, { count: rows.length });
  }

  const summary = rows.map((row) => ({
    id: row.id,
    slug: row.slug,
    title: row.title,
    isPinned: row.isPinned,
  }));
  return success(summary, { count: summary.length });
};

/**
 * Create a note. Forces `type: 'note'` and auto-fills a slug when none is given
 * (notes are frequently untitled).
 * Usage: ench notes create '<json>'  (or pipe JSON on stdin)
 */
export const create: CommandHandler = async (args, options) => {
  parseOptions(BaseOptionsSchema, options);
  const input = await parseJsonInput(RecordInsertSchema.partial(), args);
  const slug = input.slug?.trim()
    ? input.slug.trim()
    : generateSlug({ title: input.title, type: 'note' });
  try {
    const record = await upsertRecord({ ...input, slug, type: 'note' });
    return success(record);
  } catch (e) {
    throw createError('VALIDATION_ERROR', e instanceof Error ? e.message : String(e));
  }
};

const setPinned =
  (isPinned: boolean): CommandHandler =>
  async (args, options) => {
    parseOptions(BaseOptionsSchema, options);
    const id = parseId(args);
    const existing = await getRecord(id);
    if (!existing) throw createError('NOT_FOUND', `Record ${id} not found`);
    await upsertRecord({ id, slug: existing.slug, isPinned });
    return success({ id, isPinned });
  };

/** Pin a note. Usage: ench notes pin <id> */
export const pin = setPinned(true);
/** Unpin a note. Usage: ench notes unpin <id> */
export const unpin = setPinned(false);
