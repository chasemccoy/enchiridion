<template>
  <div class="NotesListView">
    <header class="NotesListView__toolbar">
      <UButton
        size="sm"
        color="neutral"
        variant="subtle"
        icon="i-lucide-plus"
        label="New note"
        :loading="isCreating"
        @click="createNote"
      />
      <span
        v-if="data"
        class="NotesListView__count"
      >
        {{ pluralize(data.length, 'note', 'notes') }}
      </span>
    </header>

    <SplitViewLayout
      v-model="data"
      :isEmpty="!route.params.slug"
      :recordCardProps="cardProps"
    >
      <RouterView />
    </SplitViewLayout>
  </div>
</template>

<script setup lang="ts">
import SplitViewLayout from '@app/components/SplitViewLayout.vue';
import useRecords from '@app/composables/useRecords';
import useRecord from '@app/composables/useRecord';
import { generateSlug, pluralize } from '@shared/lib/formatting';
import type { ListRecordsAPIResponse } from '@db/queries/records';
import { useRoute, useRouter } from 'vue-router';

const route = useRoute();
const router = useRouter();

const { data } = useRecords({
  limit: 1000,
  filters: {
    type: 'note',
  },
  orderBy: [
    { field: 'isPinned', direction: 'desc' },
    { field: 'recordCreatedAt', direction: 'desc' },
  ],
});

function cardProps(record: ListRecordsAPIResponse[number]) {
  return { to: `/notes/${record.slug}` };
}

// Inline quick-capture: create a blank note and open it. The detail view's
// debounced save then persists edits as the user types (no save button).
const { upsertRecord } = useRecord();
const { mutate: upsertRecordMutation, isPending: isCreating } = upsertRecord();

function createNote() {
  const slug = generateSlug({ type: 'note' });
  upsertRecordMutation(
    { type: 'note', title: '', slug, source: 'manual' },
    {
      onSuccess: (record) => {
        router.push(`/notes/${record.slug}`);
      },
    },
  );
}
</script>

<style scoped>
.NotesListView {
  display: grid;
  grid-template-rows: auto 1fr;
  height: 100%;
  min-height: 0;
}

.NotesListView__toolbar {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 12px 16px;
  border-bottom: 0.5px solid var(--ui-border);
}

.NotesListView__count {
  font-size: 0.8rem;
  color: var(--ui-text-dimmed);
}
</style>
