<template>
  <SplitViewLayout
    v-model="data"
    :isEmpty="route.name === RouteName.index"
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
    type: 'artifact',
    hasParent: false,
  },
  orderBy: [
    {
      field: 'recordCreatedAt',
      direction: 'desc',
    },
  ],
});
</script>
