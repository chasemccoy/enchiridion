<template>
  <div
    class="IndexView"
    :class="{ 'IndexView--detail': route.params.slug }"
  >
    <header class="IndexView__toolbar">
      <IndexSearchInput v-model="searchInput" />

      <div
        class="IndexView__group"
        role="group"
        aria-label="View mode"
      >
        <UButton
          size="xs"
          icon="i-lucide-layout-grid"
          :color="view === 'cards' ? 'primary' : 'neutral'"
          :variant="view === 'cards' ? 'soft' : 'ghost'"
          :aria-pressed="view === 'cards'"
          @click="setView('cards')"
        >
          Cards
        </UButton>
        <UButton
          size="xs"
          icon="i-lucide-table-properties"
          :color="view === 'table' ? 'primary' : 'neutral'"
          :variant="view === 'table' ? 'soft' : 'ghost'"
          :aria-pressed="view === 'table'"
          @click="setView('table')"
        >
          Table
        </UButton>
      </div>

      <div class="IndexView__divider" />

      <div class="IndexView__group">
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

      <div class="IndexView__divider" />

      <div class="IndexView__checkboxes">
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

      <div class="IndexView__sort">
        <USelectMenu
          v-model="sortKey"
          size="xs"
          variant="ghost"
          valueKey="id"
          :items="sortOptions"
          :searchInput="false"
        />
      </div>

      <div
        class="IndexView__count"
        :class="{ 'IndexView__count--error': hasQuery && searchError }"
      >
        <template v-if="hasQuery && searchError"> Search failed. Try again. </template>
        <template v-else-if="hasQuery && searchFetching && !filteredRecords?.length">
          Searching…
        </template>
        <template v-else-if="filteredRecords">
          {{ filteredRecords.length }}
          <template v-if="filteredRecords.length !== totalCount"> of {{ totalCount }} </template>
          {{ hasQuery ? 'results' : 'records' }}
        </template>
      </div>
    </header>

    <div class="IndexView__content">
      <!-- KeepAlive caches whichever pane is inactive so switching Cards↔Table
        never re-instantiates ~500 components (the switch was 0.6–0.9s of Vue
        mount + GC churn). The inactive pane is also paused, so a search doesn't
        re-render the hidden view on every keystroke. IndexTablePane wraps
        RecordTable to carry the index-specific scroll-container CSS without
        leaking it to the other RecordTable views. -->
      <KeepAlive>
        <SplitViewLayout
          v-if="view === 'cards'"
          key="cards"
          :modelValue="records"
          :isEmpty="!route.params.slug"
          :recordCardProps="cardPropsFor"
          :grouped="!hasQuery && sortKey !== 'title'"
        >
          <RouterView />
        </SplitViewLayout>

        <IndexTablePane
          v-else
          key="table"
          :modelValue="records"
          :hideColumns="tableHiddenColumns"
        />
      </KeepAlive>
    </div>
  </div>
</template>

