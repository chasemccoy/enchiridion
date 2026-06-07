<template>
  <section
    v-if="groups.length"
    class="Grouped"
  >
    <header class="Grouped__head">
      <h2 class="Grouped__title">Linked records</h2>
      <UButton
        size="xs"
        color="neutral"
        variant="ghost"
        icon="i-lucide-plus"
        label="New link"
      />
    </header>

    <div class="Grouped__groups">
      <div
        v-for="group in groups"
        :key="group.key"
        class="Grouped__group"
      >
        <div class="Grouped__label">
          <span class="Grouped__labelText">{{ group.label }}</span>
          <span
            v-if="group.items.length > 1"
            class="Grouped__count"
          >
            {{ group.items.length }}
          </span>
        </div>
        <ul class="Grouped__rows">
          <li
            v-for="item in group.items"
            :key="item.id"
          >
            <LinkRowItem
              :linkId="item.id"
              :kind="item.kind"
              :fallbackTitle="item.title"
              :fallbackSlug="item.slug"
            />
          </li>
        </ul>
      </div>
    </div>
  </section>
</template>

<script setup lang="ts">
import LinkRowItem from './LinkRowItem.vue';
import { capitalize } from '@shared/lib/formatting';
import { computed } from 'vue';
import { humanizePredicate, useLabRecord } from '../useLabRecord';

const { links } = useLabRecord();

interface Item {
  kind: 'out' | 'in';
  id: number;
  slug: string;
  title: string | null;
}

// One group per predicate. tagged_with dropped (tags live in the hero); all
// incoming links collapse into a single "Mentioned in" group.
const groups = computed(() => {
  const order: string[] = [];
  const map = new Map<string, Item[]>();

  const push = (key: string, item: Item) => {
    if (!map.has(key)) {
      map.set(key, []);
      order.push(key);
    }
    map.get(key)!.push(item);
  };

  for (const link of links.value?.outgoingLinks ?? []) {
    if (link.predicate === 'tagged_with') continue;
    push(link.predicate, {
      kind: 'out',
      id: link.targetId,
      slug: link.target.slug,
      title: link.target.title,
    });
  }
  for (const link of links.value?.incomingLinks ?? []) {
    if (!link.source) continue;
    push('mentioned_in', {
      kind: 'in',
      id: link.sourceId,
      slug: link.source.slug,
      title: link.source.title,
    });
  }

  return order.map((key) => ({
    key,
    label:
      key === 'mentioned_in' ? 'Mentioned in' : capitalize(humanizePredicate(key)),
    items: map.get(key)!,
  }));
});
</script>

<style scoped>
.Grouped {
  display: grid;
  gap: 14px;
  margin-top: 8px;
  padding-top: 20px;
  border-top: 1px solid var(--ui-border);
}

.Grouped__head {
  display: flex;
  justify-content: space-between;
  align-items: baseline;
}

.Grouped__title {
  font-size: 1rem;
  font-weight: 600;
}

.Grouped__groups {
  display: grid;
  gap: 4px;
}

.Grouped__group {
  display: grid;
  grid-template-columns: 116px 1fr;
  gap: 12px;
  align-items: start;
  padding: 10px 0;
  border-top: 1px solid var(--ui-border);
}

.Grouped__group:first-child {
  border-top: 0;
}

.Grouped__label {
  display: inline-flex;
  align-items: baseline;
  gap: 6px;
  padding-top: 10px;
  position: sticky;
  top: 8px;
}

.Grouped__labelText {
  font-size: 0.78rem;
  font-weight: 500;
  color: var(--ui-text-muted);
}

.Grouped__count {
  font-size: 0.7rem;
  color: var(--ui-text-dimmed);
}

.Grouped__rows {
  display: grid;
  gap: 2px;
  list-style: none;
  margin: 0;
  padding: 0;
  min-width: 0;
}
</style>
