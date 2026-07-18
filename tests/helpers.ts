import * as http from 'node:http';
import type { AddressInfo } from 'node:net';
import { db } from '@db/index';
import { records, type RecordInsert, type RecordSelect } from '@db/schema';

let seq = 0;

/** Insert a minimal record fixture; override any column as needed. */
export async function createRecord(overrides: Partial<RecordInsert> = {}): Promise<RecordSelect> {
  seq += 1;
  const [row] = await db
    .insert(records)
    .values({
      slug: `test-record-${process.pid}-${seq}`,
      title: `Test record ${seq}`,
      type: 'artifact',
      ...overrides,
    })
    .returning();
  if (!row) throw new Error('record fixture insert failed');
  return row;
}

/**
 * Serve a static HTML page on a local ephemeral port, so archive tests can
 * capture a real URL without touching the network.
 */
export async function servePage(
  html: string,
): Promise<{ url: string; close: () => Promise<void> }> {
  const server = http.createServer((_req, res) => {
    res.setHeader('content-type', 'text/html; charset=utf-8');
    res.end(html);
  });
  await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
  const { port } = server.address() as AddressInfo;
  return {
    url: `http://127.0.0.1:${port}`,
    close: () => new Promise((resolve) => server.close(() => resolve())),
  };
}

/** Poll until `probe` returns non-null, or fail after `timeoutMs`. */
export async function waitFor<T>(
  probe: () => Promise<T | null | undefined>,
  timeoutMs = 15_000,
  intervalMs = 100,
): Promise<T> {
  const deadline = Date.now() + timeoutMs;
  for (;;) {
    const result = await probe();
    if (result != null) return result;
    if (Date.now() > deadline) throw new Error(`waitFor timed out after ${timeoutMs}ms`);
    await new Promise((resolve) => setTimeout(resolve, intervalMs));
  }
}
