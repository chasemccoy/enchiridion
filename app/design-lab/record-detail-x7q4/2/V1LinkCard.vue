<template>
  <RouterLink
    v-if="view"
    class="Card"
    :to="`/${view.slug || fallbackSlug}`"
  >
    <div class="Card__head">
      <UIcon
        v-if="view.icon"
        class="Card__icon"
        :name="view.icon"
      />
      <span class="Card__title">
        {{ view.title || fallbackTitle || view.slug }}
      </span>
    </div>
    <p
      v-if="view.summary"
      class="Card__snip"
    >
      {{ view.summary }}
    </p>
    <div
      v-if="view.host || view.tags.length"
      class="Card__meta"
    >
      <a
        v-if="view.host"
        class="Card__host"
        target="_blank"
        :href="view.url || undefined"
        @click.stop
      >
        <img
          v-if="view.favicon"
          alt=""
          class="Card__favicon"
          width="12"
          height="12"
          :src="view.favicon"
        />
        {{ view.host }}
      </a>
      <span
        v-for="tag in view.tags"
        :key="tag"
        class="Card__tag"
      >
        #{{ tag }}
      </span>
    </div>
  </RouterLink>
  <div
    v-else
    class="Card Card--loading"
  >
    <span class="Card__title">{{ fallbackTitle || fallbackSlug }}</span>
  </div>
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
.Card {
  display: grid;
  gap: 4px;
  padding: 10px 12px;
  border: 1px solid var(--ui-border);
  border-radius: var(--radius-md);
  background: var(--ui-bg);
  color: var(--ui-text);
  transition: background 0.12s ease, border-color 0.12s ease;
  min-width: 0;

  &:hover {
    background: var(--ui-bg-elevated);
    border-color: var(--ui-border-accented);
  }
}

.Card__head {
  display: inline-flex;
  align-items: baseline;
  gap: 6px;
}

.Card__icon {
  width: 12px;
  height: 12px;
  color: var(--ui-text-dimmed);
  align-self: center;
}

.Card__title {
  font-size: 0.85rem;
  font-weight: 500;
  text-wrap: pretty;
}

.Card__snip {
  font-size: 0.75rem;
  line-height: 1.4;
  color: var(--ui-text-muted);
  margin: 0;
  display: -webkit-box;
  -webkit-line-clamp: 2;
  -webkit-box-orient: vertical;
  overflow: hidden;
}

.Card__meta {
  display: inline-flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 6px;
  font-size: 0.7rem;
  color: var(--ui-text-dimmed);
  margin-top: 2px;
}

.Card__host {
  display: inline-flex;
  align-items: center;
  gap: 3px;
  color: var(--ui-text-dimmed);
  font-family: var(--font-mono, ui-monospace, monospace);

  &:hover {
    color: var(--ui-primary);
  }
}

.Card__favicon {
  border-radius: 2px;
}

.Card__tag {
  color: var(--ui-primary);
  font-size: 0.7rem;
}
</style>
