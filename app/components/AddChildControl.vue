<template>
  <div class="AddChildControl">
    <!-- Collapsed affordance -->
    <button
      v-if="!open"
      type="button"
      class="AddChildControl__row"
      @click="openPanel"
    >
      <UIcon
        name="i-lucide-plus"
        class="AddChildControl__rowIcon"
      />
      <span class="AddChildControl__rowLabel">Add child record</span>
    </button>

    <!-- Expanded panel: write a new quote -->
    <div
      v-else
      class="AddChildControl__panel"
    >
      <textarea
        ref="inputEl"
        v-model="draft"
        class="AddChildControl__input"
        rows="3"
        placeholder="Paste or type a passage from this record…"
        @keydown="onKeydown"
      />
      <div class="AddChildControl__foot">
        <UTabs
          v-model="predicate"
          size="sm"
          :items="PREDICATES"
          :content="false"
        />
        <div class="AddChildControl__actions">
          <UButton
            color="neutral"
            variant="ghost"
            size="sm"
            label="Cancel"
            @click="close"
          />
          <UButton
            color="primary"
            variant="ghost"
            size="sm"
            icon="i-lucide-plus"
            label="Add record"
            :loading="isSaving"
            :disabled="!draft.trim() || isSaving"
            @click="addQuote"
          />
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { nextTick, ref } from 'vue';
import useRecord from '@app/composables/useRecord';
import useLink from '@app/composables/useLink';
import { slugify } from '@shared/lib/formatting';
import type { DbId } from '@shared/types/api';
import type { PredicateSlug } from '@shared/types';

/** Containment predicates a child can be attached with, child → parent. */
type ChildPredicate = Extract<PredicateSlug, 'quotes' | 'contained_by'>;

const { parentId } = defineProps<{ parentId: DbId }>();

const PREDICATES = [
  { value: 'quotes' as const, label: 'Quote', icon: 'i-lucide-quote' },
  { value: 'contained_by' as const, label: 'Part', icon: 'i-lucide-indent-increase' },
];

const toast = useToast();
const { upsertRecord } = useRecord();
const { upsertLink } = useLink();
const { mutate: upsertRecordMutation } = upsertRecord();
const { mutate: upsertLinkMutation } = upsertLink();

const open = ref(false);
const draft = ref('');
const predicate = ref<ChildPredicate>('quotes');
const isSaving = ref(false);
const inputEl = ref<HTMLTextAreaElement | null>(null);

async function openPanel() {
  open.value = true;
  await nextTick();
  inputEl.value?.focus();
}

function close() {
  open.value = false;
  draft.value = '';
}

function onKeydown(event: KeyboardEvent) {
  if (event.key === 'Escape') {
    event.preventDefault();
    close();
    return;
  }
  if ((event.metaKey || event.ctrlKey) && event.key === 'Enter') {
    event.preventDefault();
    addQuote();
  }
}

// A child quote is an untitled artifact whose content is the passage. Build a
// readable, unique slug from the passage (records.slug is NOT NULL + unique).
function makeSlug(content: string): string {
  const base = slugify(content).split('-').filter(Boolean).slice(0, 8).join('-');
  const suffix = (globalThis.crypto?.randomUUID?.() ?? Math.random().toString(36).slice(2))
    .replace(/-/g, '')
    .slice(0, 8);
  return `${base || 'quote'}-${suffix}`;
}

function addQuote() {
  const content = draft.value.trim();
  if (!content || isSaving.value) return;
  const childPredicate = predicate.value;
  isSaving.value = true;

  upsertRecordMutation(
    {
      type: 'artifact',
      title: null,
      content,
      slug: makeSlug(content),
      source: 'manual',
      isCurated: true,
    },
    {
      onSuccess: (record) => {
        // Link the new record as a child: child → parent, so the current
        // record is the link target (an incoming containment edge).
        upsertLinkMutation(
          { sourceId: record.id, targetId: parentId, predicate: childPredicate },
          {
            onSuccess: () => {
              isSaving.value = false;
              draft.value = '';
              nextTick(() => inputEl.value?.focus());
            },
            onError: () => fail(),
          },
        );
      },
      onError: () => fail(),
    },
  );
}

function fail() {
  isSaving.value = false;
  toast.add({
    title: 'Could not add child',
    description: 'Something went wrong saving the record or link.',
    color: 'error',
  });
}
</script>

<style scoped>
.AddChildControl {
  margin-top: 4px;
}

/* Collapsed trigger ------------------------------------------------------ */
.AddChildControl__row {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  margin-left: -8px;
  padding: 5px 8px;
  border: 0;
  border-radius: var(--radius-md, 6px);
  background: transparent;
  cursor: pointer;
  color: var(--ui-text-dimmed);
  text-align: left;
  transition:
    background 0.12s ease,
    color 0.12s ease;
}

.AddChildControl__row:hover {
  background: var(--ui-bg-elevated);
  color: var(--ui-text);
}

.AddChildControl__rowIcon {
  width: 15px;
  height: 15px;
}

.AddChildControl__rowLabel {
  font-size: 0.85rem;
  font-weight: 500;
}

/* Panel ------------------------------------------------------------------ */
.AddChildControl__panel {
  display: grid;
  gap: 10px;
  padding: 10px;
  border: 1px solid var(--ui-border);
  /* Concentric with the inner controls: their radius (rounded-lg) + the 10px
     padding, so the panel and tab/input corners share the same center. */
  border-radius: calc(var(--radius-lg) + 10px);
  background: var(--ui-bg-muted);
}

/* In dark mode, sit at the record-link hover surface so the panel matches the
   depth of the rows around it. */
:global(.dark .AddChildControl__panel) {
  background: var(--ui-bg-elevated);
}

.AddChildControl__input {
  width: 100%;
  border: 1px solid var(--ui-border-accented);
  border-radius: var(--radius-lg);
  background: var(--ui-bg);
  resize: none;
  outline: none;
  font: inherit;
  font-size: 0.9rem;
  line-height: 1.45;
  color: var(--ui-text-highlighted);
  padding: 8px 10px;
  transition:
    border-color 0.12s ease,
    box-shadow 0.12s ease;
}

.AddChildControl__input::placeholder {
  color: var(--ui-text-dimmed);
}

.AddChildControl__input:focus {
  border-color: var(--ui-primary);
  box-shadow: 0 0 0 3px color-mix(in oklab, var(--ui-primary) 16%, transparent);
}

.AddChildControl__foot {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
}

.AddChildControl__actions {
  display: inline-flex;
  align-items: center;
  gap: 4px;
}
</style>
