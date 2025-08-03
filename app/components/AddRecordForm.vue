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

    <UFormField
      aria-label="Content"
      size="xs"
      class="AddRecordForm__content"
    >
      <UTextarea
        v-model.trim="modelValue.content"
        size="xl"
        placeholder="Main content of the record"
        variant="none"
        :rows="1"
        autoresize
      />
    </UFormField>

    <AttachmentGallery
      v-if="files && files.length > 0"
      v-model="files"
      @fileUpload="handleFileUpload"
      @fileDelete="handleFileDelete"
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

    <CombinedFields>
      <UFormField
        aria-label="Summary"
        size="xs"
      >
        <UTextarea
          v-model.trim="modelValue.summary"
          size="lg"
          placeholder="A brief summary of this record"
          variant="outline"
          :rows="1"
          autoresize
        />
      </UFormField>

      <SlugField v-model="slug" />

      <UButtonGroup>
        <UBadge
          color="neutral"
          variant="outline"
          size="lg"
          label="URL"
          class="AddRecordForm__badge"
        />

        <UInput
          v-model="modelValue.url"
          variant="outline"
          placeholder="https://example.org"
        />
      </UButtonGroup>

      <UButtonGroup v-if="createdAt">
        <UBadge
          color="neutral"
          variant="outline"
          size="lg"
          label="Published"
          class="AddRecordForm__badge"
        />

        <UInput
          v-model="createdAt"
          variant="outline"
          placeholder="May 4, 1995"
          readonly
        />
      </UButtonGroup>

      <UButtonGroup>
        <UBadge
          color="neutral"
          variant="outline"
          size="lg"
          label="Notes"
          class="AddRecordForm__badge"
        />

        <UTextarea
          v-model="modelValue.notes"
          variant="outline"
          placeholder="Additional notes"
          :rows="1"
          autoresize
        />
      </UButtonGroup>
    </CombinedFields>

    <div v-if="links.length > 0 && predicates">
      <ul class="AddRecordForm__links">
        <li
          v-for="link in links"
          :key="link.id"
        >
          <RecordLink
            :modelValue="link.targetId"
            :predicate="getPredicateForLink(link)"
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
import type { PredicateSelect, RecordInsert, RecordSelect } from '@db/schema';
import { computed, ref, useTemplateRef, watch } from 'vue';
import SlugField from '@app/components/SlugField.vue';
import { formatDate, slugify } from '@shared/lib/formatting';
import TitleField from '@app/components/TitleField.vue';
import FileUploadButton from '@app/components/FileUploadButton.vue';
import type {
  NewRecordData,
  PartialLinkInsert,
  PartialMediaInsert,
} from '@app/views/AddRecordView.vue';
import AttachmentGallery from '@app/components/AttachmentGallery.vue';
import { mediaFileToDataURL } from '@app/utils';
import CombinedFields from '@app/components/CombinedFields.vue';
import RelationshipSelect from '@app/components/RelationshipSelect.vue';
import type { DbId } from '@shared/types/api';
import RecordLink from '@app/components/RecordLink.vue';
import type { GetPredicatesAPIResponse } from '@db/queries/links';

const modelValue = defineModel<RecordSelect | RecordInsert>({ required: true });

const files = defineModel<PartialMediaInsert[]>('files', { default: [] });

const links = defineModel<PartialLinkInsert[]>('links', { default: [] });

const emit = defineEmits<{
  save: [data: NewRecordData];
}>();

const { predicates } = defineProps<{
  predicates?: GetPredicatesAPIResponse;
}>();

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

function getPredicateForLink(link: PartialLinkInsert) {
  return predicates?.find((predicate) => predicate.id === link.predicateId);
}

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

function handleCreateLink(targetRecordId: DbId, predicateId: DbId) {
  links.value.push({
    targetId: targetRecordId,
    predicateId,
  });
}

function handleDeleteLink(targetId: DbId) {
  links.value = links.value.filter((link) => link.targetId !== targetId);
}

function handleUpdatePredicate(link: PartialLinkInsert, predicate: PredicateSelect) {
  links.value = links.value.map((link) =>
    link.targetId === link.targetId ? { ...link, predicateId: predicate.id } : link,
  );
}
</script>

<style scoped>
.AddRecordForm {
  display: flex;
  flex-direction: column;
  gap: 20px;
  --combinedFieldMinBadgeWidth: 64px;
}

:deep(.AddRecordForm__submitButton) {
  margin-top: 24px;
}

.AddRecordForm__content {
  margin-inline: -12px;
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
