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
            size="compact"
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
  grid-template-columns: minmax(350px, 0.5fr) 1fr;
  gap: 8px;
  overflow: hidden;
  height: calc(100% + 2rem);
  margin: -1rem;

  &.SplitViewLayout--empty {
    grid-template-columns: 1fr;
  }
}

.SplitViewLayout_list {
  height: 100%;
  overflow: auto;
  padding: 1rem 0.75rem 1rem 1rem;
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
  padding: 1rem 1.5rem 1rem 0.5rem;
}
</style>
