<template>
  <div
    class="foc"
    :class="gridClass"
  >
    <ConceptRail
      v-if="showSidebar"
      :concepts="concepts"
      :active-slug="activeConcept"
      :total-count="titled.length"
      @select="setConcept"
    />

    <div class="foc__listCol">
      <div class="foc__toolbar">
        <button
          v-if="selectedRecord"
          type="button"
          class="foc__sidebarToggle"
          :class="{ 'foc__sidebarToggle--on': sidebarManuallyOpen }"
          @click="sidebarManuallyOpen = !sidebarManuallyOpen"
        >
          <UIcon name="i-lucide-panel-left" />
          Concepts
        </button>
        <div
          v-else
          class="foc__filters"
        >
          <button
            v-for="f in typeFilters"
            :key="f.value ?? 'all'"
            type="button"
            class="foc__chip"
            :class="{ 'foc__chip--active': typeFilter === f.value }"
            @click="typeFilter = f.value"
          >
            <UIcon
              v-if="f.icon"
              class="foc__chipGlyph"
              :name="f.icon"
            />
            {{ f.label }}
          </button>
        </div>
        <span class="foc__count">{{ listRecords.length }}</span>
      </div>

      <div
        v-if="activeConcept"
        class="foc__filterbar"
      >
        <UIcon
          name="i-lucide-filter"
          class="foc__filterGlyph"
        />
        <span class="foc__filterLabel">{{ activeConceptTitle }}</span>
        <button
          type="button"
          class="foc__filterClear"
          @click="setConcept(null)"
        >
          Clear
        </button>
      </div>

      <div class="foc__scroll">
        <RiverList
          :records="listRecords"
          :selected-slug="selectedRecord?.slug ?? null"
          :compact="!!selectedRecord"
          :grouped="!activeConcept"
          @select="openRecord"
        />
      </div>
    </div>

    <div
      v-if="selectedRecord"
      class="foc__detail"
    >
      <RecordDetailPane
        :record="selectedRecord"
        @close="selected = null"
        @select-concept="setConcept"
        @select-record="openRecord"
      />
    </div>
  </div>
</template>

<script setup lang="ts">
import { getIconForRecordType } from '@app/utils';
import { computed, ref } from 'vue';
import type { RecordType } from '@shared/types';
import { useLabRecords } from '../useLabRecords';
import ConceptRail from './parts/ConceptRail.vue';
import RiverList from './parts/RiverList.vue';
import RecordDetailPane from './parts/RecordDetailPane.vue';

const { titled, topConcepts, recordBySlug, recordsByConcept } = useLabRecords();

const concepts = computed(() => topConcepts.value.slice(0, 40));
const activeConcept = ref<string | null>(null);
const selected = ref<string | null>(null);
const typeFilter = ref<RecordType | null>(null);
const sidebarManuallyOpen = ref(false);

const typeFilters: { label: string; value: RecordType | null; icon?: string }[] = [
  { label: 'All', value: null },
  { label: 'Artifacts', value: 'artifact', icon: getIconForRecordType('artifact') },
  { label: 'Concepts', value: 'concept', icon: getIconForRecordType('concept') },
  { label: 'Entities', value: 'entity', icon: getIconForRecordType('entity') },
];

const selectedRecord = computed(() => (selected.value ? recordBySlug.value.get(selected.value) ?? null : null));
const showSidebar = computed(() => !selectedRecord.value || sidebarManuallyOpen.value);

const gridClass = computed(() => {
  if (!selectedRecord.value) return 'foc--browse';
  return sidebarManuallyOpen.value ? 'foc--triple' : 'foc--read';
});

const activeConceptTitle = computed(
  () => concepts.value.find((c) => c.slug === activeConcept.value)?.title ?? activeConcept.value,
);

const listRecords = computed(() => {
  const base = activeConcept.value
    ? (recordsByConcept.value.get(activeConcept.value) ?? [])
    : titled.value;
  return typeFilter.value ? base.filter((r) => r.type === typeFilter.value) : base;
});

function setConcept(slug: string | null) {
  activeConcept.value = slug;
}
function openRecord(slug: string) {
  selected.value = slug;
}
</script>

<style scoped>
.foc {
  display: grid;
  height: 100%;
  min-height: 0;
}
.foc--browse {
  grid-template-columns: 222px minmax(0, 1fr);
}
.foc--read {
  grid-template-columns: minmax(300px, 0.34fr) minmax(0, 1fr);
}
.foc--triple {
  grid-template-columns: 200px minmax(280px, 0.32fr) minmax(0, 1fr);
}

.foc__listCol {
  display: grid;
  grid-template-rows: auto auto minmax(0, 1fr);
  min-height: 0;
  min-width: 0;
}
.foc--read .foc__listCol,
.foc--triple .foc__listCol {
  background: var(--ui-bg);
  border-right: 1px solid var(--ui-border);
}

.foc__toolbar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
  padding: 10px 14px 8px;
}
.foc__sidebarToggle {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  padding: 3px 9px;
  border-radius: var(--radius-md);
  border: 1px solid var(--ui-border);
  background: transparent;
  font-size: 0.74rem;
  color: var(--ui-text-muted);
  cursor: pointer;
}
.foc__sidebarToggle:hover {
  background: var(--ui-bg-elevated);
  color: var(--ui-text);
}
.foc__sidebarToggle--on {
  background: var(--ui-bg-elevated);
  color: var(--ui-text-highlighted);
  border-color: var(--ui-border-accented);
}
.foc__sidebarToggle :deep(svg) {
  width: 13px;
  height: 13px;
}
.foc__filters {
  display: inline-flex;
  gap: 3px;
  flex-wrap: wrap;
}
.foc__chip {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  padding: 3px 9px;
  border-radius: 999px;
  border: 1px solid transparent;
  background: transparent;
  font-size: 0.74rem;
  color: var(--ui-text-muted);
  cursor: pointer;
}
.foc__chip:hover {
  background: var(--ui-bg-elevated);
}
.foc__chip--active {
  background: var(--ui-bg);
  border-color: var(--ui-border);
  color: var(--ui-text-highlighted);
  font-weight: 500;
}
.foc__chipGlyph {
  width: 12px;
  height: 12px;
}
.foc__count {
  font-size: 0.72rem;
  color: var(--ui-text-dimmed);
  font-variant-numeric: tabular-nums;
}

.foc__filterbar {
  display: flex;
  align-items: center;
  gap: 8px;
  margin: 0 14px;
  padding: 5px 10px;
  border-radius: var(--radius-md);
  background: color-mix(in srgb, var(--ui-primary) 8%, transparent);
  font-size: 0.78rem;
  color: var(--ui-text-toned);
}
.foc__filterGlyph {
  width: 13px;
  height: 13px;
  color: var(--ui-primary);
}
.foc__filterLabel {
  font-weight: 500;
  flex: 1;
}
.foc__filterClear {
  border: 0;
  background: transparent;
  color: var(--ui-text-muted);
  font-size: 0.72rem;
  cursor: pointer;
}
.foc__filterClear:hover {
  color: var(--ui-primary);
}

.foc__scroll {
  overflow-y: auto;
  min-height: 0;
  padding: 0 14px 3rem;
}

.foc__detail {
  overflow-y: auto;
  min-height: 0;
  padding: 0 2rem;
}
</style>
