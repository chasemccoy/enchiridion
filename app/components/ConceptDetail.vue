<template>
  <div
    v-if="modelValue"
    class="ConceptDetail"
  >
    <div class="ConceptDetail__header">
      <div class="ConceptDetail__titleBar">
        <TitleField
          v-model="modelValue.title"
          class="ConceptDetail__title"
          :class="{ 'ConceptDetail__title--capitalize': isSingleWord }"
        />

        <div class="ConceptDetail__headerMeta">
          <div
            v-if="linkCount > 0"
            class="ConceptDetail__linkCount"
          >
            {{ pluralize(linkCount, 'record', 'records') }}
          </div>

          <div class="ConceptDetail__actions">
            <RelationshipSelect
              :sourceRecordId="modelValue.id"
              @createLink="handleCreateLink"
            />
          </div>
        </div>
      </div>

      <div
        v-if="true === null"
        class="ConceptDetail__metadata"
      >
        <UFormField
          aria-label="Summary"
          size="xs"
          class="ConceptDetail__summary"
        >
          <UTextarea
            v-model.trim="summary"
            size="lg"
            placeholder="A brief summary of this record"
            variant="none"
            :rows="1"
            autoresize
          />
        </UFormField>

        <UFormField
          aria-label="Notes"
          size="xs"
          class="ConceptDetail__notes"
        >
          <UTextarea
            v-model="notes"
            variant="none"
            placeholder="Additional notes"
            :rows="1"
            autoresize
          />
        </UFormField>
      </div>
    </div>

    <EditableContent
      v-model="content"
      class="ConceptDetail__content"
      placeholder="Write something about this concept"
    />

    <RecordLinks
      :links="links"
      :relatedRecords="relatedRecords"
      :currentRecordId="modelValue?.id"
      :truncate="false"
      :isMultiColumn="false"
      includeChildren
      @updatePredicate="handleUpdatePredicate"
      @deleteLink="handleDeleteLink"
    />
  </div>
</template>

<script setup lang="ts">
import RelationshipSelect from '@app/components/RelationshipSelect.vue';
import RecordLinks from '@app/components/RecordLinks.vue';
import type { GetRecordBySlugAPIResponse, LinksForRecordAPIResponse } from '@db/queries/records';
import type { LinkInsert, LinkSelect } from '@db/schema';
import type { DbId } from '@shared/types/api';
import { type Predicate, type PredicateSlug } from '@shared/types';
import TitleField from '@app/components/TitleField.vue';
import EditableContent from '@app/components/EditableContent.vue';
import type { FindAllRelatedRecordsAPIResponse } from '@db/queries/related-records';
import useRecordLinks from '@app/composables/useRecordLinks';
import { computed } from 'vue';
import { nullableStringField } from '@app/utils';
import { pluralize } from '@shared/lib/formatting';

const modelValue = defineModel<GetRecordBySlugAPIResponse>({ required: true });

const emit = defineEmits<{
  fileUpload: [File];
  fileDelete: [{ mediaId?: number; url?: string }];
  createLink: [{ link: LinkInsert }];
  deleteLink: [{ linkId: DbId }];
  updatePredicate: [{ link: LinkSelect; predicate: Predicate }];
}>();

const { links, relatedRecords } = defineProps<{
  links?: LinksForRecordAPIResponse;
  relatedRecords?: FindAllRelatedRecordsAPIResponse;
}>();

const content = nullableStringField(modelValue, 'content');
const summary = nullableStringField(modelValue, 'summary');
const notes = nullableStringField(modelValue, 'notes');

// Single-word concept titles read better capitalised ("Blogging" vs "blogging");
// multi-word titles are left as the user typed them so phrases like "communal
// computing" don't get the awkward Title Case treatment.
const isSingleWord = computed(() => {
  const title = modelValue.value?.title?.trim();
  return !!title && !/\s/.test(title);
});

// Use the same composable that RecordLinks renders from, so the header's
// "X records" count always equals the number of rows shown below, including
// related_to/reference/etc. links and virtual related-record entries, and
// excluding containment links (which aren't surfaced here).
const { linksByPredicateName } = useRecordLinks(
  () => links,
  () => relatedRecords,
  () => modelValue.value?.id,
);

const linkCount = computed(() =>
  Object.values(linksByPredicateName.value).reduce((sum, group) => sum + group.length, 0),
);

function handleCreateLink(targetRecordId: DbId, predicate: PredicateSlug) {
  if (!modelValue.value) return;

  emit('createLink', {
    link: {
      sourceId: modelValue.value.id,
      targetId: targetRecordId,
      predicate,
    },
  });
}

function handleUpdatePredicate({ link, predicate }: { link: LinkSelect; predicate: Predicate }) {
  emit('updatePredicate', { link, predicate });
}

function handleDeleteLink({ linkId }: { linkId: DbId }) {
  emit('deleteLink', { linkId });
}
</script>

<style scoped>
.ConceptDetail {
  display: grid;
  gap: 1.5rem;
  max-width: 800px;
  margin: 0 auto;
}

.ConceptDetail__header {
  display: flex;
  flex-direction: column;
  gap: 1rem;
}

.ConceptDetail__titleBar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 1.5rem;
  width: 100%;
}

.ConceptDetail__title {
  text-wrap: balance;
  flex: 1 1 auto;
  min-width: 0;
}

.ConceptDetail__headerMeta {
  display: flex;
  align-items: center;
  gap: 1rem;
  flex: 0 0 auto;
}

.ConceptDetail__linkCount {
  font-size: 0.875rem;
  color: var(--ui-text-dimmed);
}

.ConceptDetail__actions {
  display: flex;
}

:deep(.ConceptDetail__title .TitleField__input) {
  font-family: var(--font-serif);
  font-weight: 400;
  font-size: 2rem;
  line-height: 1.2;
}

.ConceptDetail__title--capitalize :deep(.TitleField__input) {
  text-transform: capitalize;
}

.ConceptDetail__content {
  margin-block: -0.5rem;
  margin-inline: -12px;
}

.ConceptDetail__metadata {
  display: flex;
  flex-direction: column;
  gap: 0.75rem;
  width: 100%;
  max-width: 600px;
}

.ConceptDetail__summary,
.ConceptDetail__notes {
  text-align: center;
}

:deep(.ConceptDetail__summary textarea),
:deep(.ConceptDetail__notes textarea) {
  text-align: center;
}
</style>
