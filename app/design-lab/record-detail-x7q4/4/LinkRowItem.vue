<template>
  <RouterLink
    class="Row"
    :to="`/${view?.slug || fallbackSlug}`"
  >
    <span class="Row__title">
      {{ view?.title || fallbackTitle || view?.slug || fallbackSlug }}
    </span>

    <span
      v-if="view?.summary"
      class="Row__snip"
    >
      {{ view.summary }}
    </span>

    <!-- Match the RecordLink card's meta row: LinkWithFavicon for the URL,
         plain dimmed #tag links — no custom host pill. -->
    <ul
      v-if="view?.url || (view?.tagLinks?.length ?? 0) || kind === 'in'"
      class="Row__meta"
    >
      <li v-if="view?.url">
        <LinkWithFavicon :modelValue="view.url" />
      </li>
      <li
        v-else-if="kind === 'in'"
        class="Row__incoming"
      >
        <UIcon
          name="i-lucide-corner-left-up"
          class="Row__incomingIcon"
        />
        incoming
      </li>
      <li
        v-for="tag in view?.tagLinks ?? []"
        :key="tag.slug"
      >
        <RouterLink
          class="Row__tag"
          :to="`/${tag.slug}`"
          @click.stop
        >
          #{{ slugify(tag.title) }}
        </RouterLink>
      </li>
    </ul>
  </RouterLink>
</template>

<script setup lang="ts">
import LinkWithFavicon from '@app/components/LinkWithFavicon.vue';
import slugify from 'slugify';
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

/* Mirrors RecordLink__meta. */
.Row__meta {
  display: inline-flex;
  align-items: center;
  flex-wrap: wrap;
  column-gap: 8px;
  row-gap: 2px;
  margin-top: 2px;
  color: var(--ui-text-dimmed);
  font-size: 0.75rem;
  list-style: none;
  padding: 0;

  :deep(svg) {
    width: 14px;
    height: 14px;
  }
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
  color: var(--ui-text-dimmed);

  &:hover {
    color: var(--ui-text);
    text-decoration: underline;
  }
}
</style>
