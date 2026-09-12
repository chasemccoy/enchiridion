<template>
  <div
    class="SyncReport"
    :class="`SyncReport--${status}`"
  >
    <ol class="SyncReport__phases">
      <li
        v-for="phase in phases"
        :key="phase.phase"
        class="SyncReport__phase"
        :class="`SyncReport__phase--${phase.status}`"
      >
        <span class="SyncReport__phaseMarker">
          <UIcon
            class="SyncReport__phaseIcon"
            :name="phaseIcon(phase.status)"
          />
        </span>
        <span class="SyncReport__phaseLabel">{{ phaseLabels[phase.phase] }}</span>
        <span class="SyncReport__phaseMessage">
          {{ phase.message ?? (phase.status === 'active' ? 'Working…' : '') }}
        </span>
      </li>
    </ol>

    <p
      v-if="summary"
      class="SyncReport__summary"
      :class="`SyncReport__summary--${status}`"
    >
      <UIcon
        class="SyncReport__summaryIcon"
        :name="status === 'failed' ? 'i-lucide-circle-x' : 'i-lucide-circle-check'"
      />
      <span>{{ summary }}</span>
    </p>

    <section
      v-if="records.length > 0"
      class="SyncReport__section"
    >
      <h4 class="SyncReport__sectionTitle">
        {{
          createdCount > 0 ? `Created ${pluralize(createdCount, 'record', 'records')}` : 'Records'
        }}
        <span
          v-if="mappedCount > 0"
          class="SyncReport__sectionNote"
        >
          · {{ pluralize(mappedCount, 'existing record', 'existing records') }} reused
        </span>
      </h4>

      <div
        v-for="group in recordGroups"
        :key="group.type"
        class="SyncReport__group"
      >
        <h5 class="SyncReport__groupTitle">
          <UIcon
            class="SyncReport__groupIcon"
            :name="getIconForRecordType(group.type)"
          />
          {{ recordTypeLabels[group.type] }}
          <span class="SyncReport__groupCount">{{ group.records.length }}</span>
        </h5>

        <ul class="SyncReport__records">
          <li
            v-for="record in group.records"
            :key="record.recordId"
            class="SyncReport__record"
          >
            <RouterLink
              class="SyncReport__recordTitle"
              :class="{ 'SyncReport__recordTitle--untitled': !record.title }"
              :to="`/${record.slug}`"
            >
              {{ record.title || record.reason }}
            </RouterLink>
            <UBadge
              v-if="record.action === 'mapped'"
              class="SyncReport__recordBadge"
              color="neutral"
              variant="outline"
              size="sm"
              label="existing"
            />
            <span
              v-if="record.title"
              class="SyncReport__recordReason"
            >
              {{ record.reason }}
            </span>
          </li>
        </ul>
      </div>
    </section>

    <section
      v-if="links.length > 0"
      class="SyncReport__section"
    >
      <h4 class="SyncReport__sectionTitle">Links written</h4>
      <ul class="SyncReport__links">
        <li
          v-for="link in links"
          :key="link.predicate"
          class="SyncReport__link"
        >
          <span class="SyncReport__linkCount">{{ link.count }}</span>
          <span class="SyncReport__linkPredicate">{{ predicateLabel(link.predicate) }}</span>
        </li>
      </ul>
    </section>

    <section
      v-if="warnings.length > 0"
      class="SyncReport__section"
    >
      <h4 class="SyncReport__sectionTitle">
        {{ pluralize(warnings.length, 'warning', 'warnings') }}
      </h4>
      <ul class="SyncReport__warnings">
        <li
          v-for="(warning, index) in warnings"
          :key="index"
          class="SyncReport__warning"
          :class="`SyncReport__warning--${warning.level}`"
        >
          <UIcon
            class="SyncReport__warningIcon"
            :name="warning.level === 'error' ? 'i-lucide-circle-alert' : 'i-lucide-triangle-alert'"
          />
          <span>{{ warning.message }}</span>
        </li>
      </ul>
    </section>

    <details
      v-if="log.length > 0"
      class="SyncReport__log"
      :open="status === 'running'"
    >
      <summary class="SyncReport__logSummary">
        <UIcon
          name="i-lucide-chevron-right"
          class="SyncReport__logChevron"
        />
        Log
        <span class="SyncReport__groupCount">{{ log.length }}</span>
      </summary>
      <ol
        ref="logElement"
        class="SyncReport__logLines"
      >
        <li
          v-for="(line, index) in log"
          :key="index"
          class="SyncReport__logLine"
          :class="`SyncReport__logLine--${line.level}`"
        >
          <time class="SyncReport__logTime">{{ formatTime(line.ts) }}</time>
          <span class="SyncReport__logScope">{{ line.scope }}</span>
          <span class="SyncReport__logMessage">{{ line.message }}</span>
        </li>
      </ol>
    </details>
  </div>
