<template>
  <Teleport to="body">
    <div
      class="RambleMentionMenu"
      :style="positionStyle"
    >
      <div
        v-if="results.length === 0"
        class="RambleMentionMenu__empty"
      >
        <template v-if="loading">Searching…</template>
        <template v-else-if="query">No matching {{ subject }}.</template>
        <template v-else>Type to search {{ subject }}…</template>
      </div>
      <ul
        v-else
        class="RambleMentionMenu__list"
      >
        <li
          v-for="(item, idx) in results"
          :key="item.slug"
          class="RambleMentionMenu__item"
          :class="{ 'RambleMentionMenu__item--active': idx === activeIndex }"
          @mousedown.prevent="$emit('select', item)"
          @mouseenter="$emit('hover', idx)"
        >
          <UIcon
            class="RambleMentionMenu__icon"
            :name="getIconForRecordType(item.type)"
          />
          <span class="RambleMentionMenu__label">{{ item.label }}</span>
          <span
            v-if="item.suffix"
            class="RambleMentionMenu__suffix"
          >{{ item.suffix }}</span>
        </li>
      </ul>
    </div>
  </Teleport>
</template>

<script setup lang="ts">
import { getIconForRecordType } from '@app/utils';
import type { DbId } from '@shared/types/api';
import type { RambleTrigger, RecordType } from '@shared/types/ramble';
import { computed, type CSSProperties } from 'vue';

export type MentionMenuItem = {
  id: DbId;
  slug: string;
  type: RecordType;
  label: string;
  suffix?: string;
};

const props = defineProps<{
  results: MentionMenuItem[];
  activeIndex: number;
  loading: boolean;
  query: string;
  trigger: RambleTrigger;
  rect: { top: number; left: number };
}>();

defineEmits<{
  select: [MentionMenuItem];
  hover: [number];
}>();

const subject = computed(() => (props.trigger === '#' ? 'concepts' : 'records'));

const positionStyle = computed<CSSProperties>(() => ({
  top: `${props.rect.top}px`,
  left: `${props.rect.left}px`,
}));
</script>

<style scoped>
.RambleMentionMenu {
  position: fixed;
  /* Above Nuxt UI drawer/modal overlays (which sit around z-index 50–100)
   * since the teleport lifts us to the body. */
  z-index: 200;
  width: 360px;
  max-height: 320px;
  overflow-y: auto;
  background-color: var(--ui-bg);
  border: 0.5px solid var(--ui-border);
  border-radius: var(--radius-md, 8px);
  box-shadow:
    0 12px 32px -8px rgba(0, 0, 0, 0.25),
    0 4px 8px -4px rgba(0, 0, 0, 0.15);
  font-family: var(--font-sans, sans-serif);
  font-size: 0.875rem;
}

.RambleMentionMenu__empty {
  padding: 12px 14px;
  color: var(--ui-text-dimmed);
  font-size: 0.8125rem;
}

.RambleMentionMenu__list {
  list-style: none;
  padding: 4px;
  margin: 0;
}

.RambleMentionMenu__item {
  display: flex;
  align-items: baseline;
  gap: 8px;
  padding: 8px 10px;
  border-radius: 6px;
  cursor: pointer;
  color: var(--ui-text);
}

.RambleMentionMenu__item--active {
  background-color: var(--ui-bg-elevated);
  color: var(--ui-text-highlighted);
}

.RambleMentionMenu__icon {
  flex: none;
  width: 12px;
  height: 12px;
  color: var(--ui-text-dimmed);
  position: relative;
  top: 1px;
}

.RambleMentionMenu__label {
  flex: 0 1 auto;
  min-width: 0;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  max-width: 200px;
}

.RambleMentionMenu__suffix {
  flex: 1 1 auto;
  min-width: 0;
  color: var(--ui-text-dimmed);
  font-size: 0.75rem;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
</style>
