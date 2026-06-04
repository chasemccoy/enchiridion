<template>
  <UApp>
    <div class="App">
      <UNavigationMenu
        v-if="route.name !== RouteName.add"
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

const searchQuery = ref('');
const shouldSearch = computed(() => searchQuery.value !== '');

// Smooth-scroll whichever container is scrolling on the current view back to
// the top. Different views use different scroll containers: Home/Inbox scroll
// the inner `.SplitViewLayout_list`, Records scrolls the outer `.App__content`.
// We try the inner one first so we don't accidentally scroll a parent on
// views that have their own internal scroller.
function scrollActiveViewToTop() {
  const candidates = ['.SplitViewLayout_list', '.App__content'];
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
// Without this, navigating to e.g. `/search` from `/search?q=foo` is a real
// navigation (path matches, query differs) and the query gets dropped, which
// resets the search. Same applies to `/records#concept` and friends.
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
      to: navTo('/inbox'),
      icon: 'i-lucide-inbox',
    },
    {
      to: navTo('/records'),
      icon: 'i-lucide-table-properties',
      onSelect: () => {
        if (route.path === '/records') scrollActiveViewToTop();
      },
    },
    {
      to: navTo('/search'),
      icon: 'i-lucide-search',
      onSelect: () => {
        if (route.path !== '/search') return;
        scrollActiveViewToTop();
        // Drop focus into the search box so the user can start typing right
        // away. UInput renders a real <input> inside `.SearchView__input`.
        const input = document.querySelector<HTMLInputElement>('.SearchView__input input');
        // preventScroll keeps focus() from snapping the viewport to the input,
        // which would override the smooth scroll-to-top above.
        input?.focus({ preventScroll: true });
        input?.select();
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
  max-height: 100vh;
  min-height: 100vh;
  overflow: hidden;
  display: grid;
  grid-template-rows: auto minmax(0px, 1fr);
}

:deep(.App__nav) {
  position: fixed;
  bottom: 24px;
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

.App__content {
  display: grid;
  gap: 2rem;
  align-items: start;
  overflow-y: auto;
  grid-row: 2;
}
</style>
