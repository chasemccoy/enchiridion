<template>
  <form
    ref="formRef"
    class="AddRecordForm"
    @submit.prevent
  >
    <TitleField
      v-model="modelValue.title"
      autofocus
    />

    <RecordTypeSelectButton
      v-if="modelValue.type"
      v-model="modelValue.type"
    />

    <MarkdownEditor
      v-model="content"
      class="AddRecordForm__content"
      placeholder="Main content of the record"
    />

    <AttachmentGallery
      v-if="files && files.length > 0"
      v-model="files"
      @fileUpload="handleFileUpload"
      @fileDelete="handleFileDelete"
    />

    <RecordMetadataSheet
      v-model:summary="summary"
      v-model:url="url"
      v-model:notes="notes"
      v-model:slug="slug"
      :published="createdAt"
      with-slug
      :style="{ '--metadata-sheet-label-width': '94px', '--metadata-sheet-gap': '10px' }"
    />

    <div class="AddRecordForm__actions">
      <RelationshipSelect @createLink="handleCreateLink" />

      <FileUploadButton @fileUpload="handleFileUpload" />

      <USwitch
        v-model="modelValue.isCurated"
        label="Curated"
        size="lg"
      />
    </div>

    <div v-if="links.length > 0">
      <ul class="AddRecordForm__links">
        <li
          v-for="link in links"
          :key="link.targetId"
        >
          <RecordLink
            :modelValue="link.targetId"
            :predicate="link.predicate"
            @updatePredicate="(predicate) => handleUpdatePredicate(link, predicate)"
            @deleteLink="() => handleDeleteLink(link.targetId)"
          />
        </li>
      </ul>
    </div>

    <UButton
      type="submit"
      size="xl"
      class="AddRecordForm__submitButton"
      color="neutral"
      :disabled="!isDirty"
      block
      @click="handleSubmit"
    >
      Save record
    </UButton>
  </form>
</template>

<script setup lang="ts">
import RecordTypeSelectButton from '@app/components/RecordTypeSelectButton.vue';
import type { RecordInsert, RecordSelect } from '@db/schema';
import { ref, useTemplateRef, watch, computed } from 'vue';
import { formatDate, slugify } from '@shared/lib/formatting';
import TitleField from '@app/components/TitleField.vue';
import FileUploadButton from '@app/components/FileUploadButton.vue';
import MarkdownEditor from '@app/components/MarkdownEditor.vue';
import type {
  NewRecordData,
  PartialLinkInsert,
  PartialMediaInsert,
} from '@app/views/AddRecordView.vue';
import AttachmentGallery from '@app/components/AttachmentGallery.vue';
import { mediaFileToDataURL, nullableStringField } from '@app/utils';
import RecordMetadataSheet from '@app/components/RecordMetadataSheet.vue';
import RelationshipSelect from '@app/components/RelationshipSelect.vue';
import type { DbId } from '@shared/types/api';
import type { Predicate, PredicateSlug } from '@shared/types';
import RecordLink from '@app/components/RecordLink.vue';

const modelValue = defineModel<RecordSelect | RecordInsert>({ required: true });

const files = defineModel<PartialMediaInsert[]>('files', { default: [] });

const links = defineModel<PartialLinkInsert[]>('links', { default: [] });

const emit = defineEmits<{
  save: [data: NewRecordData];
}>();

const content = nullableStringField(modelValue, 'content');
const summary = nullableStringField(modelValue, 'summary');
const url = nullableStringField(modelValue, 'url');
const notes = nullableStringField(modelValue, 'notes');

const formRef = useTemplateRef('formRef');

const isDirty = ref(false);

const slug = computed({
  get() {
    const { slug, title } = modelValue.value;
    if (slug && slug !== '') return slug;
    else if (title) return slugify(title);
    else return '';
  },
  set(value: string) {
    modelValue.value = {
      ...modelValue.value,
      slug: value,
    };
  },
});

const createdAt = computed(() => {
  if (!modelValue.value?.contentCreatedAt) return null;
  return formatDate(modelValue.value.contentCreatedAt);
});

watch(
  () => modelValue,
  () => {
    isDirty.value = true;
  },
  { deep: true },
);

function handleSubmit() {
  if (formRef.value?.checkValidity()) {
    emit('save', {
      record: { ...modelValue.value, slug: slug.value },
      links: links.value,
      files: files.value,
    });
  }
}

async function handleFileUpload(file: File) {
  const dataURL = await mediaFileToDataURL(file);
  if (!dataURL) return;

  const type = file.type.includes('image')
    ? 'image'
    : file.type.includes('video')
      ? 'video'
      : 'pdf';
  files.value.push({ url: dataURL, type: type, file });
}

function handleFileDelete({ url }: { url?: string }) {
  if (!url) return;
  files.value = files.value.filter((file) => file.url !== url);
}

function handleCreateLink(targetRecordId: DbId, predicate: PredicateSlug) {
  links.value.push({
    targetId: targetRecordId,
    predicate,
  });
}

function handleDeleteLink(targetId: DbId) {
  links.value = links.value.filter((link) => link.targetId !== targetId);
}

function handleUpdatePredicate(link: PartialLinkInsert, predicate: Predicate) {
  links.value = links.value.map((existing) =>
    existing.targetId === link.targetId
      ? { ...existing, predicate: predicate.slug as PredicateSlug }
      : existing,
  );
}
</script>

<style scoped>
.AddRecordForm {
  display: flex;
  flex-direction: column;
  gap: 20px;
  height: 100%;
  flex-grow: 1;
}

:deep(.AddRecordForm__submitButton) {
  margin-top: auto;
}

.AddRecordForm__content {
  width: 100%;
}

.AddRecordForm__actions {
  display: flex;
  column-gap: 8px;
  row-gap: 12px;
  align-items: center;
  margin-bottom: -4px;
  flex-wrap: wrap;
}

.AddRecordForm__links {
  li + li {
    margin-top: 16px;
  }
}
</style>
