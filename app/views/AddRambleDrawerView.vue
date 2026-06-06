<template>
  <UDrawer
    v-model:open="modelValue"
    direction="right"
    :handle="false"
    :ui="{ content: 'shadow-xl' }"
    handleOnly
    inset
  >
    <template #content>
      <div class="AddRambleDrawerView">
        <header class="AddRambleDrawerView__header">
          <h1
            class="AddRambleDrawerView__title"
            :class="{ 'AddRambleDrawerView__title--placeholder': !draft.title }"
          >{{ draft.title || 'Untitled draft' }}</h1>
          <UButton
            color="primary"
            size="sm"
            icon="i-lucide-check"
            :loading="isSaving"
            :disabled="!canSave"
            @click="handleSave"
          >Save</UButton>
        </header>

        <RambleComposer
          ref="composerRef"
          :placeholder="placeholder"
          :animate-layout="false"
          hide-preview-title
          @update:draft="handleDraftUpdate"
        />
      </div>
    </template>
  </UDrawer>
</template>

<script setup lang="ts">
import RambleComposer from '@app/components/ramble/RambleComposer.vue';
import useLink from '@app/composables/useLink';
import useRecord from '@app/composables/useRecord';
import { countDraftSignals, emptyDraft } from '@app/lib/ramble/draftFromEditor';
import { draftToSubmission } from '@app/lib/ramble/draftToRecord';
import type { DraftRecord } from '@shared/types/ramble';
import { computed, ref, watch } from 'vue';
import { useRouter } from 'vue-router';

const modelValue = defineModel<boolean>('open', { required: true, default: false });
const emit = defineEmits<{ close: [] }>();

const placeholder =
  'Type a title, drop in a link, tag concepts with #, reference records with @.';

const composerRef = ref<InstanceType<typeof RambleComposer> | null>(null);
const draft = ref<DraftRecord>(emptyDraft());
const isSaving = ref(false);

const canSave = computed(
  () =>
    !isSaving.value &&
    countDraftSignals(draft.value) >= 1 &&
    Boolean(draft.value.title || draft.value.content.trim()),
);

function handleDraftUpdate(next: DraftRecord) {
  draft.value = next;
}

// Refocus the editor each time the drawer opens so the cursor is ready.
watch(modelValue, (open) => {
  if (open) {
    setTimeout(() => composerRef.value?.focus(), 50);
  } else {
    draft.value = emptyDraft();
  }
});

const router = useRouter();
const toast = useToast();
const { upsertRecord } = useRecord();
const { upsertLink } = useLink();
const { mutate: upsertRecordMutation } = upsertRecord();
const { mutate: upsertLinkMutation } = upsertLink();

function handleSave() {
  let submission;
  try {
    submission = draftToSubmission(draft.value);
  } catch (e) {
    toast.add({
      title: 'Nothing to save',
      description: (e as Error).message,
      color: 'warning',
      icon: 'i-lucide-circle-alert',
    });
    return;
  }

  isSaving.value = true;
  upsertRecordMutation(submission.record, {
    onSuccess: (record) => {
      for (const link of submission.links) {
        upsertLinkMutation({ sourceId: record.id, ...link });
      }
      isSaving.value = false;
      modelValue.value = false;
      emit('close');
      toast.add({
        title: `Record “${record.slug}” was created`,
        color: 'success',
        icon: 'i-lucide-check-circle',
        actions: [
          {
            label: 'View',
            color: 'neutral',
            variant: 'outline',
            onClick: () => router.push(`/${record.slug}`),
          },
        ],
      });
    },
    onError: (e) => {
      isSaving.value = false;
      toast.add({
        title: 'Error',
        description: e.message.slice(0, 250),
        color: 'error',
        icon: 'i-lucide-circle-alert',
      });
    },
  });
}
</script>

<style scoped>
.AddRambleDrawerView {
  /* `align-content: start` keeps the editor pinned to the top instead of
   * stretching to centre when the preview is absent and there's spare room
   * in the drawer. */
  display: grid;
  align-content: start;
  gap: 20px;
  padding: 24px 28px 48px;
  width: 560px;
  max-width: 100vw;
  max-height: 100dvh;
  overflow-y: auto;
}

/* Without this the natural width of media inside the preview (tweet photos,
 * OG images) propagates up and pushes the grid out to image-native pixels.
 * `min-width: 0` lets the children shrink to the column. */
.AddRambleDrawerView > * {
  min-width: 0;
}

.AddRambleDrawerView__header {
  display: flex;
  align-items: baseline;
  gap: 12px;
}

.AddRambleDrawerView__header > .AddRambleDrawerView__title {
  flex: 1 1 auto;
  min-width: 0;
}

.AddRambleDrawerView__header > button {
  flex: 0 0 auto;
}

.AddRambleDrawerView__title {
  font-family: var(--font-serif, 'Georgia', serif);
  font-size: 1.25rem;
  font-weight: 500;
  color: var(--ui-text-highlighted);
  margin: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.AddRambleDrawerView__title--placeholder {
  color: var(--ui-text-dimmed);
  font-style: italic;
  font-weight: 400;
}

/* The standalone /ramble page uses a poster-size serif input; in the drawer
 * we want something tighter so the preview pulls more visual weight. */
.AddRambleDrawerView :deep(.RambleEditor) {
  font-size: 1.05rem;
  line-height: 1.5;
  min-height: 3.5em;
}
</style>
