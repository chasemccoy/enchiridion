/**
 * Sync progress reporting: the request-scoped reporter, the logger mirror,
 * the "why was this record created" events that record creation emits, and
 * the NDJSON contract of POST /sync/readwise (phases, run bookkeeping, and a
 * terminal `done` event on both success and failure — with the Readwise API
 * stubbed out so nothing touches the network).
 */
import { afterEach, describe, expect, it, vi } from 'vitest';
import request from 'supertest';
import { app } from '@api/app';
import { db } from '@db/index';
import { integrationRuns, readwiseDocuments } from '@db/schema';
import { createRecordsFromReadwiseDocuments } from '@integrations/readwise/records';
import { createIntegrationLogger } from '@integrations/utils/log';
import { report, withSyncReporter } from '@integrations/utils/progress';
import type { SyncEvent, SyncRecordEvent } from '@shared/types/sync';
import { createRecord } from './helpers';

async function createIntegrationRun(): Promise<number> {
  const [run] = await db
    .insert(integrationRuns)
    .values({ integrationType: 'readwise', runStartTime: new Date().toISOString() })
    .returning({ id: integrationRuns.id });
  if (!run) throw new Error('integration run fixture insert failed');
  return run.id;
}

type DocOverrides = Partial<typeof readwiseDocuments.$inferInsert> & { id: string };

async function insertDoc(integrationRunId: number, overrides: DocOverrides) {
  const now = '2026-09-01T00:00:00Z';
  await db.insert(readwiseDocuments).values({
    url: `https://read.example.com/${overrides.id}`,
    savedAt: now,
    lastMovedAt: now,
    integrationRunId,
    ...overrides,
  });
}

/** Collect every event emitted while `fn` runs. */
async function collect(fn: () => Promise<unknown>): Promise<SyncEvent[]> {
  const events: SyncEvent[] = [];
  await withSyncReporter((event) => events.push(event), fn);
  return events;
}

/** Parse an NDJSON body into events. */
function parseNdjson(body: string): SyncEvent[] {
  return body
    .split('\n')
    .filter((line) => line.trim())
    .map((line) => JSON.parse(line) as SyncEvent);
}

/** supertest doesn't buffer unknown content types by default. */
function postSync() {
  return request(app)
    .post('/sync/readwise')
    .buffer(true)
    .parse((res, callback) => {
      let text = '';
      res.setEncoding('utf8');
      res.on('data', (chunk: string) => (text += chunk));
      res.on('end', () => callback(null, text));
    });
}

const emptyPage = () =>
  new Response(JSON.stringify({ count: 0, nextPageCursor: null, results: [] }), {
    status: 200,
    headers: { 'content-type': 'application/json' },
  });

describe('sync reporter', () => {
  it('is a no-op outside a reporter scope', () => {
    expect(() => report({ type: 'link', predicate: 'tagged_with', count: 1 })).not.toThrow();
  });

  it('stamps a timestamp on every event inside a scope', async () => {
    const events = await collect(async () => {
      report({ type: 'phase', phase: 'documents', status: 'start' });
    });
    expect(events).toHaveLength(1);
    expect(events[0]).toMatchObject({ type: 'phase', phase: 'documents', status: 'start' });
    expect(new Date(events[0]!.ts).getTime()).not.toBeNaN();
  });

  it('mirrors integration logger output as log events', async () => {
    const logger = createIntegrationLogger('readwise', 'test');
    const events = await collect(async () => {
      logger.info('hello', { id: 1 });
      logger.warn('careful');
      logger.error('boom', new Error('bad thing'));
    });
    expect(events).toEqual([
      expect.objectContaining({
        type: 'log',
        level: 'info',
        scope: 'readwise:test',
        message: 'hello {"id":1}',
      }),
      expect.objectContaining({ type: 'log', level: 'warn', message: 'careful' }),
      expect.objectContaining({ type: 'log', level: 'error', message: 'boom: bad thing' }),
    ]);
  });
});

describe('record creation events', () => {
  it('explains why each document earned a record, and what was mapped vs created', async () => {
    const existing = await createRecord({
      slug: 'already-here',
      title: 'Already here',
      isCurated: true,
    });

    const runId = await createIntegrationRun();
    await insertDoc(runId, {
      id: 'article',
      title: 'A tagged article',
      category: 'article',
      location: 'archive',
      tags: ['design', 'writing'],
      notes: 'worth rereading',
    });
    await insertDoc(runId, {
      id: 'highlight-1',
      parentId: 'article',
      category: 'highlight',
      location: null,
      content: 'the important sentence',
    });
    await insertDoc(runId, {
      id: 'collision',
      title: 'Already here',
      category: 'article',
      location: 'archive',
      tags: ['design'],
    });

    const events = await collect(() => createRecordsFromReadwiseDocuments());
    const recordEvents = events.filter((e): e is SyncRecordEvent => e.type === 'record');

    const article = recordEvents.find((e) => e.slug === 'a-tagged-article');
    expect(article).toMatchObject({
      action: 'created',
      recordType: 'artifact',
      source: 'document',
      reason: 'Archived article with 1 highlight, 2 tags, and a note',
    });

    const highlight = recordEvents.find((e) => e.title === null);
    expect(highlight).toMatchObject({
      action: 'created',
      reason: 'Highlight in “A tagged article”',
    });

    const mapped = recordEvents.find((e) => e.slug === 'already-here');
    expect(mapped).toMatchObject({ action: 'mapped', recordId: existing.id });
    expect(mapped!.reason).toContain('already existed');

    const containment = events.find((e) => e.type === 'link' && e.predicate === 'contained_by');
    expect(containment).toMatchObject({ count: 1 });
  });
});

describe('POST /sync/readwise', () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it('streams NDJSON with every phase and a terminal done event', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async () => emptyPage()),
    );

    const res = await postSync();
    expect(res.status).toBe(200);
    expect(res.headers['content-type']).toContain('application/x-ndjson');

    const events = parseNdjson(res.body as string);
    const phases = events.filter((e) => e.type === 'phase');

    for (const phase of ['documents', 'books', 'authors', 'tags', 'records']) {
      expect(phases.some((e) => e.phase === phase && e.status === 'start')).toBe(true);
      expect(phases.some((e) => e.phase === phase && e.status === 'skip')).toBe(true);
    }

    const runs = events.filter((e) => e.type === 'run');
    expect(runs.map((e) => e.status)).toEqual(['started', 'completed']);

    const done = events[events.length - 1];
    expect(done).toMatchObject({ type: 'done', ok: true, entriesCreated: 0 });
    expect(events.some((e) => e.type === 'log')).toBe(true);
  });

  it('reports a failed sync in the done event rather than an HTTP error', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async () => {
        throw new Error('readwise is unreachable');
      }),
    );

    const res = await postSync();
    expect(res.status).toBe(200);

    const events = parseNdjson(res.body as string);
    const done = events[events.length - 1];
    expect(done).toMatchObject({ type: 'done', ok: false, error: 'readwise is unreachable' });
    expect(events.some((e) => e.type === 'run' && e.status === 'failed')).toBe(true);
  });
});