</template>

<script setup lang="ts">
import type {
  LinkSummary,
  PhaseState,
  PhaseStatus,
  SyncStatus,
} from '@app/composables/useReadwiseSync';
import { getIconForRecordType } from '@app/utils';
import { pluralize } from '@shared/lib/formatting';
import type { RecordType } from '@shared/types';
import type { SyncDoneEvent, SyncLogEvent, SyncPhase, SyncRecordEvent } from '@shared/types/sync';
import { computed, nextTick, useTemplateRef, watch } from 'vue';
import { RouterLink } from 'vue-router';

const { status, phases, records, links, log, warnings, done, error } = defineProps<{
  status: SyncStatus;
  phases: PhaseState[];
  records: SyncRecordEvent[];
  links: LinkSummary[];
  log: SyncLogEvent[];
  warnings: SyncLogEvent[];
  done: SyncDoneEvent | null;
  error: string | null;
}>();

const phaseLabels: Record<SyncPhase, string> = {
  documents: 'Reader documents',
  books: 'Book highlights',
  authors: 'Authors',
  tags: 'Tags',
  records: 'Records',
};

const recordTypeLabels: Record<RecordType, string> = {
  artifact: 'Artifacts',
  entity: 'Entities',
  concept: 'Concepts',
};

const recordTypeOrder: RecordType[] = ['artifact', 'entity', 'concept'];

function phaseIcon(phaseStatus: PhaseStatus): string {
  switch (phaseStatus) {
    case 'active':
      return 'i-lucide-loader-circle';
    case 'done':
      return 'i-lucide-check';
    case 'skip':
      return 'i-lucide-minus';
    case 'failed':
      return 'i-lucide-x';
    default:
      return 'i-lucide-circle-dashed';
  }
}

function predicateLabel(predicate: string): string {
  return predicate.replaceAll('_', ' ');
}

function formatTime(iso: string): string {
  return new Date(iso).toLocaleTimeString('en-US', {
    hour12: false,
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  });
}

function formatDuration(ms: number): string {
  return ms < 1000 ? `${ms}ms` : `${(ms / 1000).toFixed(1)}s`;
}

const createdCount = computed(() => records.filter((record) => record.action === 'created').length);
const mappedCount = computed(() => records.length - createdCount.value);

const recordGroups = computed(() =>
  recordTypeOrder
    .map((type) => ({ type, records: records.filter((record) => record.recordType === type) }))
    .filter((group) => group.records.length > 0),
);

const summary = computed(() => {
  if (status === 'failed') {
    return `Sync failed${error ? `: ${error}` : ''}`;
  }

  if (status === 'done' && done) {
    const created =
      createdCount.value > 0
        ? `created ${pluralize(createdCount.value, 'record', 'records')}`
        : 'nothing new to create';
    return `Synced in ${formatDuration(done.durationMs)}, ${created}`;
  }

  return null;
});

// Keep the newest log line in view while the sync is running.
const logElement = useTemplateRef<HTMLOListElement>('logElement');

