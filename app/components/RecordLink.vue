<template>
  <div
    class="RecordLink"
    :class="{ 'RecordLink--loading': isLoading }"
  >
    <div v-if="isError">Error: {{ error }}</div>

    <div class="RecordLink__header">
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
    >
      {{ summary }}
    </div>

    <div class="RecordLink__meta">
      <LinkWithFavicon
        v-if="record?.url"
        :modelValue="record.url"
      />
    </div>

    <div class="RecordLink__actions">
      <PredicateSelect
        v-if="localPredicate"
        v-model="localPredicate.id"
        :linkDirection="linkDirection"
        @select:predicate="handleSelectPredicate"
        @delete:link="handleDeleteLink"
      />
    </div>
  </div>
</template>

<script setup lang="ts">
import LinkWithFavicon from '@app/components/LinkWithFavicon.vue';
import PredicateSelect from '@app/components/PredicateSelect.vue';
import usePredicates from '@app/composables/usePredicates';
import useRecord from '@app/composables/useRecord';
import type { PredicateSelect as Predicate } from '@db/schema';
import type { DbId } from '@shared/types/api';
import { computed, ref, toRaw } from 'vue';
import { RouterLink } from 'vue-router';

const modelValue = defineModel<DbId>({ required: true });

const emit = defineEmits<{
  updatePredicate: [Predicate];
  deleteLink: [];
}>();

const { predicate, linkDirection = 'outgoing' } = defineProps<{
  predicate?: Predicate;
  linkDirection?: 'incoming' | 'outgoing';
}>();

const localPredicate = ref(structuredClone(toRaw(predicate)));

const { getRecord } = useRecord();
const { getPredicates } = usePredicates();

const { data: record, error, isError, isLoading } = getRecord(modelValue);

const { data: predicates } = getPredicates();

const outgoingLinks = computed(() => record.value?.outgoingLinks ?? null);

const predicateMap = computed(() => {
  return Object.fromEntries((predicates.value ?? []).map((p) => [p.id, p]));
});

const outgoingLinksById = computed(() => {
  if (!outgoingLinks.value) return null;

  return Object.fromEntries(
    outgoingLinks.value?.map((link) => [link.target.id, link.target]) ?? [],
  );
});

const creator = computed(() => {
  if (!outgoingLinks.value || !predicateMap.value || !outgoingLinksById.value) return null;

  for (const edge of outgoingLinks.value) {
    const predicate = predicateMap.value[edge.predicateId];

    if (predicate && predicate.type === 'creation') {
      return outgoingLinksById.value[edge.target.id];
    }
  }

  return null;
});

const parent = computed(() => {
  if (!outgoingLinks.value || !predicateMap.value || !outgoingLinksById.value) return null;

  for (const edge of outgoingLinks.value) {
    const predicate = predicateMap.value[edge.predicateId];

    if (predicate && predicate.type === 'containment') {
      return outgoingLinksById.value[edge.target.id];
    }
  }

  return null;
});

const title = computed(() => {
  if (record.value?.title) {
    return record.value.title;
  }

  if (parent.value && parent.value.title) {
    return `↳ ${parent.value.title}`;
  }

  if (creator.value && creator.value.title) {
    return creator.value.title;
  }

  return null;
});

const summary = computed(() => {
  if (record.value?.summary) {
    return record.value.summary;
  }

  if (record.value?.content) {
    return record.value.content;
  }

  return null;
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
  position: relative;
}

.RecordLink__header {
  display: inline-flex;
  column-gap: 6px;
  flex-wrap: wrap;
  padding-right: 24px;
}

.RecordLink__title,
.RecordLink__creator {
  font-size: 0.875rem;
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
  display: flex;
  align-items: center;
  font-size: 0.75rem;

  :deep(svg) {
    width: 14px;
    height: 14px;
  }
}

.RecordLink__icon {
  color: var(--ui-text-dimmed);
}

.RecordLink__summary {
  font-size: 0.875rem;
  line-height: 1.25rem;
  color: var(--ui-text-muted);
  display: -webkit-box;
  -webkit-box-orient: vertical;
  -webkit-line-clamp: 5;
  line-clamp: 5;
  overflow: hidden;
  margin: 6px 0 4px;
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
</style>
