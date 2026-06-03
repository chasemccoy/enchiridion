<template>
  <RecordTable
    v-if="data"
    v-model="data"
    :hideColumns="['id', 'type']"
  />
</template>

<script setup lang="ts">
import RecordTable from '@app/components/RecordTable.vue';
import useRecords from '@app/composables/useRecords';

const { data } = useRecords({
  limit: 300,
  filters: {
    type: 'artifact',
    hideUntitledChildren: true,
  },
  orderBy: [
    {
      field: 'recordCreatedAt',
      direction: 'desc',
    },
  ],
});
</script>
