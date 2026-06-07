<template>
  <RouterLink
    class="Row"
    :to="`/${view?.slug || fallbackSlug}`"
  >
    <span class="Row__iconCell">
      <UIcon
        v-if="view?.icon"
        :name="view.icon"
      />
    </span>
    <span class="Row__title">
      {{ view?.title || fallbackTitle || view?.slug || fallbackSlug }}
    </span>
    <span class="Row__snip">
      <template v-if="view?.summary">{{ view.summary }}</template>
    </span>
    <a
      v-if="view?.host"
      class="Row__host"
      target="_blank"
      :href="view.url || undefined"
      @click.stop
    >
      {{ view.host }}
    </a>
    <span
      v-else
      class="Row__host Row__host--empty"
    />
    <span class="Row__actions">
      <UButton
        size="xs"
        color="neutral"
        variant="ghost"
        icon="i-lucide-pencil"
        @click.prevent.stop
      />
      <UButton
        size="xs"
        color="neutral"
        variant="ghost"
        icon="i-lucide-x"
        @click.prevent.stop
      />
    </span>
  </RouterLink>
</template>

<script setup lang="ts">
import { toRef } from 'vue';
import { useLinkPreview } from './useLinkPreview';

const props = defineProps<{
  linkId: number;
  fallbackTitle?: string | null;
  fallbackSlug?: string | null;
}>();

const { view } = useLinkPreview(toRef(props, 'linkId'));
</script>

<style scoped>
.Row {
  display: grid;
  grid-template-columns: 18px minmax(120px, 0.9fr) minmax(0, 1.4fr) minmax(0, 110px) auto;
  align-items: baseline;
  gap: 10px;
  padding: 8px 12px;
  border-top: 1px solid var(--ui-border);
  font-size: 0.85rem;
  color: var(--ui-text);
  position: relative;
  transition: background 0.1s ease;

  &:hover {
    background: var(--ui-bg-elevated);
  }
}

.Row__iconCell {
  color: var(--ui-text-dimmed);
  display: inline-flex;
  align-items: center;
  justify-content: center;
}

.Row__iconCell :deep(svg) {
  width: 14px;
  height: 14px;
}

.Row__title {
  font-weight: 500;
  text-wrap: pretty;
  min-width: 0;
}

.Row__snip {
  font-size: 0.78rem;
  color: var(--ui-text-muted);
  display: -webkit-box;
  -webkit-line-clamp: 1;
  -webkit-box-orient: vertical;
  overflow: hidden;
  min-width: 0;
}

.Row__host {
  font-size: 0.72rem;
  color: var(--ui-text-dimmed);
  font-family: var(--font-mono, ui-monospace, monospace);
  text-align: right;
  text-overflow: ellipsis;
  overflow: hidden;
  white-space: nowrap;

  &:hover {
    color: var(--ui-primary);
  }
}

.Row__host--empty {
  /* keep the column slot so rows align */
}

.Row__actions {
  display: inline-flex;
  gap: 2px;
  opacity: 0;
  transition: opacity 0.1s ease;
}

.Row:hover .Row__actions {
  opacity: 1;
}
</style>
