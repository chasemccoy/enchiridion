<template>
  <div
    class="dst"
    :class="gridClass"
  >
    <ConceptRail
      :concepts="concepts"
      :active-slug="openConcept"
      :total-count="titled.length"
      @select="onConcept"
    />

    <!-- Middle list rail: only when a record is open (gives context to move
         between sibling records). In browse/concept modes the river or concept
         page occupies the wide pane directly. -->
    <div
      v-if="openRecord && contextRecords.length"
      class="dst__listCol"
    >
      <div class="dst__listHead">
        <span class="dst__listLabel">{{ contextLabel }}</span>
        <span class="dst__listCount">{{ contextRecords.length }}</span>
      </div>
      <div class="dst__scroll">
        <RiverList
          :records="contextRecords"
          :selected-slug="openRecord"
          :grouped="!openConcept"
          compact
          @select="(slug) => (openRecord = slug)"
        />
      </div>
    </div>

    <!-- Wide pane -->
    <div class="dst__main">
      <!-- Browse: the dense river -->
      <template v-if="!openConcept && !openRecord">
        <div class="dst__toolbar">
          <div class="dst__filters">
            <button
              v-for="f in typeFilters"
              :key="f.value ?? 'all'"
              type="button"
              class="dst__chip"
              :class="{ 'dst__chip--active': typeFilter === f.value }"
              @click="typeFilter = f.value"
            >
              <UIcon
                v-if="f.icon"
                class="dst__chipGlyph"
                :name="f.icon"
              />
              {{ f.label }}
            </button>
          </div>
          <span class="dst__count">{{ browseRecords.length }}</span>
        </div>
        <div class="dst__scroll dst__scroll--wide">
          <RiverList
            :records="browseRecords"
            :selected-slug="null"
            grouped
            @select="(slug) => (openRecord = slug)"
          />
        </div>
      </template>

      <!-- Record open -->
      <div
        v-else-if="openRecord"
        class="dst__scroll dst__scroll--wide"
      >
        <RecordDetailPane
          :record="recordBySlug.get(openRecord) ?? null"
          @close="openRecord = null"
          @select-concept="onConcept"
          @select-record="(slug) => (openRecord = slug)"
        />
      </div>

      <!-- Concept open (no record) -->
      <div
        v-else-if="openConcept"
        class="dst__scroll dst__scroll--wide"
      >
        <ConceptDetailPane
          :concept-slug="openConcept"
          :concept-title="openConceptTitle"
          :concept-record="recordBySlug.get(openConcept) ?? null"
          :records="conceptRecords"
          @close="openConcept = null"
          @select-record="(slug) => (openRecord = slug)"
        />
      </div>
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
import ConceptDetailPane from './parts/ConceptDetailPane.vue';

const { titled, topConcepts, recordBySlug, recordsByConcept } = useLabRecords();

const concepts = computed(() => topConcepts.value.slice(0, 40));
const openConcept = ref<string | null>(null);
const openRecord = ref<string | null>(null);
const typeFilter = ref<RecordType | null>(null);

const typeFilters: { label: string; value: RecordType | null; icon?: string }[] = [
  { label: 'All', value: null },
  { label: 'Artifacts', value: 'artifact', icon: getIconForRecordType('artifact') },
  { label: 'Concepts', value: 'concept', icon: getIconForRecordType('concept') },
  { label: 'Entities', value: 'entity', icon: getIconForRecordType('entity') },
];

const openConceptTitle = computed(
  () => concepts.value.find((c) => c.slug === openConcept.value)?.title ?? openConcept.value ?? '',
);

const browseRecords = computed(() =>
  typeFilter.value ? titled.value.filter((r) => r.type === typeFilter.value) : titled.value,
);
const conceptRecords = computed(() =>
  openConcept.value ? (recordsByConcept.value.get(openConcept.value) ?? []) : [],
);
const contextRecords = computed(() =>
  openConcept.value ? conceptRecords.value : titled.value,
);
const contextLabel = computed(() => (openConcept.value ? openConceptTitle.value : 'All records'));

const gridClass = computed(() => {
  if (openRecord.value && contextRecords.value.length) return 'dst--record';
  return 'dst--wide';
});

function onConcept(slug: string | null) {
  openRecord.value = null;
  openConcept.value = slug;
}
</script>

<style scoped>
.dst {
  display: grid;
  height: 100%;
  min-height: 0;
}
.dst--wide {
  grid-template-columns: 222px minmax(0, 1fr);
}
.dst--record {
  grid-template-columns: 222px minmax(300px, 360px) minmax(0, 1fr);
}

.dst__listCol {
  display: grid;
  grid-template-rows: auto minmax(0, 1fr);
  min-height: 0;
  min-width: 0;
  background: var(--ui-bg);
  border-right: 1px solid var(--ui-border);
}
.dst__listHead {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
  padding: 11px 14px 8px;
}
.dst__listLabel {
  font-size: 0.7rem;
  text-transform: uppercase;
  letter-spacing: 0.08em;
  font-weight: 600;
  color: var(--ui-text-muted);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.dst__listCount {
  font-size: 0.68rem;
  color: var(--ui-text-dimmed);
  font-variant-numeric: tabular-nums;
}

.dst__main {
  display: grid;
  grid-template-rows: minmax(0, 1fr);
  min-height: 0;
  min-width: 0;
}
.dst__toolbar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
  padding: 10px 16px 8px;
}
.dst__filters {
  display: inline-flex;
  gap: 3px;
  flex-wrap: wrap;
}
.dst__chip {
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
.dst__chip:hover {
  background: var(--ui-bg-elevated);
}
.dst__chip--active {
  background: var(--ui-bg);
  border-color: var(--ui-border);
  color: var(--ui-text-highlighted);
  font-weight: 500;
}
.dst__chipGlyph {
  width: 12px;
  height: 12px;
}
.dst__count {
  font-size: 0.72rem;
  color: var(--ui-text-dimmed);
  font-variant-numeric: tabular-nums;
}

.dst__main:has(.dst__toolbar) {
  grid-template-rows: auto minmax(0, 1fr);
}

.dst__scroll {
  overflow-y: auto;
  min-height: 0;
  padding: 0 14px 3rem;
}
.dst__scroll--wide {
  padding: 0 1.5rem 3rem;
}
</style>
