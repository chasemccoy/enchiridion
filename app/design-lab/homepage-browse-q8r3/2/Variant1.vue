<template>
  <div
    class="tri"
    :class="{ 'tri--split': !!selectedRecord }"
  >
    <ConceptRail
      :concepts="concepts"
      :active-slug="activeConcept"
      :total-count="titled.length"
      @select="setConcept"
    />

    <div class="tri__listCol">
      <div class="tri__toolbar">
        <div class="tri__filters">
          <button
            v-for="f in typeFilters"
            :key="f.value ?? 'all'"
            type="button"
            class="tri__chip"
            :class="{ 'tri__chip--active': typeFilter === f.value }"
            @click="typeFilter = f.value"
          >
            <UIcon
              v-if="f.icon"
              class="tri__chipGlyph"
              :name="f.icon"
            />
            {{ f.label }}
          </button>
        </div>
        <span class="tri__count">{{ listRecords.length }}</span>
      </div>

      <div
        v-if="activeConcept"
        class="tri__filterbar"
      >
        <UIcon
          name="i-lucide-filter"
          class="tri__filterGlyph"
        />
        <span class="tri__filterLabel">{{ activeConceptTitle }}</span>
        <button
          type="button"
          class="tri__filterClear"
          @click="setConcept(null)"
        >
          Clear
        </button>
      </div>

      <div class="tri__scroll">
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
      class="tri__detail"
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

const typeFilters: { label: string; value: RecordType | null; icon?: string }[] = [
  { label: 'All', value: null },
  { label: 'Artifacts', value: 'artifact', icon: getIconForRecordType('artifact') },
  { label: 'Concepts', value: 'concept', icon: getIconForRecordType('concept') },
  { label: 'Entities', value: 'entity', icon: getIconForRecordType('entity') },
];

const activeConceptTitle = computed(
  () => concepts.value.find((c) => c.slug === activeConcept.value)?.title ?? activeConcept.value,
);

const listRecords = computed(() => {
  const base = activeConcept.value
    ? (recordsByConcept.value.get(activeConcept.value) ?? [])
    : titled.value;
  return typeFilter.value ? base.filter((r) => r.type === typeFilter.value) : base;
});

const selectedRecord = computed(() => (selected.value ? recordBySlug.value.get(selected.value) ?? null : null));

function setConcept(slug: string | null) {
  activeConcept.value = slug;
}
function openRecord(slug: string) {
  selected.value = slug;
}
</script>

<style scoped>
.tri {
  display: grid;
  grid-template-columns: 222px minmax(0, 1fr);
  height: 100%;
  min-height: 0;
}
.tri--split {
  grid-template-columns: 222px minmax(300px, 360px) minmax(0, 1fr);
}

.tri__listCol {
  display: grid;
  grid-template-rows: auto auto minmax(0, 1fr);
  min-height: 0;
  min-width: 0;
  border-right: 1px solid transparent;
}
.tri--split .tri__listCol {
  background: var(--ui-bg);
  border-right: 1px solid var(--ui-border);
}

.tri__toolbar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
  padding: 10px 14px 8px;
}
.tri__filters {
  display: inline-flex;
  gap: 3px;
  flex-wrap: wrap;
}
.tri__chip {
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
.tri__chip:hover {
  background: var(--ui-bg-elevated);
}
.tri__chip--active {
  background: var(--ui-bg);
  border-color: var(--ui-border);
  color: var(--ui-text-highlighted);
  font-weight: 500;
}
.tri--split .tri__chip--active {
  background: var(--ui-bg-elevated);
}
.tri__chipGlyph {
  width: 12px;
  height: 12px;
}
.tri__count {
  font-size: 0.72rem;
  color: var(--ui-text-dimmed);
  font-variant-numeric: tabular-nums;
}

.tri__filterbar {
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
.tri__filterGlyph {
  width: 13px;
  height: 13px;
  color: var(--ui-primary);
}
.tri__filterLabel {
  font-weight: 500;
  flex: 1;
}
.tri__filterClear {
  border: 0;
  background: transparent;
  color: var(--ui-text-muted);
  font-size: 0.72rem;
  cursor: pointer;
}
.tri__filterClear:hover {
  color: var(--ui-primary);
}

.tri__scroll {
  overflow-y: auto;
  min-height: 0;
  padding: 0 14px 3rem;
}

.tri__detail {
  overflow-y: auto;
  min-height: 0;
  padding: 0 1.5rem;
}
</style>
