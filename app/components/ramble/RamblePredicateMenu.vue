<template>
  <Teleport to="body">
    <UDropdownMenu
      v-model:open="openModel"
      :items="items"
      :content="{ align: 'start', sideOffset: 6 }"
      :ui="{ content: 'min-w-[240px]' }"
    >
      <span
        :style="anchorStyle"
        aria-hidden="true"
      />
    </UDropdownMenu>
  </Teleport>
</template>

<script setup lang="ts">
import { capitalize } from '@shared/lib/formatting';
import {
  canonicalPredicates,
  type PredicateSlug,
  type PredicateType,
} from '@shared/types';
import { computed, type CSSProperties } from 'vue';

const openModel = defineModel<boolean>('open', { required: true });
const valueModel = defineModel<PredicateSlug | null>('value', { default: null });

defineProps<{
  anchorStyle: CSSProperties;
}>();

// Group once — canonicalPredicates is module-level constant data.
const predicateGroups = computed(() => {
  const groups = new Map<PredicateType, { slug: PredicateSlug; name: string }[]>();
  for (const p of canonicalPredicates) {
    const list = groups.get(p.type) ?? [];
    list.push({ slug: p.slug as PredicateSlug, name: p.name });
    groups.set(p.type, list);
  }
  return Array.from(groups.values());
});

const items = computed(() =>
  predicateGroups.value.map((group) =>
    group.map((p) => ({
      label: capitalize(p.name),
      type: 'checkbox' as const,
      checked: valueModel.value === p.slug,
      onUpdateChecked(checked: boolean) {
        if (checked) {
          valueModel.value = p.slug;
          openModel.value = false;
        }
      },
    })),
  ),
);
</script>
