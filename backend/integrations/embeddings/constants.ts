/**
 * Embedding configuration shared between the database layer (which creates the
 * sqlite-vec virtual table) and the embeddings client (which generates vectors).
 *
 * This file intentionally has no heavy imports so it can be pulled into
 * `backend/db/index.ts` without dragging in the OpenAI SDK or the db itself.
 */

/** OpenAI embedding model. `text-embedding-3-large` outputs 3072-dim vectors. */
export const EMBEDDING_MODEL = 'text-embedding-3-large';

/** Vector dimensionality for {@link EMBEDDING_MODEL}. Must match the vec0 table. */
export const EMBEDDING_DIMENSIONS = 3072;

/** sqlite-vec virtual table holding one vector per record. */
export const VEC_TABLE = 'vec_records';

/** Plain table tracking the content hash that produced each stored vector. */
export const VEC_META_TABLE = 'vec_records_meta';

/**
 * Max characters of combined record text sent to the embedding API. Keeps each
 * input well under the model's 8,191-token limit and keeps batch requests small.
 */
export const MAX_EMBED_CHARS = 12000;

/** Records embedded per OpenAI request during backfill. */
export const EMBED_BATCH_SIZE = 32;

/**
 * Predicate slugs whose linked-record titles are folded into a record's
 * embedding text, grouped by the human-readable label that prefixes them.
 * Both directions of each inverse pair are included so the link surfaces
 * regardless of which side it was authored on.
 */
export const EMBEDDING_LINK_BUCKETS: ReadonlyArray<{
  label: string;
  slugs: readonly string[];
}> = [
  { label: 'By', slugs: ['created_by', 'creator_of'] },
  { label: 'Tags', slugs: ['tag_of', 'tagged_with'] },
  { label: 'Related', slugs: ['related_to'] },
  { label: 'Format', slugs: ['format_of', 'has_format'] },
];

/** Flat set of all slugs that contribute link-context to embeddings. */
export const EMBEDDING_LINK_SLUGS: ReadonlySet<string> = new Set(
  EMBEDDING_LINK_BUCKETS.flatMap((bucket) => bucket.slugs),
);
