/**
 * Records commands for the `ench` CLI.
 *
 * Thin wrappers around the project's query functions in backend/db/queries/.
 */

import { sql, inArray } from 'drizzle-orm';
import { z } from 'zod/v4';
import {
  deleteRecord,
  getRecord,
  linksForRecord,
  listRecords,
  upsertRecord,
} from '@db/queries/records';
import { getFamilyTree } from '@db/queries/tree';
import { findSimilarRecords } from '@db/queries/similar-records';
import { embedRecord, removeRecordEmbeddings, VEC_META_TABLE } from '@integrations/embeddings';
import { links, RecordInsertSchema, records } from '@db/schema';
import {
  IntegrationSourceSchema,
  ListRecordsInputSchema,
  type ListRecordsInput,
} from '@shared/types/api';
import { RecordTypeSchema, containmentPredicateSlugs } from '@shared/types';
import {
  BaseOptionsSchema,
  LimitSchema,
  OffsetSchema,
  parseId,
  parseIds,
  parseJsonInput,
  parseOptions,
} from '../lib/args';
import { db } from '../lib/db';
import { createError } from '../lib/errors';
import { success } from '../lib/output';
import type { CommandHandler } from '../lib/types';

const OrderByFieldSchema = z.enum([
  'recordCreatedAt',
  'recordUpdatedAt',
  'title',
  'contentCreatedAt',
  'contentUpdatedAt',
  'id',
  'slug',
  'type',
  'isPinned',
]);

function parseCommaSeparated<T>(value: string | undefined, schema: z.ZodType<T>): T[] | undefined {
  if (value === undefined) return undefined;
  const items = value
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean);
  if (items.length === 0) return undefined;
  return items.map((item) => schema.parse(item));
}

function parseOrderString(value: string | undefined) {
  if (!value) return undefined;
  return value
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean)
    .map((criterion) => {
      const [field, direction = 'desc'] = criterion.split(':');
      return {
        field: OrderByFieldSchema.parse(field),
        direction: direction === 'asc' ? ('asc' as const) : ('desc' as const),
      };
    });
}

const RecordsListOptionsSchema = z.looseObject({
  ...BaseOptionsSchema.shape,
  limit: LimitSchema.optional(),
  offset: OffsetSchema.optional(),
  type: z.string().optional(),
  source: z.string().optional(),
  curated: z.boolean().optional(),
  pinned: z.boolean().optional(),
  embedding: z.boolean().optional(),
  media: z.boolean().optional(),
  parent: z.boolean().optional(),
  'has-title': z.boolean().optional(),
  order: z.string().optional(),
  full: z.boolean().optional(),
});

const RecordsGetOptionsSchema = z.looseObject({
  ...BaseOptionsSchema.shape,
  links: z.boolean().optional(),
});

/**
 * Get record(s) by id.
 * Usage: ench records get <id...> [--links]
 */
export const get: CommandHandler = async (args, options) => {
  const parsedOptions = parseOptions(RecordsGetOptionsSchema, options);
  const ids = parseIds(args);
  const includeLinks = parsedOptions.links ?? false;

  if (ids.length === 0) {
    throw createError('VALIDATION_ERROR', 'At least one ID is required');
  }

  const results = await Promise.all(
    ids.map(async (id) => {
      const record = await getRecord(id);
      if (!record) return { id, error: 'NOT_FOUND' as const };
      if (!includeLinks) return record;
      const linkBundle = await linksForRecord(id);
      return {
        ...record,
        incomingLinks: linkBundle?.incomingLinks ?? [],
        allOutgoingLinks: linkBundle?.outgoingLinks ?? [],
      };
    }),
  );

  if (ids.length === 1) {
    const result = results[0]!;
    if ('error' in result) {
      throw createError('NOT_FOUND', `Record ${ids[0]} not found`);
    }
    return success(result);
  }
  return success(results, { count: results.length });
};

/**
 * List records with filters.
 * Usage: ench records list [filters]
 */
