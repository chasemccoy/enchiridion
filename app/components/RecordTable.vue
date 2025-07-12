<template>
  <UTable
    v-if="modelValue"
    :data="modelValue"
    :columns="columns"
    :columnVisibility="columnVisibility"
    @select="handleRowSelect"
  >
    <template #title-cell="{ row }">
      <a
        v-if="row.getValue('url')"
        class="RecordTable__titleCellLink"
        target="_blank"
        :href="row.getValue('url')"
      >
        {{ row.getValue('title') }}
      </a>
      <template v-else>
        {{ row.getValue('title') }}
      </template>
    </template>
  </UTable>
</template>

<script setup lang="ts">
import type { ListRecordsAPIResponse } from '@db/queries/records';
import type { TableRow } from '@nuxt/ui';
import { capitalize, formatDate } from '@shared/lib/formatting';
import { computed, h, resolveComponent } from 'vue';
import { useRouter } from 'vue-router';

const modelValue = defineModel<ListRecordsAPIResponse>({ required: true });

const props = defineProps<{
  hideColumns?: string[];
}>();

const router = useRouter();

const UBadge = resolveComponent('UBadge');

const columnVisibility = computed(() => {
  return props.hideColumns?.reduce(
    (acc, column) => {
      acc[column] = false;
      return acc;
    },
    { slug: false, id: false, summary: false, url: false } as Record<string, boolean>,
  );
});

const columns = [
  {
    accessorKey: 'id',
    header: 'ID',
  },
  {
    accessorKey: 'type',
    header: 'Type',
    cell: ({ row }: { row: TableRow<ListRecordsAPIResponse[number]> }) => {
      return h(
        UBadge,
        {
          color: 'neutral',
          variant: 'outline',
        },
        () => capitalize(row.getValue('type') as string),
      );
    },
  },
  {
    accessorKey: 'slug',
    header: 'Slug',
  },
  {
    accessorKey: 'title',
    header: 'Title',
    meta: {
      class: {
        td: 'RecordTable__titleCell',
      },
    },
  },
  {
    accessorKey: 'url',
    header: 'URL',
  },
  {
    accessorKey: 'content',
    header: 'Content',
    cell: ({ row }: { row: TableRow<ListRecordsAPIResponse[number]> }) => {
      return row.getValue('content') || row.getValue('summary');
    },
    meta: {
      class: {
        td: 'RecordTable__contentCell',
      },
    },
  },
  {
    accessorKey: 'summary',
    header: 'Summary',
  },
  {
    accessorKey: 'recordCreatedAt',
    header: 'Saved',
    cell: ({ row }: { row: TableRow<ListRecordsAPIResponse[number]> }) => {
      return formatDate(row.getValue('recordCreatedAt'));
    },
  },
];

function handleRowSelect(row: TableRow<ListRecordsAPIResponse[number]>) {
  router.push(`/${row.getValue('slug')}`);
}
</script>

<style scoped>
:deep(.RecordTable__contentCell) {
  max-width: 400px;
  text-wrap: auto;
}

:deep(.RecordTable__titleCell) {
  max-width: 400px;
  text-wrap: auto;

  & .RecordTable__titleCellLink {
    color: var(--ui-primary);
    font-weight: 500;
  }

  & .RecordTable__titleCellLink:hover {
    text-decoration: underline;
  }
}
</style>
