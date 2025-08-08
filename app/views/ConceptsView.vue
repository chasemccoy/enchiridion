<template>
  <RecordTable
    v-if="data"
    v-model="data"
    :hideColumns="['type', 'content', 'url', 'summary']"
  />
</template>

<script setup lang="ts">
import RecordTable from '@app/components/RecordTable.vue';
import useRecords from '@app/composables/useRecords';

const { data } = useRecords({
  filters: {
    type: 'concept',
  },
  orderBy: [
    {
      field: 'title',
      direction: 'asc',
    },
  ],
});
</script>
