/**
 * Search behavior that runs without external APIs: the text filter, hybrid
 * search's degraded (text-only) mode, and vector ranking through sqlite-vec
 * using synthetic embeddings — no OpenAI key needed because similarity search
 * from a *stored* vector never embeds anything.
 */
import { describe, expect, it } from 'vitest';
import { sql } from 'drizzle-orm';
import { db } from '@db/index';
import { listRecords } from '@db/queries/records';
import { hybridSearchListRecords } from '@db/queries/hybrid-search';
import { semanticSearchListRecords } from '@db/queries/semantic-search';
import {
  EMBEDDING_DIMENSIONS,
  findSimilarRecordsByEmbedding,
  VEC_TABLE,
} from '@integrations/embeddings';
import { createRecord } from './helpers';

function insertVector(recordId: number, values: number[]) {
  const vector = new Float32Array(EMBEDDING_DIMENSIONS);
  values.forEach((v, i) => (vector[i] = v));
  db.run(
    sql`INSERT INTO ${sql.identifier(VEC_TABLE)} (record_id, embedding)
        VALUES (${BigInt(recordId)}, ${Buffer.from(vector.buffer)})`,
  );
}

describe('text search', () => {
  it('listRecords text filter matches title tokens', async () => {
    const hit = await createRecord({ title: 'Quantum unicorn taxonomy' });
    await createRecord({ title: 'Mundane gardening notes' });

    const rows = await listRecords({ filters: { text: 'unicorn' } });
    expect(rows.map((r) => r.id)).toContain(hit.id);
    expect(rows.every((r) => r.id === hit.id || !r.title?.includes('gardening'))).toBe(true);
  });
});

describe('hybridSearchListRecords (embeddings disabled)', () => {
  it('returns text hits with a fused score attached', async () => {
    const hit = await createRecord({ title: 'Xylophone maintenance manual' });
    const results = await hybridSearchListRecords({ query: 'xylophone' });
    const found = results.find((r) => r.id === hit.id);
    expect(found).toBeDefined();
    expect(found!.score).toBeGreaterThan(0);
  });

  it('returns [] for a blank query', async () => {
    expect(await hybridSearchListRecords({ query: '   ' })).toEqual([]);
  });

  it('semantic search alone degrades to [] without an API key', async () => {
    expect(await semanticSearchListRecords({ query: 'anything' })).toEqual([]);
  });
});

describe('findSimilarRecordsByEmbedding (synthetic vectors)', () => {
  it('ranks by cosine similarity and applies minScore', async () => {
    const source = await createRecord({ title: 'Vector source' });
    const near = await createRecord({ title: 'Near neighbor' });
    const far = await createRecord({ title: 'Orthogonal' });

    insertVector(source.id, [1, 0, 0]);
    insertVector(near.id, [1, 0.1, 0]);
    insertVector(far.id, [0, 0, 1]);

    const results = await findSimilarRecordsByEmbedding({
      recordId: source.id,
      minScore: 0.5,
    });
    expect(results.map((r) => r.record.id)).toEqual([near.id]);
    expect(results[0]!.score).toBeGreaterThan(0.9);
  });

  it('honors excludeIds and returns [] for a record with no vector', async () => {
    const source = await createRecord();
    const near = await createRecord();
    // Along a different axis than the previous test's vectors, so its records
    // are orthogonal to these and can't appear as neighbors here.
    insertVector(source.id, [0, 0, 0, 0, 0, 1]);
    insertVector(near.id, [0, 0, 0, 0, 0, 1, 0.05]);

    const excluded = await findSimilarRecordsByEmbedding({
      recordId: source.id,
      minScore: 0.5,
      excludeIds: [near.id],
    });
    expect(excluded).toEqual([]);

    const unembedded = await createRecord();
    expect(await findSimilarRecordsByEmbedding({ recordId: unembedded.id })).toEqual([]);
  });
});
