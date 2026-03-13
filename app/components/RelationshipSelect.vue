<template>
  <UPopover
    v-model:open="isOpen"
    :content="{ align: 'start', sideOffset: 8 }"
    :ui="{
      content: 'dark min-w-[300px] max-w-[600px] max-h-[50vh] overflow-y-auto',
    }"
  >
    <UButton
      color="neutral"
      variant="subtle"
      icon="i-lucide-list-tree"
      label="Add link"
      class="RelationshipSelect__button"
      size="sm"
      :style="{ width: 'fit-content' }"
    />

    <template #content>
      <div
        v-if="currentStep === 'predicate'"
        class="RelationshipSelect__header"
      >
        <UButton
          variant="ghost"
          size="xs"
          icon="i-lucide-arrow-left"
          color="neutral"
          @click="goBackToRecordSelection"
        />

        <span class="RelationshipSelect__headerText">
          Linking to: {{ selectedRecord?.label }}
        </span>
      </div>

      <UCommandPalette
        v-if="currentStep === 'record'"
        v-model:searchTerm="searchQuery"
        placeholder="Search for a record to link..."
        :groups="commandItems"
        :ui="{ input: '[&>input]:h-8 [&>input]:text-sm', item: 'RelationshipSelect__item' }"
        :fuse="{
          resultLimit: 100,
          matchAllWhenSearchEmpty: false,
        }"
        @update:modelValue="handleRecordSelect"
      />

      <UCommandPalette
        v-else-if="currentStep === 'predicate'"
        v-model:searchTerm="predicateQuery"
        placeholder="Select a relationship type..."
        :groups="predicateCommandItems"
        :ui="{ input: '[&>input]:h-8 [&>input]:text-sm' }"
        :fuse="{
          resultLimit: 100,
        }"
        @update:modelValue="handlePredicateSelect"
      />
    </template>
  </UPopover>
</template>

<script setup lang="ts">
import useSearch from '@app/composables/useSearch';
import { CANONICAL_PREDICATES } from '@shared/predicates';
import { capitalize } from '@shared/lib/formatting';
import type { DbId } from '@shared/types/api';
import type { CommandPaletteItem } from '@nuxt/ui';
import { computed, ref, watch } from 'vue';
import { getIconForRecordType } from '@app/utils';

type SearchResultItem = {
  label?: string;
  icon: string | object;
  id: string;
};

const emit = defineEmits<{
  createLink: [targetRecordId: DbId, predicateSlug: string];
}>();

const { sourceRecordId } = defineProps<{
  sourceRecordId?: DbId;
}>();

const isOpen = ref(false);
const currentStep = ref<'record' | 'predicate'>('record');
const searchQuery = ref('');
const predicateQuery = ref('');
const selectedRecord = ref<SearchResultItem>();

const { data: searchResults } = useSearch(
  searchQuery,
  computed(() => searchQuery.value.length > 0),
);

const commandItems = computed(() => {
  if (!searchResults.value) return [];

  const items = searchResults.value
    .filter((record) => record.id !== sourceRecordId)
    .map((record) => ({
      id: record.id.toString(),
      label: record.title || record.content || record.slug,
      icon: getIconForRecordType(record.type),
      suffix: record.summary || record.content || undefined,
    }));

  return [
    {
      id: 'records',
      items,
    },
  ];
});

const predicateCommandItems = computed(() => {
  const items = CANONICAL_PREDICATES.map((p) => ({
    id: p.slug,
    label: capitalize(p.name),
    suffix: capitalize(p.type),
  }));

  return [
    {
      id: 'predicates',
      items,
    },
  ];
});

watch(isOpen, () => {
  if (!isOpen.value) {
    resetForm();
  }
});

function handleRecordSelect(item: CommandPaletteItem) {
  if (!item) return;

  selectedRecord.value = {
    id: item.id,
    label: item.label,
    icon: item.icon || 'i-lucide-circle',
  };

  predicateQuery.value = '';
  currentStep.value = 'predicate';
}

function handlePredicateSelect(item: CommandPaletteItem) {
  if (!item || !selectedRecord.value) return;

  emit('createLink', parseInt(selectedRecord.value.id), item.id);

  resetForm();
}

function goBackToRecordSelection() {
  currentStep.value = 'record';
  selectedRecord.value = undefined;
}

function resetForm() {
  isOpen.value = false;
  currentStep.value = 'record';
  searchQuery.value = '';
  predicateQuery.value = '';
  selectedRecord.value = undefined;
}
</script>

<style scoped>
.RelationshipSelect__header {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  padding: 8px;
  border-bottom: 1px solid var(--ui-border);
}

.RelationshipSelect__headerText {
  font-size: 0.875rem;
  font-weight: 500;
  color: var(--ui-text-highlighted);
  display: -webkit-box;
  -webkit-box-orient: vertical;
  -webkit-line-clamp: 2;
  line-clamp: 2;
  overflow: hidden;
}

.RelationshipSelect__searchItem {
  display: flex;
  gap: 0.5rem;
  align-items: baseline;
}

.RelationshipSelect__searchItem :deep(svg) {
  flex-shrink: 0;
  width: 12px;
  height: 12px;
  color: var(--ui-text-dimmed);
  position: relative;
  top: 1px;
}

.RelationshipSelect__searchLabel {
  display: -webkit-box;
  -webkit-box-orient: vertical;
  -webkit-line-clamp: 2;
  line-clamp: 2;
  overflow: hidden;
}

:deep(.RelationshipSelect__item) {
  & :deep(svg) {
    width: 16px;
    height: 16px;
  }
}
</style>
