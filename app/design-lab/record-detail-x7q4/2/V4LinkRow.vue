<template>
  <RouterLink
    class="K"
    :to="`/${view?.slug || fallbackSlug}`"
  >
    <span class="K__kicker">{{ kickerLabel }}</span>
    <span class="K__main">
      <span class="K__titleLine">
        <UIcon
          v-if="view?.icon"
          class="K__icon"
          :name="view.icon"
        />
        <span class="K__title">
          {{ view?.title || fallbackTitle || view?.slug || fallbackSlug }}
        </span>
      </span>
      <span
        v-if="view?.summary"
        class="K__snip"
      >
        {{ view.summary }}
      </span>
    </span>
    <a
      v-if="view?.host"
      class="K__host"
      target="_blank"
      :href="view.url || undefined"
      @click.stop
    >
      <img
        v-if="view.favicon"
        alt=""
        class="K__favicon"
        width="12"
        height="12"
        :src="view.favicon"
      />
      {{ view.host }}
    </a>
    <span
      v-else-if="kind === 'in'"
      class="K__host K__host--in"
    >
      mentioned
    </span>
  </RouterLink>
</template>

<script setup lang="ts">
import { toRef } from 'vue';
import { useLinkPreview } from './useLinkPreview';

const props = defineProps<{
  linkId: number;
  kickerLabel: string;
  kind: 'out' | 'in';
  fallbackTitle?: string | null;
  fallbackSlug?: string | null;
}>();

const { view } = useLinkPreview(toRef(props, 'linkId'));
</script>

<style scoped>
.K {
  display: grid;
  grid-template-columns: 120px 1fr auto;
  gap: 16px;
  align-items: baseline;
  padding: 8px 10px;
  border-radius: var(--radius-md);
  color: var(--ui-text);
  transition: background 0.1s ease;

  &:hover {
    background: var(--ui-bg-elevated);
  }
}

.K__kicker {
  font-size: 0.72rem;
  color: var(--ui-text-dimmed);
  padding-top: 2px;
}

.K__main {
  display: grid;
  gap: 2px;
  min-width: 0;
}

.K__titleLine {
  display: inline-flex;
  align-items: baseline;
  gap: 6px;
}

.K__icon {
  width: 12px;
  height: 12px;
  color: var(--ui-text-dimmed);
  align-self: center;
}

.K__title {
  font-size: 0.9rem;
  font-weight: 500;
}

.K__snip {
  font-size: 0.78rem;
  color: var(--ui-text-muted);
  line-height: 1.4;
  display: -webkit-box;
  -webkit-line-clamp: 2;
  -webkit-box-orient: vertical;
  overflow: hidden;
}

.K__host {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  padding: 2px 8px;
  border-radius: 999px;
  background: var(--ui-bg-elevated);
  border: 1px solid var(--ui-border);
  font-size: 0.7rem;
  color: var(--ui-text-muted);
  font-family: var(--font-mono, ui-monospace, monospace);

  &:hover {
    color: var(--ui-primary);
    border-color: var(--ui-border-accented);
  }
}

.K__host--in {
  font-family: inherit;
  color: var(--ui-text-dimmed);
  background: transparent;
  border-style: dashed;
}

.K__favicon {
  border-radius: 2px;
}
</style>
