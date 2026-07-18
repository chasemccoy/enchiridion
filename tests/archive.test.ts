/**
 * Claim/run semantics of the archive integration: the 'pending' row as a
 * cross-run lock, failure preserving the last good capture, and per-record
 * folder scoping (URLs differing only by query string must not collide).
 */
import { describe, expect, it } from 'vitest';
import { sql } from 'drizzle-orm';
import { db } from '@db/index';
import { claimArchive, runArchive } from '@integrations/archive';
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

  it('archives into per-record folders so query-string twins cannot collide', async () => {
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
      expect(resultA.path).toMatch(new RegExp(`^${a.id}/`));
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
