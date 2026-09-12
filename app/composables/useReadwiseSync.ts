/**
 * Drives a Readwise sync from the settings panel and turns the backend's
 * NDJSON event stream (see backend/api/integrations.ts) into reactive state
 * the UI can render while the sync is still running: which phase is active,
 * which records were created and why, what got linked, and the raw log.
 */
import useApiClient from '@app/composables/useApiClient';
import type {
  SyncDoneEvent,
  SyncEvent,
  SyncLinkEvent,
  SyncLogEvent,
  SyncPhase,
  SyncRecordEvent,
} from '@shared/types/sync';
import { syncPhaseEnum } from '@shared/types/sync';
import { useQueryClient } from '@tanstack/vue-query';
import { computed, ref, shallowRef, triggerRef } from 'vue';

export type SyncStatus = 'idle' | 'running' | 'done' | 'failed';

export type PhaseStatus = 'pending' | 'active' | 'done' | 'skip' | 'failed';

export interface PhaseState {
  phase: SyncPhase;
  status: PhaseStatus;
  /** Latest progress line while active; the outcome once done. */
  message: string | null;
  count: number | null;
}

export interface LinkSummary {
  predicate: string;
  count: number;
}

export default function useReadwiseSync() {
  const { backendBaseUrl } = useApiClient();
  const queryClient = useQueryClient();

  const status = ref<SyncStatus>('idle');
  const error = ref<string | null>(null);
  // shallowRef + manual trigger: the array can grow to hundreds of log lines
  // and none of them change after arrival, so deep reactivity is wasted work.
  const events = shallowRef<SyncEvent[]>([]);

  function push(event: SyncEvent) {
    events.value.push(event);
    triggerRef(events);
  }

  async function run() {
    if (status.value === 'running') return;

    status.value = 'running';
    error.value = null;
    events.value = [];

    try {
      const response = await window.fetch(new URL('/sync/readwise', backendBaseUrl), {
        method: 'POST',
      });

      if (!response.ok || !response.body) {
        throw new Error(`Sync request failed with status ${response.status}`);
      }

      const reader = response.body.pipeThrough(new TextDecoderStream()).getReader();
      let buffer = '';

      for (;;) {
        const { value, done } = await reader.read();
        if (done) break;

        buffer += value;
        const lines = buffer.split('\n');
        buffer = lines.pop() ?? '';

        for (const line of lines) {
          if (line.trim()) push(JSON.parse(line) as SyncEvent);
        }
      }

      if (buffer.trim()) push(JSON.parse(buffer) as SyncEvent);

      const last = events.value[events.value.length - 1];

      if (last?.type === 'done') {
        status.value = last.ok ? 'done' : 'failed';
        error.value = last.error ?? null;
      } else {
        status.value = 'failed';
        error.value = 'The sync ended without reporting a result.';
      }
    } catch (caught) {
      status.value = 'failed';
      error.value = caught instanceof Error ? caught.message : String(caught);
    } finally {
      // Even a failed run may have created records before it stopped.
      queryClient.invalidateQueries({ queryKey: ['list-records'] });
    }
  }

  function reset() {
    if (status.value === 'running') return;
    status.value = 'idle';
    error.value = null;
    events.value = [];
  }

  const phases = computed<PhaseState[]>(() => {
    const byPhase = new Map<SyncPhase, PhaseState>(
      syncPhaseEnum.map((phase) => [
        phase,
        { phase, status: 'pending', message: null, count: null },
      ]),
    );

    for (const event of events.value) {
      if (event.type === 'phase') {
        const state = byPhase.get(event.phase)!;
        state.status = event.status === 'start' ? 'active' : event.status;
        state.message = event.message ?? state.message;
        state.count = event.count ?? state.count;
      } else if (event.type === 'progress') {
        const state = byPhase.get(event.phase)!;
        if (state.status === 'pending') state.status = 'active';
        state.message = event.message;
      }
    }

    if (status.value === 'failed') {
      for (const state of byPhase.values()) {
        if (state.status === 'active') state.status = 'failed';
      }
    }

    return [...byPhase.values()];
  });

  const records = computed<SyncRecordEvent[]>(() =>
    events.value.filter((event): event is SyncRecordEvent => event.type === 'record'),
  );

  const links = computed<LinkSummary[]>(() => {
    const totals = new Map<string, number>();
    for (const event of events.value) {
      if (event.type === 'link') {
        totals.set(event.predicate, (totals.get(event.predicate) ?? 0) + event.count);
      }
    }
    return [...totals.entries()]
      .map(([predicate, count]) => ({ predicate, count }))
      .sort((a, b) => b.count - a.count);
  });

  const log = computed<SyncLogEvent[]>(() =>
    events.value.filter((event): event is SyncLogEvent => event.type === 'log'),
  );

  const warnings = computed<SyncLogEvent[]>(() =>
    log.value.filter((event) => event.level !== 'info'),
  );

  const done = computed<SyncDoneEvent | null>(() => {
    const last = events.value[events.value.length - 1];
    return last?.type === 'done' ? last : null;
  });

  return {
    status,
    error,
    events,
    phases,
    records,
    links,
    log,
    warnings,
    done,
    run,
    reset,
  };
}

export type { SyncLinkEvent };
