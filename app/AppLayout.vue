<template>
  <UApp>
    <div class="App">
      <UNavigationMenu
        v-if="route.name !== RouteName.add && !isDesignLabRoute"
        color="neutral"
        class="App__nav shadow-2xl"
        :items="navItems"
        :ui="{
          link: 'App__navLink',
          list: 'App__navList',
        }"
      />

      <div class="App__content">
        <RouterView v-slot="{ Component }">
          <KeepAlive :max="6">
            <component :is="Component" />
          </KeepAlive>
        </RouterView>
      </div>
    </div>

    <SearchModal
      v-model:open="isSearchModalOpen"
      v-model:searchQuery="searchQuery"
      :searchResultItems="searchResultItems"
    />

    <SettingsModalView v-model:isOpen="isSettingsModalOpen" />

    <AddRecordDrawerView
      v-model:open="isAddRecordDrawerOpen"
      @close="isAddRecordDrawerOpen = false"
    />
  </UApp>
</template>

<script async setup lang="ts">
import SearchModal from '@app/components/SearchModal.vue';
import useSearch from '@app/composables/useSearch';
import { RouteName } from '@app/router';
import { getIconForRecordType } from '@app/utils';
import AddRecordDrawerView from '@app/views/AddRecordDrawerView.vue';
import SettingsModalView from '@app/views/SettingsModalView.vue';
import { computed, ref, watch } from 'vue';
import { useRoute } from 'vue-router';

const route = useRoute();

// Match the design-lab route by a *matched* route record's path, not the raw
// URL. The index route has a `:slug` child, so `route.path.startsWith(...)`
// would also fire for a real record whose slug merely begins with "design-lab"
// (e.g. /design-lab-notes), wrongly hiding the bottom nav on that record.
const isDesignLabRoute = computed(() =>
  route.matched.some((record) => record.path.startsWith('/design-lab')),
);

const searchQuery = ref('');
const shouldSearch = computed(() => searchQuery.value !== '');

// Smooth-scroll whichever container is scrolling on the current view back to
// the top. The index's cards pane scrolls the inner `.SplitViewLayout_list`,
// its table pane scrolls the `.IndexTablePane` wrapper, and other views fall
// back to the outer `.App__content`. We try the inner ones first so we don't
// accidentally scroll a parent on views with their own internal scroller.
// (IndexView.scrollActiveViewToTop probes the same two pane selectors.)
function scrollActiveViewToTop() {
  const candidates = ['.SplitViewLayout_list', '.IndexTablePane', '.App__content'];
  for (const selector of candidates) {
    const el = document.querySelector(selector) as HTMLElement | null;
    if (el && el.scrollHeight > el.clientHeight) {
      el.scrollTo({ top: 0, behavior: 'smooth' });
      return;
    }
  }
}

// Resolve a nav item's `to` so clicking it while you're already on that page
// is a true no-op for the router — same `fullPath` in, same `fullPath` out.
// Without this, clicking Home from `/?q=foo` would be a real navigation (path
// matches, query differs) and the index's search query would get dropped.
function navTo(basePath: string) {
  return route.path === basePath ? route.fullPath : basePath;
}

const navItems = computed(() => [
  [
    {
      to: navTo('/'),
      icon: 'i-lucide-home',
      onSelect: () => {
        if (route.path === '/') scrollActiveViewToTop();
      },
    },
    {
      icon: 'i-lucide-search',
      onSelect: () => {
        isSearchModalOpen.value = true;
      },
    },
  ],
  [
    {
      icon: 'i-lucide-settings',
      onSelect: () => {
        isSettingsModalOpen.value = true;
      },
    },
    {
      icon: 'i-lucide-plus',
      onSelect: () => {
        isAddRecordDrawerOpen.value = true;
      },
    },
  ],
]);

const isSearchModalOpen = ref(false);
const isAddRecordDrawerOpen = ref(false);
const isSettingsModalOpen = ref(false);

