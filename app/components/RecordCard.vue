<template>
  <div
    v-if="modelValue"
    class="RecordCard"
    :data-size="size"
  >
    <h1
      v-if="modelValue.title"
      class="RecordCard__title"
    >
      <RouterLink :to="href">
        {{ modelValue.title }}
      </RouterLink>
    </h1>

    <div
      v-if="creator || modelValue.url"
      class="RecordCard__byline"
    >
      <span
        v-if="creator"
        class="RecordCard__bylineItem"
      >
        by
        <UButton
          icon="i-lucide-user-pen"
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
        v-if="modelValue.url"
        prefix="at"
        :modelValue="modelValue.url"
      />
    </div>

    <img
      v-if="modelValue.media.length > 0 && modelValue.media[0].type === 'image'"
      class="RecordCard__image"
      :src="`${backendBaseUrl}${modelValue.media[0].url}`"
      :alt="modelValue.media[0].altText ?? ''"
    />

    <AttachmentGallery
      v-if="false"
      v-model="modelValue.media"
      readonly
    />

    <div
      v-if="modelValue.summary"
      class="RecordCard__summary"
    >
      {{ modelValue.summary }}
    </div>

    <div
      v-if="modelValue.content"
      class="RecordCard__content"
    >
      {{ modelValue.content }}
    </div>

    <ul class="RecordCard__tags">
      <li v-if="modelValue.source === 'twitter'">
        <UIcon
          name="i-lucide-twitter"
          class="size-4"
        />
      </li>

      <li v-if="modelValue.notes">
        <UIcon
          name="i-lucide-message-circle"
          class="size-4"
        />
      </li>

      <li>
        <RouterLink
          activeClass="RouterLink--isActive"
          :to="href"
        >
          {{ formatDate(new Date(modelValue.recordCreatedAt), { year: false }) }}
        </RouterLink>
      </li>

      <li
        v-for="tag in tags"
        :key="tag.id"
        class="RecordCard__tag"
      >
        <RouterLink :to="`/${tag.slug}`"> #{{ slugify(tag.title ?? tag.slug) }} </RouterLink>
      </li>
    </ul>
  </div>
</template>

<script setup lang="ts">
import AttachmentGallery from '@app/components/AttachmentGallery.vue';
import type { ListRecordsAPIResponse } from '@db/queries/records';
import { computed } from 'vue';
import { formatDate, slugify } from '@shared/lib/formatting';
import useApiClient from '@app/composables/useApiClient';
import LinkWithFavicon from '@app/components/LinkWithFavicon.vue';

const modelValue = defineModel<ListRecordsAPIResponse[number]>({ required: true });

const { to, size = 'default' } = defineProps<{
  to?: string;
  size?: 'compact' | 'default';
}>();

const { backendBaseUrl } = useApiClient();

const href = computed(() => {
  if (to) return to;

  return `/${modelValue.value.slug}`;
});

const outgoingLinks = computed(() => modelValue.value?.outgoingLinks ?? null);

const creator = computed(() => {
  if (!outgoingLinks.value) return null;

  return outgoingLinks.value.find((link) => link.predicate.slug === 'created_by')?.target ?? null;
});

const tags = computed(() => {
  if (!outgoingLinks.value) return null;

  return (
    outgoingLinks.value
      .filter((link) => link.predicate.type === 'description')
      ?.map((link) => link.target) ?? null
  );
});
</script>

<style scoped>
.RecordCard {
  display: grid;
  gap: 4px;
  background-color: var(--ui-bg);
  border: 1px solid var(--ui-border);
  border-radius: var(--radius-lg);
  padding: 16px;

  -webkit-column-break-inside: avoid;
  page-break-inside: avoid;
  break-inside: avoid;

  &[data-size='compact'] {
    padding: 12px;
    gap: 6px;
  }

  & > * {
    overflow-wrap: break-word;
    hyphens: auto;
    min-width: 0;
  }

  &:has(.RouterLink--isActive) {
    border-color: var(--ui-primary);
    box-shadow: 0 0 0 1px var(--ui-primary);
  }
}

.RecordCard__title {
  font-size: 1.25rem;
  line-height: 1.2;
  text-wrap: pretty;

  & a {
    display: block;
  }

  & a:hover {
    text-decoration: underline;
  }

  [data-size='compact'] & {
    font-size: 1rem;
    line-height: 1.3;
  }
}

.RecordCard__byline {
  display: inline-flex;
  margin-top: -2px;
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
  padding-inline: 4px;

  & :deep(span) {
    min-width: 0;
    text-overflow: ellipsis;
    overflow: hidden;
    white-space: nowrap;
  }

  & :deep(svg) {
    width: 14px;
    height: 14px;
  }
}

.RecordCard__summary,
.RecordCard__content {
  font-size: 0.8rem;
  display: -webkit-box;
  -webkit-box-orient: vertical;
  -webkit-line-clamp: 8;
  line-clamp: 8;
  overflow: hidden;
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
  gap: 8px;
  margin-top: 4px;
  margin-bottom: -2px;
  color: var(--ui-text-dimmed);
  font-size: 0.8rem;
}

.RecordCard__tag {
  display: inline-block;
  color: var(--ui-text-dimmed);
}

.RecordCard__image {
  height: 150px;
  width: 100%;
  object-fit: cover;
  object-position: top;
  border-radius: var(--radius-md);
  margin-bottom: 4px;
}
</style>
