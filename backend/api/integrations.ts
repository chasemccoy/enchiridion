import { syncReadwiseData } from '@integrations/readwise/sync';
import { withSyncReporter } from '@integrations/utils/progress';
import type { SyncDoneEvent, SyncEvent } from '@shared/types/sync';
import { Router } from 'express';

export const integrationRoutes = Router();

// ============================================================================
// POST
// ============================================================================

/**
 * Runs a Readwise sync and streams its progress as NDJSON — one `SyncEvent`
 * per line, ending with a `done` event. The settings panel consumes this to
 * show phases, created records, and the log while the sync is still running.
 *
 * Because the response is streamed, failures can't use the JSON errorHandler
 * (headers are already out): they're reported in the terminal `done` event
 * instead, and the HTTP status is always 200.
 */
integrationRoutes.post('/sync/readwise', async (_, res) => {
  const startedAt = performance.now();
  let entriesCreated = 0;

  res.status(200);
  res.setHeader('Content-Type', 'application/x-ndjson; charset=utf-8');
  // no-transform keeps the compression middleware (and any proxy) from
  // buffering the stream; X-Accel-Buffering is the same hint for nginx-style
  // proxies.
  res.setHeader('Cache-Control', 'no-cache, no-transform');
  res.setHeader('X-Accel-Buffering', 'no');
  res.flushHeaders();

  const send = (event: SyncEvent) => {
    // The sync fires background work (Wayback submissions) that may log after
    // the response has ended; don't try to write to a closed stream.
    if (res.writableEnded || res.destroyed) return;
    res.write(`${JSON.stringify(event)}\n`);
    // compression exposes flush(); it's a no-op when nothing is compressed.
    (res as typeof res & { flush?: () => void }).flush?.();
  };

  const finish = (done: Omit<SyncDoneEvent, 'ts' | 'type' | 'durationMs'>) => {
    send({
      type: 'done',
      ts: new Date().toISOString(),
      durationMs: Math.round(performance.now() - startedAt),
      ...done,
    });
    res.end();
  };

  try {
    await withSyncReporter((event) => {
      if (event.type === 'run' && event.status === 'completed') {
        entriesCreated = event.entriesCreated ?? 0;
      }
      send(event);
    }, syncReadwiseData);

    finish({ ok: true, entriesCreated });
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Unknown error occurred';
    finish({ ok: false, entriesCreated, error: message });
  }
});
