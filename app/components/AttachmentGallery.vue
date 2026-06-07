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
      :ui="{
        content:
          'w-fit max-w-[96vw] p-0 bg-transparent shadow-none ring-0 rounded-none overflow-visible divide-y-0',
        overlay: 'bg-black/80',
      }"
    >
      <template #content>
        <div
          v-if="currentAttachment"
          class="Lightbox"
        >
          <button
            type="button"
            class="Lightbox__btn Lightbox__close"
            aria-label="Close"
            @click="closeLightbox"
          >
            <UIcon name="i-lucide-x" />
          </button>

          <button
            v-if="modelValue.length > 1"
            type="button"
            class="Lightbox__btn Lightbox__nav Lightbox__nav--prev"
            aria-label="Previous"
            @click="previousAttachment"
          >
            <UIcon name="i-lucide-chevron-left" />
          </button>
          <button
            v-if="modelValue.length > 1"
            type="button"
            class="Lightbox__btn Lightbox__nav Lightbox__nav--next"
            aria-label="Next"
            @click="nextAttachment"
          >
            <UIcon name="i-lucide-chevron-right" />
          </button>

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
            v-if="modelValue.length > 1 || currentAttachment.altText"
            class="Lightbox__caption"
          >
            <span
              v-if="modelValue.length > 1"
              class="Lightbox__counter"
            >
              {{ currentAttachmentIndex + 1 }} / {{ modelValue.length }}
            </span>
            <span
              v-if="currentAttachment.altText"
              class="Lightbox__alt"
            >
              {{ currentAttachment.altText }}
            </span>
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

/* The UModal content is w-fit + overflow-visible, so the panel hugs the media
   with no surrounding dialog chrome. The controls float in the dark margin just
   outside the image. */
.Lightbox {
  position: relative;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 12px;
}

.Lightbox__content {
  display: flex;
}

.Lightbox__image,
.Lightbox__video {
  display: block;
  max-width: calc(100vw - 140px);
  max-height: 86vh;
  object-fit: contain;
  border-radius: var(--radius-lg);
  box-shadow: 0 12px 48px rgba(0, 0, 0, 0.45);
}

.Lightbox__pdf {
  width: 80vw;
  height: 86vh;
  border: none;
  border-radius: var(--radius-lg);
  background: var(--ui-bg);
}

/* Floating translucent controls so nothing competes with the image. */
.Lightbox__btn {
  position: absolute;
  z-index: 2;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 36px;
  height: 36px;
  border: 0;
  border-radius: 9999px;
  background: rgba(0, 0, 0, 0.45);
  color: #fff;
  font-size: 18px;
  cursor: pointer;
  backdrop-filter: blur(4px);
  transition: background 0.12s ease;
}

.Lightbox__btn:hover {
  background: rgba(0, 0, 0, 0.7);
}

.Lightbox__close {
  top: 0;
  right: -44px;
}

.Lightbox__nav {
  top: 50%;
  transform: translateY(-50%);
}

.Lightbox__nav--prev {
  left: -44px;
}

.Lightbox__nav--next {
  right: -44px;
}

.Lightbox__caption {
  display: inline-flex;
  align-items: center;
  gap: 10px;
  max-width: 100%;
  font-size: 0.8rem;
  color: rgba(255, 255, 255, 0.78);
  text-align: center;
}

.Lightbox__counter {
  flex-shrink: 0;
  color: rgba(255, 255, 255, 0.5);
  font-variant-numeric: tabular-nums;
}
</style>
