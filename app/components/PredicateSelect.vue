<template>
  <UDropdownMenu
    size="sm"
    :items="menuItems"
    :ui="{
      content: 'min-w-[200px]',
    }"
    :content="{
      align: 'start',
      alignOffset: 10,
      sideOffset: 4,
    }"
  >
    <UButton
      color="neutral"
      variant="link"
      trailingIcon="i-lucide-settings"
      size="sm"
      class="PredicateSelect__button"
      :aria-label="label"
    />
  </UDropdownMenu>
</template>

<script setup lang="ts">
import {
  getPredicateSafe,
  canonicalPredicates,
  getInverse,
  type Predicate,
  type PredicateSlug,
} from '@shared/types';
import { capitalize } from '@shared/lib/formatting';
import { computed } from 'vue';

const modelValue = defineModel<PredicateSlug>({ default: 'related_to' });

const emit = defineEmits<{
  'select:predicate': [Predicate];
  'delete:link': [];
}>();

const { linkDirection = 'outgoing' } = defineProps<{
  linkDirection?: 'incoming' | 'outgoing';
}>();

const menuItems = computed(() => {
  const predicateItems = canonicalPredicates.map((p) => {
    let label = capitalize(p.name);

    if (linkDirection === 'incoming') {
      const inverse = getInverse(p.slug as PredicateSlug);
      label = capitalize(inverse.name);
    }

    return {
      label,
      type: 'checkbox' as const,
      checked: modelValue.value === p.slug,
      onUpdateChecked(checked: boolean) {
        if (checked && p.slug !== modelValue.value) {
          modelValue.value = p.slug as PredicateSlug;
          emit('select:predicate', p);
        }
      },
    };
  });

  return [
    predicateItems,
    [
      {
        label: 'Delete',
        icon: 'i-lucide-trash',
        color: 'error',
        onSelect() {
          emit('delete:link');
        },
      },
    ],
  ];
});

const selectedPredicate = computed(() => {
  return getPredicateSafe(modelValue.value) ?? null;
});

const selectedInverse = computed(() => {
  if (!selectedPredicate.value) return null;
  return getInverse(selectedPredicate.value.slug as PredicateSlug);
});

const label = computed(() => {
  let name = selectedPredicate.value?.name;

  if (linkDirection === 'incoming') {
    name = selectedInverse.value?.name;
  }

  return name ? capitalize(name) : 'Predicates';
});
</script>

<style scoped>
:global(.PredicateSelect__button) {
  gap: 2px;
}

:global(.PredicateSelect__button svg) {
  width: 14px;
  height: 14px;
  color: var(--ui-text-dimmed);
}
</style>
