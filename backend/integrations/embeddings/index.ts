import { createHash } from 'node:crypto';
import { sql } from 'drizzle-orm';
import { db } from '@db/index';
import type { RecordSelect } from '@db/schema';
import {
  EMBEDDING_LINK_BUCKETS,
  EMBEDDING_LINK_SLUGS,
  EMBEDDING_MODEL,
  EMBED_BATCH_SIZE,
  MAX_EMBED_CHARS,
  VEC_META_TABLE,
  VEC_TABLE,
} from './constants';
import { embedTexts, isEmbeddingEnabled } from './client';

export { isEmbeddingEnabled } from './client';
export * from './constants';

/** Subset of a record's columns that contribute to its embedding. */
type EmbeddableRecord = Pick<RecordSelect, 'id' | 'title' | 'summary' | 'content' | 'notes'>;

/** Titles of records linked to the source record, grouped by bucket label. */
export type LinkedTitlesByBucket = Record<string, string[]>;

/**
 * Build the text we embed for a record from its human-meaningful fields, plus
 * the titles of records connected via the predicates in `EMBEDDING_LINK_BUCKETS`.
 *
 * The link section is rendered as one line per non-empty bucket, e.g.
 *   Tags: typography, design
 *   Related: Web Without Walls, A Different Internet
 *
 * giving the embedding model structured context about the record's neighborhood
 * in the knowledge graph.
 */
export const buildEmbedText = (
  record: EmbeddableRecord,
  linkedTitles: LinkedTitlesByBucket = {},
): string => {
  const linkLines = EMBEDDING_LINK_BUCKETS.flatMap(({ label }) => {
    const titles = linkedTitles[label];
    return titles && titles.length ? [`${label}: ${titles.join(', ')}`] : [];
  });

  const text = [record.title, record.summary, record.content, record.notes, ...linkLines]
    .filter((part): part is string => Boolean(part && part.trim()))
    .join('\n\n')
    .trim();
  return text.slice(0, MAX_EMBED_CHARS);
};

interface NeighborRow {
  slug: string;
  neighbor_id: number;
  neighbor_title: string;
}

/**
 * Fetch titles of records linked to `recordId` via the embedding-context
 * predicates, bucketed by the human label. Both directions of each inverse
 * pair are followed. Untitled neighbors are skipped (their slugs are usually
 * opaque ids and would add noise rather than signal).
 */
export const getLinkedTitlesForEmbedding = (recordId: number): LinkedTitlesByBucket => {
  const rows = db.all(
    sql`SELECT l.predicate AS slug,
               CASE WHEN l.source_id = ${recordId} THEN l.target_id ELSE l.source_id END AS neighbor_id,
               r.title AS neighbor_title
        FROM links l
        JOIN records r
          ON r.id = CASE WHEN l.source_id = ${recordId} THEN l.target_id ELSE l.source_id END
        WHERE (l.source_id = ${recordId} OR l.target_id = ${recordId})
          AND r.title IS NOT NULL AND r.title != ''
          AND l.predicate IN (${sql.join(
            [...EMBEDDING_LINK_SLUGS].map((slug) => sql`${slug}`),
            sql`, `,
          )})`,
  ) as NeighborRow[];

  // Bucket by label, dedupe titles within each bucket (the inverse-pair links
  // would otherwise duplicate each neighbor twice).
  const buckets: LinkedTitlesByBucket = {};
  const seen: Record<string, Set<string>> = {};
  for (const row of rows) {
    const bucket = EMBEDDING_LINK_BUCKETS.find((b) => b.slugs.includes(row.slug));
    if (!bucket) continue;
    const label = bucket.label;
    buckets[label] ??= [];
    seen[label] ??= new Set();
    if (!seen[label].has(row.neighbor_title)) {
      seen[label].add(row.neighbor_title);
      buckets[label].push(row.neighbor_title);
    }
  }
  for (const list of Object.values(buckets)) list.sort((a, b) => a.localeCompare(b));
  return buckets;
};

/** Hash of the embedded text, namespaced by model so a model change re-embeds. */
const contentHash = (text: string): string =>
  createHash('sha256').update(`${EMBEDDING_MODEL}\n${text}`).digest('hex');

/** Serialize a vector to the float32 blob sqlite-vec expects. */
const toBlob = (vector: number[]): Buffer => Buffer.from(new Float32Array(vector).buffer);

// vec0 virtual tables require integer-typed bindings for INTEGER PRIMARY KEY
// columns. better-sqlite3 binds JS `number` as float64 by default, which vec0
// rejects ("Only integers are allowed for primary key values"). Wrapping the
// id in BigInt forces an integer binding.
const bn = (n: number): bigint => BigInt(n);

