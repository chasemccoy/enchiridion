<template>
  <div
    v-if="modelValue"
    class="RecordCard shadow-xs"
    :class="{ 'RecordCard--expanded': expanded }"
  >
    <h1
      v-if="modelValue.title || (showParent && parent)"
      class="RecordCard__title"
    >
      <ParentRefChip
        v-if="showParent && parent"
        :parent="parent"
      />

      <RouterLink
        v-if="modelValue.title"
        :to="href"
      >
        {{ modelValue.title }}
      </RouterLink>

      <span
        v-if="creator || (modelValue.url && !showParentRef)"
        class="RecordCard__byline"
      >
        <span
          v-if="creator"
          class="RecordCard__bylineItem"
        >
          by
          <UButton
            size="sm"
            color="neutral"
            variant="link"
            class="RecordCard__bylineButton"
            :to="`/${creator.slug}`"
          >
            <span>{{ creator.title }}</span>
          </UButton>
        </span>

        <LinkWithFavicon
          v-if="modelValue.url && !showParentRef"
          prefix="at"
          :modelValue="modelValue.url"
        />
      </span>
    </h1>

    <div
      v-if="modelValue.media?.length > 0 && modelValue.media[0]?.type === 'image'"
      class="RecordCard__image"
    >
      <img
        loading="lazy"
        decoding="async"
        :src="`${backendBaseUrl}${modelValue.media[0]?.url}`"
        :alt="modelValue.media[0].altText ?? ''"
      />
    </div>

    <AttachmentGallery
      v-if="false"
      v-model="modelValue.media"
      readonly
    />

    <MarkdownRender
      v-if="preferContent && modelValue.content"
      class="RecordCard__content"
      :source="modelValue.content"
    />
    <div
      v-else-if="modelValue.summary"
      class="RecordCard__summary"
    >
      {{ modelValue.summary }}
    </div>
    <MarkdownRender
      v-else-if="modelValue.content"
      class="RecordCard__content"
      :source="modelValue.content"
    />

    <ul class="RecordCard__tags">
      <li v-if="modelValue.type !== 'artifact'">
        <UBadge
          color="neutral"
          variant="outline"
          class="RecordCard__badge"
          size="sm"
          :icon="getIconForRecordType(modelValue.type)"
        >
          {{ capitalize(modelValue.type) }}
        </UBadge>
      </li>
      <li v-if="modelValue.source === 'twitter'">
        <UIcon
          name="i-lucide-twitter"
          class="size-4"
        />
      </li>

      <li>
        <RouterLink
          activeClass="RouterLink--isActive"
          :to="href"
        >
          {{ formatDate(modelValue.recordCreatedAt, { year: false }) }}
        </RouterLink>
      </li>

      <li
        v-if="childrenCount > 0"
        class="RecordCard__childrenCount"
      >
        {{ pluralize(childrenCount, 'highlight', 'highlights') }}
      </li>

      <li
        v-for="tag in tags"
        :key="tag.id"
        class="RecordCard__tag"
      >
        <RouterLink :to="`/${tag.slug}`"> #{{ slugify(tag.title ?? tag.slug) }} </RouterLink>
      </li>
    </ul>

    <ChatBubble
      v-if="modelValue.notes"
      class="RecordCard__notes"
    >
      {{ modelValue.notes }}
    </ChatBubble>
  </div>
</template>

<script setup lang="ts">
import AttachmentGallery from '@app/components/AttachmentGallery.vue';
import type { ListRecordsAPIResponse } from '@db/queries/records';
import { capitalize, computed } from 'vue';
import { formatDate, pluralize, slugify } from '@shared/lib/formatting';
import { isPredicateType, type PredicateSlug } from '@shared/types';
import useApiClient from '@app/composables/useApiClient';
import LinkWithFavicon from '@app/components/LinkWithFavicon.vue';
import ParentRefChip from '@app/components/ParentRefChip.vue';
import { getIconForRecordType } from '@app/utils';
import ChatBubble from '@app/components/ChatBubble.vue';
import MarkdownRender from '@app/components/MarkdownRender.vue';

const modelValue = defineModel<ListRecordsAPIResponse[number]>({ required: true });

const { to, expanded, preferContent, showParent } = defineProps<{
  to?: string;
  /** Render summary/content without the 4-line clamp. */
  expanded?: boolean;
  /** Show the record's `content` instead of `summary` when both exist. */
  preferContent?: boolean;
  /**
   * Show a small inset reference to the record's parent (contained_by / quotes
   * target) above the title. Used on the search page so a hit that's nested
   * inside a larger work (a highlight from a book, a quote from an article)
   * carries that context with it.
   */
  showParent?: boolean;
}>();

const { backendBaseUrl } = useApiClient();

const href = computed(() => {
  if (to) return to;

  return `/${modelValue.value.slug}`;
});

const outgoingLinks = computed(() => modelValue.value?.outgoingLinks ?? null);
const incomingLinks = computed(() => modelValue.value?.incomingLinks ?? null);

const creator = computed(() => {
  if (!outgoingLinks.value) return null;

  return outgoingLinks.value.find((link) => link.predicate === 'created_by')?.target ?? null;
});