<script setup lang="ts">
import IndexSearchInput from '@app/components/IndexSearchInput.vue';
import IndexTablePane from '@app/components/IndexTablePane.vue';
import SplitViewLayout from '@app/components/SplitViewLayout.vue';
import useQueryState from '@app/composables/useQueryState';
import useRecords from '@app/composables/useRecords';
import useHybridSearch from '@app/composables/useHybridSearch';
import { getIconForRecordType, hasMedia, isRecordType, stripScore } from '@app/utils';
import type { ListRecordsAPIResponse } from '@db/queries/records';
import type { RecordType } from '@shared/types';
import { capitalize, computed, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';

type ViewMode = 'cards' | 'table';
type SortKey = 'relevance' | 'newest' | 'oldest' | 'title';

const route = useRoute();
const router = useRouter();
const { readQuery, updateQuery } = useQueryState();

// Search query (URL `?q=`). Defined up here because the sort options and default
// below switch on whether a search is active.
const isString = (value: unknown): value is string => typeof value === 'string';
const q = computed(() => readQuery('q', '', isString));
const hasQuery = computed(() => q.value.trim().length > 0);

// The serif logo doubles as the search input (IndexSearchInput); it writes
// keystrokes here immediately, and we debounce the URL commit so typing doesn't
// thrash the router or fire a hybrid search per character. The query is
// URL-backed (`?q=`) so it survives reloads, deep links, and back/forward.
const searchInput = ref(q.value);

// External URL changes (back/forward, deep links) flow back into the input.
// This also clears any pending commit below, since the watcher reschedules.
watch(q, (next) => {
  if (next !== searchInput.value) searchInput.value = next;
});

let commitTimer: ReturnType<typeof setTimeout> | undefined;
watch(searchInput, (next) => {
  // Capture where the user was typing: if the path changes before the timer
  // fires (they opened a record, or left the index entirely while this view sat
  // cached in KeepAlive), the pending commit is stale — drop it instead of
  // yanking the route back to '/' or stamping `?q=` onto another view's URL.
  const pathAtKeystroke = route.path;
  clearTimeout(commitTimer);
  commitTimer = setTimeout(() => {
    if (route.path !== pathAtKeystroke) {
      // Navigating abandoned the in-progress search; resync the input to the
      // URL so the box doesn't show text that was never committed.
      searchInput.value = q.value;
      return;
    }
    if (next === q.value) return;

    const query = { ...route.query };
    if (next) query.q = next;
    else delete query.q;

    // Starting a search while a record is open: deselect it by dropping the
    // `/:slug` child route, so results fill the page instead of rendering in
    // the narrow split-view list. Other query state is preserved.
    const location = next.trim() && route.params.slug ? { path: '/', query } : { query };

    // Entering a search pushes a history entry so Back returns to the
    // pre-search browse state; refining or clearing replaces so individual
    // keystrokes don't pile up in history.
    if (next.trim() && !hasQuery.value) router.push(location);
    else router.replace(location);
  }, 150);
});

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
const typeFilter = computed(() => readQuery<RecordType | null>('type', null, isRecordType));
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

function setView(value: ViewMode) {
  // Pressing the already-active view toggle scrolls that pane to the top
  // (mirrors the bottom-nav "tap active tab to scroll up" behavior).
  if (value === view.value) {
    scrollActiveViewToTop();
    return;
  }
  // The detail pane only exists in cards mode, so switching to the table
  // deselects the open record rather than leaving a record in the URL that
  // nothing renders.
  if (value === 'table' && route.params.slug) {
    router.replace({ path: '/', query: { ...route.query, view: 'table' } });
    return;
  }
  updateQuery({ view: value === 'cards' ? undefined : value });
}

// Deep links and back/forward can still pair a record with `?view=table` (e.g.
// a shared URL). The record wins: drop the view param so the cards pane renders
// the detail instead of silently hiding it behind the table.
watch(
  () => [route.params.slug, view.value] as const,
  ([slug, viewMode]) => {
    if (slug && viewMode === 'table') updateQuery({ view: undefined });
  },
  { immediate: true },
);

// Each pane has its own scroll container: the cards list scrolls the inner
// `.SplitViewLayout_list`, the table scrolls the `.IndexTablePane` wrapper
// (RecordTable itself is overflow: initial). The inactive pane is detached by
// <KeepAlive>, so a scoped query resolves to whichever is currently showing.
// AppLayout's nav scroll-to-top probes the same two selectors.
function scrollActiveViewToTop() {
  const selector = view.value === 'cards' ? '.SplitViewLayout_list' : '.IndexTablePane';
  const scroller = document.querySelector<HTMLElement>(`.IndexView__content ${selector}`);
  scroller?.scrollTo({ top: 0, behavior: 'smooth' });
}

function toggleType(value: RecordType) {
  updateQuery({ type: typeFilter.value === value ? undefined : value });
}

// Effectively unbounded — the API has no max-limit and this page is supposed to
// surface every record at once. The number just has to stay comfortably above
// the real record count (704 today).
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
const {
  data: hybridData,
  isFetching: searchFetching,
  error: searchError,
} = useHybridSearch(q, hasQuery);

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

  // `.filter()` returns a fresh array, so sorting in place is safe. The browse
  // list already arrives newest-first from the server, so 'newest' only sorts
  // while searching (where server order is relevance); 'relevance' keeps the
  // server order outright.
  const filtered = baseRecords.value.filter((record) => {
    if (typeFilter.value && record.type !== typeFilter.value) return false;
    if (needsCuration.value && record.isCurated) return false;
    if (hasMediaOnly.value && !hasMedia(record)) return false;
    return true;
  });

  const sort = sortKey.value;
  if (sort === 'newest' && hasQuery.value) {
    filtered.sort((a, b) => (b.recordCreatedAt ?? '').localeCompare(a.recordCreatedAt ?? ''));
  } else if (sort === 'oldest') {
    filtered.sort((a, b) => (a.recordCreatedAt ?? '').localeCompare(b.recordCreatedAt ?? ''));
  } else if (sort === 'title') {
    filtered.sort((a, b) => (a.title ?? '').localeCompare(b.title ?? ''));
  }
  return filtered;
});