export const list: CommandHandler = async (_args, options) => {
  const parsed = parseOptions(RecordsListOptionsSchema, options);

  const types = parseCommaSeparated(parsed.type, RecordTypeSchema);
  const sources = parseCommaSeparated(parsed.source, IntegrationSourceSchema);

  const input: ListRecordsInput = {
    filters: {
      type: types && types.length > 1 ? { in: types } : (types?.[0] ?? undefined),
      source: sources && sources.length > 1 ? { in: sources } : (sources?.[0] ?? undefined),
      isCurated: parsed.curated,
      isPinned: parsed.pinned,
      hasParent: parsed.parent,
      hasMedia: parsed.media,
      hasTitle: parsed['has-title'],
    },
    limit: parsed.limit ?? 100,
    offset: parsed.offset ?? 0,
    orderBy: parseOrderString(parsed.order) ?? [{ field: 'recordCreatedAt', direction: 'desc' }],
  };

  // Validate via the shared schema (also fills defaults).
  ListRecordsInputSchema.parse(input);

  let rows = await listRecords(input);

  // hasEmbedding is applied post-query: it's an existence check against a
  // virtual table the relational query builder doesn't see.
  if (parsed.embedding !== undefined) {
    const embeddedRows = db.all(
      sql`SELECT record_id AS id FROM ${sql.identifier(VEC_META_TABLE)}`,
    ) as { id: number }[];
    const embeddedIds = new Set(embeddedRows.map((row) => row.id));
    rows = rows.filter((row) => embeddedIds.has(row.id) === parsed.embedding);
  }

  if (parsed.full) {
    return success(rows, {
      count: rows.length,
      limit: input.limit,
      offset: input.offset,
    });
  }

  const ids = rows.map((row) => ({ id: row.id, slug: row.slug, title: row.title }));
  return success(ids, {
    count: ids.length,
    limit: input.limit,
    offset: input.offset,
  });
};

/**
 * Create a new record.
 * Usage: ench records create '<json>'  (or echo '<json>' | ench records create)
 */
export const create: CommandHandler = async (args, options) => {
  parseOptions(BaseOptionsSchema, options);
  const input = await parseJsonInput(RecordInsertSchema, args);
  try {
    const record = await upsertRecord(input);
    return success(record);
  } catch (e) {
    throw createError('VALIDATION_ERROR', e instanceof Error ? e.message : String(e));
  }
};

/**
 * Update an existing record by id.
 * Usage: ench records update <id> '<json>'
 */
export const update: CommandHandler = async (args, options) => {
  parseOptions(BaseOptionsSchema, options);
  const id = parseId(args);
  const existing = await getRecord(id);
  if (!existing) {
    throw createError('NOT_FOUND', `Record ${id} not found`);
  }
  const input = await parseJsonInput(RecordInsertSchema.partial(), args.slice(1));
  const merged = { ...input, id, slug: input.slug ?? existing.slug };
  const record = await upsertRecord(merged);
  return success(record);
};

const BulkUpdateDataSchema = RecordInsertSchema.omit({
  id: true,
  slug: true,
}).partial();

/**
 * Bulk-update records by id.
 * Usage: ench records bulk-update <id,...> '<json-data>'
 */
export const bulkUpdate: CommandHandler = async (args, options) => {
  parseOptions(BaseOptionsSchema, options);
  if (args.length < 2) {
    throw createError('VALIDATION_ERROR', 'Usage: ench records bulk-update <id,...> <json-data>');
  }
  const ids = parseIds(args[0]!.split(','));
  if (ids.length === 0) {
    throw createError('VALIDATION_ERROR', 'At least one ID is required');
  }
  const data = await parseJsonInput(BulkUpdateDataSchema, args.slice(1));
  const dryRun = options['dry-run'] === true || options.n === true;

  if (dryRun) {
    return success({ wouldUpdate: ids, data }, { count: ids.length });
  }

  const updated = await db
    .update(records)
    .set({ ...data, recordUpdatedAt: sql`(CURRENT_TIMESTAMP)` })
    .where(inArray(records.id, ids))
    .returning({ id: records.id });
  return success(
    updated.map((row) => row.id),
    { count: updated.length },
  );
};
export { bulkUpdate as 'bulk-update' };

