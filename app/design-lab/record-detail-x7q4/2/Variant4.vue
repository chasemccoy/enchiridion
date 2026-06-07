<template>
  <div class="V24">
    <RecordHero />

    <section
      v-if="entries.length"
      class="V24__links"
    >
      <header class="V24__sectionHead">
        <h2 class="V24__sectionTitle">Linked records</h2>
        <UButton
          size="xs"
          color="neutral"
          variant="ghost"
          icon="i-lucide-plus"
          label="New link"
        />
      </header>

      <ul class="V24__list">
        <li
          v-for="(entry, idx) in entries"
          :key="`${entry.kind}-${entry.id}-${idx}`"
          :class="{
            'V24__sep': idx > 0 && entries[idx - 1]?.predicate !== entry.predicate,
          }"
        >
          <V4LinkRow
            :linkId="entry.id"
            :kickerLabel="
              entry.predicate === 'mentioned_in'
                ? 'Mentioned in'
                : capitalize(humanizePredicate(entry.predicate))
            "
            :kind="entry.kind"
            :fallbackTitle="entry.title"
            :fallbackSlug="entry.slug"
          />
        </li>
      </ul>
    </section>
  </div>
</template>

<script setup lang="ts">
import RecordHero from './RecordHero.vue';
import V4LinkRow from './V4LinkRow.vue';
import { capitalize } from '@shared/lib/formatting';
import { computed } from 'vue';
import { humanizePredicate, useLabRecord } from '../useLabRecord';

const { links } = useLabRecord();

interface Entry {
  kind: 'out' | 'in';
  id: number;
  slug: string;
  title: string | null;
  predicate: string;
}

const entries = computed<Entry[]>(() => {
  const out: Entry[] = [];
  for (const link of links.value?.outgoingLinks ?? []) {
    if (link.predicate === 'tagged_with') continue;
    out.push({
      kind: 'out',
      id: link.targetId,
      slug: link.target.slug,
      title: link.target.title,
      predicate: link.predicate,
    });
  }
  for (const link of links.value?.incomingLinks ?? []) {
    if (!link.source) continue;
    out.push({
      kind: 'in',
      id: link.sourceId,
      slug: link.source.slug,
      title: link.source.title,
      predicate: 'mentioned_in',
    });
  }
  // Cluster by predicate so the section header rules in the list stay quiet
  // (one rule per predicate change rather than churning).
  out.sort((a, b) => a.predicate.localeCompare(b.predicate));
  return out;
});
</script>

<style scoped>
.V24 {
  display: grid;
  gap: 24px;
  max-width: 820px;
  margin: 0 auto;
}

.V24__links {
  display: grid;
  gap: 10px;
  margin-top: 8px;
  padding-top: 20px;
  border-top: 1px solid var(--ui-border);
}

.V24__sectionHead {
  display: flex;
  justify-content: space-between;
  align-items: baseline;
}

.V24__sectionTitle {
  font-size: 1rem;
  font-weight: 600;
}

.V24__list {
  display: grid;
  list-style: none;
  margin: 0;
  padding: 0;
}

.V24__sep {
  border-top: 1px dashed var(--ui-border);
  margin-top: 4px;
  padding-top: 4px;
}
</style>
