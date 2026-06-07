<template>
  <RouterLink
    class="Row"
    :to="`/${view?.slug || fallbackSlug}`"
  >
    <span class="Row__titleLine">
      <UIcon
        v-if="view?.icon"
        class="Row__icon"
        :name="view.icon"
      />
      <span class="Row__title">
        {{ view?.title || fallbackTitle || view?.slug || fallbackSlug }}
      </span>
    </span>

    <span
      v-if="view?.summary"
      class="Row__snip"
    >
      {{ view.summary }}
    </span>

    <span
      v-if="view?.host || view?.tags.length || kind === 'in'"
      class="Row__meta"
    >
      <a
        v-if="view?.host"
        class="Row__host"
        target="_blank"
        :href="view.url || undefined"
        @click.stop
      >
        <img
          v-if="view.favicon"
          alt=""
          class="Row__favicon"
          width="12"
          height="12"
          :src="view.favicon"
        />
        {{ view.host }}
      </a>
      <span
        v-else-if="kind === 'in'"
        class="Row__incoming"
      >
        <UIcon
          name="i-lucide-corner-left-up"
          class="Row__incomingIcon"
        />
        incoming
      </span>
      <span
        v-for="tag in view?.tags ?? []"
        :key="tag"
        class="Row__tag"
      >
        #{{ tag }}
      </span>
    </span>
  </RouterLink>
</template>

<script setup lang="ts">
import { toRef } from 'vue';
import { useLinkPreview } from '../2/useLinkPreview';

const props = defineProps<{
  linkId: number;
  kind: 'out' | 'in';
  fallbackTitle?: string | null;
  fallbackSlug?: string | null;
}>();

const { view } = useLinkPreview(toRef(props, 'linkId'));
</script>

<style scoped>
.Row {
  display: grid;
  gap: 2px;
  padding: 8px 10px;
  border-radius: var(--radius-md);
  color: var(--ui-text);
  transition: background 0.1s ease;

  &:hover {
    background: var(--ui-bg-elevated);
  }
}

.Row__titleLine {
  display: inline-flex;
  align-items: baseline;
  gap: 6px;
}

.Row__icon {
  width: 12px;
  height: 12px;
  color: var(--ui-text-dimmed);
  align-self: center;
}

.Row__title {
  font-size: 0.9rem;
  font-weight: 500;
  text-wrap: pretty;
}

.Row__snip {
  font-size: 0.78rem;
  color: var(--ui-text-muted);
  line-height: 1.4;
  display: -webkit-box;
  -webkit-line-clamp: 2;
  -webkit-box-orient: vertical;
  overflow: hidden;
}

.Row__meta {
  display: inline-flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 4px 8px;
  margin-top: 2px;
  font-size: 0.7rem;
  color: var(--ui-text-dimmed);
}

.Row__host {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  padding: 1px 7px;
  border-radius: 999px;
  background: var(--ui-bg-elevated);
  border: 1px solid var(--ui-border);
  color: var(--ui-text-muted);
  font-family: var(--font-mono, ui-monospace, monospace);

  &:hover {
    color: var(--ui-primary);
    border-color: var(--ui-border-accented);
  }
}

.Row:hover .Row__host {
  background: var(--ui-bg);
}

.Row__favicon {
  border-radius: 2px;
}

.Row__incoming {
  display: inline-flex;
  align-items: center;
  gap: 3px;
  color: var(--ui-text-dimmed);
}

.Row__incomingIcon {
  width: 11px;
  height: 11px;
}

.Row__tag {
  color: var(--ui-primary);
}
</style>
