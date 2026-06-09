<template>
  <div class="IndexV2View">
    <header class="IndexV2View__toolbar">
      <div
        ref="searchBox"
        class="IndexV2View__brand"
      >
        <button
          v-if="!showSearchInput"
          type="button"
          class="IndexV2View__logo"
          aria-label="Search"
          @click="openSearch"
        >
          Enchiridion
        </button>
        <div
          v-else
          class="IndexV2View__search"
        >
          <UIcon
            name="i-lucide-search"
            class="IndexV2View__searchIcon"
          />
          <UInput
            v-model="qInput"
            placeholder="Search records…"
            size="xs"
            variant="ghost"
            class="IndexV2View__searchInput"
            @blur="onSearchBlur"
            @keydown.esc="clearSearch"
          />
          <UButton
            v-if="qInput"
            icon="i-lucide-x"
            size="xs"
            color="neutral"
            variant="ghost"
            class="IndexV2View__searchClear"
            aria-label="Clear search"
            @click="clearSearch"
          />
        </div>
      </div>

      <div
        class="IndexV2View__group"
        role="tablist"
        aria-label="View mode"
      >
        <UButton
          size="xs"
          icon="i-lucide-layout-grid"
          :color="view === 'cards' ? 'primary' : 'neutral'"
          :variant="view === 'cards' ? 'soft' : 'ghost'"
          @click="setView('cards')"
        >
          Cards
        </UButton>
        <UButton
          size="xs"
          icon="i-lucide-table-properties"
          :color="view === 'table' ? 'primary' : 'neutral'"
          :variant="view === 'table' ? 'soft' : 'ghost'"
          @click="setView('table')"
        >
          Table
        </UButton>
      </div>

      <div class="IndexV2View__divider" />

      <div class="IndexV2View__group">
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

      <div class="IndexV2View__divider" />

      <div class="IndexV2View__checkboxes">
        <UCheckbox
          v-model="needsCuration"
          label="Needs curation"
          size="xs"
        />
        <UCheckbox
          v-model="hasMediaOnly"
          label="Media"
          size="xs"
        />
      </div>

      <div class="IndexV2View__sort">
        <USelectMenu
          v-model="sortKey"
          size="xs"
          variant="ghost"
          valueKey="id"
          :items="sortOptions"
          :searchInput="false"
        />
      </div>

      <div class="IndexV2View__count">
        <template v-if="hasQuery && searchFetching && !filteredRecords?.length">
          Searching…
        </template>
        <template v-else-if="filteredRecords">
          {{ filteredRecords.length }}
          <template v-if="filteredRecords.length !== totalCount"> of {{ totalCount }} </template>
          {{ hasQuery ? 'results' : 'records' }}
        </template>
      </div>
    </header>

    <div class="IndexV2View__content">
      <!-- KeepAlive caches whichever pane is inactive so switching Cards↔Table
        never re-instantiates ~500 components (the switch was 0.6–0.9s of Vue
        mount + GC churn). The inactive pane is also paused, so a search doesn't
        re-render the hidden view on every keystroke. Both children must be
        components for KeepAlive to cache them — hence IndexV2TablePane. -->
      <KeepAlive>
        <SplitViewLayout
          v-if="view === 'cards'"
          key="cards"
          v-model="filteredRecordsModel"
          :isEmpty="!route.params.slug"
          :recordCardProps="cardPropsFor"
          :grouped="!hasQuery && sortKey !== 'title'"
        >
          <RouterView />
        </SplitViewLayout>

        <IndexV2TablePane
          v-else
          key="table"
          v-model="filteredRecordsModel"
          :hideColumns="tableHiddenColumns"
          :rowTo="(slug) => `/v2/${slug}`"
        />
      </KeepAlive>
    </div>
  </div>
</template>

