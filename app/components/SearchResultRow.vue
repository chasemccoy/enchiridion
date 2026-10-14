<template>
  <div class="SearchResultRow">
    <UIcon
      class="SearchResultRow__icon"
      :name="getIconForRecordType(record.type) ?? 'i-lucide-circle'"
    />

    <div class="SearchResultRow__body">
      <div
        v-if="parent"
        class="SearchResultRow__parent"
      >
        <UIcon
          name="i-lucide-corner-down-right"
          class="size-3"
        />
        <span>{{ parent.title ?? parent.slug }}</span>
      </div>

      <div class="SearchResultRow__title">
        <template
          v-for="(segment, index) in titleSegments"
          :key="index"
        >
          <mark v-if="segment.match">{{ segment.text }}</mark>
          <template v-else>{{ segment.text }}</template>
        </template>
      </div>

      <div
        v-if="meta"
        class="SearchResultRow__meta"
      >
        {{ meta }}
      </div>

      <div
        v-if="previewSegments.length"
        class="SearchResultRow__preview"
      >
        <template
          v-for="(segment, index) in previewSegments"
          :key="index"
        >
          <mark v-if="segment.match">{{ segment.text }}</mark>
          <template v-else>{{ segment.text }}</template>
        </template>
      </div>

      <div
        v-if="record.notes"
        class="SearchResultRow__note"
      >
        <UIcon
          name="i-lucide-pencil-line"
          class="size-3 shrink-0"
        />
        <span>{{ record.notes }}</span>
      </div>
    </div>

    <img
      v-if="imageUrl"
      class="SearchResultRow__image"
      loading="lazy"
      decoding="async"
      alt=""
      :src="imageUrl"
    />
  </div>
</template>

<script setup lang="ts">
import useApiClient from '@app/composables/useApiClient';
import { getIconForRecordType, getOriginOfUrl } from '@app/utils';
import type { ListRecordsAPIResponse } from '@db/queries/records';
import { capitalize, pluralize, slugify } from '@shared/lib/formatting';
import { excerpt, highlightSegments, plainText } from '@shared/lib/search-preview';
import { isPredicateType } from '@shared/types';
import { computed } from 'vue';

/**
 * A record in the search palette: its type icon, the record it sits in (a book
 * for a highlight), the title, a muted line of who and where, a preview
 * (the summary, or the content around what was searched for), the note, and the
 * first image as a thumbnail. Searched words are highlighted throughout.
 */
const { record, query } = defineProps<{
  record: ListRecordsAPIResponse[number];
  query: string;
}>();

const { backendBaseUrl } = useApiClient();

const content = computed(() => plainText(record.content));

const title = computed(() => record.title || excerpt(content.value, query, 90) || record.slug);
const titleSegments = computed(() => highlightSegments(title.value, query));

const creator = computed(
  () => record.outgoingLinks?.find((link) => link.predicate === 'created_by')?.target ?? null,
);

const parent = computed(
  () =>
    record.outgoingLinks?.find(
      (link) => link.predicate === 'contained_by' || link.predicate === 'quotes',
    )?.target ?? null,
);

const domain = computed(() => {
  if (!record.url) return null;
  try {
    return getOriginOfUrl(record.url);
  } catch {
    return null;
  }
});

const highlights = computed(
  () =>
    record.incomingLinks?.filter((link) => isPredicateType(link.predicate, 'containment')).length ??
    0,
);

const tags = computed(
  () =>
    record.outgoingLinks
      ?.filter((link) => isPredicateType(link.predicate, 'description'))
      .map((link) => `#${slugify(link.target.title ?? link.target.slug)}`) ?? [],
);

const meta = computed(() =>
  [
    creator.value ? `by ${creator.value.title ?? creator.value.slug}` : null,
    domain.value,
    record.type !== 'artifact' ? capitalize(record.type) : null,
    highlights.value > 0 ? pluralize(highlights.value, 'highlight', 'highlights') : null,
    ...tags.value.slice(0, 3),
  ]
    .filter(Boolean)
    .join(' · '),
);

// The content when the search matched inside it, else the summary, else the
// content's opening. An untitled record already leads with its content.
const preview = computed(() => {
  const words = query.toLowerCase().split(/\s+/).filter(Boolean);
  const lowerContent = content.value.toLowerCase();
  const matchesContent = words.some((word) => lowerContent.includes(word));
  const summary = plainText(record.summary);
  if (!record.title) return summary;
  if (matchesContent && !words.some((word) => summary.toLowerCase().includes(word))) {
    return excerpt(content.value, query);
  }
  return summary || excerpt(content.value, query);
});
const previewSegments = computed(() => highlightSegments(preview.value, query));

const imageUrl = computed(() => {
  const image = record.media?.find((media) => media.type === 'image');
  return image ? `${backendBaseUrl}${image.url}` : null;
});
</script>

<style scoped>
.SearchResultRow {
  display: grid;
  grid-template-columns: auto minmax(0, 1fr) auto;
  align-items: start;
  column-gap: 10px;
  width: 100%;
  padding: 4px 0;
  text-align: left;
}

.SearchResultRow__icon {
  width: 14px;
  height: 14px;
  margin-top: 3px;
  color: var(--ui-text-dimmed);
}

.SearchResultRow__body {
  display: grid;
  gap: 3px;
  min-width: 0;
}

.SearchResultRow__parent {
  display: flex;
  align-items: center;
  gap: 4px;
  font-size: 0.75rem;
  color: var(--ui-text-muted);

  & span {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
}

.SearchResultRow__title {
  font-size: 0.875rem;
  font-weight: 500;
  color: var(--ui-text-highlighted);
  line-height: 1.35;
  display: -webkit-box;
  -webkit-line-clamp: 2;
  -webkit-box-orient: vertical;
  overflow: hidden;
}

.SearchResultRow__meta {
  font-size: 0.75rem;
  color: var(--ui-text-muted);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.SearchResultRow__preview {
  font-size: 0.8125rem;
  line-height: 1.45;
  color: var(--ui-text-toned);
  display: -webkit-box;
  -webkit-line-clamp: 2;
  -webkit-box-orient: vertical;
  overflow: hidden;
}

.SearchResultRow__note {
  display: flex;
  align-items: center;
  gap: 4px;
  font-size: 0.75rem;
  color: var(--ui-primary);

  & span {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
}

.SearchResultRow__image {
  width: 56px;
  height: 56px;
  border-radius: var(--radius-md);
  object-fit: cover;
  border: 0.5px solid var(--ui-border);
}

mark {
  background: none;
  color: var(--ui-primary);
}
</style>
