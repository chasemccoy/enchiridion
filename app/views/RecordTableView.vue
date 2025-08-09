<template>
  <div class="ConceptsView">
    <header class="ConceptsView__header">
      <USelectMenu
        v-model="type"
        valueKey="id"
        size="sm"
        variant="none"
        :items="typeOptions"
        :searchInput="false"
      />

      <div v-if="data">{{ data.length }} records</div>
    </header>

    <RecordTable
      v-if="data"
      v-model="data"
      :hideColumns="['type', 'url', 'summary']"
    />
  </div>
</template>

<script setup lang="ts">
import RecordTable from '@app/components/RecordTable.vue';
import useRecords from '@app/composables/useRecords';
import type { RecordType } from '@shared/types';
import type { ListRecordsInput } from '@shared/types/api';
import { computed, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';

const route = useRoute();
const router = useRouter();

const defaultType = 'artifact';
const type = ref<RecordType>(defaultType);

const typeOptions = [
  {
    label: 'Artifacts',
    id: 'artifact',
  },
  {
    label: 'Concepts',
    id: 'concept',
  },
  {
    label: 'Entities',
    id: 'entity',
  },
];

watch(type, (newType) => {
  if (newType && newType !== defaultType) {
    router.replace({ hash: `#${newType}` });
  } else {
    router.replace({ hash: '' });
  }
});

watch(
  () => route.hash,
  (newHash) => {
    const hashValue = newHash.replace('#', '');

    if (hashValue && typeOptions.some((option) => option.id === hashValue)) {
      type.value = hashValue as RecordType;
    } else {
      type.value = defaultType;
    }
  },
  { immediate: true },
);

const queryOptions = computed<ListRecordsInput>(() => ({
  filters: {
    type: type.value,
  },
  limit: 300,
  orderBy:
    type.value === 'artifact'
      ? [{ field: 'recordCreatedAt', direction: 'desc' }]
      : [{ field: 'title', direction: 'asc' }],
}));

const { data } = useRecords(queryOptions);
</script>

<style scoped>
.ConceptsView__header {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 4px 16px 4px 6px;
  background-color: var(--ui-bg);
  font-size: 12px;
  border-bottom: 1px solid var(--ui-border);
  color: var(--ui-text-muted);
}
</style>
