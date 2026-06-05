<template>
  <div v-if="modelValue.length > 0">
    <ul
      class="Attachments"
      :class="{ 'Attachments--isEmpty': modelValue.length === 0 }"
    >
      <li
        v-for="(attachment, index) in modelValue"
        :key="attachment.id"
        class="Attachments__item"
        :class="{ 'Attachments__item--clickable': !readonly }"
        @click="openLightbox(index)"
      >
        <img
          v-if="attachment.type === 'image'"
          loading="lazy"
          decoding="async"
          :src="getSrcForAttachmentUrl(attachment.url)"
          :width="attachment.width ?? undefined"
          :height="attachment.height ?? undefined"
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
          @click.stop="emit('fileDelete', { mediaId: attachment.id, url: attachment.url })"
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

    <UModal
      v-model:open="isModalOpen"
      :ui="{ content: 'max-w-5xl' }"
    >
      <template #content>
        <div
          v-if="currentAttachment"
          class="Lightbox"
        >
          <div class="Lightbox__header">
            <div class="Lightbox__counter">
              {{ currentAttachmentIndex + 1 }} of {{ modelValue.length }}
            </div>
            <UButton
              icon="i-lucide-x"
              variant="ghost"
              color="neutral"
              @click="closeLightbox"
            />
          </div>

          <div class="Lightbox__content">
            <img
              v-if="currentAttachment.type === 'image'"
              class="Lightbox__image"
              decoding="async"
              :src="getSrcForAttachmentUrl(currentAttachment.url)"
              :alt="currentAttachment.altText || ''"
              :width="currentAttachment.width ?? undefined"
              :height="currentAttachment.height ?? undefined"
            />
            <video
              v-else-if="currentAttachment.type === 'video'"
              class="Lightbox__video"
              :src="getSrcForAttachmentUrl(currentAttachment.url)"
              controls
              autoplay
            />
            <iframe
              v-else-if="currentAttachment.url.includes('.pdf')"
              class="Lightbox__pdf"
              :src="getSrcForAttachmentUrl(currentAttachment.url)"
            />
          </div>

          <div
            v-if="modelValue.length > 1"
            class="Lightbox__nav"
          >
            <UButton
              icon="i-lucide-chevron-left"
              variant="outline"
              color="neutral"
              @click="previousAttachment"
            />
            <UButton
              icon="i-lucide-chevron-right"
              variant="outline"
              color="neutral"
              @click="nextAttachment"
            />
          </div>

          <div
            v-if="currentAttachment.altText"
            class="Lightbox__metadata"
          >
            {{ currentAttachment.altText }}
          </div>
        </div>
      </template>
    </UModal>
  </div>
</template>

<script setup lang="ts">
import useApiClient from '@app/composables/useApiClient';
import type { PartialMediaInsert } from '@app/views/AddRecordView.vue';
import type { MediaInsert } from '@db/schema';
import { SUPPORTED_MEDIA_TYPES } from '@shared/types/api';
import { useTemplateRef, computed, ref, onMounted, onUnmounted } from 'vue';

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

// Lightbox state
const isModalOpen = ref(false);
const currentAttachmentIndex = ref(0);

const currentAttachment = computed(() => {
  return modelValue.value[currentAttachmentIndex.value];
});

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

function openLightbox(index: number) {
  currentAttachmentIndex.value = index;
  isModalOpen.value = true;
}

function closeLightbox() {
  isModalOpen.value = false;
}

function nextAttachment() {
  currentAttachmentIndex.value = (currentAttachmentIndex.value + 1) % modelValue.value.length;
}

function previousAttachment() {
  currentAttachmentIndex.value =
    (currentAttachmentIndex.value - 1 + modelValue.value.length) % modelValue.value.length;
}

function handleKeydown(event: KeyboardEvent) {
  if (!isModalOpen.value) return;

  if (event.key === 'ArrowRight') {
    event.preventDefault();
    nextAttachment();
  } else if (event.key === 'ArrowLeft') {
    event.preventDefault();
    previousAttachment();
  } else if (event.key === 'Escape') {
    event.preventDefault();
    closeLightbox();
  }
}

onMounted(() => {
  window.addEventListener('keydown', handleKeydown);
});

onUnmounted(() => {
  window.removeEventListener('keydown', handleKeydown);
});
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

.Attachments__item--clickable {
  cursor: pointer;
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

.Lightbox {
  display: flex;
  flex-direction: column;
  gap: 1rem;
  padding: 1rem;
}

.Lightbox__header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding-bottom: 0.5rem;
  border-bottom: 1px solid var(--ui-border);
}

.Lightbox__counter {
  font-size: 0.875rem;
  color: var(--ui-text-dimmed);
}

.Lightbox__content {
  display: flex;
  justify-content: center;
  align-items: center;
  min-height: 400px;
  max-height: 70vh;
}

.Lightbox__image,
.Lightbox__video {
  max-width: 100%;
  max-height: 70vh;
  object-fit: contain;
  border-radius: var(--radius-lg);
}

.Lightbox__pdf {
  width: 100%;
  height: 70vh;
  border: none;
  border-radius: var(--radius-lg);
}

.Lightbox__nav {
  display: flex;
  justify-content: center;
  gap: 1rem;
  padding-top: 0.5rem;
}

.Lightbox__metadata {
  text-align: center;
  font-size: 0.875rem;
  color: var(--ui-text-dimmed);
  padding-top: 0.5rem;
  border-top: 1px solid var(--ui-border);
}
</style>
