<template>
  <div
    v-if="modelValue"
    class="RecordDetail"
    @dragenter.prevent="handleDragEnter"
    @dragover.prevent="handleDragOver"
    @dragleave.prevent="handleDragLeave"
    @drop.prevent="handleDrop"
  >
    <div
      v-if="isDraggingFile"
      class="RecordDetail__dropOverlay"
    />

    <div class="RecordDetail__badges">
      <UBadge
        v-if="modelValue.isCurated !== true"
        color="neutral"
        variant="outline"
        class="RecordDetail__badge"
        icon="i-lucide-inbox"
        label="Needs curating"
      />

      <UBadge
        color="neutral"
        variant="outline"
        class="RecordDetail__badge"
        :icon="getIconForRecordType(modelValue.type)"
      >
        {{ capitalize(modelValue.type) }}
      </UBadge>

      <UBadge
        v-if="modelValue.source && modelValue.source !== 'manual'"
        color="neutral"
        variant="outline"
        class="RecordDetail__badge"
        :icon="getIconForRecordSource(modelValue.source)"
      >
        {{ capitalize(modelValue.source) }}
      </UBadge>

      <UBadge
        color="neutral"
        variant="outline"
        class="RecordDetail__badge"
        icon="i-lucide-calendar-arrow-down"
      >
        {{ capturedAt }}
      </UBadge>

      <UBadge
        v-if="modelValue"
        color="neutral"
        variant="outline"
        class="RecordDetail__badge"
        icon="i-lucide-hash"
      >
        {{ modelValue.id }}
      </UBadge>
    </div>

    <TitleField v-model="modelValue.title" />

    <div
      v-if="parent || creator"
      class="RecordDetail__byline"
    >
      <span
        v-if="parent"
        class="RecordDetail__bylineItem"
      >
        from
        <UButton
          icon="i-lucide-workflow"
          size="sm"
          color="neutral"
          variant="link"
          class="RecordDetail__bylineButton"
          :to="`/${parent.slug}`"
        >
          <span>{{ parent.title }}</span>
        </UButton>
      </span>

      <span
        v-if="creator"
        class="RecordDetail__bylineItem"
      >
        by
        <UButton
          icon="i-lucide-user-pen"
          size="sm"
          color="neutral"
          variant="link"
          class="RecordDetail__bylineButton"
          :to="`/${creator.slug}`"
        >
          <span>{{ creator.title }}</span>
        </UButton>
      </span>

      <span
        v-if="modelValue.url"
        class="RecordDetail__bylineItem"
      >
        at
        <LinkWithFavicon
          v-if="modelValue.url"
          class="RecordDetail__linkWithFavicon"
          :modelValue="modelValue.url"
        />
      </span>
    </div>

    <EditableContent
      v-model="content"
      class="RecordDetail__content"
      placeholder="Write something about this record"
    />

    <div v-if="children && children.length > 0">
      <ul
        class="RecordDetail__children"
        :class="{
          'RecordDetail__children--singleChild': children.length === 1,
        }"
      >
        <li
          v-for="child in children"
          :key="child.id"
        >
          <RecordLink
            class="RecordDetail__recordLink shadow-xs"
            linkDirection="incoming"
            :modelValue="child.sourceId"
            :truncate="false"
            :showParent="false"
            @updatePredicate="(predicate) => handleUpdatePredicate({ link: child, predicate })"
            @deleteLink="() => handleDeleteLink({ linkId: child.id })"
          />
        </li>
      </ul>
    </div>

    <AttachmentGallery
      v-if="modelValue.media && modelValue.media.length > 0"
      v-model="modelValue.media"
      @fileUpload="(file) => emit('fileUpload', file)"
      @fileDelete="({ mediaId }) => emit('fileDelete', { mediaId })"
    />

    <CombinedFields>
      <UFormField
        aria-label="Summary"
        size="xs"
      >
        <UTextarea
          v-model.trim="summary"
          size="lg"
          placeholder="A brief summary of this record"
          variant="outline"
          :rows="1"
          autoresize
        />
      </UFormField>

      <UFieldGroup>
        <UBadge
          color="neutral"
          variant="outline"
          size="lg"
          label="URL"
          class="RecordDetail__badge"
        />

        <UInput
          v-model="url"
          class="RecordDetail__input"
          variant="outline"
          placeholder="example.com"
        >
          <template
            v-if="modelValue.url"
            #trailing
          >
            <UTooltip text="Open source URL">
              <UButton
                variant="link"
                size="sm"
                icon="i-lucide-external-link"
                aria-label="Open source URL"
                target="_blank"
                :to="modelValue.url"
              />
            </UTooltip>
          </template>
        </UInput>
      </UFieldGroup>

      <UFieldGroup v-if="createdAt">
        <UBadge
          color="neutral"
          variant="outline"
          size="lg"
          label="Published"
          class="RecordDetail__badge"
        />

        <UInput
          v-model="createdAt"
          class="RecordDetail__input"
          variant="outline"
          placeholder="May 4, 1995"
          readonly
        />
      </UFieldGroup>

      <UFieldGroup>
        <UBadge
          color="neutral"
          variant="outline"
          size="lg"
          label="Notes"
          class="RecordDetail__badge"
        />

        <UTextarea
          v-model="notes"
          class="RecordDetail__input"
          variant="outline"
          placeholder="Additional notes"
          :rows="1"
          autoresize
        />
      </UFieldGroup>
    </CombinedFields>

    <div class="RecordDetail__actions">
      <FileUploadButton @fileUpload="(file) => emit('fileUpload', file)" />

      <UButton
        color="neutral"
        icon="i-lucide-trash"
        variant="subtle"
        label="Delete record"
        size="sm"
        @click="emit('deleteRecord', modelValue.id)"
      />

      <USwitch
        v-model="modelValue.isCurated"
        label="Curated"
        size="lg"
        class="RecordDetail__curatedSwitch"
      />
    </div>

    <RecordLinks
      class="RecordDetail__links"
      :links="links"
      :relatedRecords="relatedRecords"
      :currentRecordId="modelValue?.id"
      @updatePredicate="handleUpdatePredicate"
      @deleteLink="handleDeleteLink"
      @createLink="handleCreateLink"
    />

    <section
      v-if="similarRecords && similarRecords.length > 0"
      class="RecordDetail__similar"
    >
      <h2 class="RecordDetail__similarLabel">Similar records</h2>

      <ul class="RecordDetail__similarRows">
        <li
          v-for="entry in similarRecords"
          :key="entry.record.id"
        >
          <RecordLink
            layout="row"
            :modelValue="entry.record.id"
          />
        </li>
      </ul>
    </section>

    <BrowserFrame
      v-if="modelValue.url && modelValue.type !== 'concept'"
      :key="modelValue.url"
      :url="modelValue.url"
    />
  </div>
