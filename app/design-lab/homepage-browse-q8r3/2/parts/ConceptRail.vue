<template>
  <aside class="crail">
    <div class="crail__head">
      <span class="crail__title">Concepts</span>
      <span class="crail__hint">by popularity</span>
    </div>

    <button
      type="button"
      class="crail__all"
      :class="{ 'crail__all--active': !activeSlug }"
      @click="$emit('select', null)"
    >
      <UIcon
        name="i-lucide-layers"
        class="crail__allGlyph"
      />
      <span>All records</span>
      <span class="crail__allCount">{{ totalCount }}</span>
    </button>

    <ul class="crail__list">
      <li
        v-for="c in concepts"
        :key="c.slug"
      >
        <button
          type="button"
          class="crail__item"
          :class="{ 'crail__item--active': c.slug === activeSlug }"
          @click="$emit('select', c.slug)"
        >
          <span class="crail__name">{{ c.title }}</span>
          <span class="crail__barWrap">
            <span
              class="crail__bar"
              :style="{ width: `${(c.count / maxCount) * 100}%` }"
            />
          </span>
          <span class="crail__count">{{ c.count }}</span>
        </button>
      </li>
    </ul>
  </aside>
</template>

<script setup lang="ts">
import { computed } from 'vue';

type Concept = { slug: string; title: string; count: number; type: string };

defineEmits<{ select: [slug: string | null] }>();

const props = defineProps<{
  concepts: Concept[];
  activeSlug: string | null;
  totalCount: number;
}>();

const maxCount = computed(() => props.concepts[0]?.count ?? 1);
</script>

<style scoped>
.crail {
  display: grid;
  grid-template-rows: auto auto minmax(0, 1fr);
  gap: 6px;
  height: 100%;
  min-height: 0;
  padding: 1.1rem 0.9rem 1rem 1.25rem;
  border-right: 1px solid var(--ui-border);
  background: var(--ui-bg-elevated);
}
.crail__head {
  display: flex;
  align-items: baseline;
  gap: 8px;
  padding: 0 4px 2px;
}
.crail__title {
  font-size: 0.82rem;
  font-weight: 600;
  color: var(--ui-text-highlighted);
}
.crail__hint {
  font-size: 0.62rem;
  text-transform: uppercase;
  letter-spacing: 0.1em;
  color: var(--ui-text-dimmed);
}

.crail__all {
  display: flex;
  align-items: center;
  gap: 8px;
  width: 100%;
  padding: 6px 8px;
  border: 0;
  border-radius: var(--radius-md);
  background: transparent;
  cursor: pointer;
  font-size: 0.8rem;
  color: var(--ui-text-toned);
  text-align: left;
}
.crail__all:hover {
  background: var(--ui-bg);
}
.crail__all--active {
  background: var(--ui-bg);
  color: var(--ui-text-highlighted);
  font-weight: 500;
  box-shadow: inset 0 0 0 1px var(--ui-border);
}
.crail__allGlyph {
  width: 14px;
  height: 14px;
  color: var(--ui-text-muted);
}
.crail__allCount {
  margin-left: auto;
  font-size: 0.68rem;
  color: var(--ui-text-dimmed);
  font-variant-numeric: tabular-nums;
}

.crail__list {
  overflow-y: auto;
  min-height: 0;
  display: grid;
  gap: 1px;
  scrollbar-width: thin;
  padding-right: 2px;
}
.crail__item {
  display: grid;
  grid-template-columns: 1fr 42px auto;
  align-items: center;
  gap: 8px;
  width: 100%;
  padding: 5px 8px;
  border: 0;
  border-radius: var(--radius-md);
  background: transparent;
  cursor: pointer;
  text-align: left;
}
.crail__item:hover {
  background: var(--ui-bg);
}
.crail__item:hover .crail__name {
  color: var(--ui-text-highlighted);
}
.crail__item--active {
  background: var(--ui-bg);
  box-shadow: inset 0 0 0 1px var(--ui-border);
}
.crail__item--active .crail__name {
  color: var(--ui-primary);
  font-weight: 500;
}
.crail__item--active .crail__bar {
  background: var(--ui-primary);
  opacity: 1;
}
.crail__name {
  font-size: 0.8rem;
  color: var(--ui-text-toned);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.crail__barWrap {
  height: 4px;
  background: var(--ui-bg-accented);
  border-radius: 999px;
  overflow: hidden;
}
.crail__bar {
  display: block;
  height: 100%;
  background: var(--ui-primary);
  opacity: 0.65;
  border-radius: 999px;
}
.crail__count {
  font-size: 0.66rem;
  color: var(--ui-text-dimmed);
  font-variant-numeric: tabular-nums;
  text-align: right;
}
</style>
