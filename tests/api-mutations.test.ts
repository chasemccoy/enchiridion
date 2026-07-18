/**
 * Mutation routes the frontend and CLI depend on: record upsert/delete and
 * link upsert (including predicate canonicalization) via supertest.
 */
import { describe, expect, it } from 'vitest';
import request from 'supertest';
import { app } from '@api/app';
import { db } from '@db/index';
import { getPredicate, type PredicateSlug } from '@shared/types';
import { createRecord } from './helpers';

describe('PUT /record', () => {
  it('creates a record', async () => {
    const res = await request(app)
      .put('/record')
      .send({ slug: 'api-created', title: 'API created', type: 'concept' });
    expect(res.status).toBe(200);
    expect(res.body.id).toBeGreaterThan(0);
    expect(res.body.type).toBe('concept');
  });

  it('updates a record when the body carries an id', async () => {
    const record = await createRecord({ title: 'Before' });
    const res = await request(app)
      .put('/record')
      .send({ id: record.id, slug: record.slug, title: 'After' });
    expect(res.status).toBe(200);
    expect(res.body.id).toBe(record.id);
    expect(res.body.title).toBe('After');
  });

  it('rejects an invalid body via errorHandler as JSON', async () => {
    const res = await request(app).put('/record').send({ title: 'no slug' });
    expect(res.status).toBe(500);
    expect(res.headers['content-type']).toMatch(/application\/json/);
  });
});

describe('DELETE /record/:id', () => {
  it('deletes and reports the removed record', async () => {
    const record = await createRecord();
    const res = await request(app).delete(`/record/${record.id}`);
    expect(res.status).toBe(200);
    expect(res.body.map((r: { id: number }) => r.id)).toEqual([record.id]);
    expect(await db.query.records.findFirst({ where: { id: record.id } })).toBeUndefined();
  });
});

describe('PUT /link', () => {
  it('creates a link between records', async () => {
    const a = await createRecord();
    const b = await createRecord();
    const res = await request(app)
      .put('/link')
      .send({ sourceId: a.id, targetId: b.id, predicate: 'related_to' });
    expect(res.status).toBe(200);
    expect(res.body).toMatchObject({ sourceId: a.id, targetId: b.id, predicate: 'related_to' });
  });

  it('upserts instead of duplicating on repeat submission', async () => {
    const a = await createRecord();
    const b = await createRecord();
    const payload = { sourceId: a.id, targetId: b.id, predicate: 'related_to' };
    await request(app).put('/link').send(payload);
    await request(app).put('/link').send(payload);
    const rows = await db.query.links.findMany({
      where: { sourceId: a.id, targetId: b.id },
    });
    expect(rows).toHaveLength(1);
  });

  it('stores links in canonical predicate direction', async () => {
    const slug: PredicateSlug = 'contained_by';
    const def = getPredicate(slug);
    const a = await createRecord();
    const b = await createRecord();

    const res = await request(app)
      .put('/link')
      .send({ sourceId: a.id, targetId: b.id, predicate: slug });
    expect(res.status).toBe(200);

    if (def.canonical) {
      expect(res.body).toMatchObject({ sourceId: a.id, targetId: b.id, predicate: slug });
    } else {
      // Non-canonical input must be flipped to its canonical inverse.
      expect(res.body).toMatchObject({
        sourceId: b.id,
        targetId: a.id,
        predicate: def.inverseSlug,
      });
    }
  });

  it('rejects self-links via errorHandler', async () => {
    const a = await createRecord();
    const res = await request(app)
      .put('/link')
      .send({ sourceId: a.id, targetId: a.id, predicate: 'related_to' });
    expect(res.status).toBe(500);
    expect(res.body.message).toMatch(/cannot be identical/);
  });
});

describe('DELETE /link/:id', () => {
  it('removes the link', async () => {
    const a = await createRecord();
    const b = await createRecord();
    const created = await request(app)
      .put('/link')
      .send({ sourceId: a.id, targetId: b.id, predicate: 'related_to' });
    const res = await request(app).delete(`/link/${created.body.id}`);
    expect(res.status).toBe(200);
    expect(await db.query.links.findFirst({ where: { id: created.body.id } })).toBeUndefined();
  });
});