<script setup lang="ts">
import IndexV2TablePane from '@app/components/IndexV2TablePane.vue';
import SplitViewLayout from '@app/components/SplitViewLayout.vue';
import useQueryState from '@app/composables/useQueryState';
import useRecords from '@app/composables/useRecords';
import useHybridSearch from '@app/composables/useHybridSearch';
import { getIconForRecordType, hasMedia, isRecordType, stripScore } from '@app/utils';
import type { ListRecordsAPIResponse } from '@db/queries/records';
import type { RecordType } from '@shared/types';
import { capitalize, computed, nextTick, ref, useTemplateRef, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';

type ViewMode = 'cards' | 'table';
type SortKey = 'relevance' | 'newest' | 'oldest' | 'title';

const route = useRoute();
const router = useRouter();
const { readQuery, updateQuery } = useQueryState();

// Search query (URL `?q=`). Defined up here because the sort options and default
// below switch on whether a search is active.
const q = computed(() => {
  const raw = route.query.q;
  const value = Array.isArray(raw) ? raw[0] : raw;
  return typeof value === 'string' ? value : '';
});
const hasQuery = computed(() => q.value.trim().length > 0);

const recordTypes: RecordType[] = ['artifact', 'concept', 'entity'];

const browseSortOptions: { id: SortKey; label: string }[] = [
  { id: 'newest', label: 'Newest' },
  { id: 'oldest', label: 'Oldest' },
  { id: 'title', label: 'Title A–Z' },
];
// Relevance only makes sense while searching (it preserves the semantic
// ranking), so it appears — and leads — only then.
const sortOptions = computed<{ id: SortKey; label: string }[]>(() =>
  hasQuery.value
    ? [{ id: 'relevance', label: 'Relevance' }, ...browseSortOptions]
    : browseSortOptions,
);

const isViewMode = (value: unknown): value is ViewMode => value === 'cards' || value === 'table';
const isSortKey = (value: unknown): value is SortKey =>
  value === 'relevance' || value === 'newest' || value === 'oldest' || value === 'title';

const view = computed<ViewMode>(() => readQuery('view', 'cards', isViewMode));
const typeFilter = computed<RecordType | null>(() => {
  const raw = route.query.type;
  const value = Array.isArray(raw) ? raw[0] : raw;
  return isRecordType(value) ? value : null;
});
const needsCuration = computed({
  get: () => route.query.uncurated === '1',
  set: (value: boolean) => updateQuery({ uncurated: value ? '1' : undefined }),
});
const hasMediaOnly = computed({
  get: () => route.query.media === '1',
  set: (value: boolean) => updateQuery({ media: value ? '1' : undefined }),
});
// Default sort: relevance while searching, newest while browsing. Storing the
// default omits `sort` from the URL, so the param only appears on an explicit,
// non-default choice — and a leftover `?sort=relevance` is ignored once the
// search clears.
const defaultSortKey = computed<SortKey>(() => (hasQuery.value ? 'relevance' : 'newest'));
const sortKey = computed({
  get: (): SortKey => {
    const value = readQuery('sort', defaultSortKey.value, isSortKey);
    return !hasQuery.value && value === 'relevance' ? 'newest' : value;
  },
  set: (value: SortKey) =>
    updateQuery({ sort: value === defaultSortKey.value ? undefined : value }),
});

// --- Search (the serif logo doubles as the search input) ---------------------
// `q` / `hasQuery` live near the top of setup (the sort options depend on them);
// everything else for the search input lives here. The query is URL-backed
// (`?q=`) so it survives reloads, deep links, and back/forward.
const qInput = ref(q.value);

// Keep the URL in sync as the user types, debounced so we don't spam history.
let qInputTimer: ReturnType<typeof setTimeout> | undefined;
watch(qInput, (next) => {
  if (qInputTimer) clearTimeout(qInputTimer);
  qInputTimer = setTimeout(() => {
    if (next === q.value) return;
    // Starting a search while a record is open: deselect it by dropping the
    // `/v2/:slug` child route, so results fill the page instead of rendering in
    // the narrow split-view list. Other query state is preserved.
    if (next.trim() && route.params.slug) {
      router.replace({ path: '/v2', query: { ...route.query, q: next } });
    } else {
      updateQuery({ q: next || undefined });
    }
  }, 150);
});

// External URL changes (back/forward, deep link) flow back into the input.
watch(q, (next) => {
  if (next !== qInput.value) qInput.value = next;
});

// `isSearchOpen` tracks the logo→input toggle; an active query forces it open so
// a deep-linked `?q=` lands on the expanded input, not the collapsed logo.
const isSearchOpen = ref(hasQuery.value);
const showSearchInput = computed(() => isSearchOpen.value || hasQuery.value);
const searchBoxRef = useTemplateRef<HTMLElement>('searchBox');

function openSearch() {
  isSearchOpen.value = true;
  nextTick(() => searchBoxRef.value?.querySelector('input')?.focus());
}

function onSearchBlur() {
  // Collapse back to the logo only when there's nothing to keep showing.
  if (!qInput.value) isSearchOpen.value = false;
}

function clearSearch() {
  qInput.value = '';
  updateQuery({ q: undefined });
  isSearchOpen.value = false;
}

function setView(value: ViewMode) {
  // Pressing the already-active view toggle scrolls that pane to the top
  // (mirrors the bottom-nav "tap active tab to scroll up" behavior).
  if (value === view.value) {
    scrollActiveViewToTop();
    return;
  }
  updateQuery({ view: value === 'cards' ? undefined : value });
}

// Each pane has its own virtualized scroll container: the cards list scrolls
// `.SplitViewLayout_list`, the table scrolls its own root `.RecordTable--virtual`.
// The inactive pane is detached by <KeepAlive>, so a scoped query resolves to
// whichever is currently showing.
function scrollActiveViewToTop() {
  const selector = view.value === 'cards' ? '.SplitViewLayout_list' : '.RecordTable--virtual';
  const scroller = document.querySelector<HTMLElement>(`.IndexV2View__content ${selector}`);
  scroller?.scrollTo({ top: 0, behavior: 'smooth' });
}

function toggleType(value: RecordType) {
  updateQuery({ type: typeFilter.value === value ? undefined : value });
}

// Effectively unbounded — the API has no max-limit and the v2 page is
// supposed to surface every record at once. The number just has to stay
// comfortably above the real record count (704 today).
const { data } = useRecords({
  limit: 100000,
  filters: {
    hideUntitledChildren: true,
  },
  orderBy: [
    {
      field: 'recordCreatedAt',
      direction: 'desc',
    },
  ],
});

// Hybrid search: reciprocal-rank-fusion of full-text + semantic, so exact tokens
// (names, domains, slugs) and meaning both rank well. Only runs when there's a
// query; otherwise the page shows the full record list above.
const { data: hybridData, isFetching: searchFetching } = useHybridSearch(q, hasQuery);

// The record set the page renders: search results when searching, otherwise the
// full list. Filters/sort/cards/table downstream don't care which it is.
const baseRecords = computed<ListRecordsAPIResponse | undefined>(() => {
  if (hasQuery.value) {
    if (!hybridData.value) return undefined;
    return hybridData.value.map((row) => stripScore(row));
  }
  return data.value;
});

const totalCount = computed(() => baseRecords.value?.length ?? 0);

const filteredRecords = computed<ListRecordsAPIResponse | undefined>(() => {
  if (!baseRecords.value) return undefined;

  const filtered = baseRecords.value.filter((record) => {
    if (typeFilter.value && record.type !== typeFilter.value) return false;
    if (needsCuration.value && record.isCurated) return false;
    if (hasMediaOnly.value && !hasMedia(record)) return false;
    return true;
  });

  const next = [...filtered];
  const sort = sortKey.value;
  if (sort === 'newest') {
    next.sort((a, b) => (b.recordCreatedAt ?? '').localeCompare(a.recordCreatedAt ?? ''));
  } else if (sort === 'oldest') {
    next.sort((a, b) => (a.recordCreatedAt ?? '').localeCompare(b.recordCreatedAt ?? ''));
  } else if (sort === 'title') {
    next.sort((a, b) => (a.title ?? '').localeCompare(b.title ?? ''));
  }
  // 'relevance' keeps the server order: semantic ranking while searching, and
  // the records query's recordCreatedAt-desc order otherwise.
  return next;
});

// SplitViewLayout/RecordTable both use a defineModel binding to mutate cards
// inline (e.g. inline edits). Wrap filteredRecords in a writable computed so
// children can write back without us re-deriving on every keystroke.
const filteredRecordsModel = computed<ListRecordsAPIResponse>({
  get: () => filteredRecords.value ?? [],
  set: () => {
    // Mutations from RecordCard go to its own model object; we don't need to
    // persist a re-ordered array back. No-op preserves the derived order.
  },
});

function cardPropsFor(record: ListRecordsAPIResponse[number]) {
  // While searching, render results like the dedicated search page: full
  // (un-clamped) content, content preferred over summary, and a parent chip on
  // nested hits (highlights/quotes) so they carry their source context. Return a
  // uniform shape (no optional keys) so it stays assignable to the card-props
  // index signature; the flags default to falsy outside search anyway.
  const searching = hasQuery.value;
  return {
    to: `/v2/${record.slug}`,
    expanded: searching,
    preferContent: searching,
    showParent: searching,
  };
}

const tableHiddenColumns = computed(() => {
  const cols = ['url', 'summary'];
  // When a type filter is active, every row shares the same type — the column
  // adds noise without information.
  if (typeFilter.value) cols.push('type');
  return cols;
});
</script>

<style scoped>
.IndexV2View {
  display: grid;
  grid-template-rows: auto minmax(0, 1fr);
  height: 100%;
  /* `overflow: hidden` resolves the grid's implicit `min-height: auto` to 0, so
   * a large list can't push the row beyond the App__content height. Mirrors
   * the same trick on SplitViewLayout. */
  overflow: hidden;
  /* chrome-top: chrome tone behind the toolbar (--v2-chrome is defined per-mode
   * in the non-scoped <style> below). */
  background-color: var(--v2-chrome);
}

.IndexV2View__toolbar {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 8px;
  padding: 8px 16px;
  /* chrome-top: slightly-darker chrome strip (vs the lighter content panel). */
  background-color: var(--v2-chrome);
  font-size: 12px;
  color: var(--ui-text-muted);
}

.IndexV2View__brand {
  display: inline-flex;
  align-items: center;
  min-width: 0;
}

.IndexV2View__logo {
  font-family: var(--font-serif, 'Georgia', serif);
  font-size: 1.05rem;
  font-weight: 500;
  line-height: 1.2;
  letter-spacing: 0.01em;
  color: var(--ui-text);
  background: transparent;
  border: 0;
  padding: 0;
  margin: 0;
  white-space: nowrap;
  cursor: text;
  transition: color 0.15s ease;
}

.IndexV2View__logo:hover {
  color: var(--ui-text-muted);
}

.IndexV2View__search {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  width: 200px;
  max-width: 32vw;
}

.IndexV2View__searchIcon {
  flex: none;
  width: 16px;
  height: 16px;
  color: var(--ui-text-dimmed);
}

:deep(.IndexV2View__searchInput) {
  flex: 1;
  min-width: 0;

  & input {
    /* Match the collapsed logo / toolbar-control height (24px) so swapping the
     * logo for the input doesn't nudge the toolbar taller. */
    height: 24px;
    font-family: var(--font-serif, 'Georgia', serif);
    font-size: 0.95rem;
    padding-block: 0;
    padding-inline: 0;
    background-color: transparent;
  }
}

:deep(.IndexV2View__searchClear svg) {
  color: var(--ui-text-muted);
}

.IndexV2View__group {
  display: inline-flex;
  align-items: center;
  gap: 2px;
}

/* Slightly smaller icons in the toggle buttons (view mode + type filters). */
:deep(.IndexV2View__group button svg) {
  width: 14px;
  height: 14px;
}

.IndexV2View__divider {
  width: 1px;
  height: 16px;
  background-color: var(--ui-border);
  /* Negative inline margin pulls the divider's neighbors 2px closer than the
   * toolbar's flex gap, tightening item↔divider spacing without touching the
   * non-divider gaps elsewhere in the toolbar. */
  margin: 0 -2px;
}

.IndexV2View__label {
  font-size: 12px;
  color: var(--ui-text-dimmed);
}

.IndexV2View__checkboxes {
  display: inline-flex;
  align-items: center;
  gap: 16px;
  margin-left: 6px;
}

/* Tighten the gap between each checkbox and its label (Nuxt UI defaults to
 * ms-2 / 8px on the label wrapper). */
:deep(.IndexV2View__checkboxes .ms-2) {
  margin-inline-start: 6px;
}

.IndexV2View__sort {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  margin-left: auto;
}

.IndexV2View__count {
  font-size: 12px;
  color: var(--ui-text-dimmed);
}

.IndexV2View__content {
  position: relative;
  min-height: 0;
  overflow: hidden;
  /* chrome-top: lighter content panel with rounded top corners, tucked under
   * the toolbar. The 1px ring + soft shadow lift it off the chrome; the parent's
   * overflow:hidden clips the ring's sides/bottom, leaving a clean hairline +
   * shadow along the rounded top edge. */
  background-color: var(--page-bg);
  border-top-left-radius: var(--radius-lg);
  border-top-right-radius: var(--radius-lg);
  box-shadow:
    0 0 0 1px var(--ui-border-muted),
    0 -1px 4px rgba(0, 0, 0, 0.03);
  transform: translateZ(0);
}

/* chrome-top: subtle top fade so scrolling content dissolves into the panel bg
 * at the rounded top edge instead of cutting off hard. Pinned to the top of the
 * content panel, clipped to its rounded corners by the parent's overflow:hidden,
 * and non-interactive so it never blocks clicks/scroll on the content beneath. */
.IndexV2View__content::before {
  content: '';
  position: absolute;
  inset: 0 0 auto 0;
  height: 20px;
  background: linear-gradient(to bottom, var(--page-bg), transparent);
  pointer-events: none;
  z-index: 2;
}

/* Phones: the search field fills the toolbar row when open (32vw collapses it to
 * an unusable ~125px), and the toolbar's controls stay reachable as it wraps. */
@media (max-width: 640px) {
  .IndexV2View__search {
    width: 100%;
    max-width: 100%;
  }

  .IndexV2View__sort {
    margin-left: 0;
  }
}
</style>

<!-- chrome-top chrome tone, defined per-mode at the document level (not scoped)
  so the dark override lands on <html> instead of being hoisted off the scoped
  .IndexV2View. Kept ~3 levels off the content panel in both modes to match: in
  light #fcfcfb content / #f9f9f7 chrome; in dark #1a1a19 content / #171716
  chrome. -->
<style>
:root {
  --v2-chrome: #f9f9f7;
}

html.dark,
.dark {
  --v2-chrome: #171716;
}
</style>
