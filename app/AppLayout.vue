<template>
  <UApp>
    <div class="App">
      <UNavigationMenu
        v-if="route.name !== RouteName.add"
        color="neutral"
        class="App__nav"
        :items="navItems"
        :ui="{
          link: 'App__navLink',
          list: 'App__navList',
        }"
      />

      <div class="App__content">
        <RouterView />
      </div>
    </div>

    <SearchModal
      v-model:open="isSearchModalOpen"
      v-model:searchQuery="searchQuery"
      :searchResultItems="searchResultItems"
    />

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
import { computed, ref, watch } from 'vue';
import { useRoute } from 'vue-router';

const route = useRoute();

const searchQuery = ref('');
const shouldSearch = computed(() => searchQuery.value !== '');

const navItems = [
  [
    {
      to: '/',
      icon: 'i-lucide-home',
    },
    {
      to: '/inbox',
      icon: 'i-lucide-inbox',
    },
    {
      to: '/concepts',
      icon: getIconForRecordType('concept'),
    },
    {
      to: '/entities',
      icon: getIconForRecordType('entity'),
    },
  ],
  [
    {
      icon: 'i-lucide-search',
      onSelect: () => {
        isSearchModalOpen.value = true;
      },
    },
    {
      icon: 'i-lucide-plus',
      onSelect: () => {
        isAddRecordDrawerOpen.value = true;
      },
    },
  ],
];

const isSearchModalOpen = ref(false);
const isAddRecordDrawerOpen = ref(false);

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