/** Upsert one vector + its content hash. Synchronous (better-sqlite3). */
const storeEmbedding = (recordId: number, vector: number[], hash: string): void => {
  const id = bn(recordId);
  db.run(sql`DELETE FROM ${sql.identifier(VEC_TABLE)} WHERE record_id = ${id}`);
  db.run(
    sql`INSERT INTO ${sql.identifier(VEC_TABLE)} (record_id, embedding) VALUES (${id}, ${toBlob(vector)})`,
  );
  db.run(
    sql`INSERT INTO ${sql.identifier(VEC_META_TABLE)} (record_id, content_hash) VALUES (${recordId}, ${hash})
        ON CONFLICT(record_id) DO UPDATE SET content_hash = excluded.content_hash`,
  );
};

/** Remove stored vectors + hashes for the given record ids. */
export const removeRecordEmbeddings = (recordIds: number[]): void => {
  if (recordIds.length === 0) return;
  const vecIds = sql.join(
    recordIds.map((id) => sql`${bn(id)}`),
    sql`, `,
  );
  const metaIds = sql.join(
    recordIds.map((id) => sql`${id}`),
    sql`, `,
  );
  db.run(sql`DELETE FROM ${sql.identifier(VEC_TABLE)} WHERE record_id IN (${vecIds})`);
  db.run(sql`DELETE FROM ${sql.identifier(VEC_META_TABLE)} WHERE record_id IN (${metaIds})`);
};

const getStoredHash = (recordId: number): string | undefined => {
  const row = db.get(
    sql`SELECT content_hash AS hash FROM ${sql.identifier(VEC_META_TABLE)} WHERE record_id = ${recordId}`,
  ) as { hash: string } | undefined;
  return row?.hash;
};

/**
 * Embed (or re-embed) a single record. Best-effort: never throws, so a record
 * write is never blocked by an embedding failure. No-ops when embeddings are
 * disabled or the record's text is unchanged since it was last embedded.
 */
export const embedRecord = async (record: EmbeddableRecord): Promise<void> => {
  try {
    if (!isEmbeddingEnabled()) return;

    const linkedTitles = getLinkedTitlesForEmbedding(record.id);
    const text = buildEmbedText(record, linkedTitles);
    if (!text) {
      // Record has no embeddable text anymore — drop any stale vector.
      removeRecordEmbeddings([record.id]);
      return;
    }

    const hash = contentHash(text);
    if (getStoredHash(record.id) === hash) return;

    const [vector] = await embedTexts([text]);
    if (vector) storeEmbedding(record.id, vector, hash);
  } catch (error) {
    // eslint-disable-next-line no-console
    console.warn(
      `[embeddings] failed to embed record ${record.id}:`,
      error instanceof Error ? error.message : error,
    );
  }
};

export interface SemanticSearchResult {
  record: RecordSelect;
  /** Cosine distance (0 = identical, 2 = opposite). */
  distance: number;
  /** Cosine similarity in [-1, 1]; higher is more similar. */
  score: number;
}

export interface SemanticSearchInput {
  query: string;
  limit?: number;
  /** Drop hits whose cosine similarity is below this threshold. */
  minScore?: number;
}

export interface SimilarByEmbeddingInput {
  recordId: number;
  limit?: number;
  /** Drop hits whose cosine similarity is below this threshold (0-1). */
  minScore?: number;
}

export interface SimilarByEmbeddingResult {
  record: RecordSelect;
  score: number;
  reasons: string[];
}

/**
 * Find records semantically similar to a given record using its stored
 * embedding. Returns an empty array when the source record has no embedding
 * (e.g. it has no embeddable text, or embeddings are disabled).
 */
export const findSimilarRecordsByEmbedding = async ({
  recordId,
  limit = 10,
  minScore = 0,
}: SimilarByEmbeddingInput): Promise<SimilarByEmbeddingResult[]> => {
  const source = db.get(
    sql`SELECT embedding FROM ${sql.identifier(VEC_TABLE)} WHERE record_id = ${BigInt(recordId)}`,
  ) as { embedding: Buffer } | undefined;
  if (!source) return [];

  // Over-fetch by 1 so we can drop the source record itself from the results.
  const hits = (
    db.all(
      sql`SELECT record_id AS recordId, distance
          FROM ${sql.identifier(VEC_TABLE)}
          WHERE embedding MATCH ${source.embedding} AND k = ${BigInt(limit + 1)}
          ORDER BY distance`,
    ) as { recordId: number; distance: number }[]
  )
    .filter((hit) => hit.recordId !== recordId)
    .map((hit) => ({ recordId: hit.recordId, score: 1 - hit.distance }))
    .filter((hit) => hit.score >= minScore)
    .slice(0, limit);

  if (hits.length === 0) return [];

  const records = await db.query.records.findMany({
    where: { id: { in: hits.map((hit) => hit.recordId) } },
  });
  const byId = new Map(records.map((record) => [record.id, record]));

  const results: SimilarByEmbeddingResult[] = [];
  for (const hit of hits) {
    const record = byId.get(hit.recordId);
    if (record) {
      results.push({
        record,
        score: hit.score,
        reasons: [`${Math.round(hit.score * 100)}% similar by content`],
      });
    }
  }
  return results;
};

