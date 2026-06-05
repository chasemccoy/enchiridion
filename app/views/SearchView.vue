<template>
  <div class="SearchView">
    <header class="SearchView__header">
      <UIcon
        name="i-lucide-search"
        class="SearchView__icon"
      />
      <UInput
        v-model="qInput"
        placeholder="Search records…"
        size="xl"
        variant="ghost"
        class="SearchView__input"
        autofocus
      />
    </header>

    <div class="SearchView__toolbar">
      <div
        class="SearchView__group"
        role="tablist"
        aria-label="Search mode"
      >
        <UButton
          size="xs"
          :color="mode === 'semantic' ? 'primary' : 'neutral'"
          :variant="mode === 'semantic' ? 'soft' : 'ghost'"
          @click="setMode('semantic')"
        >
          Semantic
        </UButton>
        <UButton
          size="xs"
          :color="mode === 'keyword' ? 'primary' : 'neutral'"
          :variant="mode === 'keyword' ? 'soft' : 'ghost'"
          @click="setMode('keyword')"
        >
          Full-text
        </UButton>
      </div>

      <div class="SearchView__divider" />

      <div class="SearchView__group">
        <UButton
          v-for="type in recordTypes"
          :key="type"
          size="xs"
          :color="typeFilter === type ? 'primary' : 'neutral'"
          :variant="typeFilter === type ? 'soft' : 'ghost'"
          :icon="getIconForRecordType(type)"
          @click="toggleType(type)"
        >
          {{ capitalize(type) }}
        </UButton>
      </div>

      <div class="SearchView__divider" />

      <div class="SearchView__checkboxes">
        <UCheckbox
          v-model="curatedOnly"
          label="Curated only"
          size="xs"
        />
        <UCheckbox
          v-model="hasMediaOnly"
          label="Has media"
          size="xs"
        />
      </div>

      <div class="SearchView__sort">
        <span class="SearchView__label">Sort:</span>
        <USelectMenu
          v-model="sortKey"
          size="xs"
          variant="ghost"
          valueKey="id"
          :items="sortOptions"
          :searchInput="false"
        />
      </div>
    </div>

    <div
      v-if="hasQuery"
      class="SearchView__status"
    >
      <template v-if="isLoading">Searching…</template>
      <template v-else-if="errorMessage">{{ errorMessage }}</template>
      <template v-else-if="!sortedResults.length">No results found.</template>
      <template v-else>
        Showing {{ sortedResults.length }}
        <template v-if="sortedResults.length !== rawCount"> of {{ rawCount }}</template>
      </template>
    </div>

    <div
      v-if="isLoading && !sortedResults.length"
      class="SearchView__loading"
    >
      <UIcon
        name="i-lucide-loader-2"
        class="SearchView__spinner"
      />
    </div>

    <div
      v-else-if="!hasQuery"
      class="SearchView__empty"
    >
      <UIcon
        name="i-lucide-telescope"
        class="SearchView__emptyIcon"
      />
      <h2 class="SearchView__emptyHeadline">Search the knowledge base</h2>
      <p class="SearchView__emptyHint">
        <template v-if="mode === 'semantic'">
          Semantic mode finds records by meaning. Paraphrases, synonyms, and
          related concepts all count.
        </template>
        <template v-else>
          Full-text mode matches exact words and phrases across titles, content,
          summaries, and notes.
        </template>
      </p>
      <div class="SearchView__emptySuggestions">
        <UButton
          v-for="suggestion in suggestions"
          :key="suggestion"
          size="xs"
          color="neutral"
          variant="outline"
          @click="qInput = suggestion"
        >
          {{ suggestion }}
        </UButton>
      </div>
    </div>

    <ul
      v-else-if="sortedResults.length"
      class="SearchView__grid"
    >
      <li
        v-for="(record, idx) in sortedResults"
        :key="record.id"
        class="SearchView__cell"
      >
        <RecordCard
          v-model="sortedResults[idx]!"
          expanded
          preferContent
          showParent
        />
      </li>
    </ul>
  </div>
</template>

