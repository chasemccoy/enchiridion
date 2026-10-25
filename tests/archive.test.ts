/**
 * Claim/run semantics of the archive integration: the 'pending' row as a
 * cross-run lock, failure preserving the last good capture, and per-record
 * folder scoping (URLs differing only by query string must not collide).
 */
import { describe, expect, it } from 'vitest';
import { sql } from 'drizzle-orm';
import { db } from '@db/index';
import * as http from 'node:http';
import type { AddressInfo } from 'node:net';
import request from 'supertest';
import { app } from '@api/app';
import {
  claimArchive,
  listArchiveVersions,
  pastVersionStamp,
  runArchive,
} from '@integrations/archive';
import { createRecord, servePage } from './helpers';

const PAGE = '<html><head><title>Test Page</title></head><body><p>hello</p></body></html>';

describe('claimArchive', () => {
  it('claims a fresh record as pending', async () => {
    const record = await createRecord({ url: 'https://example.com/fresh' });
    const claimed = await claimArchive(record);
    expect(claimed?.status).toBe('pending');
    expect(claimed?.recordId).toBe(record.id);
  });

  it('refuses a second claim while the first is fresh', async () => {
    const record = await createRecord({ url: 'https://example.com/contended' });
    expect((await claimArchive(record))?.status).toBe('pending');
    expect(await claimArchive(record)).toBeNull();
  });

  it('reclaims a stale pending row from a crashed run', async () => {
    const record = await createRecord({ url: 'https://example.com/stale' });
    await claimArchive(record);
    await db.run(
      sql`UPDATE archives SET updated_at = datetime('now', '-11 minutes') WHERE record_id = ${record.id}`,
    );
    expect((await claimArchive(record))?.status).toBe('pending');
  });

  it('throws for a record with no URL', async () => {
    const record = await createRecord({ url: null });
    await expect(claimArchive(record)).rejects.toThrow(/has no URL/);
  });

  it('preserves the last good capture on the pending row', async () => {
    const record = await createRecord({ url: 'https://example.com/preserve' });
    await claimArchive(record);
    await db.run(
      sql`UPDATE archives SET status = 'ok', path = 'seed/example', title = 'Seed',
          archived_at = datetime('now', '-1 day') WHERE record_id = ${record.id}`,
    );
    const reclaimed = await claimArchive(record);
    expect(reclaimed?.status).toBe('pending');
    expect(reclaimed?.path).toBe('seed/example');
    expect(reclaimed?.title).toBe('Seed');
  });
});

