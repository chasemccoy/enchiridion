<template>
  <Teleport to="body">
    <UPopover
      v-model:open="openModel"
      :content="{ align: 'start', sideOffset: 6 }"
      :ui="{ content: 'min-w-[320px]' }"
    >
      <span
        :style="anchorStyle"
        aria-hidden="true"
      />
      <template #content>
      <form
        class="RambleLinkEditor__form"
        @submit.prevent="commit"
      >
        <UInput
          v-model="draftValue"
          size="sm"
          autofocus
          spellcheck="false"
          @keydown.escape="openModel = false"
        />
        <div class="RambleLinkEditor__actions">
          <UButton
            size="xs"
            color="neutral"
            variant="ghost"
            @click="openModel = false"
          >
            Cancel
          </UButton>
          <UButton
            size="xs"
            color="primary"
            type="submit"
            :disabled="!isValid"
          >
            Save
          </UButton>
        </div>
      </form>
    </template>
  </UPopover>
  </Teleport>
</template>

<script setup lang="ts">
import { isUrl } from '@app/lib/ramble/draftFromEditor';
import { computed, ref, watch, type CSSProperties } from 'vue';

const openModel = defineModel<boolean>('open', { required: true });

const props = defineProps<{
  value: string;
  anchorStyle: CSSProperties;
}>();

const emit = defineEmits<{
  save: [string];
}>();

const draftValue = ref(props.value);

// Reset the local working copy each time the popover opens, so reopening
// after a cancel doesn't keep stale input.
watch(openModel, (open) => {
  if (open) draftValue.value = props.value;
});

const isValid = computed(() => isUrl(draftValue.value.trim()));

function commit() {
  if (!isValid.value) return;
  emit('save', draftValue.value.trim());
  openModel.value = false;
}
</script>

<style scoped>
.RambleLinkEditor__form {
  display: flex;
  flex-direction: column;
  gap: 8px;
  padding: 12px;
  font-family: var(--font-sans, sans-serif);
}

.RambleLinkEditor__actions {
  display: flex;
  justify-content: flex-end;
  gap: 6px;
  margin-top: 2px;
}
</style>