<script setup lang="ts">
import RecordCard from '@app/components/RecordCard.vue';
import useSearch from '@app/composables/useSearch';
import useSemanticSearch from '@app/composables/useSemanticSearch';
import { getIconForRecordType } from '@app/utils';
import type { ListRecordsAPIResponse } from '@db/queries/records';
import { recordTypeEnum, type RecordType } from '@shared/types';
import { capitalize, computed, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';

type SearchMode = 'keyword' | 'semantic';
type SortKey = 'relevance' | 'newest' | 'oldest' | 'title';

const route = useRoute();
const router = useRouter();

const recordTypes: RecordType[] = ['artifact', 'concept', 'entity'];

const sortOptions: { id: SortKey; label: string }[] = [
  { id: 'relevance', label: 'Relevance' },
  { id: 'newest', label: 'Newest' },
  { id: 'oldest', label: 'Oldest' },
  { id: 'title', label: 'Title A–Z' },
];

// Hand-picked example queries shown in the empty state. They double as a hint
// about what semantic vs. full-text mode is good at: abstract phrasings for
// semantic, concrete keywords for full-text.
const semanticSuggestions = [
  'ways of thinking about links',
  'tools for personal knowledge',
  'the texture of the web',
];
const keywordSuggestions = ['hypertext', 'typography', 'rss'];

const isSearchMode = (value: unknown): value is SearchMode =>
  value === 'keyword' || value === 'semantic';
const isRecordType = (value: unknown): value is RecordType =>
  typeof value === 'string' && (recordTypeEnum as readonly string[]).includes(value);
const isSortKey = (value: unknown): value is SortKey =>
  value === 'relevance' || value === 'newest' || value === 'oldest' || value === 'title';

const readQuery = <T,>(key: string, fallback: T, guard: (v: unknown) => v is T): T => {
  const raw = route.query[key];
  const value = Array.isArray(raw) ? raw[0] : raw;
  return guard(value) ? value : fallback;
};

const q = computed(() => {
  const raw = route.query.q;
  const value = Array.isArray(raw) ? raw[0] : raw;
  return typeof value === 'string' ? value : '';
});

const mode = computed<SearchMode>(() => readQuery('mode', 'semantic', isSearchMode));
const typeFilter = computed<RecordType | null>(() => {
  const raw = route.query.type;
  const value = Array.isArray(raw) ? raw[0] : raw;
  return isRecordType(value) ? value : null;
});
const curatedOnly = computed({
  get: () => route.query.curated === '1',
  set: (value: boolean) => updateQuery({ curated: value ? '1' : undefined }),
});
const hasMediaOnly = computed({
  get: () => route.query.media === '1',
  set: (value: boolean) => updateQuery({ media: value ? '1' : undefined }),
});
const sortKey = computed({
  get: (): SortKey => readQuery('sort', 'relevance', isSortKey),
  set: (value: SortKey) => updateQuery({ sort: value === 'relevance' ? undefined : value }),
});

const qInput = ref(q.value);

// Keep the URL in sync as the user types, debounced so we don't spam history.
let qInputTimer: ReturnType<typeof setTimeout> | undefined;
watch(qInput, (next) => {
  if (qInputTimer) clearTimeout(qInputTimer);
  qInputTimer = setTimeout(() => {
    if (next !== q.value) updateQuery({ q: next || undefined });
  }, 150);
});

// External URL changes (back/forward, "See all results" from the modal) should
// flow back into the input.
watch(q, (next) => {
  if (next !== qInput.value) qInput.value = next;
});

function updateQuery(patch: Record<string, string | undefined>) {
  const next = { ...route.query };
  for (const [key, value] of Object.entries(patch)) {
    if (value === undefined || value === '') delete next[key];
    else next[key] = value;
  }
  router.replace({ query: next });
}

function setMode(value: SearchMode) {
  if (value === mode.value) return;
  updateQuery({ mode: value === 'semantic' ? undefined : value, sort: undefined });
}

function toggleType(value: RecordType) {
  updateQuery({ type: typeFilter.value === value ? undefined : value });
}

const hasQuery = computed(() => q.value.trim().length > 0);
const keywordEnabled = computed(() => hasQuery.value && mode.value === 'keyword');
const semanticEnabled = computed(() => hasQuery.value && mode.value === 'semantic');

const suggestions = computed(() =>
  mode.value === 'semantic' ? semanticSuggestions : keywordSuggestions,
);

const {
  data: keywordData,
  isFetching: keywordFetching,
  error: keywordError,
} = useSearch(q, keywordEnabled);

const {
  data: semanticData,
  isFetching: semanticFetching,
  error: semanticError,
} = useSemanticSearch(q, semanticEnabled);

const isLoading = computed(() =>
  mode.value === 'keyword' ? keywordFetching.value : semanticFetching.value,
);

const errorMessage = computed(() => {
  const err = mode.value === 'keyword' ? keywordError.value : semanticError.value;
  if (!err) return null;
  if (mode.value === 'semantic' && /503/.test(err.message)) {
    return 'Semantic search is not configured. Set OPENAI_API_KEY on the backend to enable it.';
  }
  return 'Search failed. Try again.';
});

const rawResults = computed<ListRecordsAPIResponse>(() => {
  if (!hasQuery.value) return [];
  if (mode.value === 'keyword') return keywordData.value ?? [];
  // Drop the `score` field so the downstream shape matches RecordCard's model.
  return (semanticData.value ?? []).map((row) => stripScore(row));
});

function stripScore<T extends { score: number }>(row: T): Omit<T, 'score'> {
  const copy: Partial<T> = { ...row };
  delete copy.score;
  return copy as Omit<T, 'score'>;
}

const rawCount = computed(() => rawResults.value.length);

const hasMedia = (record: ListRecordsAPIResponse[number]) =>
  Array.isArray(record.media) && record.media.length > 0;

const filteredResults = computed(() =>
  rawResults.value.filter((record) => {
    if (typeFilter.value && record.type !== typeFilter.value) return false;
    if (curatedOnly.value && !record.isCurated) return false;
    if (hasMediaOnly.value && !hasMedia(record)) return false;
    return true;
  }),
);

const sortedResults = ref<ListRecordsAPIResponse>([]);

watch(
  [filteredResults, sortKey, mode],
  ([list, sort]) => {
    const next = [...list];
    if (sort === 'newest') {
      next.sort((a, b) => (b.recordCreatedAt ?? '').localeCompare(a.recordCreatedAt ?? ''));
    } else if (sort === 'oldest') {
      next.sort((a, b) => (a.recordCreatedAt ?? '').localeCompare(b.recordCreatedAt ?? ''));
    } else if (sort === 'title') {
      next.sort((a, b) => (a.title ?? '').localeCompare(b.title ?? ''));
    }
    // 'relevance' keeps the server-provided order (semantic ranking or
    // listRecords' default recordCreatedAt desc).
    sortedResults.value = next;
  },
  { immediate: true },
);
</script>

<style scoped>
.SearchView {
  display: flex;
  flex-direction: column;
  gap: 12px;
  padding: 24px 32px 96px;
  max-width: 1400px;
  width: 100%;
  margin: 0 auto;
  /* Fill the viewport at minimum so the page never collapses to just the
   * header/toolbar (empty state, no-results, single-row results). 100dvh
   * over 100vh so the dynamic mobile browser chrome doesn't cut off the bottom. */
  min-height: 100dvh;
}

.SearchView__header {
  display: flex;
  align-items: center;
  gap: 16px;
}

.SearchView__icon {
  flex: none;
  width: 28px;
  height: 28px;
  color: var(--ui-text-dimmed);
}

:deep(.SearchView__input) {
  flex: 1;
  min-width: 0;

  & input {
    font-family: var(--font-serif, 'Georgia', serif);
    font-size: 1.5rem;
    padding-block: 8px;
    padding-inline: 0;
    background-color: transparent;
  }
}

.SearchView__toolbar {
  position: sticky;
  top: 0;
  z-index: 2;
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 8px;
  padding-block: 8px;
  border-bottom: 0.5px solid var(--ui-border);
  background-color: var(--page-bg);
  font-size: 12px;
  color: var(--ui-text-muted);
}

.SearchView__group {
  display: inline-flex;
  align-items: center;
  gap: 4px;
}

.SearchView__divider {
  width: 1px;
  height: 16px;
  background-color: var(--ui-border);
  margin: 0 4px;
}

.SearchView__label {
  font-size: 12px;
  color: var(--ui-text-dimmed);
}

.SearchView__checkboxes {
  display: inline-flex;
  align-items: center;
  gap: 16px;
}

.SearchView__sort {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  margin-left: auto;
}

.SearchView__status {
  font-size: 12px;
  color: var(--ui-text-dimmed);
}

.SearchView__loading {
  display: flex;
  justify-content: center;
  padding: 64px 0;
  color: var(--ui-text-dimmed);
}

.SearchView__empty {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  text-align: center;
  gap: 12px;
  padding: 48px 24px;
  color: var(--ui-text-muted);
  max-width: 540px;
  width: 100%;
  margin: 0 auto;
  /* Stretch to absorb whatever space is left after header/toolbar so the
   * content visually centres in the remaining viewport. */
  flex: 1;
}

.SearchView__emptyIcon {
  width: 48px;
  height: 48px;
  color: var(--ui-text-dimmed);
  opacity: 0.6;
  margin-bottom: 4px;
}

.SearchView__emptyHeadline {
  font-family: var(--font-serif, 'Georgia', serif);
  font-size: 1.5rem;
  line-height: 1.2;
  color: var(--ui-text);
  font-weight: 400;
}

.SearchView__emptyHint {
  font-size: 0.875rem;
  line-height: 1.5;
  color: var(--ui-text-muted);
  text-wrap: balance;
}

.SearchView__emptySuggestions {
  display: inline-flex;
  flex-wrap: wrap;
  align-items: center;
  justify-content: center;
  gap: 8px;
  margin-top: 12px;
}


.SearchView__spinner {
  width: 24px;
  height: 24px;
  animation: SearchView__spin 1s linear infinite;
}

@keyframes SearchView__spin {
  to {
    transform: rotate(360deg);
  }
}

.SearchView__grid {
  columns: 320px 4;
  column-gap: 8px;
}

.SearchView__cell {
  break-inside: avoid;
  -webkit-column-break-inside: avoid;
  page-break-inside: avoid;
  display: block;
  margin-bottom: 8px;
}
</style>
