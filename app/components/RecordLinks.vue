<template>
  <div
    v-if="linksByPredicateName && Object.keys(linksByPredicateName).length > 0"
    class="RecordLinks"
    :class="{
      'RecordLinks--singleSection': Object.keys(linksByPredicateName).length === 1,
      'RecordLinks--isMultiColumn': isMultiColumn,
    }"
  >
    <div
      v-for="(linksForType, predicateName) in linksByPredicateName"
      :key="predicateName"
      class="RecordLinks__section"
    >
      <h2 class="RecordLinks__sectionTitle">
        {{ capitalize(String(predicateName)) }}
        <template v-if="linksForType.length > 3">({{ linksForType.length }})</template>
      </h2>

      <ul class="RecordLinks__list">
        <li
          v-for="linkData in linksForType"
          :key="linkData.link.id"
        >
          <RecordLink
            class="RecordLinks__recordLink shadow-xxs"
            :modelValue="
              linkData.direction === 'outgoing' ? linkData.link.targetId : linkData.link.sourceId
            "
            :truncate="truncate"
            :predicate="linkData.link.predicate"
            :linkDirection="linkData.direction"
            :includeChildren="includeChildren"
            @updatePredicate="
              (predicate) =>
                linkData.link ? handleUpdatePredicate(linkData.link, predicate) : undefined
            "
            @deleteLink="() => handleDeleteLink(linkData.link.id)"
          />
        </li>
      </ul>
    </div>
  </div>
</template>

<script setup lang="ts">
import RecordLink from '@app/components/RecordLink.vue';
import type { LinksForRecordAPIResponse } from '@db/queries/records';
import type { FindAllRelatedRecordsAPIResponse } from '@db/queries/related-records';
import { capitalize } from '@shared/lib/formatting';
import type { LinkSelect } from '@db/schema';
import type { Predicate } from '@shared/predicates';
import type { DbId } from '@shared/types/api';
import useRecordLinks from '@app/composables/useRecordLinks';
import type { VirtualLink } from '@app/composables/useRecordLinks';

const emit = defineEmits<{
  updatePredicate: [{ link: LinkSelect; predicate: Predicate }];
  deleteLink: [{ linkId: DbId }];
}>();

const {
  isMultiColumn = true,
  links,
  relatedRecords,
  currentRecordId,
  truncate,
  includeChildren = false,
} = defineProps<{
  links?: LinksForRecordAPIResponse;
  relatedRecords?: FindAllRelatedRecordsAPIResponse;
  currentRecordId?: number;
  truncate?: boolean;
  isMultiColumn?: boolean;
  includeChildren?: boolean;
}>();

const { linksByPredicateName } = useRecordLinks(
  () => links,
  () => relatedRecords,
  () => currentRecordId,
);

function handleUpdatePredicate(link: LinkSelect | VirtualLink, predicate: Predicate) {
  emit('updatePredicate', {
    link: link as LinkSelect,
    predicate: predicate,
  });
}

function handleDeleteLink(linkId: DbId) {
  emit('deleteLink', { linkId });
}
</script>

<style scoped>
.RecordLinks--isMultiColumn:not(.RecordLinks--singleSection) {
  columns: 300px auto;
}

.RecordLinks__section {
  border-radius: var(--radius-xl);
  padding: 2px;
  break-inside: avoid;
  background-color: var(--ui-bg-elevated);

  & + & {
    margin-top: 16px;
  }
}

.RecordLinks__sectionTitle {
  font-size: 0.85rem;
  display: flex;
  align-items: center;
  gap: 0.25rem;
  color: var(--ui-text-dimmed);
  font-weight: 500;
  padding: 4px 12px 6px;

  & :deep(svg) {
    width: 12px;
    height: 12px;
  }
}

.RecordLinks__list {
  column-gap: 2px;
  columns: 300px auto;

  li + li {
    margin-top: 2px;
  }
}

.RecordLinks__recordLink {
  break-inside: avoid;
}
</style>
