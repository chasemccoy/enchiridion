<template>
  <div class="cd">
    <header class="cd__head">
      <button
        type="button"
        class="cd__close"
        @click="$emit('close')"
      >
        <UIcon name="i-lucide-x" />
      </button>
      <span class="cd__kind">
        <UIcon
          name="i-lucide-brain"
          class="cd__kindGlyph"
        />
        Concept
      </span>
    </header>

    <h1 class="cd__title">{{ title }}</h1>
    <p class="cd__count">
      {{ records.length }} {{ records.length === 1 ? 'record' : 'records' }} tagged with this concept
    </p>

    <MarkdownRender
      v-if="description"
      class="cd__desc"
      :source="description"
    />

    <div class="cd__listHead">
      <span>Tagged records</span>
      <span class="cd__rule" />
    </div>

    <RiverList
      :records="records"
      :selected-slug="null"
      grouped
      @select="(slug) => $emit('selectRecord', slug)"
    />
  </div>
</template>

<script setup lang="ts">
import MarkdownRender from '@app/components/MarkdownRender.vue';
import { computed } from 'vue';
import type { LabRecord } from '../../useLabRecords';
import RiverList from './RiverList.vue';

defineEmits<{ close: []; selectRecord: [slug: string] }>();

const props = defineProps<{
  conceptSlug: string;
  conceptTitle: string;
  conceptRecord: LabRecord | null;
  records: LabRecord[];
}>();

const title = computed(() => props.conceptRecord?.title ?? props.conceptTitle);
const description = computed(
  () => props.conceptRecord?.content || props.conceptRecord?.summary || '',
);
</script>

<style scoped>
.cd {
  max-width: 720px;
  margin: 0 auto;
  padding: 1.5rem 0.5rem 4rem;
}
.cd__head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 1rem;
}
.cd__close {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 28px;
  height: 28px;
  border-radius: 999px;
  border: 1px solid var(--ui-border);
  background: var(--ui-bg);
  color: var(--ui-text-muted);
  cursor: pointer;
}
.cd__close:hover {
  background: var(--ui-bg-elevated);
  color: var(--ui-text);
}
.cd__kind {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  font-size: 0.66rem;
  text-transform: uppercase;
  letter-spacing: 0.1em;
  font-weight: 600;
  color: var(--ui-primary);
}
.cd__kindGlyph {
  width: 13px;
  height: 13px;
}
.cd__title {
  font-family: var(--font-serif);
  font-size: 2.1rem;
  font-weight: 600;
  line-height: 1.05;
  letter-spacing: -0.02em;
  color: var(--ui-text-highlighted);
  text-transform: lowercase;
}
.cd__count {
  margin-top: 6px;
  font-size: 0.8rem;
  color: var(--ui-text-muted);
}
.cd__desc {
  margin-top: 1.25rem;
  font-size: 0.95rem;
  line-height: 1.6;
  color: var(--ui-text-toned);
}
.cd__listHead {
  display: flex;
  align-items: center;
  gap: 12px;
  margin-top: 2rem;
  margin-bottom: 0.25rem;
  font-size: 0.66rem;
  text-transform: uppercase;
  letter-spacing: 0.12em;
  color: var(--ui-text-dimmed);
}
.cd__rule {
  flex: 1;
  height: 1px;
  background: var(--ui-border);
}
</style>
