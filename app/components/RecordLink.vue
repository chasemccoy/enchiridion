<template>
  <component
    v-if="record"
    :is="!title ? RouterLink : 'div'"
    class="RecordLink"
    :to="`/${record.slug}`"
    :class="{
      'RecordLink--loading': isLoading,
      'RecordLink--includeChildren': includeChildren,
      'RecordLink--row': layout === 'row',
    }"
  >
    <div
      v-if="title"
      class="RecordLink__header"
    >
      <RouterLink
        v-if="record"
        class="RecordLink__title"
        :to="`/${record.slug}`"
      >
        {{ title }}
      </RouterLink>

      <span
        v-if="creator"
        class="RecordLink__creator"
      >
        by <RouterLink :to="`/${creator.slug}`">{{ creator.title }}</RouterLink>
      </span>
    </div>

    <ParentRefChip
      v-else-if="parent && showParent"
      class="RecordLink__parent"
      :parent="parent"
    />

    <MarkdownRender
      v-if="summary && !truncate"
      class="RecordLink__summary RecordLink__summary--markdown"
      :source="summary"
    />

    <div
      v-else-if="summary"
      class="RecordLink__summary RecordLink__summary--truncated"
    >
      {{ summary }}
    </div>

    <ChatBubble
      v-if="record?.notes"
      class="RecordLink__notes"
    >
      {{ record.notes }}
    </ChatBubble>

    <ul
      v-if="includeChildren && children && children.length > 0"
      class="RecordLink__children"
    >
      <li
        v-for="(child, index) in children"
        :key="index"
        class="RecordLink__child"
      >
        {{ child.content }}
      </li>
    </ul>

    <ul
      v-if="title && (record?.url || tags?.length)"
      class="RecordLink__meta"
    >
      <li v-if="record?.url">
        <LinkWithFavicon :modelValue="record.url" />
      </li>

      <li
        v-for="tag in tags"
        :key="tag.id"
      >
        <RouterLink :to="`/${tag.slug}`">#{{ slugify(tag.title ?? tag.slug) }} </RouterLink>
      </li>
    </ul>

    <div class="RecordLink__actions">
      <PredicateSelect
        v-if="localPredicateSlug"
        v-model="localPredicateSlug"
        :linkDirection="linkDirection"
        @select:predicate="handleSelectPredicate"
        @delete:link="handleDeleteLink"
      />
    </div>
  </component>
</template>

<script setup lang="ts">
import ChatBubble from '@app/components/ChatBubble.vue';
import LinkWithFavicon from '@app/components/LinkWithFavicon.vue';
import MarkdownRender from '@app/components/MarkdownRender.vue';
import ParentRefChip from '@app/components/ParentRefChip.vue';
import PredicateSelect from '@app/components/PredicateSelect.vue';
import useRecord from '@app/composables/useRecord';
import { isPredicateType, type Predicate, type PredicateSlug } from '@shared/types';
import type { DbId } from '@shared/types/api';
import slugify from 'slugify';
import { computed, ref } from 'vue';
import { RouterLink } from 'vue-router';

const modelValue = defineModel<DbId>({ required: true });

const emit = defineEmits<{
  updatePredicate: [Predicate];
  deleteLink: [];
}>();

const {
  predicate,
  linkDirection = 'outgoing',
  truncate = true,
  includeChildren = false,
  showParent = true,
  layout = 'card',
} = defineProps<{
  predicate?: PredicateSlug;
  linkDirection?: 'incoming' | 'outgoing';
  truncate?: boolean;
  includeChildren?: boolean;
  layout?: 'card' | 'row';
  /**
   * Show a parent reference chip on untitled records. Defaults to true. Pass
   * false when the surrounding context already establishes the parent (e.g.
   * the children list on a record detail page, where every row's parent IS
   * the record being viewed).
   *
   * (Named to match `RecordCard.showParent` for cross-component consistency,
   * though the defaults differ: RecordCard is opt-in because most pages don't
   * want it, RecordLink is opt-out because most pages do.)
   */
  showParent?: boolean;
}>();

const localPredicateSlug = ref<PredicateSlug | null>(predicate ?? null);

const { getRecord, getRecordLinks } = useRecord();

const { data: record, isLoading } = getRecord(modelValue);

const { data: links } = getRecordLinks(modelValue, () => includeChildren);

const outgoingLinks = computed(() => record.value?.outgoingLinks ?? null);
const incomingLinks = computed(() => links.value?.incomingLinks ?? null);

const creator = computed(() => {
  return (
    outgoingLinks.value?.find((edge) => isPredicateType(edge.predicate, 'creation'))?.target ?? null
  );
});

const title = computed(() => {
  if (record.value?.title) {
    return record.value.title;
  }

  if (creator.value && creator.value.title) {
    return creator.value.title;
  }

  return null;
});

