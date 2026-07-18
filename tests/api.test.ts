/**
 * API contract tests via supertest — no port binding, real scratch DB.
 * Covers the archive route's status codes, the errorHandler actually running
 * (it was once mounted before the routes and never fired), and the record
 * endpoints the frontend leans on.
 */
import { describe, expect, it } from 'vitest';
import request from 'supertest';
import { app } from '@api/app';
import { db } from '@db/index';
import { claimArchive } from '@integrations/archive';
import { createRecord, servePage, waitFor } from './helpers';

describe('GET /record', () => {
  it('returns a record with its archives relation', async () => {
    const record = await createRecord();
    const res = await request(app).get(`/record/${record.id}`);
    expect(res.status).toBe(200);
    expect(res.body.id).toBe(record.id);
    expect(res.body.archives).toEqual([]);
  });

  it('looks records up by slug', async () => {
    const record = await createRecord();
    const res = await request(app).get(`/record/slug/${record.slug}`);
    expect(res.status).toBe(200);
    expect(res.body.id).toBe(record.id);
  });
});

describe('POST /record/:id/archive', () => {
  it('404s for an unknown record', async () => {
    const res = await request(app).post('/record/999999/archive');
    expect(res.status).toBe(404);
  });

  it('400s for a record without a URL', async () => {
    const record = await createRecord({ url: null });
    const res = await request(app).post(`/record/${record.id}/archive`);
    expect(res.status).toBe(400);
  });

  it('409s with a JSON message while a claim is held', async () => {
    const record = await createRecord({ url: 'https://example.com/held' });
    await claimArchive(record);
    const res = await request(app).post(`/record/${record.id}/archive`);
    expect(res.status).toBe(409);
    expect(res.body.message).toMatch(/already being archived/);
  });

  it('routes thrown errors through errorHandler as JSON', async () => {
    // Non-numeric id makes the zod parse throw inside the route; the error
    // must reach errorHandler (mounted after the routes) and come back as
    // JSON, not Express's default HTML error page.
    const res = await request(app).post('/record/not-a-number/archive');
    expect(res.status).toBe(500);
    expect(res.headers['content-type']).toMatch(/application\/json/);
    expect(typeof res.body.message).toBe('string');
  });

  it('202s with a pending row, then the detached capture lands on the record', async () => {
    const page = await servePage(
      '<html><head><title>Archived via API</title></head><body>content</body></html>',
    );
    try {
      const record = await createRecord({ url: `${page.url}/article` });

      const res = await request(app).post(`/record/${record.id}/archive`);
      expect(res.status).toBe(202);
      expect(res.body.status).toBe('pending');

      const settled = await waitFor(async () => {
        const row = await db.query.archives.findFirst({ where: { recordId: record.id } });
        return row && row.status !== 'pending' ? row : null;
      });
      expect(settled.status).toBe('ok');
      expect(settled.title).toBe('Archived via API');

      // The stored copy must be reachable where the frontend builds its
      // iframe src: /archives/<path>/index.html.
      const served = await request(app).get(`/archives/${settled.path}/index.html`);
      expect(served.status).toBe(200);
      expect(served.text).toContain('Archived via API');
    } finally {
      await page.close();
    }
  });
});
