<template>
  <div
    ref="elRef"
    class="SplitViewLayout"
    :class="{ 'SplitViewLayout--empty': isEmpty }"
  >
    <div class="SplitViewLayout_list">
      <ul
        v-if="modelValue"
        class="SplitViewLayout_grid"
      >
        <li
          v-for="(record, index) in modelValue"
          :key="record.id"
        >
          <RecordCard
            v-model="modelValue[index]"
            v-bind="getRecordCardProps(record)"
            :data-slug="record.slug"
            @vue:Mounted="handleRecordMounted(modelValue[index])"
          />
        </li>
      </ul>
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
import { useTemplateRef, watch } from 'vue';
import { useRoute } from 'vue-router';

const modelValue = defineModel<ListRecordsAPIResponse>();

const { isEmpty, recordCardProps } = defineProps<{
  isEmpty?: boolean;
  recordCardProps?: (record: ListRecordsAPIResponse[number]) => Record<string, string>;
}>();

const elRef = useTemplateRef('elRef');
const route = useRoute();

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