// The panes only read this array — inline edits from RecordCard mutate the
// record objects in place, never the array itself — so it's a plain prop
// binding (`:modelValue`), not a v-model.
const records = computed<ListRecordsAPIResponse>(() => filteredRecords.value ?? []);

// Query params carried through card/row navigation: everything except `q`
// (opening a result deliberately ends the search — results and an open detail
// don't coexist) and `view` (the detail pane only exists in cards mode).
// Serialized once here because RecordCard's `to` prop is a string.
const detailQuerySuffix = computed(() => {
  const search = new URLSearchParams();
  for (const [key, value] of Object.entries(route.query)) {
    if (key === 'q' || key === 'view') continue;
    const values = Array.isArray(value) ? value : [value];
    for (const entry of values) {
      if (typeof entry === 'string') search.append(key, entry);
    }
  }
  const serialized = search.toString();
  return serialized ? `?${serialized}` : '';
});

function cardPropsFor(record: ListRecordsAPIResponse[number]) {
  // While searching, render results like the old dedicated search page: full
  // (un-clamped) content, content preferred over summary, and a parent chip on
  // nested hits (highlights/quotes) so they carry their source context. Return a
  // uniform shape (no optional keys) so it stays assignable to the card-props
  // index signature; the flags default to falsy outside search anyway.
  const searching = hasQuery.value;
  return {
    to: `/${record.slug}${detailQuerySuffix.value}`,
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
.IndexView {
  display: grid;
  grid-template-rows: auto minmax(0, 1fr);
  height: 100%;
  /* `overflow: hidden` resolves the grid's implicit `min-height: auto` to 0, so
   * a large list can't push the row beyond the App__content height. Mirrors
   * the same trick on SplitViewLayout. */
  overflow: hidden;
  /* chrome-top: chrome tone behind the toolbar (--index-chrome is a per-mode
   * theme token defined in app/assets/theme.css). */
  background-color: var(--index-chrome);
}

.IndexView__toolbar {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 8px;
  padding: 8px 16px;
  /* chrome-top: slightly-darker chrome strip (vs the lighter content panel). */
  background-color: var(--index-chrome);
  font-size: 12px;
  color: var(--ui-text-muted);
}

.IndexView__group {
  display: inline-flex;
  align-items: center;
  gap: 2px;
}

/* Slightly smaller icons in the toggle buttons (view mode + type filters). */
:deep(.IndexView__group button svg) {
  width: 14px;
  height: 14px;
}

.IndexView__divider {
  width: 1px;
  height: 16px;
  background-color: var(--ui-border);
  /* Negative inline margin pulls the divider's neighbors 2px closer than the
   * toolbar's flex gap, tightening item↔divider spacing without touching the
   * non-divider gaps elsewhere in the toolbar. */
  margin: 0 -2px;
}

.IndexView__checkboxes {
  display: inline-flex;
  align-items: center;
  gap: 16px;
  margin-left: 6px;
}

/* Tighten the gap between each checkbox and its label (Nuxt UI defaults to
 * ms-2 / 8px on the label wrapper). */
:deep(.IndexView__checkboxes .ms-2) {
  margin-inline-start: 6px;
}

.IndexView__sort {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  margin-left: auto;
}

.IndexView__count {
  font-size: 12px;
  color: var(--ui-text-dimmed);
}

.IndexView__count--error {
  color: var(--ui-error);
}

.IndexView__content {
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
.IndexView__content::before {
  content: '';
  position: absolute;
  inset: 0 0 auto 0;
  height: 20px;
  background: linear-gradient(to bottom, var(--page-bg), transparent);
  pointer-events: none;
  z-index: 2;
}

/* Phones: keep the sort control flush-left as the toolbar wraps. */
@media (max-width: 640px) {
  .IndexView__sort {
    margin-left: 0;
  }
}

/* Phones: with a record open the split view collapses to the detail only
 * (SplitViewLayout hides the list ≤768px), so hide the toolbar too — its
 * controls act on the hidden list and just steal height from the record. */
@media (max-width: 768px) {
  .IndexView--detail .IndexView__toolbar {
    display: none;
  }
}
</style>