const summary = computed(() => {
  if (record.value?.summary && !includeChildren) {
    return record.value.summary;
  }

  return record.value?.content || record.value?.summary;
});

const tags = computed(() => {
  if (!outgoingLinks.value) return null;

  return outgoingLinks.value
    .filter((link) => isPredicateType(link.predicate, 'description'))
    .map((link) => link.target);
});

// The canonical containment outgoings (contained_by, quotes) point at the
// record's parent. Surfaced as a small chip only when the link has no title
// of its own. Titled links already self-identify, so the parent reference
// would be noise.
const parentPredicates: PredicateSlug[] = ['contained_by', 'quotes'];
const parent = computed(() => {
  return (
    outgoingLinks.value?.find((link) => parentPredicates.includes(link.predicate))?.target ?? null
  );
});

const children = computed(() => {
  if (!includeChildren || !incomingLinks.value) return null;

  return incomingLinks.value
    .filter((link) => isPredicateType(link.predicate, 'containment'))
    .map((link) => link.source)
    .filter((child) => child.content);
});

function handleSelectPredicate(predicate: Predicate) {
  emit('updatePredicate', predicate);
}

function handleDeleteLink() {
  emit('deleteLink');
}
</script>

<style scoped>
.RecordLink {
  display: grid;
  gap: 2px;
  position: relative;
  padding: 8px 12px;
  border-radius: var(--radius-lg);
  background-color: var(--ui-bg);
  border: 0.5px solid var(--ui-border);
  contain: layout style;
}

.RecordLink__header {
  display: inline-flex;
  column-gap: 6px;
  flex-wrap: wrap;
  padding-right: 24px;
  align-items: baseline;
}

.RecordLink__parent {
  /* Don't let the chip stretch across the RecordLink grid row. */
  justify-self: start;
  margin-top: 2px;
  margin-bottom: 6px;
}

.RecordLink__title,
.RecordLink__creator {
  font-size: 0.875rem;
  text-wrap: pretty;
}

.RecordLink--includeChildren {
  & .RecordLink__title {
    font-size: 1rem;
  }
}

.RecordLink__title,
.RecordLink__creator a {
  font-weight: 500;

  &:hover {
    text-decoration: underline;
  }
}

.RecordLink__creator {
  color: var(--ui-text-muted);
}

.RecordLink__meta {
  display: inline-flex;
  align-items: center;
  flex-wrap: wrap;
  column-gap: 8px;
  margin-bottom: -2px;
  color: var(--ui-text-dimmed);
  font-size: 0.75rem;

  :deep(svg) {
    width: 14px;
    height: 14px;
  }
}

.RecordLink__icon {
  color: var(--ui-text-dimmed);
}

.RecordLink__summary,
.RecordLink__child {
  font-size: 0.8rem;
  line-height: 1.15rem;
  color: var(--ui-text-muted);
  white-space: preserve wrap;
}

.RecordLink__summary--markdown {
  white-space: normal;
}

.RecordLink__summary--markdown :deep(:last-child) {
  margin-bottom: 0;
}

.RecordLink:has(.RecordLink__title) .RecordLink__summary {
  margin-top: 2px;
}

.RecordLink:has(.RecordLink__title):has(.RecordLink__meta) .RecordLink__summary {
  margin-bottom: 4px;
}

.RecordLink__summary--truncated {
  display: -webkit-box;
  -webkit-box-orient: vertical;
  -webkit-line-clamp: 3;
  line-clamp: 3;
  overflow: hidden;
}

.RecordLink__actions {
  position: absolute;
  top: 6px;
  right: 6px;
  opacity: 0;
  transition: opacity 0.15s ease-in-out;
}

.RecordLink:hover .RecordLink__actions,
.RecordLink__actions:has(button[aria-expanded='true']) {
  opacity: 1;
}

.RecordLink__notes {
  margin-top: 6px;
}

.RecordLink__children {
  display: grid;
  gap: 4px;
  margin-bottom: 8px;
}

.RecordLink__child {
  color: var(--ui-text-muted);
}

.RecordLink__children li {
  margin-top: 4px;
  border-top: 1px solid var(--ui-border);
  padding-top: 8px;
}

.RecordLink--row {
  padding: 7px 10px;
  border: 0;
  border-radius: var(--radius-lg);
  background-color: transparent;
  transition: background-color 0.1s ease;
}

.RecordLink--row:hover {
  background-color: var(--ui-bg-elevated);
}

.RecordLink--row:not(.RecordLink--includeChildren) .RecordLink__title {
  font-size: 0.9rem;
}

.RecordLink--row .RecordLink__summary {
  font-size: 0.78rem;
}

.RecordLink--row .RecordLink__summary--truncated {
  -webkit-line-clamp: 2;
  line-clamp: 2;
}
</style>
