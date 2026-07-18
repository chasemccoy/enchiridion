/**
 * Record lifecycle invariants: upsert, delete (and everything delete must
 * clean up), and the CLI merge command's link re-pointing.
 */
import { describe, expect, it } from 'vitest';
import { sql } from 'drizzle-orm';
import { db } from '@db/index';
import { links } from '@db/schema';
import { deleteRecord, upsertRecord } from '@db/queries/records';
import { claimArchive } from '@integrations/archive';
import { VEC_META_TABLE, VEC_TABLE } from '@integrations/embeddings';
import { merge } from '../backend/cli/ench/commands/records';
import { createRecord } from './helpers';

/** Insert a synthetic embedding vector + meta row for a record. */
function insertVector(recordId: number, values: number[]) {
  const vector = new Float32Array(3072);
  values.forEach((v, i) => (vector[i] = v));
  db.run(
    sql`INSERT INTO ${sql.identifier(VEC_TABLE)} (record_id, embedding)
        VALUES (${BigInt(recordId)}, ${Buffer.from(vector.buffer)})`,
  );
  db.run(
    sql`INSERT INTO ${sql.identifier(VEC_META_TABLE)} (record_id, content_hash)
        VALUES (${recordId}, 'test-hash')`,
  );
}

function countVectors(recordId: number): number {
  const row = db.get(
    sql`SELECT count(*) AS n FROM ${sql.identifier(VEC_TABLE)} WHERE record_id = ${BigInt(recordId)}`,
  ) as { n: number };
  return row.n;
}

describe('upsertRecord', () => {
  it('creates a record with defaults', async () => {
    const record = await upsertRecord({ slug: 'lifecycle-create', title: 'Created' });
    expect(record.id).toBeGreaterThan(0);
    expect(record.type).toBe('artifact');
    expect(record.isCurated).toBe(false);
  });

  it('updates in place when an id is provided', async () => {
    const created = await upsertRecord({ slug: 'lifecycle-update', title: 'Before' });
    const updated = await upsertRecord({ id: created.id, slug: created.slug, title: 'After' });
    expect(updated.id).toBe(created.id);
    expect(updated.title).toBe('After');
    const rows = await db.query.records.findMany({ where: { slug: 'lifecycle-update' } });
    expect(rows).toHaveLength(1);
  });
});

describe('deleteRecord', () => {
  it('removes the record, its links, its archive row, and its embedding', async () => {
    const doomed = await createRecord({ url: 'https://example.com/doomed' });
    const neighbor = await createRecord();
    await db.insert(links).values({
      sourceId: doomed.id,
      targetId: neighbor.id,
      predicate: 'related_to',
    });
    await claimArchive(doomed);
    insertVector(doomed.id, [1]);

    const deleted = await deleteRecord([doomed.id]);
    expect(deleted.map((r) => r.id)).toEqual([doomed.id]);

    expect(await db.query.records.findFirst({ where: { id: doomed.id } })).toBeUndefined();
    expect(await db.query.links.findMany({ where: { sourceId: doomed.id } })).toEqual([]);
    expect(await db.query.archives.findFirst({ where: { recordId: doomed.id } })).toBeUndefined();
    expect(countVectors(doomed.id)).toBe(0);

    // The neighbor is untouched.
    expect(await db.query.records.findFirst({ where: { id: neighbor.id } })).toBeDefined();
  });

  it('returns only the records that existed', async () => {
    const real = await createRecord();
    const deleted = await deleteRecord([real.id, 999999]);
    expect(deleted.map((r) => r.id)).toEqual([real.id]);
  });
});

describe('records merge (CLI)', () => {
  it('re-points links onto the target, dropping duplicates and self-links', async () => {
    const x = await createRecord({ title: 'X' });
    const y = await createRecord({ title: 'Y' });
    const source = await createRecord({ title: 'Source' });
    const target = await createRecord({ title: 'Target' });

    await db.insert(links).values([
      { sourceId: source.id, targetId: x.id, predicate: 'related_to' },
      { sourceId: y.id, targetId: source.id, predicate: 'related_to' },
      // Would become a self-link after re-pointing — must be dropped.
      { sourceId: source.id, targetId: target.id, predicate: 'related_to' },
      // Already exists on the target — the re-pointed duplicate must be dropped.
      { sourceId: target.id, targetId: x.id, predicate: 'related_to' },
    ]);

    const result = await merge([String(source.id), String(target.id)], {});
    expect(result.data).toMatchObject({ merged: { sourceId: source.id, targetId: target.id } });

    expect(await db.query.records.findFirst({ where: { id: source.id } })).toBeUndefined();

    const remaining = await db.query.links.findMany();
    const involving = (id: number) =>
      remaining.filter((l) => l.sourceId === id || l.targetId === id);
    expect(involving(source.id)).toEqual([]);
    expect(remaining.filter((l) => l.sourceId === l.targetId)).toEqual([]);
    expect(remaining.filter((l) => l.sourceId === target.id && l.targetId === x.id)).toHaveLength(
      1,
    );
    expect(remaining.filter((l) => l.sourceId === y.id && l.targetId === target.id)).toHaveLength(
      1,
    );
  });

  it('rejects merging a record into itself and dry-runs without changes', async () => {
    const record = await createRecord();
    await expect(merge([String(record.id), String(record.id)], {})).rejects.toThrow(
      /cannot be the same/,
    );

    const other = await createRecord();
    const dry = await merge([String(record.id), String(other.id)], { 'dry-run': true });
    expect(dry.data).toMatchObject({ wouldMerge: { sourceId: record.id, targetId: other.id } });
    expect(await db.query.records.findFirst({ where: { id: record.id } })).toBeDefined();
  });
});