defineShortcuts({
  meta_k: () => {
    isSearchModalOpen.value = !isSearchModalOpen.value;
  },
  n: () => {
    isAddRecordDrawerOpen.value = !isAddRecordDrawerOpen.value;
  },
});

const { data: searchResults } = useSearch(searchQuery, shouldSearch);

const searchResultItems = computed(() => {
  if (!searchResults.value) return undefined;

  return searchResults.value.map((result) => ({
    label: result.title || result.content || result.slug,
    id: result.slug,
    icon: getIconForRecordType(result.type),
    to: `/${result.slug}`,
    suffix: result.summary || result.content || result.notes || undefined,
    onSelect: () => {
      isSearchModalOpen.value = false;
    },
  }));
});

watch(isSearchModalOpen, () => {
  if (!isSearchModalOpen.value) {
    searchQuery.value = '';
  }
});
</script>

<style scoped>
.App {
  isolation: isolate;
  /* dvh tracks the visible viewport as mobile browser chrome shows/hides; vh is
   * the fallback for engines without dvh. */
  max-height: 100vh;
  max-height: 100dvh;
  min-height: 100vh;
  min-height: 100dvh;
  overflow: hidden;
  display: grid;
  grid-template-rows: auto minmax(0px, 1fr);
  /* Inset the whole app from the notch in landscape (≈0 in portrait). Done once
   * here so every view clears the Dynamic Island without per-view padding. */
  padding-left: env(safe-area-inset-left);
  padding-right: env(safe-area-inset-right);
}

:deep(.App__nav) {
  position: fixed;
  /* Lift the pill above the home indicator on notched iPhones (inset ≈ 34px);
   * falls back to a flat 24px where there's no inset. */
  bottom: calc(24px + env(safe-area-inset-bottom));
  left: 50%;
  transform: translateX(-50%);
  z-index: 1;
  background-color: var(--ui-color-neutral-800);
  color: var(--ui-text-inverted);
  padding: 0 4px;
  overflow-x: hidden;
  border-radius: 9999px;
  gap: 0px;
}

:global(.App__navList) {
  gap: 4px;
}

:global(.App__nav > div:not(:first-child) > .App__navList) {
  gap: 0px;
}

:global(.App__nav > div:not(:first-child) > .App__navList:before) {
  content: '';
  width: 2px;
  background-color: var(--ui-color-neutral-700);
  height: 16px;
  border-radius: 2px;
  margin-inline: 8px;
}

:global(.App__navLink) {
  padding: 10px;
  cursor: default;
  margin: -4px 0;
}

:global(.App__navLink:before) {
  border-radius: 9999px;
  inset: 0;
}

@supports (corner-shape: superellipse(1.333)) {
  :global(.App__navLink:before) {
    border-radius: 16px;
    inset: 0;
  }
}

:global(.App__navLink:not([aria-current]):hover svg),
:global(.dark .App__navLink:not([aria-current]):hover svg) {
  color: var(--ui-color-neutral-400);
}

:global(.dark .App__navLink:not([aria-current]) svg) {
  color: var(--ui-color-neutral-500);
}

:global(.App__navLink:not([aria-current]):hover:before) {
  background-color: var(--ui-color-neutral-700);
}

:global(.dark .App__navLink[aria-current]:before) {
  background-color: var(--ui-color-neutral-600);
}

.App__content {
  display: grid;
  /* minmax(0, 1fr) caps the content column at the viewport width so an over-wide
   * child (e.g. the records table) overflows its own area instead of stretching
   * the whole column past the screen and dragging headers/toolbars off-edge. */
  grid-template-columns: minmax(0, 1fr);
  gap: 2rem;
  align-items: start;
  overflow-y: auto;
  grid-row: 2;
  /* Keep edge bounce inside the app shell rather than chaining to the document
   * (which would expose the area behind the shell on iOS). */
  overscroll-behavior: contain;
  /* Anchored scrolls (scrollIntoView on the selected record, table sticky
   * header) stop clear of the floating nav pill. */
  scroll-padding-bottom: var(--nav-clearance);
}
</style>
