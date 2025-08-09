<template>
  <UTable
    v-if="modelValue"
    v-model:globalFilter="globalFilter"
    :data="modelValue"
    :columns="columns"
    :columnVisibility="columnVisibility"
    :ui="{
      root: 'RecordTable',
      th: 'RecordTable__th',
    }"
    :globalFilterOptions
    sticky
    @select="handleRowSelect"
  >
    <template #title-cell="{ row }">
      <img
        v-if="row.original.media?.[0]"
        class="RecordTable__media"
        :src="`${backendBaseUrl}${row.original.media[0].url}`"
      />
      <div class="RecordTable__titleCellContent">
        <div
          v-if="row.original.title"
          class="RecordTable__titleCellTitle"
        >
          <a
            v-if="row.original.url"
            class="RecordTable__titleCellLink"
            target="_blank"
            :href="row.original.url"
          >
            {{ row.original.title }}
          </a>
          <template v-else>
            {{ row.original.title }}
          </template>
        </div>

        <div v-if="row.original.summary || row.original.content">
          {{ row.original.summary || row.original.content }}
        </div>
      </div>
    </template>
  </UTable>
</template>

<script setup lang="ts">
import useApiClient from '@app/composables/useApiClient';
import type { ListRecordsAPIResponse } from '@db/queries/records';
import type { TableColumn, TableRow } from '@nuxt/ui';
import { capitalize, formatDate } from '@shared/lib/formatting';
import { computed, h, resolveComponent } from 'vue';
import { useRouter } from 'vue-router';

const modelValue = defineModel<ListRecordsAPIResponse>({ required: true });
const globalFilter = defineModel<string>('globalFilter');

const props = defineProps<{
  hideColumns?: string[];
}>();

const router = useRouter();
const { backendBaseUrl } = useApiClient();

const globalFilterOptions = {
  getColumnCanGlobalFilter: (column: TableColumn<ListRecordsAPIResponse[number]>) => {
    return column.enableGlobalFilter === undefined ? true : column.enableGlobalFilter;
  },
};

const UBadge = resolveComponent('UBadge');

const columnVisibility = computed(() => {
  return props.hideColumns?.reduce(
    (acc, column) => {
      acc[column] = false;
      return acc;
    },
    { slug: false, id: false, url: false, content: false, media: false } as Record<string, boolean>,
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
    header: 'Record',
    meta: {
      class: {
        td: 'RecordTable__titleCell',
      },
    },
  },
  {
    accessorKey: 'url',
    header: 'URL',
    enableGlobalFilter: false,
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
  {
    accessorKey: 'media',
    header: 'Media',
    enableGlobalFilter: false,
  },
];

function handleRowSelect(row: TableRow<ListRecordsAPIResponse[number]>) {
  router.push(`/${row.getValue('slug')}`);
}
</script>

<style scoped>
:global(.RecordTable) {
  overflow: initial;
  padding-bottom: 6rem;
}

:deep(.RecordTable__contentCell) {
  max-width: 400px;
  text-wrap: auto;
}

:deep(.RecordTable__titleCell) {
  text-wrap: auto;
  display: flex;
  gap: 12px;

  & .RecordTable__titleCellContent {
    display: grid;
  }

  & .RecordTable__titleCellLink {
    color: var(--ui-primary);
    font-weight: 500;
  }

  & .RecordTable__titleCellLink:hover {
    text-decoration: underline;
  }
}

:deep(.RecordTable__th) {
  padding-block: 12px;
  font-size: 12px;
}

:deep(.RecordTable__media) {
  width: 88px;
  aspect-ratio: 1;
  object-fit: cover;
  border-radius: 8px;
}
</style>
