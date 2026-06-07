<template>
  <div class="IndexV2TablePane">
    <RecordTable
      v-if="model"
      v-model="model"
      :hideColumns="hideColumns"
      :rowTo="rowTo"
    />
  </div>
</template>

<script setup lang="ts">
import RecordTable from '@app/components/RecordTable.vue';
import type { ListRecordsAPIResponse } from '@db/queries/records';

const model = defineModel<ListRecordsAPIResponse>();

defineProps<{
  hideColumns?: string[];
  rowTo?: (slug: string) => string;
}>();
</script>

<style scoped>
.IndexV2TablePane {
  height: 100%;
  overflow-y: auto;
  overscroll-behavior: contain;
  padding: 0 16px var(--nav-clearance);
}
</style>
