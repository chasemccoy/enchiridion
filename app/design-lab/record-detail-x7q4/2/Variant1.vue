<template>
  <div class="V21">
    <RecordHero />

    <section
      v-if="groups.length || incoming.length"
      class="V21__links"
    >
      <header class="V21__sectionHead">
        <h2 class="V21__sectionTitle">Linked records</h2>
        <UButton
          size="xs"
          color="neutral"
          variant="ghost"
          icon="i-lucide-plus"
          label="New link"
        />
      </header>

      <div
        v-for="group in groups"
        :key="group.predicate"
        class="V21__group"
      >
        <div class="V21__groupHead">
          <span class="V21__groupName">
            {{ capitalize(humanizePredicate(group.predicate)) }}
          </span>
          <span class="V21__groupCount">{{ group.items.length }}</span>
        </div>
        <ul class="V21__grid">
          <li
            v-for="item in group.items"
            :key="item.id"
          >
            <V1LinkCard
              :linkId="item.id"
              :fallbackTitle="item.title"
              :fallbackSlug="item.slug"
            />
          </li>
        </ul>
      </div>

      <div
        v-if="incoming.length"
        class="V21__group"
      >
        <div class="V21__groupHead">
          <span class="V21__groupName">Mentioned in</span>
          <span class="V21__groupCount">{{ incoming.length }}</span>
        </div>
        <ul class="V21__grid">
          <li
            v-for="child in incoming"
            :key="child.id"
          >
            <V1LinkCard
              :linkId="child.id"
              :fallbackTitle="child.title"
              :fallbackSlug="child.slug"
            />
          </li>
        </ul>
      </div>
    </section>
  </div>
</template>

<script setup lang="ts">
import RecordHero from './RecordHero.vue';
import V1LinkCard from './V1LinkCard.vue';
import { capitalize } from '@shared/lib/formatting';
import { computed } from 'vue';
import { humanizePredicate, useLabRecord } from '../useLabRecord';

const { links } = useLabRecord();

const skipPredicates = new Set(['tagged_with']);

const groups = computed(() => {
  const outgoing = links.value?.outgoingLinks ?? [];
  const filtered = outgoing.filter((l) => !skipPredicates.has(l.predicate));
  const m = new Map<string, Array<{ id: number; slug: string; title: string | null }>>();
  for (const link of filtered) {
    if (!m.has(link.predicate)) m.set(link.predicate, []);
    m.get(link.predicate)!.push({
      id: link.targetId,
      slug: link.target.slug,
      title: link.target.title,
    });
  }
  return Array.from(m.entries()).map(([predicate, items]) => ({ predicate, items }));
});

const incoming = computed(() =>
  (links.value?.incomingLinks ?? [])
    .filter((l) => l.source)
    .map((l) => ({
      id: l.sourceId,
      slug: l.source.slug,
      title: l.source.title,
    })),
);
</script>

<style scoped>
.V21 {
  display: grid;
  gap: 24px;
  max-width: 760px;
  margin: 0 auto;
}

.V21__links {
  display: grid;
  gap: 16px;
  margin-top: 8px;
  padding-top: 20px;
  border-top: 1px solid var(--ui-border);
}

.V21__sectionHead {
  display: flex;
  justify-content: space-between;
  align-items: baseline;
}

.V21__sectionTitle {
  font-size: 1rem;
  font-weight: 600;
  color: var(--ui-text);
}

.V21__group {
  display: grid;
  gap: 8px;
}

.V21__groupHead {
  display: inline-flex;
  align-items: baseline;
  gap: 6px;
}

.V21__groupName {
  font-size: 0.8rem;
  font-weight: 500;
  color: var(--ui-text);
}

.V21__groupCount {
  font-size: 0.72rem;
  color: var(--ui-text-dimmed);
}

.V21__grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(260px, 1fr));
  gap: 6px;
  list-style: none;
  margin: 0;
  padding: 0;
}
</style>