/**
 * Delete record(s) by id.
 * Usage: ench records delete <id...>
 */
export const del: CommandHandler = async (args, options) => {
  parseOptions(BaseOptionsSchema, options);
  const ids = parseIds(args);
  if (ids.length === 0) {
    throw createError('VALIDATION_ERROR', 'At least one ID is required');
  }
  const dryRun = options['dry-run'] === true || options.n === true;
  if (dryRun) {
    const existing = await db.query.records.findMany({
      columns: { id: true, slug: true, title: true },
      where: { id: { in: ids } },
    });
    return success({ wouldDelete: existing }, { count: existing.length });
  }
  const deleted = await deleteRecord(ids);
  return success(
    deleted.map((row) => ({ id: row.id, slug: row.slug, title: row.title })),
    { count: deleted.length },
  );
};
export { del as delete };

/**
 * Merge a source record into a target record.
 *
 * Re-points the source's incoming and outgoing links at the target (unique
 * conflicts are silently dropped), then deletes the source. The target's
 * embedding is refreshed afterwards so it picks up the new neighborhood.
 *
 * Usage: ench records merge <src-id> <target-id>
 */
export const merge: CommandHandler = async (args, options) => {
  parseOptions(BaseOptionsSchema, options);
  const sourceId = parseId(args, 0);
  const targetId = parseId(args, 1);
  if (sourceId === targetId) {
    throw createError('VALIDATION_ERROR', 'Source and target cannot be the same record');
  }

  const [source, target] = await Promise.all([getRecord(sourceId), getRecord(targetId)]);
  if (!source) throw createError('NOT_FOUND', `Source record ${sourceId} not found`);
  if (!target) throw createError('NOT_FOUND', `Target record ${targetId} not found`);

  const dryRun = options['dry-run'] === true || options.n === true;
  if (dryRun) {
    return success({ wouldMerge: { sourceId, targetId } });
  }

  // Re-point links from source onto target. UPDATE OR IGNORE drops rows that
  // would collide with the (source_id, target_id, predicate) UNIQUE; any rows
  // that remain pointing at source are cleaned up by the cascade in
  // deleteRecord below.
  db.run(
    sql`UPDATE OR IGNORE ${links} SET source_id = ${targetId}
        WHERE source_id = ${sourceId} AND target_id != ${targetId}`,
  );
  db.run(
    sql`UPDATE OR IGNORE ${links} SET target_id = ${targetId}
        WHERE target_id = ${sourceId} AND source_id != ${targetId}`,
  );

  await deleteRecord([sourceId]);

  const refreshed = await getRecord(targetId);
  if (refreshed) await embedRecord(refreshed);
  return success({ merged: { sourceId, targetId }, target: refreshed });
};

const RecordsEmbedOptionsSchema = z.looseObject({
  ...BaseOptionsSchema.shape,
  force: z.boolean().optional(),
});

/**
 * Force-regenerate the embedding for one or more records.
 * Usage: ench records embed <id...> [--force]
 */
export const embed: CommandHandler = async (args, options) => {
  const parsed = parseOptions(RecordsEmbedOptionsSchema, options);
  const ids = parseIds(args);
  if (ids.length === 0) {
    throw createError('VALIDATION_ERROR', 'At least one ID is required');
  }

  // The --force flag (default true for this command — explicit `embed` means
  // "do it now") wipes the meta hash so embedRecord doesn't short-circuit.
  const force = parsed.force ?? true;
  if (force) removeRecordEmbeddings(ids);

  const results = await Promise.all(
    ids.map(async (id) => {
      const record = await getRecord(id);
      if (!record) return { id, error: 'NOT_FOUND' as const };
      await embedRecord(record);
      return { id, embedded: true };
    }),
  );

  if (ids.length === 1) {
    const result = results[0]!;
    if ('error' in result) throw createError('NOT_FOUND', `Record ${ids[0]} not found`);
    return success(result);
  }
  return success(results, { count: results.length });
};

