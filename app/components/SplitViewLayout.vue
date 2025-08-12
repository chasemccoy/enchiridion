<template>
  <div
    ref="elRef"
    class="SplitViewLayout"
    :class="{ 'SplitViewLayout--empty': isEmpty }"
  >
    <div class="SplitViewLayout_list">
      <div
        v-if="modelValue"
        class="SplitViewLayout_groups"
      >
        <div
          v-for="(group, groupKey) in groupedRecords"
          :key="groupKey"
          class="SplitViewLayout_group"
        >
          <h3 class="SplitViewLayout_groupHeader">
            {{ groupKey }}
            <template v-if="group.length > 4">({{ group.length }})</template>
          </h3>
          <ul class="SplitViewLayout_grid">
            <li
              v-for="record in group"
              :key="record.id"
            >
              <RecordCard
                v-model="modelValue[getRecordIndex(record.id)]"
                v-bind="getRecordCardProps(record)"
                :data-slug="record.slug"
                @vue:Mounted="handleRecordMounted(modelValue[getRecordIndex(record.id)])"
              />
            </li>
          </ul>
        </div>
      </div>
    </div>

    <div
      v-if="!isEmpty"
      class="SplitViewLayout_detail"
    >
      <slot />
    </div>
  </div>
</template>

<script setup lang="ts">
import RecordCard from '@app/components/RecordCard.vue';
import type { ListRecordsAPIResponse } from '@db/queries/records';
import { useTemplateRef, watch, computed } from 'vue';
import { useRoute } from 'vue-router';

const modelValue = defineModel<ListRecordsAPIResponse>();

const { isEmpty, recordCardProps } = defineProps<{
  isEmpty?: boolean;
  recordCardProps?: (record: ListRecordsAPIResponse[number]) => Record<string, string>;
}>();

const elRef = useTemplateRef('elRef');
const route = useRoute();

// Group records by month and year
const groupedRecords = computed(() => {
  if (!modelValue.value) return {};

  const groups: Record<string, ListRecordsAPIResponse> = {};

  modelValue.value.forEach((record) => {
    if (!record.recordCreatedAt) return;

    const date = new Date(record.recordCreatedAt + 'Z');
    const monthYear = date.toLocaleDateString('en-US', {
      month: 'long',
      year: 'numeric',
    });

    if (!groups[monthYear]) {
      groups[monthYear] = [];
    }

    groups[monthYear].push(record);
  });

  // Sort groups by date (newest first)
  const sortedGroups: Record<string, ListRecordsAPIResponse> = {};
  Object.keys(groups)
    .sort((a, b) => {
      // Parse the month/year strings back to dates for proper sorting
      const dateA = new Date(a);
      const dateB = new Date(b);
      return dateB.getTime() - dateA.getTime();
    })
    .forEach((key) => {
      sortedGroups[key] = groups[key];
    });

  return sortedGroups;
});

// Helper function to get the original index of a record in the modelValue array
function getRecordIndex(recordId: number): number {
  return modelValue.value?.findIndex((record) => record.id === recordId) ?? -1;
}

watch(
  route,
  () => {
    scrollToSelectedRecord();
  },
  { flush: 'post', immediate: true },
);

function getRecordCardProps(record: ListRecordsAPIResponse[number]) {
  if (typeof recordCardProps === 'function') {
    return recordCardProps(record);
  }

  return recordCardProps || {};
}

function scrollToSelectedRecord() {
  if (!elRef.value) return;

  const selectedRecord = elRef.value.querySelector('[aria-current="page"]');
  if (!selectedRecord) return;

  if (
    !selectedRecord.getBoundingClientRect().top ||
    selectedRecord.getBoundingClientRect().top < 0 ||
    selectedRecord.getBoundingClientRect().bottom > window.innerHeight
  ) {
    selectedRecord.scrollIntoView();
  }
}

function handleRecordMounted(record: ListRecordsAPIResponse[number]) {
  if (record.slug === route.params.slug) {
    scrollToSelectedRecord();
  }
}
</script>

<style scoped>
.SplitViewLayout {
  display: grid;
  grid-template-columns: minmax(400px, 0.35fr) 1fr;
  overflow-y: hidden;
  height: 100%;

  &.SplitViewLayout--empty {
    grid-template-columns: 1fr;
  }
}

.SplitViewLayout_list {
  height: 100%;
  overflow-y: auto;
  padding: 2rem;
}

.SplitViewLayout:has(.SplitViewLayout_detail) .SplitViewLayout_list {
  padding-right: 1.2rem;
}

.SplitViewLayout_groups {
  display: grid;
  gap: 32px;
}

.SplitViewLayout_group {
  display: grid;
  gap: 8px;
  margin-top: -4px;
}

.SplitViewLayout_groupHeader {
  display: grid;
  grid-template-columns: 1fr auto 1fr;
  align-items: center;
  gap: 8px;
  font-size: 0.75rem;
  color: var(--ui-text-dimmed);

  &::before,
  &::after {
    content: '';
    height: 1px;
    background-color: var(--ui-border);
    display: block;
    width: 100%;
  }
}

.SplitViewLayout_grid {
  column-gap: 12px;

  & > * + * {
    margin-top: 8px;
  }

  .SplitViewLayout--empty & {
    columns: 30ch 3;

    & > * + * {
      margin-top: 12px;
    }
  }
}

.SplitViewLayout_detail {
  overflow: auto;
  padding: 2rem 2rem 4rem 1rem;
}
</style>
