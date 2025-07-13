<template>
  <UApp>
    <div class="App">
      <UNavigationMenu
        v-if="route.name !== RouteName.add"
        color="neutral"
        class="App__nav"
        :items="navItems"
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
  </UApp>
</template>

<script async setup lang="ts">
import SearchModal from '@app/components/SearchModal.vue';
import useSearch from '@app/composables/useSearch';
import { RouteName } from '@app/router';
import { getIconForRecordType } from '@app/utils';
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
      label: 'Inbox',
      to: '/inbox',
      icon: 'i-lucide-inbox',
    },
    {
      label: 'Concepts',
      to: '/concepts',
      icon: getIconForRecordType('concept'),
    },
    {
      label: 'Entities',
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
      to: '/add',
      icon: 'i-lucide-plus',
    },
  ],
];

const isSearchModalOpen = ref(false);

defineShortcuts({
  meta_k: () => {
    isSearchModalOpen.value = !isSearchModalOpen.value;
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
  position: sticky;
  top: 0px;
  z-index: 1;
  background-color: var(--ui-bg);
  border-bottom: 1px solid var(--ui-border);
  padding: 0.25rem 0.5rem;
  overflow-x: hidden;
}

.App__content {
  padding: 1rem;
  display: grid;
  gap: 2rem;
  align-items: start;
  overflow: auto;
  grid-row: 2;
}
</style>
