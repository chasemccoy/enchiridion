/**
 * Links commands for the `ench` CLI.
 */

import { z } from 'zod/v4';
import { deleteLink, upsertLink } from '@db/queries/links';
import { linksForRecord } from '@db/queries/records';
import { LinkInsertSchema } from '@db/schema';
import { PREDICATES, PredicateSlugSchema, predicateSlugs, type PredicateSlug } from '@shared/types';
import { BaseOptionsSchema, parseId, parseIds, parseJsonInput, parseOptions } from '../lib/args';
import { createError } from '../lib/errors';
import { success } from '../lib/output';
import type { CommandHandler } from '../lib/types';

const LinksListOptionsSchema = z.looseObject({
  ...BaseOptionsSchema.shape,
  predicate: z.enum(predicateSlugs as [PredicateSlug, ...PredicateSlug[]]).optional(),
  direction: z.enum(['incoming', 'outgoing']).optional(),
});

/**
 * List links for a record, optionally filtered by predicate or direction.
 * Usage: ench links list <record-id> [--predicate=<slug>] [--direction=incoming|outgoing]
 */
export const list: CommandHandler = async (args, options) => {
  const parsed = parseOptions(LinksListOptionsSchema, options);
  const id = parseId(args);

  const result = await linksForRecord(id);
  if (!result) throw createError('NOT_FOUND', `Record ${id} not found`);

  let outgoing = result.outgoingLinks ?? [];
  let incoming = result.incomingLinks ?? [];

  if (parsed.predicate) {
    outgoing = outgoing.filter((link) => link.predicate === parsed.predicate);
    incoming = incoming.filter((link) => link.predicate === parsed.predicate);
  }
  if (parsed.direction === 'outgoing') incoming = [];
  if (parsed.direction === 'incoming') outgoing = [];

  return success(
    { id: result.id, outgoingLinks: outgoing, incomingLinks: incoming },
    { count: outgoing.length + incoming.length },
  );
};

/**
 * Create or update a link.
 * Usage: ench links create '<json>'
 * JSON: { sourceId, targetId, predicate, notes? }
 */
export const create: CommandHandler = async (args, options) => {
  parseOptions(BaseOptionsSchema, options);
  const input = await parseJsonInput(
    LinkInsertSchema.extend({ predicate: PredicateSlugSchema }),
    args,
  );
  try {
    const link = await upsertLink(input);
    return success(link);
  } catch (e) {
    throw createError('VALIDATION_ERROR', e instanceof Error ? e.message : String(e));
  }
};

/**
 * Delete link(s) by id.
 * Usage: ench links delete <id...>
 */
export const del: CommandHandler = async (args, options) => {
  parseOptions(BaseOptionsSchema, options);
  const ids = parseIds(args);
  if (ids.length === 0) {
    throw createError('VALIDATION_ERROR', 'At least one link ID is required');
  }
  const results = await Promise.all(
    ids.map(async (id) => {
      const deleted = await deleteLink(id);
      return deleted[0] ?? { id, error: 'NOT_FOUND' as const };
    }),
  );
  return success(results, { count: results.length });
};
export { del as delete };

/**
 * Dump the canonical predicate vocabulary.
 * Usage: ench links predicates
 */
export const predicates: CommandHandler = async (_args, options) => {
  parseOptions(BaseOptionsSchema, options);
  const all = Object.values(PREDICATES);
  return success(all, { count: all.length });
};
