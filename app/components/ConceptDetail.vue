<template>
  <div
    v-if="modelValue"
    class="ConceptDetail"
  >
    <div class="ConceptDetail__header">
      <div class="ConceptDetail__titleBar">
        <div
          v-if="linkCount > 0"
          class="ConceptDetail__linkCount"
        >
          {{ pluralize(linkCount, 'record', 'records') }}
        </div>

        <TitleField
          v-model="modelValue.title"
          class="ConceptDetail__title"
          :isFlush="false"
        />

        <div class="ConceptDetail__actions">
          <RelationshipSelect
            :sourceRecordId="modelValue.id"
            @createLink="handleCreateLink"
          />
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
import type { LinkInsert, LinkSelect, PredicateSelect } from '@db/schema';
import type { DbId } from '@shared/types/api';
import TitleField from '@app/components/TitleField.vue';
import type { FindAllRelatedRecordsAPIResponse } from '@db/queries/related-records';
import { computed } from 'vue';
import { nullableStringField } from '@app/utils';
import { pluralize } from '@shared/lib/formatting';

const modelValue = defineModel<GetRecordBySlugAPIResponse>({ required: true });

const emit = defineEmits<{
  fileUpload: [File];
  fileDelete: [{ mediaId?: number; url?: string }];
  createLink: [{ link: LinkInsert }];
  deleteLink: [{ linkId: DbId }];
  updatePredicate: [{ link: LinkSelect; predicate: PredicateSelect }];
}>();

const { links, relatedRecords } = defineProps<{
  links?: LinksForRecordAPIResponse;
  relatedRecords?: FindAllRelatedRecordsAPIResponse;
}>();

const summary = nullableStringField(modelValue, 'summary');
const notes = nullableStringField(modelValue, 'notes');

const linkCount = computed(() => {
  if (!links) return 0;

  const outgoingDescriptionLinks =
    links.outgoingLinks?.filter((link) => link.predicate.type === 'description').length ?? 0;

  const incomingDescriptionLinks =
    links.incomingLinks?.filter((link) => link.predicate.type === 'description').length ?? 0;

  return outgoingDescriptionLinks + incomingDescriptionLinks;
});

function handleCreateLink(targetRecordId: DbId, predicateId: DbId) {
  if (!modelValue.value) return;

  emit('createLink', {
    link: {
      sourceId: modelValue.value.id,
      targetId: targetRecordId,
      predicateId,
    },
  });
}

function handleUpdatePredicate({
  link,
  predicate,
}: {
  link: LinkSelect;
  predicate: PredicateSelect;
}) {
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
  align-items: center;
  text-align: center;
  gap: 1rem;
}

.ConceptDetail__titleBar {
  display: grid;
  align-items: baseline;
  grid-template-columns: 1fr 60% 1fr;
  width: 100%;
}

.ConceptDetail__title {
  text-align: center;
  text-wrap: balance;
}

.ConceptDetail__linkCount {
  justify-self: start;
  font-size: 0.875rem;
  color: var(--ui-text-dimmed);
}

.ConceptDetail__actions {
  display: flex;
  justify-content: center;
  justify-self: end;
}

.ConceptDetail__linkCount,
.ConceptDetail__actions {
  position: relative;
  top: -2px;
}

.ConceptDetail__linkCount {
  top: -4px;
}

:deep(.ConceptDetail__title .TitleField__input) {
  text-align: center;
  text-transform: capitalize;
  font-family: var(--font-serif);
  font-weight: bold;
  font-size: 2rem;
  line-height: 1.2;
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