/**
 * Family tree (parent + siblings + children) for record(s).
 * Usage: ench records tree <id...>
 */
export const tree: CommandHandler = async (args, options) => {
  parseOptions(BaseOptionsSchema, options);
  const ids = parseIds(args);
  if (ids.length === 0) {
    throw createError('VALIDATION_ERROR', 'At least one ID is required');
  }
  const results = await Promise.all(
    ids.map(async (id) => {
      const result = await getFamilyTree(id);
      if (!result) return { id, error: 'NOT_FOUND' as const };
      return result;
    }),
  );
  if (ids.length === 1) {
    const result = results[0]!;
    if ('error' in result) throw createError('NOT_FOUND', `Record ${ids[0]} not found`);
    return success(result);
  }
  return success(results, { count: results.length });
};

/**
 * Records that link to this record via a containment predicate.
 * Usage: ench records children <id>
 */
export const children: CommandHandler = async (args, options) => {
  parseOptions(BaseOptionsSchema, options);
  const id = parseId(args);
  const result = await getFamilyTree(id);
  if (!result) throw createError('NOT_FOUND', `Record ${id} not found`);
  const children = (result.incomingLinks ?? [])
    .filter((link) => containmentPredicateSlugs.includes(link.predicate))
    .map((link) => ({
      id: link.source.id,
      title: link.source.title,
      slug: link.source.slug,
      recordCreatedAt: link.source.recordCreatedAt,
      predicate: link.predicate,
    }));
  return success({ parentId: id, children }, { count: children.length });
};

/**
 * The record (if any) this record is contained_by.
 * Usage: ench records parent <id>
 */
export const parent: CommandHandler = async (args, options) => {
  parseOptions(BaseOptionsSchema, options);
  const id = parseId(args);
  const result = await getFamilyTree(id);
  if (!result) throw createError('NOT_FOUND', `Record ${id} not found`);
  const parentLink = (result.outgoingLinks ?? []).find((link) =>
    containmentPredicateSlugs.includes(link.predicate),
  );
  if (!parentLink) return success({ childId: id, parent: null });
  return success({
    childId: id,
    parent: {
      id: parentLink.target.id,
      title: parentLink.target.title,
      slug: parentLink.target.slug,
      recordCreatedAt: parentLink.target.recordCreatedAt,
      predicate: parentLink.predicate,
    },
  });
};

const SimilarOptionsSchema = z.looseObject({
  ...BaseOptionsSchema.shape,
  limit: LimitSchema.optional(),
});

/**
 * Find records similar (by embedding cosine similarity) to the given record(s).
 * Usage: ench records similar <id...> [--limit=N]
 *
 * Also exposed as `ench search similar` for symmetry with rcr.
 */
export const similar: CommandHandler = async (args, options) => {
  const parsed = parseOptions(SimilarOptionsSchema, options);
  const ids = parseIds(args);
  if (ids.length === 0) {
    throw createError('VALIDATION_ERROR', 'At least one ID is required');
  }
  const limit = parsed.limit ?? 10;
  const results = await Promise.all(
    ids.map(async (id) => {
      const record = await getRecord(id);
      if (!record) return { id, error: 'NOT_FOUND' as const };
      const similar = await findSimilarRecords({ recordId: id, limit });
      return { id, similar };
    }),
  );

  if (ids.length === 1) {
    const result = results[0]!;
    if ('error' in result) throw createError('NOT_FOUND', `Record ${ids[0]} not found`);
    return success(result.similar, { count: result.similar.length, limit });
  }
  return success(results, { count: results.length, limit });
};
