<template>
  <div class="dr">
    <header class="dr__bar">
      <div class="dr__barLeft">
        <h1 class="dr__heading">Stream</h1>
        <span class="dr__total">{{ visibleCount }} of {{ titled.length }}</span>
      </div>
      <div class="dr__filters">
        <button
          v-for="f in filters"
          :key="f.value ?? 'all'"
          type="button"
          class="dr__chip"
          :class="{ 'dr__chip--active': activeType === f.value }"
          @click="activeType = f.value"
        >
          <UIcon
            v-if="f.icon"
            class="dr__chipGlyph"
            :name="f.icon"
          />
          {{ f.label }}
        </button>
      </div>
    </header>

    <div class="dr__scroll">
      <section
        v-for="group in groups"
        :key="group.label"
        class="dr__group"
      >
        <div class="dr__monthHead">
          <span class="dr__month">{{ group.label }}</span>
          <span class="dr__monthCount">{{ group.records.length }}</span>
          <span class="dr__monthRule" />
        </div>

        <RouterLink
          v-for="r in group.records"
          :key="r.id"
          class="dr__row"
          :to="`/${r.slug}`"
        >
          <UIcon
            class="dr__rowGlyph"
            :name="icon(r.type)"
            :class="`dr__rowGlyph--${r.type}`"
          />
          <span class="dr__rowMain">
            <span class="dr__rowTitle">{{ r.title }}</span>
            <span
              v-if="preview(r)"
              class="dr__rowPreview"
            >
              {{ preview(r) }}
            </span>
          </span>
          <span
            v-if="tagsOf(r).length"
            class="dr__rowTags"
          >
            <span
              v-for="t in tagsOf(r).slice(0, 2)"
              :key="t!.slug"
              class="dr__tag"
              >{{ t!.title }}</span
            >
          </span>
          <span
            v-if="host(r)"
            class="dr__rowHost"
            >{{ host(r) }}</span
          >
          <span class="dr__rowDate">{{ date(r) }}</span>
          <img
            v-if="thumb(r)"
            class="dr__rowThumb"
            loading="lazy"
            :src="thumb(r)!"
            :alt="''"
          />
          <span
            v-else
            class="dr__rowThumb dr__rowThumb--empty"
          />
        </RouterLink>
      </section>
    </div>
  </div>
</template>

<script setup lang="ts">
import { getIconForRecordType } from '@app/utils';
import { formatDate } from '@shared/lib/formatting';
import { computed, ref } from 'vue';
import {
  firstImage,
  hostOf,
  plain,
  tagsOf,
  useLabRecords,
  type LabRecord,
} from '../useLabRecords';
import type { RecordType } from '@shared/types';

const { titled, byMonth, backendBaseUrl } = useLabRecords();

const activeType = ref<RecordType | null>(null);
const filters: { label: string; value: RecordType | null; icon?: string }[] = [
  { label: 'All', value: null },
  { label: 'Artifacts', value: 'artifact', icon: getIconForRecordType('artifact') },
  { label: 'Concepts', value: 'concept', icon: getIconForRecordType('concept') },
  { label: 'Entities', value: 'entity', icon: getIconForRecordType('entity') },
];

const groups = computed(() =>
  byMonth.value
    .map((g) => ({
      label: g.label,
      records: activeType.value ? g.records.filter((r) => r.type === activeType.value) : g.records,
    }))
    .filter((g) => g.records.length > 0),
);
const visibleCount = computed(() => groups.value.reduce((n, g) => n + g.records.length, 0));

function icon(type: LabRecord['type']) {
  return getIconForRecordType(type);
}
function host(r: LabRecord) {
  return hostOf(r);
}
function date(r: LabRecord) {
  return r.recordCreatedAt ? formatDate(r.recordCreatedAt, { year: false }) : '';
}
function preview(r: LabRecord) {
  return plain(r.summary || r.content);
}
function thumb(r: LabRecord) {
  const path = firstImage(r);
  return path ? `${backendBaseUrl}${path}` : null;
}
</script>

<style scoped>
.dr {
  display: grid;
  grid-template-rows: auto 1fr;
  height: 100%;
  min-height: 0;
  max-width: 1100px;
  margin: 0 auto;
  width: 100%;
}