describe('runArchive', () => {
  it('persists a failed run without wiping the last good capture', async () => {
    const record = await createRecord({ url: 'http://127.0.0.1:1/unreachable' });
    await claimArchive(record);
    const seeded = await db.run(
      sql`UPDATE archives SET path = 'seed/example', title = 'Seed',
          archived_at = datetime('now', '-1 day') WHERE record_id = ${record.id}`,
    );
    expect(seeded).toBeTruthy();

    const failed = await runArchive(record);
    expect(failed.status).toBe('failed');
    expect(failed.error).toBeTruthy();
    expect(failed.path).toBe('seed/example');
    expect(failed.title).toBe('Seed');
  });

  it('archives into the flat slug folder amber itself uses', async () => {
    const page = await servePage(PAGE);
    try {
      const record = await createRecord({ url: `${page.url}/page` });
      await claimArchive(record);
      const result = await runArchive(record);
      expect(result.status).toBe('ok');
      expect(result.path).not.toMatch(/^\d+\//);
      expect(result.path).toMatch(/-page$/);
    } finally {
      await page.close();
    }
  });

  it('records with the same URL share one archive folder', async () => {
    const page = await servePage(PAGE);
    try {
      const a = await createRecord({ url: `${page.url}/shared` });
      const b = await createRecord({ url: `${page.url}/shared` });
      await claimArchive(a);
      const resultA = await runArchive(a);
      await claimArchive(b);
      const resultB = await runArchive(b);
      expect(resultA.status).toBe('ok');
      expect(resultB.status).toBe('ok');
      expect(resultB.path).toBe(resultA.path);
    } finally {
      await page.close();
    }
  });

  it('falls back to a per-record folder only when a different URL already owns the slug', async () => {
    const page = await servePage(PAGE);
    try {
      const a = await createRecord({ url: `${page.url}/watch?v=aaa` });
      const b = await createRecord({ url: `${page.url}/watch?v=bbb` });

      await claimArchive(a);
      const resultA = await runArchive(a);
      await claimArchive(b);
      const resultB = await runArchive(b);

      expect(resultA.status).toBe('ok');
      expect(resultB.status).toBe('ok');
      expect(resultA.path).not.toMatch(/^\d+\//);
      expect(resultB.path).toMatch(new RegExp(`^${b.id}/`));
      expect(resultA.path).not.toBe(resultB.path);
    } finally {
      await page.close();
    }
  });

  it('stamps archivedAt and stores the page title on success', async () => {
    const page = await servePage(PAGE);
    try {
      const record = await createRecord({ url: `${page.url}/page` });
      await claimArchive(record);
      const result = await runArchive(record);
      expect(result.status).toBe('ok');
      expect(result.title).toBe('Test Page');
      expect(result.error).toBeNull();
      expect(result.archivedAt).toBeTruthy();
    } finally {
      await page.close();
    }
  });
});

/** A stand-in Wayback Machine: every request answers with `html` as the capture from 9 March 2000. */
async function serveWayback(html: string): Promise<{ base: string; close: () => Promise<void> }> {
  const server = http.createServer((_req, res) => {
    res.setHeader('content-type', 'text/html; charset=utf-8');
    res.setHeader('memento-datetime', 'Thu, 09 Mar 2000 21:22:37 GMT');
    res.end(html);
  });
  await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
  const { port } = server.address() as AddressInfo;
  return {
    base: `http://127.0.0.1:${port}`,
    close: () => new Promise((resolve) => server.close(() => resolve())),
  };
}

describe('pastVersionStamp', () => {
  it('reads dates, stamps and latest', () => {
    expect(pastVersionStamp('2000', 'https://kottke.org/')).toBe('2000');
    expect(pastVersionStamp(' 2000-03-09 ', 'https://kottke.org/')).toBe('20000309');
    expect(pastVersionStamp('20000309212237', 'https://kottke.org/')).toBe('20000309212237');
    expect(pastVersionStamp('Latest', 'https://kottke.org/')).toBe('latest');
  });

  it('takes a Wayback link to the same page, www or not', () => {
    expect(
      pastVersionStamp(
        'https://web.archive.org/web/20000309212237/http://www.kottke.org/',
        'https://kottke.org/',
      ),
    ).toBe('20000309212237');
  });

  it('refuses a Wayback link to another page, and anything unreadable', () => {
    expect(() =>
      pastVersionStamp(
        'https://web.archive.org/web/2000/http://example.com/',
        'https://kottke.org/',
      ),
    ).toThrow(/not this record/);
    expect(() => pastVersionStamp('last spring', 'https://kottke.org/')).toThrow(/Can't read/);
  });
});

describe('past versions', () => {
  it('files a Wayback capture as a past version and leaves the current copy alone', async () => {
    const page = await servePage(PAGE);
    const wayback = await serveWayback(
      '<html><head><title>Old Page</title></head><body><p>the year 2000</p></body></html>',
    );
    process.env.ARCHIVE_WAYBACK_BASE = wayback.base;
    try {
      const record = await createRecord({ url: `${page.url}/site` });
      await claimArchive(record);
      const current = await runArchive(record);
      expect(current.status).toBe('ok');

      await claimArchive(record);
      const filed = await runArchive(record, { at: '2000' });
      expect(filed.status).toBe('ok');
      expect(filed.path).toBe(current.path);
      expect(filed.title).toBe('Test Page');
      expect(filed.archivedAt).toBe(current.archivedAt);

      const versions = listArchiveVersions(filed.path);
      expect(versions).toHaveLength(2);
      expect(versions[0]).toMatchObject({ current: true, wayback: false, title: 'Test Page' });
      expect(versions[1]).toMatchObject({ current: false, wayback: true, title: 'Old Page' });
      expect(versions[1]?.date).toMatch(/^2000-03-09/);
      expect(versions[1]?.path).toMatch(new RegExp(`^${current.path}/versions/`));
    } finally {
      delete process.env.ARCHIVE_WAYBACK_BASE;
      await page.close();
      await wayback.close();
    }
  });

  it('lists nothing for a record never archived, and refuses an unreadable date', async () => {
    const record = await createRecord({ url: 'https://kottke.org/' });
    const versions = await request(app).get(`/record/${record.id}/archive/versions`);
    expect(versions.status).toBe(200);
    expect(versions.body).toEqual([]);

    const refused = await request(app).post(`/record/${record.id}/archive`).send({ at: 'someday' });
    expect(refused.status).toBe(400);
    expect(refused.body.message).toMatch(/Can't read/);
  });
});
