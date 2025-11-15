<template>
  <UModal
    v-model:open="open"
    title="Search"
    description="Search for records"
  >
    <template #content>
      <UCommandPalette
        v-model:searchTerm="searchQuery"
        placeholder="Search records..."
        class="h-100"
        :groups="groups"
        :ui="{
          item: 'SearchModal__item',
        }"
        :fuse="{
          resultLimit: 100,
          matchAllWhenSearchEmpty: false,
          fuseOptions: {
            includeMatches: true,
          },
        }"
      />
    </template>
  </UModal>
</template>

<script setup lang="ts">
import type { CommandPaletteItem } from '@nuxt/ui';
import { computed } from 'vue';

const open = defineModel<boolean>('open', {
  required: true,
  default: false,
});

const searchQuery = defineModel<string>('searchQuery');

const { searchResultItems } = defineProps<{
  searchResultItems?: CommandPaletteItem[];
}>();

const groups = computed(() => {
  if (!searchResultItems) return [];

  return [
    {
      id: 'records',
      items: searchResultItems,
    },
  ];
});
</script>

<style scoped>
:deep(.SearchModal__item) {
  & :deep(svg) {
    width: 16px;
    height: 16px;
  }
}
</style>
