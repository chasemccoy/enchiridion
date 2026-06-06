<template>
  <div class="RambleComposer">
    <RambleEditor
      ref="editorRef"
      :placeholder="placeholder"
      @change="handleEditorChange"
      @trigger-update="handleTriggerUpdate"
      @mention-key="handleMentionKey"
      @pill-click="handlePillClick"
    />

    <RambleMentionMenu
      v-if="triggerState"
      :results="mentionResults"
      :active-index="mentionActiveIndex"
      :loading="mentionLoading"
      :query="triggerState.query"
      :trigger="triggerState.trigger"
      :rect="triggerState.rect"
      @select="handleMentionSelect"
      @hover="(idx: number) => (mentionActiveIndex = idx)"
    />

    <RamblePredicateMenu
      v-model:open="predicateMenuOpen"
      v-model:value="activePredicate"
      :anchor-style="anchor.style.value"
    />

    <RambleLinkEditor
      v-model:open="linkEditorOpen"
      :value="activeLinkUrl"
      :anchor-style="anchor.style.value"
      @save="handleLinkSave"
    />

    <RambleDraftPreview
      v-if="shouldShowPreview"
      :draft="draft"
      :hide-title="hidePreviewTitle"
      @updateReferencePredicate="handleReferencePredicateChange"
    />
  </div>
</template>

<script setup lang="ts">
import RambleDraftPreview from '@app/components/RambleDraftPreview.vue';
import RambleEditor, {
  type MentionKey,
  type TriggerState,
} from '@app/components/ramble/RambleEditor.vue';
import RambleLinkEditor from '@app/components/ramble/RambleLinkEditor.vue';
import RambleMentionMenu, {
  type MentionMenuItem,
} from '@app/components/ramble/RambleMentionMenu.vue';
import RamblePredicateMenu from '@app/components/ramble/RamblePredicateMenu.vue';
import useFloatingAnchor from '@app/composables/useFloatingAnchor';
import useRecords from '@app/composables/useRecords';
import useSearch from '@app/composables/useSearch';
import {
  countDraftSignals,
  draftFromEditor,
  emptyDraft,
} from '@app/lib/ramble/draftFromEditor';
import type { ListRecordsAPIResponse } from '@db/queries/records';
import type { PredicateSlug } from '@shared/types';
import type { DraftRecord } from '@shared/types/ramble';
import { computed, nextTick, ref, watch } from 'vue';

const props = defineProps<{
  placeholder: string;
  /** When false, never animate the editor's vertical position. */
  animateLayout?: boolean;
  /** Hide the title row inside the preview (e.g. when a drawer header
   * already shows the title). */
  hidePreviewTitle?: boolean;
}>();

const emit = defineEmits<{
  'update:draft': [DraftRecord];
}>();

const editorRef = ref<InstanceType<typeof RambleEditor> | null>(null);

// ─── Draft + preview gating ───────────────────────────────────────────────

const draft = ref<DraftRecord>(emptyDraft());
const shouldShowPreview = computed(() => countDraftSignals(draft.value) >= 2);

function handleEditorChange() {
  draft.value = draftFromEditor(editorRef.value?.getElement() ?? null);
  emit('update:draft', draft.value);
}

// FLIP the editor between its old and new vertical position when the preview
// mounts/unmounts so it slides instead of jumping. `flush: 'pre'` measures
// before Vue applies the v-if.
watch(
  shouldShowPreview,
  async (next, prev) => {
    if (next === prev) return;
    if (props.animateLayout === false) return;
    const el = editorRef.value?.getElement();
    if (!el) return;
    const before = el.getBoundingClientRect().top;
    await nextTick();
    const after = el.getBoundingClientRect().top;
    const delta = before - after;
    if (Math.abs(delta) < 1) return;
    el.animate(
      [{ transform: `translateY(${delta}px)` }, { transform: 'translateY(0)' }],
      { duration: 480, easing: 'cubic-bezier(0.22, 1, 0.36, 1)' },
    );
  },
  { flush: 'pre' },
);

// ─── Mention typeahead ────────────────────────────────────────────────────

const triggerState = ref<TriggerState | null>(null);
const mentionActiveIndex = ref(0);

const mentionQuery = computed(() => triggerState.value?.query ?? '');
const mentionSearchEnabled = computed(
  () => Boolean(triggerState.value && mentionQuery.value.length > 0),
);

