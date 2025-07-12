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
        class="h-80"
        :groups="groups"
        :ui="{
          item: 'SearchModal__item',
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
      ignoreFilter: true,
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