// The canonical containment outgoings (contained_by, quotes) point at the
// record's parent. Whichever shows up first wins; records rarely have more
// than one containment parent.
const parentPredicates: PredicateSlug[] = ['contained_by', 'quotes'];
const parent = computed(() => {
  if (!outgoingLinks.value) return null;
  return (
    outgoingLinks.value.find((link) => parentPredicates.includes(link.predicate))?.target ?? null
  );
});
// True when we're actually going to render the parent chip. Used to suppress
// the record's own "at <url>" byline since the chip already carries the
// source context.
const showParentRef = computed(() => Boolean(showParent && parent.value));

const childrenCount = computed(() => {
  if (!incomingLinks.value) return 0;

  return incomingLinks.value.filter((link) => isPredicateType(link.predicate, 'containment'))
    .length;
});

const tags = computed(() => {
  if (!outgoingLinks.value) return null;

  return (
    outgoingLinks.value
      .filter((link) => isPredicateType(link.predicate, 'description'))
      ?.map((link) => link.target) ?? null
  );
});
</script>

<style scoped>
.RecordCard {
  display: grid;
  background-color: var(--ui-bg);
  border: 0.5px solid var(--ui-border);
  border-radius: var(--radius-lg);
  padding: 12px;
  gap: 6px;
  contain: layout style;

  -webkit-column-break-inside: avoid;
  page-break-inside: avoid;
  break-inside: avoid;

  & > * {
    overflow-wrap: break-word;
    hyphens: auto;
    min-width: 0;
  }

  &:has(.RouterLink--isActive) {
    box-shadow: inset 0 0 0 2px var(--ui-primary);
  }
}

.RecordCard__title {
  text-wrap: pretty;
  display: inline-flex;
  flex-wrap: wrap;
  align-items: baseline;
  column-gap: 4px;
  row-gap: 10px;
  font-size: 1rem;
  line-height: 1.3;

  & a:hover {
    text-decoration: underline;
  }
}

.RecordCard__byline {
  display: inline-flex;
  margin-top: -4px;
  row-gap: 4px;
  flex-wrap: wrap;
  font-weight: 500;
  font-size: 0.75rem;
  color: var(--ui-text-muted);
}

.RecordCard__bylineItem {
  display: flex;
  align-items: center;
}

:deep(.RecordCard__bylineButton) {
  max-width: 250px;
  margin-left: 1px;
  padding: 0 4px;

  &:hover {
    text-decoration: underline;
  }

  & :deep(span) {
    min-width: 0;
    text-overflow: ellipsis;
    overflow: hidden;
    white-space: nowrap;
  }
}

.RecordCard__summary,
.RecordCard__content {
  font-size: 0.8rem;
  display: -webkit-box;
  -webkit-box-orient: vertical;
  -webkit-line-clamp: 4;
  line-clamp: 4;
  overflow: hidden;
}

.RecordCard--expanded :is(.RecordCard__summary, .RecordCard__content) {
  display: block;
  -webkit-line-clamp: none;
  line-clamp: none;
  overflow: visible;
}

.RecordCard--expanded .RecordCard__summary {
  white-space: pre-wrap;
}

.RecordCard__section {
  display: grid;
  gap: 0.25rem;
}

.RecordCard__sectionTitle {
  font-size: 0.75rem;
  text-transform: uppercase;
  display: flex;
  align-items: center;
  gap: 0.25rem;
  margin-bottom: 0.5rem;
  color: var(--ui-text-dimmed);
}

.RecordCard__list {
  li + li {
    margin-top: 1rem;
  }
}

.RecordCard__input {
  & :deep(input) {
    color: var(--ui-text-muted);
  }

  & :deep(input:hover),
  & :deep(input:focus) {
    color: var(--ui-text);
  }

  & :deep(svg) {
    width: 12px;
    height: 12px;
    color: var(--ui-text-muted);
  }
}

.RecordCard__tags {
  display: inline-flex;
  align-items: center;
  flex-wrap: wrap;
  column-gap: 8px;
  row-gap: 2px;
  margin-bottom: -2px;
  color: var(--ui-text-dimmed);
  font-size: 0.8rem;

  & > li {
    display: inline-flex;
    align-items: center;
  }
}

.RecordCard__tag {
  color: var(--ui-text-dimmed);
}

.RecordCard__image {
  position: relative;
  height: 150px;
  width: 100%;
  border-radius: var(--radius-md);
  overflow: hidden;
  margin-bottom: 4px;
  margin-top: 4px;
}

.RecordCard__image img {
  height: 100%;
  width: 100%;
  object-fit: cover;
  object-position: 50% 25%;
  display: block;
}

/* Hairline overlay painted on top of the image — an inset box-shadow on the
   <img> (or its wrapper) is covered by the image content, so draw it on a
   pseudo-element layered above instead. */
.RecordCard__image::after {
  content: '';
  position: absolute;
  inset: 0;
  border-radius: inherit;
  box-shadow: inset 0 0 0 1px var(--ui-border);
  pointer-events: none;
}

.RecordCard__childrenCount {
  background-color: var(--ui-bg);
  box-shadow: var(--shadow-edge);
  padding: 1px 6px;
  border-radius: 9999px;
  font-size: 0.625rem;
  color: var(--ui-text-dimmed);
  text-transform: uppercase;
}

.RecordCard__badge {
  width: fit-content;

  & :deep(svg) {
    width: 12px;
    height: 12px;
    color: var(--ui-text-muted);
  }
}

.RecordCard__notes {
  margin-top: 8px;
}
</style>
