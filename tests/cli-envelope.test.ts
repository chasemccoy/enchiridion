/**
 * The CLI's output contract — agents parse the `{data, meta}` envelope and
 * `{error: {code, message}}` failures, so this is an API surface. Handlers are
 * exercised directly (importing backend/cli/ench/index.ts would run main()).
 */
import { describe, expect, it } from 'vitest';
import { create, get, list } from '../backend/cli/ench/commands/records';
import { CLICommandError, formatErrorResult, normalizeError } from '../backend/cli/ench/lib/errors';
import { createRecord } from './helpers';

describe('success envelopes', () => {
  it('records get wraps a single record as {data}', async () => {
    const record = await createRecord({ title: 'Envelope single' });
    const result = await get([String(record.id)], {});
    expect(result.data).toMatchObject({ id: record.id, title: 'Envelope single' });
    expect(result.meta).toBeUndefined();
  });

  it('records get with several ids adds meta.count and inlines misses', async () => {
    const a = await createRecord();
    const b = await createRecord();
    const result = await get([String(a.id), String(b.id), '999999'], {});
    expect(result.meta).toMatchObject({ count: 3 });
    const rows = result.data as Array<Record<string, unknown>>;
    expect(rows[2]).toMatchObject({ id: 999999, error: 'NOT_FOUND' });
  });

  it('records list returns id/slug/title triples with paging meta', async () => {
    const record = await createRecord({ title: 'Envelope list' });
    const result = await list([], { limit: 5 });
    expect(result.meta).toMatchObject({ limit: 5, offset: 0 });
    const rows = result.data as Array<{ id: number; slug: string; title: string | null }>;
    const hit = rows.find((row) => row.id === record.id);
    expect(hit).toMatchObject({ slug: record.slug, title: 'Envelope list' });
    expect(hit && Object.keys(hit).sort()).toEqual(['id', 'slug', 'title']);
  });

  it('records create parses JSON args and returns the created row', async () => {
    const result = await create([JSON.stringify({ slug: 'cli-created', title: 'CLI' })], {});
    expect(result.data).toMatchObject({ slug: 'cli-created', title: 'CLI' });
  });
});

describe('error contract', () => {
  it('handlers throw typed CLICommandErrors', async () => {
    await expect(get(['999999'], {})).rejects.toMatchObject({
      code: 'NOT_FOUND',
      name: 'CLICommandError',
    });
    await expect(get(['not-a-number'], {})).rejects.toMatchObject({ code: 'VALIDATION_ERROR' });
  });

  it('normalizeError maps error flavors to stable codes', () => {
    expect(normalizeError(new CLICommandError('NOT_FOUND', 'nope')).code).toBe('NOT_FOUND');
    expect(normalizeError(new Error('SQLITE_CONSTRAINT: oops')).code).toBe('DB_ERROR');
    expect(normalizeError(new Error('OpenAI rate limit')).code).toBe('EMBEDDING_ERROR');
    expect(normalizeError(new Error('anything else')).code).toBe('INTERNAL_ERROR');
    expect(normalizeError('plain string').code).toBe('INTERNAL_ERROR');
  });

  it('formatErrorResult produces the {error: {code, message}} envelope', () => {
    const result = formatErrorResult(new CLICommandError('VALIDATION_ERROR', 'bad input'));
    expect(result).toMatchObject({ error: { code: 'VALIDATION_ERROR', message: 'bad input' } });
  });
});