const { data: searchData, isFetching: mentionLoading } = useSearch(
  mentionQuery,
  mentionSearchEnabled,
);

const { data: conceptList } = useRecords({
  limit: 200,
  filters: { type: 'concept', hasTitle: true },
  orderBy: [{ field: 'title', direction: 'asc' }],
});
const { data: recentList } = useRecords({
  limit: 50,
  filters: { hasTitle: true, hideUntitledChildren: true },
  orderBy: [{ field: 'recordCreatedAt', direction: 'desc' }],
});

const mentionResults = computed<MentionMenuItem[]>(() => {
  const state = triggerState.value;
  if (!state) return [];
  let rows: ListRecordsAPIResponse;
  if (state.query.length === 0) {
    rows = (state.trigger === '#' ? conceptList.value : recentList.value) ?? [];
  } else {
    rows = searchData.value ?? [];
    if (state.trigger === '#') rows = rows.filter((row) => row.type === 'concept');
  }
  return rows.slice(0, 8).map((row) => ({
    id: row.id,
    slug: row.slug,
    type: row.type,
    label: row.title || row.content?.slice(0, 80) || row.slug,
    suffix: row.summary?.slice(0, 60) || row.content?.slice(0, 60) || undefined,
  }));
});

watch(mentionResults, () => {
  mentionActiveIndex.value = 0;
});

function handleTriggerUpdate(state: TriggerState | null) {
  triggerState.value = state;
}

function handleMentionKey(key: MentionKey) {
  const results = mentionResults.value;
  switch (key) {
    case 'down':
      if (results.length > 0) {
        mentionActiveIndex.value = (mentionActiveIndex.value + 1) % results.length;
      }
      break;
    case 'up':
      if (results.length > 0) {
        mentionActiveIndex.value =
          (mentionActiveIndex.value - 1 + results.length) % results.length;
      }
      break;
    case 'enter':
    case 'tab': {
      const pick = results[mentionActiveIndex.value];
      if (pick) editorRef.value?.commitMention(pick);
      break;
    }
    case 'esc':
      editorRef.value?.dismissTrigger();
      break;
  }
}

function handleMentionSelect(item: MentionMenuItem) {
  editorRef.value?.commitMention(item);
}

// ─── Pill menus ───────────────────────────────────────────────────────────

const anchor = useFloatingAnchor();
const activePill = ref<HTMLElement | null>(null);
const predicateMenuOpen = ref(false);
const linkEditorOpen = ref(false);
const activePredicate = ref<PredicateSlug | null>(null);
const activeLinkUrl = ref('');

function handlePillClick(pill: HTMLElement) {
  anchor.openAt(pill);
  activePill.value = pill;
  if (pill.dataset.pill === 'link') {
    activeLinkUrl.value = pill.dataset.url ?? '';
    linkEditorOpen.value = true;
  } else {
    activePredicate.value = (pill.dataset.predicate as PredicateSlug | undefined) ?? null;
    predicateMenuOpen.value = true;
  }
}

watch(activePredicate, (next, prev) => {
  if (next === prev || next === null) return;
  const pill = activePill.value;
  if (!pill) return;
  editorRef.value?.updatePillPredicate(pill, next);
});

watch([predicateMenuOpen, linkEditorOpen], ([predicateOpen, linkOpen]) => {
  if (!predicateOpen && !linkOpen) {
    activePill.value = null;
    activePredicate.value = null;
  }
});

function handleLinkSave(url: string) {
  const pill = activePill.value;
  if (!pill) return;
  editorRef.value?.updateLinkPill(pill, url);
}

function handleReferencePredicateChange({
  reference,
  predicate,
}: {
  reference: { slug: string; predicate: PredicateSlug };
  predicate: { slug: string };
}) {
  const editorEl = editorRef.value?.getElement();
  if (!editorEl) return;
  const pill = Array.from(editorEl.querySelectorAll<HTMLElement>('[data-pill]')).find(
    (el) =>
      el.dataset.slug === reference.slug && el.dataset.predicate === reference.predicate,
  );
  if (!pill) return;
  editorRef.value?.updatePillPredicate(pill, predicate.slug as PredicateSlug);
}

// ─── Imperative API ───────────────────────────────────────────────────────

function focus() {
  editorRef.value?.focus();
}

function getDraft(): DraftRecord {
  return draft.value;
}

defineExpose({ focus, getDraft });
</script>

<style scoped>
.RambleComposer {
  position: relative;
  width: 100%;
}
</style>
