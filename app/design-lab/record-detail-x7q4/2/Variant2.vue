<template>
  <div class="V22">
    <RecordHero />

    <section
      v-if="rows.length"
      class="V22__links"
    >
      <header class="V22__sectionHead">
        <h2 class="V22__sectionTitle">Linked records</h2>
        <div class="V22__filterBar">
          <button
            v-for="filter in filters"
            :key="filter.key"
            type="button"
            class="V22__filterChip"
            :class="{ 'V22__filterChip--active': activeFilter === filter.key }"
            @click="activeFilter = filter.key"
          >
            {{ filter.label }}
            <span class="V22__filterCount">{{ filter.count }}</span>
          </button>
          <UButton
            size="xs"
            color="neutral"
            variant="ghost"
            icon="i-lucide-plus"
            label="Add link"
            class="V22__filterAdd"
          />
        </div>
      </header>

      <div class="V22__table">
        <template
          v-for="bucket in renderBuckets"
          :key="bucket.predicate"
        >
          <div class="V22__bucketHead">
            <span class="V22__bucketName">
              {{
                bucket.predicate === 'mentioned_in'
                  ? 'Mentioned in'
                  : capitalize(humanizePredicate(bucket.predicate))
              }}
            </span>
            <span class="V22__bucketCount">{{ bucket.rows.length }}</span>
          </div>
          <V2LinkRow
            v-for="row in bucket.rows"
            :key="`${bucket.predicate}-${row.id}`"
            :linkId="row.id"
            :fallbackTitle="row.title"
            :fallbackSlug="row.slug"
          />
        </template>
      </div>
    </section>
  </div>
</template>

<script setup lang="ts">
import RecordHero from './RecordHero.vue';
import V2LinkRow from './V2LinkRow.vue';
import { capitalize } from '@shared/lib/formatting';
import { computed, ref } from 'vue';
import { humanizePredicate, useLabRecord } from '../useLabRecord';

const { links } = useLabRecord();

interface Row {
  id: number;
  slug: string;
  title: string | null;
  predicate: string;
}

const rows = computed<Row[]>(() => {
  const all: Row[] = [];
  for (const link of links.value?.outgoingLinks ?? []) {
    if (link.predicate === 'tagged_with') continue;
    all.push({
      id: link.targetId,
      slug: link.target.slug,
      title: link.target.title,
      predicate: link.predicate,
    });
  }
  for (const link of links.value?.incomingLinks ?? []) {
    if (!link.source) continue;
    all.push({
      id: link.sourceId,
      slug: link.source.slug,
      title: link.source.title,
      predicate: 'mentioned_in',
    });
  }
  return all;
});

const filters = computed(() => {
  const counts = new Map<string, number>();
  for (const r of rows.value) {
    counts.set(r.predicate, (counts.get(r.predicate) ?? 0) + 1);
  }
  const list = [{ key: 'all', label: 'All', count: rows.value.length }];
  for (const [predicate, count] of counts) {
    list.push({
      key: predicate,
      label:
        predicate === 'mentioned_in'
          ? 'Mentioned in'
          : capitalize(humanizePredicate(predicate)),
      count,
    });
  }
  return list;
});

const activeFilter = ref<string>('all');

const filteredRows = computed(() => {
  if (activeFilter.value === 'all') return rows.value;
  return rows.value.filter((r) => r.predicate === activeFilter.value);
});

const renderBuckets = computed(() => {
  const m = new Map<string, Row[]>();
  for (const r of filteredRows.value) {
    if (!m.has(r.predicate)) m.set(r.predicate, []);
    m.get(r.predicate)!.push(r);
  }
  return Array.from(m.entries()).map(([predicate, rows]) => ({ predicate, rows }));
});
</script>

<style scoped>
.V22 {
  display: grid;
  gap: 24px;
  max-width: 820px;
  margin: 0 auto;
}

.V22__links {
  display: grid;
  gap: 12px;
  margin-top: 8px;
  padding-top: 20px;
  border-top: 1px solid var(--ui-border);
}

.V22__sectionHead {
  display: grid;
  gap: 8px;
}

.V22__sectionTitle {
  font-size: 1rem;
  font-weight: 600;
}

.V22__filterBar {
  display: inline-flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 4px;
}

.V22__filterChip {
  display: inline-flex;
  align-items: baseline;
  gap: 4px;
  border: 1px solid transparent;
  background: transparent;
  border-radius: 999px;
  padding: 3px 10px;
  font-size: 0.75rem;
  color: var(--ui-text-muted);
  cursor: pointer;

  &:hover {
    color: var(--ui-text);
    background: var(--ui-bg-elevated);
  }
}

.V22__filterChip--active {
  background: var(--ui-bg);
  border-color: var(--ui-border);
  color: var(--ui-text);
  font-weight: 500;
}

.V22__filterCount {
  font-size: 0.7rem;
  color: var(--ui-text-dimmed);
}

.V22__filterAdd {
  margin-left: auto;
}

.V22__table {
  border: 1px solid var(--ui-border);
  border-radius: var(--radius-lg);
  background: var(--ui-bg);
  overflow: hidden;
}

.V22__bucketHead {
  display: flex;
  align-items: baseline;
  gap: 6px;
  padding: 6px 12px;
  font-size: 0.72rem;
  color: var(--ui-text-dimmed);
  background: var(--ui-bg-elevated);
  border-top: 1px solid var(--ui-border);
}

.V22__bucketHead:first-child {
  border-top: 0;
}

.V22__bucketName {
  color: var(--ui-text);
  font-weight: 500;
}

.V22__bucketCount {
  color: var(--ui-text-dimmed);
}
</style>
