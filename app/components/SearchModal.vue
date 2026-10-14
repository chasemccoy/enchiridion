<template>
  <UModal
    v-model:open="open"
    title="Search"
    description="Search for records"
    :ui="{ content: 'sm:max-w-2xl' }"
  >
    <template #content>
      <UCommandPalette
        v-model:searchTerm="searchQuery"
        placeholder="Search records..."
        class="max-h-[min(460px,70dvh)]"
        size="sm"
        :groups="groups"
        :ui="{
          input: '[&>input]:text-xs',
          item: 'SearchModal__item',
        }"
      >
        <template #record="{ item }">
          <SearchResultRow
            :record="item.record"
            :query="searchQuery ?? ''"
          />
        </template>
      </UCommandPalette>
    </template>
  </UModal>
</template>

<script setup lang="ts">
import SearchResultRow from '@app/components/SearchResultRow.vue';
import type { ListRecordsAPIResponse } from '@db/queries/records';
import { computed } from 'vue';

const open = defineModel<boolean>('open', {
  required: true,
  default: false,
});

const searchQuery = defineModel<string>('searchQuery');

const { records } = defineProps<{
  records?: ListRecordsAPIResponse;
}>();

// The server already searched, so the palette shows its results as they are
// (`ignoreFilter`) rather than fuzzy-filtering them again by label, and each
// row draws itself (`slot: 'record'`).
const groups = computed(() => {
  if (!records) return [];

  return [
    {
      id: 'records',
      ignoreFilter: true,
      items: records.map((record) => ({
        id: record.slug,
        label: record.title || record.content || record.slug,
        slot: 'record' as const,
        record,
        to: `/${record.slug}`,
        onSelect: () => {
          open.value = false;
        },
      })),
    },
  ];
});
</script>

<style scoped>
:deep(.SearchModal__item) {
  align-items: start;
}
</style>
