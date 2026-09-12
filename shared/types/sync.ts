/**
 * Structured progress events emitted while an integration sync runs.
 *
 * The backend streams these to the settings panel as NDJSON (one event per
 * line) so the UI can show what the sync is doing while it's doing it — which
 * phase is active, which records were created and why, what got linked — and
 * the raw log alongside for anyone who wants the details.
 */
import type { RecordType } from './index';

export const syncPhaseEnum = ['documents', 'books', 'authors', 'tags', 'records'] as const;
export type SyncPhase = (typeof syncPhaseEnum)[number];

export type SyncLogLevel = 'info' | 'warn' | 'error';

export type SyncRecordSource = 'document' | 'author' | 'tag';

interface SyncEventBase {
  /** ISO timestamp, stamped by the reporter. */
  ts: string;
}

/** A phase of the sync started, finished, or had nothing to do. */
export interface SyncPhaseEvent extends SyncEventBase {
  type: 'phase';
  phase: SyncPhase;
  status: 'start' | 'done' | 'skip';
  /** Human-readable outcome, e.g. "Fetched 12 documents". */
  message?: string;
  /** Number of items the phase handled. */
  count?: number;
}

/** Incremental progress inside a phase (page fetched, batch processed). */
export interface SyncProgressEvent extends SyncEventBase {
  type: 'progress';
  phase: SyncPhase;
  message: string;
  current?: number;
  total?: number;
}

/** A knowledge-graph record was created from (or mapped onto) Readwise data. */
export interface SyncRecordEvent extends SyncEventBase {
  type: 'record';
  /** `created` = new row; `mapped` = an existing record adopted the Readwise item (slug match). */
  action: 'created' | 'mapped';
  recordId: number;
  recordType: RecordType;
  title: string | null;
  slug: string;
  url?: string | null;
  /** Which Readwise thing the record came from. */
  source: SyncRecordSource;
  /** Why this item qualified for a record, e.g. "Archived article with 3 highlights and 2 tags". */
  reason: string;
}

/** A link was written between two records. Aggregated by predicate in the UI. */
export interface SyncLinkEvent extends SyncEventBase {
  type: 'link';
  predicate: string;
  count: number;
}

/** A plain log line, mirrored from the integration logger. */
export interface SyncLogEvent extends SyncEventBase {
  type: 'log';
  level: SyncLogLevel;
  scope: string;
  message: string;
}

/** Bookkeeping for the integration run row. */
export interface SyncRunEvent extends SyncEventBase {
  type: 'run';
  status: 'started' | 'completed' | 'failed';
  runId: number;
  entriesCreated?: number;
  message?: string;
}

/** Terminal event: the stream ends after one of these. */
export interface SyncDoneEvent extends SyncEventBase {
  type: 'done';
  ok: boolean;
  durationMs: number;
  entriesCreated: number;
  error?: string;
}

export type SyncEvent =
  | SyncPhaseEvent
  | SyncProgressEvent
  | SyncRecordEvent
  | SyncLinkEvent
  | SyncLogEvent
  | SyncRunEvent
  | SyncDoneEvent;

/** Omit that distributes over a union, so each member keeps its own shape. */
type DistributiveOmit<T, K extends PropertyKey> = T extends unknown ? Omit<T, K> : never;

/** What integration code hands to the reporter; `ts` is stamped on the way out. */
export type SyncEventInput = DistributiveOmit<SyncEvent, 'ts'>;