/** Find records whose embedding is nearest to the query text. */
export const searchRecordsByEmbedding = async ({
  query,
  limit = 10,
  minScore = 0,
}: SemanticSearchInput): Promise<SemanticSearchResult[]> => {
  if (!isEmbeddingEnabled()) return [];
  const text = query.trim().slice(0, MAX_EMBED_CHARS);
  if (!text) return [];

  const [vector] = await embedTexts([text]);
  if (!vector) return [];

  const hits = (
    db.all(
      sql`SELECT record_id AS recordId, distance
          FROM ${sql.identifier(VEC_TABLE)}
          WHERE embedding MATCH ${toBlob(vector)} AND k = ${bn(limit)}
          ORDER BY distance`,
    ) as { recordId: number; distance: number }[]
  ).filter((hit) => 1 - hit.distance >= minScore);

  if (hits.length === 0) return [];

  const records = await db.query.records.findMany({
    where: { id: { in: hits.map((hit) => hit.recordId) } },
  });
  const byId = new Map(records.map((record) => [record.id, record]));

  const results: SemanticSearchResult[] = [];
  for (const hit of hits) {
    const record = byId.get(hit.recordId);
    if (record) {
      results.push({ record, distance: hit.distance, score: 1 - hit.distance });
    }
  }
  return results;
};

export interface BackfillResult {
  embedded: number;
  skipped: number;
  removed: number;
}

export interface BackfillOptions {
  /** Re-embed every record even if its text is unchanged. */
  force?: boolean;
  onProgress?: (done: number, total: number) => void;
}

/**
 * Embed every record that is missing a vector or whose text changed since it
 * was last embedded, and prune vectors for records that no longer exist.
 */
export const backfillEmbeddings = async ({
  force = false,
  onProgress,
}: BackfillOptions = {}): Promise<BackfillResult> => {
  if (!isEmbeddingEnabled()) {
    throw new Error('OPENAI_API_KEY is not set — cannot generate embeddings.');
  }

  const records = await db.query.records.findMany({
    columns: { id: true, title: true, summary: true, content: true, notes: true },
  });

  const metaRows = db.all(
    sql`SELECT record_id AS recordId, content_hash AS hash FROM ${sql.identifier(VEC_META_TABLE)}`,
  ) as { recordId: number; hash: string }[];
  const hashById = new Map(metaRows.map((row) => [row.recordId, row.hash]));

  // Prune vectors for records that were deleted while embeddings were disabled.
  const liveIds = new Set(records.map((record) => record.id));
  const orphanIds = metaRows.map((row) => row.recordId).filter((id) => !liveIds.has(id));
  removeRecordEmbeddings(orphanIds);

  const queue: { id: number; text: string; hash: string }[] = [];
  let skipped = 0;

  for (const record of records) {
    const linkedTitles = getLinkedTitlesForEmbedding(record.id);
    const text = buildEmbedText(record, linkedTitles);
    if (!text) {
      if (hashById.has(record.id)) removeRecordEmbeddings([record.id]);
      continue;
    }
    const hash = contentHash(text);
    if (!force && hashById.get(record.id) === hash) {
      skipped += 1;
      continue;
    }
    queue.push({ id: record.id, text, hash });
  }

  let embedded = 0;
  for (let i = 0; i < queue.length; i += EMBED_BATCH_SIZE) {
    const batch = queue.slice(i, i + EMBED_BATCH_SIZE);
    const vectors = await embedTexts(batch.map((item) => item.text));
    batch.forEach((item, index) => {
      const vector = vectors[index];
      if (vector) storeEmbedding(item.id, vector, item.hash);
    });
    embedded += batch.length;
    onProgress?.(Math.min(i + EMBED_BATCH_SIZE, queue.length), queue.length);
  }

  return { embedded, skipped, removed: orphanIds.length };
};
