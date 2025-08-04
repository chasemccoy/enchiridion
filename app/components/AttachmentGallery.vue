<template>
  <div v-if="modelValue.length > 0">
    <ul
      class="Attachments"
      :class="{ 'Attachments--isEmpty': modelValue.length === 0 }"
    >
      <li
        v-for="attachment in modelValue"
        :key="attachment.id"
        class="Attachments__item"
      >
        <img
          v-if="attachment.type === 'image'"
          :src="getSrcForAttachmentUrl(attachment.url)"
        />
        <video
          v-else-if="attachment.type === 'video'"
          :src="getSrcForAttachmentUrl(attachment.url)"
          autoplay
          muted
          playsinline
          loop
        />
        <div v-else-if="attachment.url.includes('.pdf')">PDF</div>

        <UButton
          v-if="!readonly"
          variant="outline"
          color="neutral"
          icon="i-lucide-trash"
          size="md"
          class="justify-center Attachments__itemDeleteButton"
          @click="emit('fileDelete', { mediaId: attachment.id, url: attachment.url })"
        />
      </li>

      <li v-if="!readonly && modelValue.length !== 0">
        <div class="Attachments__fileUpload">
          <input
            ref="fileInput"
            type="file"
            class="Attachments__fileInput"
            :accept="acceptedFileTypes"
            multiple
            @change="handleFileSelect"
          />
          <UButton
            color="neutral"
            class="justify-center Attachments__fileUploadButton"
            icon="i-lucide-upload"
            variant="outline"
            size="lg"
            @click="triggerFileSelect"
          />
        </div>
      </li>
    </ul>
  </div>
</template>

<script setup lang="ts">
import useApiClient from '@app/composables/useApiClient';
import type { PartialMediaInsert } from '@app/views/AddRecordView.vue';
import type { MediaInsert } from '@db/schema';
import { SUPPORTED_MEDIA_TYPES } from '@shared/types/api';
import { useTemplateRef } from 'vue';

const modelValue = defineModel<MediaInsert[] | PartialMediaInsert[]>({ required: true });

const emit = defineEmits<{
  fileUpload: [File];
  fileDelete: [{ mediaId?: number; url?: string }];
}>();

const { readonly = false } = defineProps<{
  readonly?: boolean;
}>();

const fileInput = useTemplateRef('fileInput');

const { backendBaseUrl } = useApiClient();
const acceptedFileTypes = SUPPORTED_MEDIA_TYPES.join(',');

function getSrcForAttachmentUrl(url: string) {
  if (url.startsWith('data:')) {
    return url;
  }
  return `${backendBaseUrl}${url}`;
}

function triggerFileSelect() {
  fileInput.value?.click();
}

function handleFileSelect(event: Event) {
  const target = event.target as HTMLInputElement;
  const files = target.files;

  if (files && files.length > 0) {
    for (const file of Array.from(files)) {
      emit('fileUpload', file);
    }

    target.value = '';
  }
}
</script>

<style scoped>
.Attachments {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(min(120px, 100%), 1fr));
  gap: 8px;
}

.Attachments__item {
  position: relative;
  box-shadow: inset 0 0 0 1px var(--ui-border-muted);
  border-radius: var(--radius-lg);
  overflow: hidden;
  padding: 1px;

  img,
  video {
    object-fit: cover;
    aspect-ratio: 1 / 1;
    border-radius: var(--radius-lg);
  }
}

:deep(.Attachments__itemDeleteButton) {
  opacity: 0;
  position: absolute;
  top: 8px;
  right: 8px;
  transition: opacity 0.15s ease-in-out;
  padding: 8px;

  .Attachments__item:hover & {
    opacity: 1;
  }

  :deep(svg) {
    width: 16px;
    height: 16px;
  }
}

:deep(.Attachments__fileUploadButton) {
  background-color: transparent;
  box-shadow: none;
  color: var(--ui-text-dimmed);
  border: 1px dashed var(--ui-border);

  &:hover {
    background-color: var(--ui-bg);
    background-color: var(--ui-bg-elevated);
  }
}

.Attachments:not(.Attachments--isEmpty) .Attachments__fileUpload {
  display: grid;
  gap: 0.5rem;
  height: 100%;
  aspect-ratio: 1 / 1;
}

.Attachments__fileInput {
  display: none;
}
</style>
