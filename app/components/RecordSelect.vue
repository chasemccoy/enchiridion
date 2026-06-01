<template>
  <USelectMenu
    v-model:searchTerm="modelValue"
    v-model:modelValue="selectedSlug"
    placeholder="Select a record"
    valueKey="id"
    size="lg"
    variant="ghost"
    icon="i-lucide-arrow-left-right"
    trailingIcon="i-lucide-chevrons-up-down"
    :items="searchResultItems"
    :ui="{
      content: 'min-w-[400px]',
    }"
    ignoreFilter
    @update:modelValue="handleSelect"
  >
    <template
      v-if="searchResultItems && searchResultItems.length > 0"
      #item="{ item }"
    >
      <div class="RecordSelect__item">
        <UIcon
          v-if="item.icon"
          :name="item.icon"
        />
        <span class="RecordSelect__label">{{ item.label }}</span>
      </div>
    </template>
  </USelectMenu>
</template>

<script setup lang="ts">
import type { InputMenuItem } from '@nuxt/ui';
import { ref } from 'vue';
import { useRouter } from 'vue-router';

type SearchResultItem = InputMenuItem & {
  label: string;
  icon: string;
  id: string;
};

const modelValue = defineModel<string>();

const { searchResultItems } = defineProps<{
  searchResultItems?: SearchResultItem[];
}>();

const router = useRouter();

const selectedSlug = ref('');

function handleSelect(slug: string) {
  router.push(`/${slug}`);
  selectedSlug.value = '';
}
</script>

<style scoped>
.RecordSelect__item {
  display: flex;
  gap: 0.5rem;
  align-items: baseline;

  & :deep(svg) {
    flex-shrink: 0;
    width: 12px;
    height: 12px;
    color: var(--ui-text-dimmed);
    position: relative;
    top: 1px;
  }
}

.RecordSelect__label {
  display: -webkit-box;
  -webkit-box-orient: vertical;
  -webkit-line-clamp: 2;
  line-clamp: 2;
  overflow: hidden;
}
</style>
