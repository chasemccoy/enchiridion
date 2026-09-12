/**
 * Request-scoped progress reporting for integration syncs.
 *
 * Integration code calls `report()` wherever something worth surfacing
 * happens (a phase starting, a record being created, a link written). Whoever
 * kicked off the sync — the streaming API route — wraps the call in
 * `withSyncReporter()` to receive those events. Outside such a scope (the
 * `ench` CLI, scripts, tests that don't opt in) `report()` is a no-op, so the
 * integration code never has to thread a reporter through its signatures.
 *
 * AsyncLocalStorage carries the reporter across every await inside the scope,
 * including concurrent requests, without any global state.
 */
import { AsyncLocalStorage } from 'node:async_hooks';
import type { SyncEvent, SyncEventInput } from '@shared/types/sync';

export type SyncReporter = (event: SyncEvent) => void;

const storage = new AsyncLocalStorage<SyncReporter>();

/** Run `fn` with `reporter` receiving every `report()` call made inside it. */
export function withSyncReporter<T>(reporter: SyncReporter, fn: () => Promise<T>): Promise<T> {
  return storage.run(reporter, fn);
}

/** Emit a progress event to the active reporter, if any. */
export function report(event: SyncEventInput): void {
  const reporter = storage.getStore();
  if (!reporter) return;

  reporter({ ...event, ts: new Date().toISOString() } as SyncEvent);
}
