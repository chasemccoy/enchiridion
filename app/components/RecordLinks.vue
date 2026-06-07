<template>
  <!-- Cards variant: the prior grouped-panel layout — one elevated section per
       predicate, each holding bordered RecordLink cards. Used on concept pages. -->
  <div
    v-if="variant === 'cards'"
    v-show="hasGroups"
    class="RecordLinks RecordLinks--cards"
    :class="{
      'RecordLinks--singleSection': groupCount === 1,
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
            v-if="preloadedFor(linkData)"
            class="RecordLinks__recordLink shadow-xxs"
            :modelValue="
              linkData.direction === 'outgoing' ? linkData.link.targetId : linkData.link.sourceId
            "
            :preloaded="preloadedFor(linkData)"
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

  <!-- Grouped variant: label-column + compact rows under a "Linked records"
       header. Used on record pages. -->
  <section
    v-else-if="hasGroups || currentRecordId"
    class="RecordLinks RecordLinks--grouped"
  >
    <header class="RecordLinks__head">
      <h2 class="RecordLinks__title">Linked records</h2>
      <RelationshipSelect
        v-if="currentRecordId"
        variant="ghost"
        size="sm"
        :sourceRecordId="currentRecordId"
        @createLink="handleCreateLink"
      />
    </header>

    <div
      v-if="hasGroups"
      class="RecordLinks__groups"
    >
      <div
        v-for="(linksForType, predicateName) in linksByPredicateName"
        :key="predicateName"
        class="RecordLinks__group"
      >
        <div class="RecordLinks__label">
          <span class="RecordLinks__labelText">{{ capitalize(String(predicateName)) }}</span>
        </div>

        <ul class="RecordLinks__rows">
          <li
            v-for="linkData in linksForType"
            :key="linkData.link.id"
          >
            <RecordLink
              v-if="preloadedFor(linkData)"
              layout="row"
              :modelValue="
                linkData.direction === 'outgoing' ? linkData.link.targetId : linkData.link.sourceId
              "
              :preloaded="preloadedFor(linkData)"
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
  </section>
</template>

<script setup lang="ts">
import RecordLink from '@app/components/RecordLink.vue';
import RelationshipSelect from '@app/components/RelationshipSelect.vue';
import type { LinksForRecordAPIResponse, ListRecordsAPIResponse } from '@db/queries/records';
import type { FindAllRelatedRecordsAPIResponse } from '@db/queries/related-records';
import { capitalize } from '@shared/lib/formatting';
import type { LinkSelect } from '@db/schema';
import type { DbId } from '@shared/types/api';
import type { Predicate, PredicateSlug } from '@shared/types';
import useRecordLinks from '@app/composables/useRecordLinks';
import type { LinkWithDirection, VirtualLink } from '@app/composables/useRecordLinks';
import useRecords from '@app/composables/useRecords';
import { computed } from 'vue';

const emit = defineEmits<{
  updatePredicate: [{ link: LinkSelect; predicate: Predicate }];
  deleteLink: [{ linkId: DbId }];
  createLink: [targetRecordId: DbId, predicate: PredicateSlug];
}>();

const {
  links,
  relatedRecords,
  currentRecordId,
  truncate,
  includeChildren = false,
  variant = 'grouped',
  isMultiColumn = true,
} = defineProps<{
  links?: LinksForRecordAPIResponse;
  relatedRecords?: FindAllRelatedRecordsAPIResponse;
  currentRecordId?: number;
  truncate?: boolean;
  includeChildren?: boolean;
  /**
   * `grouped` (default) is the label-column + compact-rows layout under a
   * "Linked records" header, used on record detail pages. `cards` is the prior
   * layout — one elevated panel per predicate holding bordered RecordLink
   * cards — kept for concept detail pages.
   */
  variant?: 'grouped' | 'cards';
  /** Cards variant only: flow the predicate sections into CSS columns. */
  isMultiColumn?: boolean;
}>();

const { linksByPredicateName } = useRecordLinks(
  () => links,
  () => relatedRecords,
  () => currentRecordId,
);

