<template>
  <component
    v-if="record"
    :is="!title ? RouterLink : 'div'"
    class="RecordLink"
    :to="`/${record.slug}`"
    :class="{
      'RecordLink--loading': isLoading,
      'RecordLink--includeChildren': includeChildren,
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

    <div
      v-if="summary"
      class="RecordLink__summary"
      :class="{ 'RecordLink__summary--truncated': truncate }"
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
      v-if="title"
      class="RecordLink__meta"
    >
      <li>
        <LinkWithFavicon
          v-if="record?.url"
          :modelValue="record.url"
        />
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
        v-if="localPredicate"
        v-model="localPredicate"
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
import PredicateSelect from '@app/components/PredicateSelect.vue';
import useRecord from '@app/composables/useRecord';
import { getPredicate, type Predicate } from '@shared/predicates';
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
} = defineProps<{
  predicate?: string;
  linkDirection?: 'incoming' | 'outgoing';
  truncate?: boolean;
  includeChildren?: boolean;
}>();

const localPredicate = ref(predicate ?? null);

const { getRecord, getRecordLinks } = useRecord();

const { data: record, isLoading } = getRecord(modelValue);

const { data: links } = getRecordLinks(modelValue, () => includeChildren);

const outgoingLinks = computed(() => record.value?.outgoingLinks ?? null);
const incomingLinks = computed(() => links.value?.incomingLinks ?? null);

const creator = computed(() => {
  if (!outgoingLinks.value) return null;

  for (const edge of outgoingLinks.value) {
    const pred = getPredicate(edge.predicate);

    if (pred.type === 'creation') {
      return edge.target;
    }
  }

  return null;
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
    .filter((link) => {
      const pred = getPredicate(link.predicate);
      return pred.type === 'description';
    })
    .map((link) => link.target);
});

const children = computed(() => {
  if (!includeChildren || !incomingLinks.value) return null;

  return incomingLinks.value
    .filter((link) => {
      const pred = getPredicate(link.predicate);
      return pred.type === 'containment';
    })
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
}

.RecordLink__header {
  display: inline-flex;
  column-gap: 6px;
  flex-wrap: wrap;
  padding-right: 24px;
  align-items: baseline;
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
  text-decoration: underline;
  text-decoration-color: var(--ui-border-accented);
  transition: text-decoration-color 0.15s ease-in-out;

  &:hover {
    text-decoration-color: currentColor;
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

.RecordLink:has(.RecordLink__title) .RecordLink__summary {
  margin: 4px 0 6px;
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
</style>
