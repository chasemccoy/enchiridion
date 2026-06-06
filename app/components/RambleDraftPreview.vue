<template>
  <div
    v-if="hasVisibleContent"
    class="RambleDraftPreview"
  >
    <h2
      v-if="!hideTitle"
      class="RambleDraftPreview__title"
    >
      <template v-if="draft.title">{{ draft.title }}</template>
      <span
        v-else
        class="RambleDraftPreview__titleHint"
      >Untitled draft</span>
    </h2>

    <template
      v-for="entry in draft.urls"
      :key="entry.url"
    >
      <RambleDraftTweetCard
        v-if="isTweetUrl(entry.url)"
        :url="entry.url"
      />
      <RambleDraftUrlCard
        v-else
        :url="entry.url"
      />
    </template>

    <div
      v-if="referenceSections.length > 0"
      class="RambleDraftPreview__links"
      :class="{ 'RambleDraftPreview__links--singleSection': referenceSections.length === 1 }"
    >
      <div
        v-for="section in referenceSections"
        :key="section.predicate"
        class="RambleDraftPreview__section"
      >
        <h2 class="RambleDraftPreview__sectionTitle">
          {{ capitalize(section.predicateName) }}
          <template v-if="section.references.length > 3">({{ section.references.length }})</template>
        </h2>
        <ul class="RambleDraftPreview__sectionList">
          <li
            v-for="ref in section.references"
            :key="ref.slug"
          >
            <RecordLink
              class="RambleDraftPreview__recordLink shadow-xxs"
              :modelValue="ref.id"
              :predicate="ref.predicate"
              @updatePredicate="(p) => $emit('updateReferencePredicate', { reference: ref, predicate: p })"
            />
          </li>
        </ul>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import RecordLink from '@app/components/RecordLink.vue';
import RambleDraftTweetCard from '@app/components/ramble/RambleDraftTweetCard.vue';
import RambleDraftUrlCard from '@app/components/ramble/RambleDraftUrlCard.vue';
import { isTweetUrl } from '@app/lib/ramble/tweetUrl';
import { capitalize } from '@shared/lib/formatting';
import { getPredicateSafe, type Predicate, type PredicateSlug } from '@shared/types';
import type { DraftRecord, DraftReference } from '@shared/types/ramble';
import { computed } from 'vue';

// Re-export types so existing consumers keep working.
export type { DraftRecord, DraftReference } from '@shared/types/ramble';

const props = defineProps<{
  draft: DraftRecord;
  /** Suppress the in-preview title — used when a parent surface (e.g. the
   * drawer header) already shows it. */
  hideTitle?: boolean;
}>();

/**
 * The preview wrapper (and its editorial divider) only renders when at
 * least one of its inner sections actually has something to show. Without
 * this gate, drafts with title+content but no URL or tag would render
 * just the divider line.
 */
const hasVisibleContent = computed(() => {
  if (!props.hideTitle) return true; // standalone view always shows the title block
  return props.draft.urls.length > 0 || props.draft.references.length > 0;
});

defineEmits<{
  updateReferencePredicate: [{ reference: DraftReference; predicate: Predicate }];
}>();

// Group references by predicate the same way the record-detail page does
// (RecordLinks). One section per predicate, ordered by first appearance.
type Section = {
  predicate: PredicateSlug;
  predicateName: string;
  references: DraftReference[];
};
const referenceSections = computed<Section[]>(() => {
  const order: PredicateSlug[] = [];
  const buckets = new Map<PredicateSlug, DraftReference[]>();
  for (const ref of props.draft.references) {
    if (!buckets.has(ref.predicate)) {
      buckets.set(ref.predicate, []);
      order.push(ref.predicate);
    }
    buckets.get(ref.predicate)!.push(ref);
  }
  return order.map((predicate) => ({
    predicate,
    predicateName: getPredicateSafe(predicate)?.name ?? predicate,
    references: buckets.get(predicate)!,
  }));
});
</script>

<style scoped>
.RambleDraftPreview {
  display: grid;
  gap: 0.75rem;
  margin-top: 28px;
  font-family: var(--font-sans, sans-serif);
  animation: RambleDraftPreview__shell 480ms cubic-bezier(0.22, 1, 0.36, 1) backwards;
}

/* Children stagger in after the shell appears so the preview unfolds rather
 * than popping. `backwards` keeps each child invisible during its delay. */
.RambleDraftPreview > * {
  animation: RambleDraftPreview__rise 520ms cubic-bezier(0.22, 1, 0.36, 1) backwards;
  will-change: opacity, transform;
}

/* Stagger pattern: first child waits 80ms; each subsequent child waits an
 * extra ~80ms. Repeats the chain past 12 children by re-using the same
 * delays — a 13th item flashing in alongside a 1st item is still better
 * than every late child landing in unison. */
.RambleDraftPreview > *:nth-child(1) { animation-delay: 80ms; }
.RambleDraftPreview > *:nth-child(2) { animation-delay: 160ms; }
.RambleDraftPreview > *:nth-child(3) { animation-delay: 240ms; }
.RambleDraftPreview > *:nth-child(4) { animation-delay: 320ms; }
.RambleDraftPreview > *:nth-child(5) { animation-delay: 400ms; }
.RambleDraftPreview > *:nth-child(6) { animation-delay: 480ms; }
.RambleDraftPreview > *:nth-child(7) { animation-delay: 560ms; }
.RambleDraftPreview > *:nth-child(8) { animation-delay: 640ms; }
.RambleDraftPreview > *:nth-child(9) { animation-delay: 720ms; }
.RambleDraftPreview > *:nth-child(10) { animation-delay: 800ms; }
.RambleDraftPreview > *:nth-child(11) { animation-delay: 880ms; }
.RambleDraftPreview > *:nth-child(12) { animation-delay: 960ms; }

@keyframes RambleDraftPreview__shell {
  from {
    opacity: 0;
    transform: translateY(12px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}

@keyframes RambleDraftPreview__rise {
  from {
    opacity: 0;
    transform: translateY(14px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}

.RambleDraftPreview__title {
  font-family: var(--font-serif, 'Georgia', serif);
  font-size: 1.5rem;
  font-weight: 500;
  line-height: 1.2;
  color: var(--ui-text-highlighted);
  margin: 0;
}

.RambleDraftPreview__titleHint {
  color: var(--ui-text-dimmed);
  font-style: italic;
}

.RambleDraftPreview__links:not(.RambleDraftPreview__links--singleSection) {
  columns: 300px auto;
}

.RambleDraftPreview__section {
  border-radius: var(--radius-xl);
  padding: 2px;
  break-inside: avoid;
  background-color: var(--ui-bg-elevated);

  & + & {
    margin-top: 16px;
  }
}

.RambleDraftPreview__sectionTitle {
  font-size: 0.85rem;
  display: flex;
  align-items: center;
  gap: 0.25rem;
  color: var(--ui-text-dimmed);
  font-weight: 500;
  padding: 4px 12px 6px;
  margin: 0;

  & :deep(svg) {
    width: 12px;
    height: 12px;
  }
}

.RambleDraftPreview__sectionList {
  column-gap: 2px;
  columns: 300px auto;
  list-style: none;
  padding: 0;
  margin: 0;

  li + li {
    margin-top: 2px;
  }
}

.RambleDraftPreview__recordLink {
  break-inside: avoid;
}
</style>