const hasGroups = computed(() => Object.keys(linksByPredicateName.value).length > 0);
const groupCount = computed(() => Object.keys(linksByPredicateName.value).length);

// The linked record a row points at (target for outgoing edges, source for
// incoming).
function linkedRecordId(linkData: LinkWithDirection): number {
  return linkData.direction === 'outgoing' ? linkData.link.targetId : linkData.link.sourceId;
}

// Batch-load every linked record's full card data in ONE query instead of each
// RecordLink fetching its own /record/:id. A hub concept ("article", 225 links)
// went from ~450 requests to one. The data is then present up front, so rows
// render (and can be measured) without per-row fetches.
const linkedRecordIds = computed(() => {
  const ids = new Set<number>();
  for (const group of Object.values(linksByPredicateName.value)) {
    for (const linkData of group) ids.add(linkedRecordId(linkData));
  }
  return [...ids];
});

const recordsInput = computed(() => ({
  filters: { ids: linkedRecordIds.value },
  limit: Math.max(1, linkedRecordIds.value.length),
}));
const { data: preloadedRecords } = useRecords(recordsInput);

const recordsById = computed(() => {
  const map = new Map<number, ListRecordsAPIResponse[number]>();
  for (const record of preloadedRecords.value ?? []) map.set(record.id, record);
  return map;
});

function preloadedFor(linkData: LinkWithDirection): ListRecordsAPIResponse[number] | undefined {
  return recordsById.value.get(linkedRecordId(linkData));
}

function handleUpdatePredicate(link: LinkSelect | VirtualLink, predicate: Predicate) {
  emit('updatePredicate', {
    link: link as LinkSelect,
    predicate: predicate,
  });
}

function handleDeleteLink(linkId: DbId) {
  emit('deleteLink', { linkId });
}

function handleCreateLink(targetRecordId: DbId, predicate: PredicateSlug) {
  emit('createLink', targetRecordId, predicate);
}
</script>

<style scoped>
/* Grouped variant ------------------------------------------------------- */
.RecordLinks--grouped {
  display: grid;
  gap: 10px;
  padding-top: 16px;
}

.RecordLinks__head {
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 12px;
}

.RecordLinks__title {
  font-size: 1rem;
  font-weight: 600;
}

.RecordLinks__groups {
  display: grid;
}

/* Each predicate is a row: a sticky label column on the left, the matching
   records stacked on the right. Faint rules separate the groups. */
.RecordLinks__group {
  display: grid;
  grid-template-columns: 116px 1fr;
  gap: 8px;
  align-items: start;
  padding: 6px 0;
  border-top: 0.5px solid var(--ui-border);
}

.RecordLinks__group:first-child {
  border-top: 0;
}

.RecordLinks__label {
  display: inline-flex;
  align-items: baseline;
  gap: 6px;
  padding-top: 9px;
  position: sticky;
  /* The detail scroller has 2rem top padding, so a top of 0 would stick the
     label 2rem down — letting rows scroll above it. Offset that padding (less a
     small gap) so the label sticks near the pane's top edge, above the rows. */
  top: calc(-2rem + 8px);
}

.RecordLinks__labelText {
  font-size: 0.78rem;
  font-weight: 500;
  color: var(--ui-text-muted);
}

.RecordLinks__rows {
  display: grid;
  min-width: 0;

  li {
    min-width: 0;
  }
}

/* Cards variant --------------------------------------------------------- */
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

.RecordLinks__list .RecordLinks__recordLink {
  break-inside: avoid;
  border-radius: calc(var(--radius-xl) - 2px);
}

/* Phones: stack both variants into a single column. The grouped variant's 116px
 * sticky label column eats ~30% of a 390px screen, and the 300px CSS columns in
 * the cards variant force tracks wider than the viewport. */
@media (max-width: 768px) {
  .RecordLinks--grouped .RecordLinks__group {
    grid-template-columns: 1fr;
    gap: 2px;
  }

  .RecordLinks__label {
    position: static;
    top: auto;
    padding-top: 4px;
  }

  .RecordLinks--isMultiColumn:not(.RecordLinks--singleSection),
  .RecordLinks__list {
    columns: 1;
  }
}
</style>