watch(
  () => log.length,
  async () => {
    if (status !== 'running') return;
    await nextTick();
    const el = logElement.value;
    if (el) el.scrollTop = el.scrollHeight;
  },
);
</script>

<style scoped>
.SyncReport {
  display: grid;
  gap: 14px;
  font-size: 13px;
}

/* --- Phase timeline --------------------------------------------------- */

.SyncReport__phases {
  display: grid;
  gap: 2px;
}

.SyncReport__phase {
  display: grid;
  grid-template-columns: 18px minmax(120px, max-content) 1fr;
  column-gap: 8px;
  align-items: center;
  min-height: 24px;
  color: var(--ui-text-muted);
}

.SyncReport__phaseMarker {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 18px;
  height: 18px;
  border-radius: 999px;
  background-color: var(--ui-bg-elevated);
  color: var(--ui-text-dimmed);
}

.SyncReport__phaseIcon {
  width: 12px;
  height: 12px;
}

.SyncReport__phaseLabel {
  font-weight: 500;
}

.SyncReport__phaseMessage {
  font-size: 12px;
  color: var(--ui-text-dimmed);
  text-wrap: pretty;
}

.SyncReport__phase--active {
  color: var(--ui-text);

  & .SyncReport__phaseMarker {
    color: var(--ui-primary);
  }

  & .SyncReport__phaseIcon {
    animation: SyncReport-spin 1s linear infinite;
  }

  & .SyncReport__phaseMessage {
    color: var(--ui-text-muted);
  }
}

.SyncReport__phase--done {
  color: var(--ui-text);

  & .SyncReport__phaseMarker {
    background-color: color-mix(in oklab, var(--ui-success) 14%, transparent);
    color: var(--ui-success);
  }
}

.SyncReport__phase--failed {
  color: var(--ui-text);

  & .SyncReport__phaseMarker {
    background-color: color-mix(in oklab, var(--ui-error) 14%, transparent);
    color: var(--ui-error);
  }
}

@keyframes SyncReport-spin {
  to {
    transform: rotate(360deg);
  }
}

@media (prefers-reduced-motion: reduce) {
  .SyncReport__phase--active .SyncReport__phaseIcon {
    animation: none;
  }
}

/* --- Summary line ----------------------------------------------------- */

.SyncReport__summary {
  display: flex;
  align-items: flex-start;
  gap: 6px;
  padding: 8px 10px;
  border-radius: var(--radius-lg);
  background-color: var(--ui-bg-elevated);
  color: var(--ui-text);
  text-wrap: pretty;
}

.SyncReport__summaryIcon {
  flex-shrink: 0;
  width: 15px;
  height: 15px;
  margin-top: 1px;
  color: var(--ui-success);
}

.SyncReport__summary--failed {
  background-color: color-mix(in oklab, var(--ui-error) 10%, transparent);

  & .SyncReport__summaryIcon {
    color: var(--ui-error);
  }
}

/* --- Sections --------------------------------------------------------- */

.SyncReport__section {
  display: grid;
  gap: 8px;
  padding-top: 12px;
  border-top: 1px solid var(--ui-border);
}

.SyncReport__sectionTitle {
  font-weight: 600;
  color: var(--ui-text);
}

.SyncReport__sectionNote {
  font-weight: 400;
  color: var(--ui-text-muted);
}

.SyncReport__group {
  display: grid;
  gap: 4px;
}

.SyncReport__groupTitle {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  font-size: 12px;
  font-weight: 500;
  color: var(--ui-text-muted);
}

.SyncReport__groupIcon {
  width: 13px;
  height: 13px;
}

.SyncReport__groupCount {
  padding: 0 5px;
  border-radius: 999px;
  background-color: var(--ui-bg-elevated);
  font-size: 11px;
  font-variant-numeric: tabular-nums;
  color: var(--ui-text-dimmed);
}

.SyncReport__records {
  display: grid;
  gap: 1px;
}