</template>

<script setup lang="ts">
import AttachmentGallery from '@app/components/AttachmentGallery.vue';
import BrowserFrame from '@app/components/BrowserFrame.vue';
import RecordLink from '@app/components/RecordLink.vue';
import RecordLinks from '@app/components/RecordLinks.vue';
import type { GetRecordBySlugAPIResponse, LinksForRecordAPIResponse } from '@db/queries/records';
import { capitalize, formatDate } from '@shared/lib/formatting';
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import type { LinkInsert, LinkSelect } from '@db/schema';
import { isPredicateType, type Predicate, type PredicateSlug } from '@shared/types';
import { getIconForRecordSource, getIconForRecordType, nullableStringField } from '@app/utils';
import type { DbId } from '@shared/types/api';
import FileUploadButton from '@app/components/FileUploadButton.vue';
import TitleField from '@app/components/TitleField.vue';
import EditableContent from '@app/components/EditableContent.vue';
import CombinedFields from '@app/components/CombinedFields.vue';
import LinkWithFavicon from '@app/components/LinkWithFavicon.vue';
import type { FindAllRelatedRecordsAPIResponse } from '@db/queries/related-records';
import type { SimilarRecordsAPIResponse } from '@db/queries/similar-records';

const modelValue = defineModel<GetRecordBySlugAPIResponse>({ required: true });

const emit = defineEmits<{
  fileUpload: [File];
  fileDelete: [{ mediaId?: number; url?: string }];
  createLink: [{ link: LinkInsert }];
  deleteLink: [{ linkId: DbId }];
  updatePredicate: [{ link: LinkSelect; predicate: Predicate }];
  deleteRecord: [DbId];
  paste: [ClipboardEvent];
}>();

const { links, relatedRecords, similarRecords } = defineProps<{
  links?: LinksForRecordAPIResponse;
  relatedRecords?: FindAllRelatedRecordsAPIResponse;
  similarRecords?: SimilarRecordsAPIResponse;
}>();

const content = nullableStringField(modelValue, 'content');
const summary = nullableStringField(modelValue, 'summary');
const url = nullableStringField(modelValue, 'url');
const notes = nullableStringField(modelValue, 'notes');

const capturedAt = computed(() => {
  if (!modelValue.value) return null;
  return formatDate(modelValue.value.recordCreatedAt, { time: true });
});

const createdAt = computed(() => {
  if (!modelValue.value?.contentCreatedAt) return null;
  return formatDate(modelValue.value.contentCreatedAt);
});

const incomingLinks = computed(() => links?.incomingLinks ?? null);
const outgoingLinks = computed(() => links?.outgoingLinks ?? null);

const parent = computed(() => {
  if (!outgoingLinks.value) return null;

  return (
    outgoingLinks.value.find((link) => isPredicateType(link.predicate, 'containment'))?.target ??
    null
  );
});

