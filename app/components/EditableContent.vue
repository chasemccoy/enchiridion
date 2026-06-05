<template>
  <div
    class="EditableContent"
    :class="{ 'EditableContent--editing': isEditing }"
  >
    <template v-if="isEditing">
      <div
        class="EditableContent__editor"
        @keydown.escape.stop.prevent="handleCancel"
        @keydown.meta.enter.stop.prevent="handleSave"
        @keydown.ctrl.enter.stop.prevent="handleSave"
      >
        <MarkdownEditor
          v-model="draft"
          autofocus
          :placeholder="placeholder"
        />
      </div>

      <div class="EditableContent__actions">
        <UButton
          color="neutral"
          variant="ghost"
          size="xs"
          label="Cancel"
          icon="i-lucide-x"
          @click="handleCancel"
        />
        <UButton
          color="primary"
          variant="ghost"
          size="xs"
          label="Save"
          icon="i-lucide-check"
          @click="handleSave"
        />
      </div>
    </template>

    <button
      v-else
      type="button"
      class="EditableContent__view"
      :aria-label="modelValue ? 'Edit content' : 'Add content'"
      @click="startEditing"
    >
      <MarkdownRender
        v-if="modelValue"
        :source="modelValue"
      />
      <span
        v-else
        class="EditableContent__placeholder"
      >
        {{ placeholder }}
      </span>

      <span class="EditableContent__editHint">
        <UIcon
          name="i-lucide-pencil"
          class="EditableContent__editHintIcon"
        />
        Edit
      </span>
    </button>
  </div>
</template>

<script setup lang="ts">
import MarkdownEditor from '@app/components/MarkdownEditor.vue';
import MarkdownRender from '@app/components/MarkdownRender.vue';
import { ref } from 'vue';

const { placeholder = 'Write something about this record' } = defineProps<{
  placeholder?: string;
}>();

const modelValue = defineModel<string | null | undefined>();

const isEditing = ref(false);
const draft = ref('');

function startEditing() {
  draft.value = modelValue.value ?? '';
  isEditing.value = true;
}

function handleSave() {
  const next = draft.value.trim();
  modelValue.value = next.length > 0 ? next : null;
  isEditing.value = false;
}

function handleCancel() {
  draft.value = '';
  isEditing.value = false;
}
</script>

<style scoped>
.EditableContent {
  position: relative;
  display: grid;
  gap: 6px;
}

.EditableContent__view {
  position: relative;
  display: block;
  width: 100%;
  text-align: left;
  background: transparent;
  border: none;
  border-radius: var(--radius-xl);
  padding: 10px 14px;
  cursor: text;
  font: inherit;
  color: inherit;
  transition: background-color 120ms ease;
}

.EditableContent__view:hover,
.EditableContent__view:focus-visible {
  background-color: var(--ui-bg-elevated);
  outline: none;
}

.EditableContent__placeholder {
  color: var(--ui-text-dimmed);
  font-size: 0.8rem;
}

.EditableContent__editHint {
  position: absolute;
  top: 8px;
  right: 8px;
  display: inline-flex;
  align-items: center;
  gap: 4px;
  padding: 2px 8px;
  border-radius: var(--radius-sm);
  background-color: var(--ui-bg);
  border: 1px solid var(--ui-border);
  color: var(--ui-text-muted);
  font-size: 0.7rem;
  opacity: 0;
  transition: opacity 120ms ease;
  pointer-events: none;
}

.EditableContent__view:hover .EditableContent__editHint,
.EditableContent__view:focus-visible .EditableContent__editHint {
  opacity: 1;
}

.EditableContent__editHintIcon {
  width: 10px;
  height: 10px;
}

.EditableContent__editor {
  padding: 10px 14px;
  background-color: var(--ui-bg-elevated);
  border-radius: var(--radius-xl);
}

.EditableContent__actions {
  display: flex;
  gap: 2px;
  align-items: center;
  justify-content: flex-end;
  padding-inline: 14px;
}
</style>
