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
      td: 'RecordTable__td',
    }"
    :globalFilterOptions
    sticky
    @select="handleRowSelect"
  >
    <template #title-cell="{ row }">
      <img
        v-if="row.original.media?.[0]"
        class="RecordTable__media"
        width="120"
        height="120"
        loading="lazy"
        decoding="async"
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

        <ul
          v-if="getCreator(row) || (getTags(row) ?? []).length > 0"
          class="RecordTable__cellByline"
        >
          <li v-if="getCreator(row)">
            <UButton
              size="sm"
              color="neutral"
              variant="link"
              class="RecordTable__cellButton"
              :to="`/${getCreator(row)!.slug}`"
            >
              <span>{{ getCreator(row)!.title }}</span>
            </UButton>
          </li>

          <template v-if="getTags(row)">
            <li
              v-for="tag in getTags(row)"
              :key="tag.id"
            >
              <RouterLink :to="`/${tag.slug}`"> #{{ slugify(tag.title ?? tag.slug) }} </RouterLink>
            </li>
          </template>
        </ul>
      </div>
    </template>
  </UTable>
</template>

<script setup lang="ts">
import useApiClient from '@app/composables/useApiClient';
import type { ListRecordsAPIResponse } from '@db/queries/records';
import type { TableColumn, TableRow } from '@nuxt/ui';
import { capitalize, formatDate } from '@shared/lib/formatting';
import { isPredicateType } from '@shared/types';
import slugify from 'slugify';
import { computed, h, resolveComponent } from 'vue';
import { useRouter } from 'vue-router';

const modelValue = defineModel<ListRecordsAPIResponse>({ required: true });
const globalFilter = defineModel<string>('globalFilter');

const props = defineProps<{
  hideColumns?: string[];
  /**
   * Build the destination route for a clicked row. Defaults to the root record
   * route (`/{slug}`); pass a builder when the table lives under a parent route
   * (e.g. IndexV2View at `/v2`) so a row click stays in that context instead of
   * escaping to the home index.
   */
  rowTo?: (slug: string) => string;
}>();

const router = useRouter();
const { backendBaseUrl } = useApiClient();

type RecordRow = ListRecordsAPIResponse[number];
type LinkTarget = RecordRow['outgoingLinks'][number]['target'];

// Build per-record creator/tag lookups once per data change. The previous
// implementation cached lazily on first cell access but recomputed on every
// modelValue change only by accident — and templates call these helpers
// multiple times per row, so the map lookup wins on both correctness and cost.
const bylineByRecordId = computed(() => {
  const map = new Map<number, { creator: LinkTarget | null; tags: LinkTarget[] }>();
  const records = modelValue.value;
  if (!records) return map;

  for (const record of records) {
    const outgoingLinks = record.outgoingLinks;
    if (!outgoingLinks) {
      map.set(record.id, { creator: null, tags: [] });
      continue;
    }

    let creator: LinkTarget | null = null;
    const tags: LinkTarget[] = [];
    for (const link of outgoingLinks) {
      if (!creator && link.predicate === 'created_by') {
        creator = link.target;
      } else if (isPredicateType(link.predicate, 'description')) {
        tags.push(link.target);
      }
    }
    map.set(record.id, { creator, tags });
  }
  return map;
});

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
    {
      slug: false,
      id: false,
      url: false,
      content: false,
      media: false,
      outgoingLinks: false,
      incomingLinks: false,
    } as Record<string, boolean>,
  );
});

const columns = [
  {
    accessorKey: 'id',
    header: 'ID',
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
  {
    accessorKey: 'outgoingLinks',
    enableGlobalFilter: false,
  },
  {
    accessorKey: 'incomingLinks',
    enableGlobalFilter: false,
  },
];

function getCreator(row: TableRow<RecordRow>): LinkTarget | null {
  return bylineByRecordId.value.get(row.original.id)?.creator ?? null;
}

function getTags(row: TableRow<RecordRow>): LinkTarget[] {
  return bylineByRecordId.value.get(row.original.id)?.tags ?? [];
}

function handleRowSelect(_event: Event, row: TableRow<ListRecordsAPIResponse[number]>) {
  const slug = row.getValue('slug') as string;
  router.push(props.rowTo ? props.rowTo(slug) : `/${slug}`);
}
</script>

<style scoped>
:global(.RecordTable) {
  overflow: initial;
  /* Clear the floating nav pill + home indicator below the last row. */
  padding-bottom: var(--nav-clearance);
}

.RecordTable__td {
  padding-block: 12px;
}

.RecordTable__contentCell {
  text-wrap: auto;
}

:global(.RecordTable__titleCell) {
  text-wrap: auto;
  display: flex;
  gap: 12px;
}

.RecordTable__titleCell {
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

.RecordTable__titleCellContent {
  display: grid;
  grid-auto-rows: min-content;
  gap: 2px;
}

:global(.RecordTable__th) {
  padding-block: 12px;
  font-size: 12px;
}

.RecordTable__media {
  width: 120px;
  aspect-ratio: 1;
  object-fit: cover;
  border-radius: 8px;
}

:deep(.RecordTable__cellByline) {
  margin-top: 6px;
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
  font-size: 12px;

  & li {
    margin: 0;
  }

  & a:hover {
    color: var(--ui-text);
    text-decoration: underline;
  }
}

:deep(.RecordTable__cellButton) {
  padding: 0;

  &:hover {
    text-decoration: underline;
  }

  & :deep(span) {
    min-width: 0;
    text-overflow: ellipsis;
    overflow: hidden;
    white-space: nowrap;
  }
}
</style>
