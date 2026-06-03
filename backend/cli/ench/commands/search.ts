/**
 * Search commands for the `ench` CLI.
 *
 * The three search modes share data shape via `listRecords` for text matching
 * and `semanticSearchListRecords` for vector matching. `hybrid` merges them
 * with reciprocal rank fusion.
 */

import { z } from 'zod/v4';
import { listRecords } from '@db/queries/records';
import { semanticSearchListRecords } from '@db/queries/semantic-search';
import { findSimilarRecords } from '@db/queries/similar-records';
import { isEmbeddingEnabled } from '@integrations/embeddings';
import { RecordTypeSchema } from '@shared/types';
import {
  BaseOptionsSchema,
  CommaSeparatedIdsSchema,
  LimitSchema,
  parseIds,
  parseOptions,
} from '../lib/args';
import { createError } from '../lib/errors';
import { success } from '../lib/output';
import type { CommandHandler } from '../lib/types';

const SearchHybridOptionsSchema = z.looseObject({
  ...BaseOptionsSchema.shape,
  limit: LimitSchema.optional(),
});

const SearchTextOptionsSchema = z.looseObject({
  ...BaseOptionsSchema.shape,
  limit: LimitSchema.optional(),
  type: RecordTypeSchema.optional(),
});

const SearchSemanticOptionsSchema = z.looseObject({
  ...BaseOptionsSchema.shape,
  limit: LimitSchema.optional(),
  exclude: CommaSeparatedIdsSchema.optional(),
});

/** RRF constant from the original Cormack/Clarke/Buettcher paper. */
const RRF_K = 60;

/**
 * Hybrid search — combines trigram-style text matching with embedding-based
 * semantic search via reciprocal rank fusion. Default mode for `ench search`.
 * Usage: ench search <query> [--limit=N]
 */
export const hybrid: CommandHandler = async (args, options) => {
  const parsed = parseOptions(SearchHybridOptionsSchema, options);
  const query = args.join(' ').trim();
  if (!query) throw createError('VALIDATION_ERROR', 'Search query is required');

  const limit = parsed.limit ?? 20;
  const overFetch = Math.max(limit * 2, 40);

  const [textRows, semanticRows] = await Promise.all([
    listRecords({ filters: { text: query }, limit: overFetch }),
    isEmbeddingEnabled()
      ? semanticSearchListRecords({ query, limit: overFetch })
      : Promise.resolve([]),
  ]);

  const scores = new Map<number, number>();
  const byId = new Map<number, (typeof textRows)[number]>();

  textRows.forEach((row, rank) => {
    byId.set(row.id, row);
    scores.set(row.id, (scores.get(row.id) ?? 0) + 1 / (RRF_K + rank));
  });
  semanticRows.forEach((row, rank) => {
    byId.set(row.id, row);
    scores.set(row.id, (scores.get(row.id) ?? 0) + 1 / (RRF_K + rank));
  });

  const merged = [...scores.entries()]
    .sort(([, a], [, b]) => b - a)
    .slice(0, limit)
    .map(([id, score]) => ({ ...byId.get(id)!, score }));

  return success(merged, { count: merged.length, limit });
};

/**
 * Trigram-style substring search over title/slug/content/summary/notes.
 * Usage: ench search text <query> [--type=...] [--limit=N]
 */
export const text: CommandHandler = async (args, options) => {
  const parsed = parseOptions(SearchTextOptionsSchema, options);
  const query = args.join(' ').trim();
  if (!query) throw createError('VALIDATION_ERROR', 'Search query is required');

  const limit = parsed.limit ?? 20;
  const rows = await listRecords({
    filters: { text: query, type: parsed.type },
    limit,
  });
  return success(rows, { count: rows.length, limit });
};

/**
 * Vector search over record embeddings.
 * Usage: ench search semantic <query> [--limit=N] [--exclude=id,id]
 */
export const semantic: CommandHandler = async (args, options) => {
  const parsed = parseOptions(SearchSemanticOptionsSchema, options);
  const query = args.join(' ').trim();
  if (!query) throw createError('VALIDATION_ERROR', 'Search query is required');

  if (!isEmbeddingEnabled()) {
    throw createError(
      'EMBEDDING_ERROR',
      'Embeddings are not configured. Set OPENAI_API_KEY in your environment.',
    );
  }

  const limit = parsed.limit ?? 20;
  const excludeSet = new Set(parsed.exclude ?? []);
  // Over-fetch then filter so excluded ids don't shrink the result set.
  const rows = await semanticSearchListRecords({
    query,
    limit: excludeSet.size ? limit + excludeSet.size : limit,
  });
  const filtered = rows.filter((row) => !excludeSet.has(row.id)).slice(0, limit);
  return success(filtered, { count: filtered.length, limit });
};

/**
 * Similarity search by record id (delegates to the same logic as the API).
 * Usage: ench search similar <id...> [--limit=N]
 */
export const similar: CommandHandler = async (args, options) => {
  const parsed = parseOptions(SearchHybridOptionsSchema, options);
  const ids = parseIds(args);
  if (ids.length === 0) {
    throw createError('VALIDATION_ERROR', 'At least one ID is required');
  }
  const limit = parsed.limit ?? 10;
  const results = await Promise.all(
    ids.map(async (id) => {
      const similar = await findSimilarRecords({ recordId: id, limit });
      return { id, similar };
    }),
  );
  if (ids.length === 1) {
    return success(results[0]!.similar, { count: results[0]!.similar.length, limit });
  }
  return success(results, { count: results.length, limit });
};