.dr__bar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  padding: 1.25rem 1.5rem 0.85rem;
}
.dr__barLeft {
  display: inline-flex;
  align-items: baseline;
  gap: 10px;
}
.dr__heading {
  font-family: var(--font-serif);
  font-size: 1.5rem;
  font-weight: 600;
  letter-spacing: -0.01em;
  color: var(--ui-text-highlighted);
}
.dr__total {
  font-size: 0.72rem;
  color: var(--ui-text-dimmed);
  font-variant-numeric: tabular-nums;
}
.dr__filters {
  display: inline-flex;
  gap: 4px;
}
.dr__chip {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  padding: 4px 11px;
  border-radius: 999px;
  border: 1px solid transparent;
  background: transparent;
  font-size: 0.76rem;
  color: var(--ui-text-muted);
  cursor: pointer;
  transition:
    background 0.12s ease,
    color 0.12s ease;
}
.dr__chip:hover {
  background: var(--ui-bg-elevated);
}
.dr__chip--active {
  background: var(--ui-bg);
  border-color: var(--ui-border);
  color: var(--ui-text-highlighted);
  font-weight: 500;
}
.dr__chipGlyph {
  width: 13px;
  height: 13px;
}

.dr__scroll {
  min-height: 0;
  overflow: visible;
  padding: 0 1.5rem 4rem;
}

.dr__monthHead {
  position: sticky;
  top: 0;
  z-index: 2;
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 14px 0 8px;
  background: linear-gradient(var(--page-bg) 70%, transparent);
}
.dr__month {
  font-size: 0.66rem;
  text-transform: uppercase;
  letter-spacing: 0.14em;
  font-weight: 600;
  color: var(--ui-text-muted);
}
.dr__monthCount {
  font-size: 0.62rem;
  color: var(--ui-text-dimmed);
  font-variant-numeric: tabular-nums;
}
.dr__monthRule {
  flex: 1;
  height: 1px;
  background: var(--ui-border);
}

.dr__row {
  display: grid;
  grid-template-columns: 18px minmax(0, 1fr) auto auto 3.2rem 28px;
  align-items: center;
  gap: 12px;
  padding: 7px 10px;
  margin: 0 -10px;
  border-radius: var(--radius-md);
  content-visibility: auto;
  contain-intrinsic-size: 0 38px;
  transition: background 0.1s ease;
}
.dr__row:hover {
  background: var(--ui-bg);
}
.dr__rowGlyph {
  width: 14px;
  height: 14px;
  color: var(--ui-text-dimmed);
}
.dr__rowGlyph--concept {
  color: var(--ui-primary);
}
.dr__rowMain {
  /* Title gets priority up to a generous cap, then the preview takes the rest
     and truncates first — a flex row let the title shrink to nothing. */
  display: grid;
  grid-template-columns: minmax(0, auto) minmax(0, 1fr);
  align-items: baseline;
  gap: 10px;
  min-width: 0;
}
.dr__rowTitle {
  font-size: 0.85rem;
  font-weight: 500;
  color: var(--ui-text-highlighted);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  max-width: 42ch;
}
.dr__row:hover .dr__rowTitle {
  color: var(--ui-primary);
}
.dr__rowPreview {
  font-size: 0.78rem;
  color: var(--ui-text-dimmed);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  min-width: 0;
}
.dr__rowTags {
  display: inline-flex;
  gap: 4px;
}
.dr__tag {
  font-size: 0.64rem;
  color: var(--ui-text-muted);
  background: var(--ui-bg-elevated);
  border: 1px solid var(--ui-border-muted);
  padding: 1px 7px;
  border-radius: 999px;
  white-space: nowrap;
  max-width: 110px;
  overflow: hidden;
  text-overflow: ellipsis;
}
.dr__rowHost {
  font-size: 0.7rem;
  color: var(--ui-text-dimmed);
  white-space: nowrap;
  max-width: 130px;
  overflow: hidden;
  text-overflow: ellipsis;
  text-align: right;
}
.dr__rowDate {
  font-size: 0.7rem;
  color: var(--ui-text-dimmed);
  text-align: right;
  font-variant-numeric: tabular-nums;
  white-space: nowrap;
}
.dr__rowThumb {
  width: 28px;
  height: 28px;
  object-fit: cover;
  border-radius: var(--radius-sm, 5px);
  border: 1px solid var(--ui-border);
}
.dr__rowThumb--empty {
  border: 0;
  background: transparent;
}

@media (max-width: 760px) {
  .dr__row {
    grid-template-columns: 18px minmax(0, 1fr) auto 28px;
  }
  .dr__rowTags,
  .dr__rowHost {
    display: none;
  }
}
</style>