.SyncReport__record {
  display: grid;
  grid-template-columns: auto 1fr;
  column-gap: 6px;
  row-gap: 1px;
  align-items: center;
  padding: 5px 8px;
  border-radius: var(--radius-lg);
  background-color: var(--ui-bg-elevated);
}

.SyncReport__recordTitle {
  font-weight: 500;
  color: var(--ui-text);
  overflow-wrap: anywhere;

  &:hover {
    text-decoration: underline;
  }
}

:deep(.SyncReport__recordBadge) {
  justify-self: start;
  font-size: 10px;
}

/* Untitled records (highlights) are identified by their reason instead — the
 * slug is a Reader id and means nothing to a reader. */
.SyncReport__recordTitle--untitled {
  font-weight: 400;
  color: var(--ui-text-muted);
}

.SyncReport__recordReason {
  grid-column: 1 / -1;
  font-size: 12px;
  color: var(--ui-text-muted);
  text-wrap: pretty;
}

.SyncReport__links {
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
}

.SyncReport__link {
  display: inline-flex;
  align-items: baseline;
  gap: 4px;
  padding: 2px 8px;
  border: 0.5px solid var(--ui-border);
  border-radius: 999px;
  font-size: 12px;
  color: var(--ui-text-muted);
}

.SyncReport__linkCount {
  font-weight: 600;
  font-variant-numeric: tabular-nums;
  color: var(--ui-text);
}

.SyncReport__warnings {
  display: grid;
  gap: 4px;
}

.SyncReport__warning {
  display: flex;
  gap: 6px;
  align-items: flex-start;
  font-size: 12px;
  color: var(--ui-text-muted);
  overflow-wrap: anywhere;
}

.SyncReport__warningIcon {
  flex-shrink: 0;
  width: 13px;
  height: 13px;
  margin-top: 2px;
  color: var(--ui-warning);
}

.SyncReport__warning--error .SyncReport__warningIcon {
  color: var(--ui-error);
}

/* --- Raw log ---------------------------------------------------------- */

.SyncReport__log {
  padding-top: 12px;
  border-top: 1px solid var(--ui-border);
}

.SyncReport__logSummary {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  font-weight: 600;
  color: var(--ui-text);
  cursor: pointer;
  list-style: none;
  user-select: none;

  &::-webkit-details-marker {
    display: none;
  }
}

.SyncReport__logChevron {
  width: 13px;
  height: 13px;
  color: var(--ui-text-dimmed);
  transition: transform 0.15s ease;
}

.SyncReport__log[open] .SyncReport__logChevron {
  transform: rotate(90deg);
}

.SyncReport__logLines {
  display: grid;
  gap: 1px;
  max-height: 220px;
  margin-top: 8px;
  padding: 8px 10px;
  border-radius: var(--radius-lg);
  background-color: var(--ui-bg-elevated);
  overflow-y: auto;
  overscroll-behavior: contain;
  font-family: var(--font-mono, ui-monospace, monospace);
  font-size: 11px;
  line-height: 1.5;
}

.SyncReport__logLine {
  display: grid;
  grid-template-columns: auto auto 1fr;
  column-gap: 8px;
  color: var(--ui-text-muted);
}

.SyncReport__logTime {
  color: var(--ui-text-dimmed);
  font-variant-numeric: tabular-nums;
}

.SyncReport__logScope {
  color: var(--ui-text-dimmed);
}

.SyncReport__logMessage {
  white-space: pre-wrap;
  overflow-wrap: anywhere;
}

.SyncReport__logLine--warn .SyncReport__logMessage {
  color: var(--ui-warning);
}

.SyncReport__logLine--error .SyncReport__logMessage {
  color: var(--ui-error);
}

@media (max-width: 480px) {
  .SyncReport__phase {
    grid-template-columns: 18px 1fr;
  }

  .SyncReport__phaseMessage {
    grid-column: 2;
  }

  .SyncReport__logLine {
    grid-template-columns: auto 1fr;
  }

  .SyncReport__logScope {
    display: none;
  }
}
</style>
