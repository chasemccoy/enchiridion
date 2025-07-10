<template>
  <SplitViewLayout
    v-model="data"
    :recordCardProps="(record) => ({ to: `/inbox/record/${record.slug}` })"
    :isEmpty="route.name === RouteName.inbox"
  >
    <RouterView />
  </SplitViewLayout>
</template>

<script setup lang="ts">
import SplitViewLayout from '@app/components/SplitViewLayout.vue';
import useRecords from '@app/composables/useRecords';
import { RouteName } from '@app/router';
import { useRoute } from 'vue-router';

const route = useRoute();

const { data } = useRecords({
  limit: 100,
  filters: {
    isCurated: false,
    hasParent: false,
  },
  orderBy: [
    {
      field: 'recordCreatedAt',
      direction: 'desc',
    },
    {
      field: 'contentCreatedAt',
      direction: 'desc',
    },
    {
      field: 'type',
      direction: 'asc',
    },
  ],
});
</script>