const creator = computed(() => {
  if (!outgoingLinks.value) return null;

  return outgoingLinks.value.find((link) => link.predicate === 'created_by')?.target ?? null;
});

const children = computed(() => {
  if (!incomingLinks.value) return null;

  return incomingLinks.value.filter((link) => isPredicateType(link.predicate, 'containment'));
});

onMounted(() => {
  document.addEventListener('paste', handlePaste);
});

onBeforeUnmount(() => {
  document.removeEventListener('paste', handlePaste);
});

function handlePaste(event: ClipboardEvent) {
  emit('paste', event);
}

const isDraggingFile = ref(false);
let dragDepth = 0;

function dragHasFiles(event: DragEvent): boolean {
  const types = event.dataTransfer?.types;
  return !!types && Array.from(types).includes('Files');
}

function handleDragEnter(event: DragEvent) {
  if (!dragHasFiles(event)) return;
  dragDepth++;
  isDraggingFile.value = true;
}

function handleDragOver(event: DragEvent) {
  if (!dragHasFiles(event)) return;
  if (event.dataTransfer) event.dataTransfer.dropEffect = 'copy';
}

function handleDragLeave(event: DragEvent) {
  if (!dragHasFiles(event)) return;
  dragDepth = Math.max(0, dragDepth - 1);
  if (dragDepth === 0) isDraggingFile.value = false;
}

function handleDrop(event: DragEvent) {
  dragDepth = 0;
  isDraggingFile.value = false;
  const files = event.dataTransfer?.files;
  if (!files || files.length === 0) return;
  for (const file of Array.from(files)) {
    emit('fileUpload', file);
  }
}

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
.RecordDetail {
  position: relative;
  display: grid;
  gap: 1rem;
  max-width: 680px;
  margin: 0 auto;
}

.RecordDetail__dropOverlay {
  position: absolute;
  inset: -16px;
  z-index: 10;
  background-color: color-mix(in oklab, var(--ui-primary) 14%, transparent);
  border: 2px dashed var(--ui-primary);
  border-radius: var(--radius-xl);
  pointer-events: none;
}

.RecordDetail__badges {
  display: flex;
  gap: 6px;
  flex-wrap: wrap;
}

.RecordDetail__byline {
  display: inline-flex;
  margin-top: -12px;
  flex-wrap: wrap;
}

.RecordDetail__bylineItem {
  display: flex;
  align-items: center;
  color: var(--ui-text-muted);
  font-size: 0.8rem;
}

:deep(.RecordDetail__bylineButton) {
  max-width: 250px;
  margin-inline: -2px;

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

:deep(.RecordDetail__linkWithFavicon) {
  margin-inline: 0.75em;
}

.RecordDetail__content {
  margin-top: -8px;
  margin-inline: -10px;
}

.RecordDetail__children:not(.RecordDetail__children--singleChild) {
  columns: 300px auto;
  gap: 8px;

  & > * + * {
    margin-top: 8px;
  }
}

.RecordDetail__section {
  display: grid;
  gap: 8px;
}

.RecordDetail__badge {
  width: fit-content;

  & :deep(svg) {
    width: 12px;
    height: 12px;
    color: var(--ui-text-muted);
  }
}

.RecordDetail__input {
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

.RecordDetail__actions {
  display: flex;
  column-gap: 8px;
  row-gap: 12px;
  align-items: center;
  margin-bottom: -4px;
  flex-wrap: wrap;
}

.RecordDetail__curatedSwitch {
  margin-left: 4px;
}

.RecordDetail__links {
  margin-top: 16px;
  gap: 4px;
}

.RecordDetail__similar {
  margin-top: -1rem;
  padding: 6px 0;
  border-top: 0.5px solid var(--ui-border);
  display: grid;
  grid-template-columns: 116px 1fr;
  gap: 8px;
  align-items: start;
}

.RecordDetail__similarLabel {
  padding-top: 9px;
  position: sticky;
  /* Offset the detail scroller's 2rem top padding (less a small gap) so the
     label sticks near the pane's top edge rather than 2rem down. */
  top: calc(-2rem + 8px);
  font-size: 0.78rem;
  font-weight: 500;
  color: var(--ui-text-muted);
}

.RecordDetail__similarRows {
  display: grid;
  min-width: 0;

  li {
    min-width: 0;
  }
}

.RecordDetail__recordLink {
  break-inside: avoid;
}

/* Phones: collapse the two-column grids that assume desktop width. The 116px
 * sticky label column and the 300px child-card columns both crowd a ~390px
 * screen, so stack them into a single readable column. */
@media (max-width: 640px) {
  .RecordDetail__children:not(.RecordDetail__children--singleChild) {
    columns: 1;
  }

  .RecordDetail__similar {
    grid-template-columns: 1fr;
    gap: 4px;
  }

  .RecordDetail__similarLabel {
    position: static;
    top: auto;
    padding-top: 0;
  }
}
</style>
